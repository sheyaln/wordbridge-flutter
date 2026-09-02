import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the four things the engine needs ended up.
///
/// A record of paths rather than a directory, because "the model is installed"
/// has to mean all four arrived. A tablet that ran out of space between the
/// 345 MB of weights and the phonemizer's data has a directory, a size, and no
/// voice — and it reports exactly the same way as a build that never worked,
/// which is a day nobody gets back.
class VoiceModelFiles {
  VoiceModelFiles(this.root);

  final Directory root;

  File get model => File(p.join(root.path, 'model.onnx'));
  File get voices => File(p.join(root.path, 'voices.bin'));
  File get tokens => File(p.join(root.path, 'tokens.txt'));
  Directory get espeakData => Directory(p.join(root.path, 'espeak-ng-data'));
  File get license => File(p.join(root.path, 'LICENSE'));

  /// Whether all four are here **and have something in them**.
  ///
  /// Existence is not enough. A tar entry read without its content writes a
  /// file of zero bytes, and a tablet that filled up mid-write leaves one too:
  /// both give a directory that passes a file-by-file check and a model that
  /// will not load, reported as "the voice could not be loaded" three screens
  /// away from the thing that actually went wrong.
  bool get arePresent =>
      _hasBytes(model) &&
      _hasBytes(voices) &&
      _hasBytes(tokens) &&
      espeakData.existsSync() &&
      espeakData.listSync().isNotEmpty;

  static bool _hasBytes(File file) =>
      file.existsSync() && file.lengthSync() > 0;
}

/// A model release, named rather than assumed.
///
/// One record instead of five constants because these five facts only make
/// sense together: a digest belongs to a URL, and a size belongs to both. A
/// future release, or a different model altogether, is a value rather than an
/// edit in four places.
typedef PublishedModel = ({
  String url,

  /// Checked before a byte is unpacked. This is the voice a person will speak
  /// in for years; a truncated download or a mirror serving something else has
  /// to fail loudly rather than as a model that says something nobody chose.
  String sha256,

  /// What it costs somebody's data allowance, and what it costs their tablet
  /// for good. Different questions, so both are shown. Peak use is briefly the
  /// sum, while the archive and its contents are both on disk.
  int downloadBytes,
  int installedBytes,

  /// The archive's own top-level directory, stripped on the way out so the
  /// installed paths do not carry a version nothing else knows about.
  String archiveRoot,
});

/// Kokoro-82M v0.19, as `sherpa-onnx` publishes it.
///
/// A release asset with a fixed URL rather than anything this project hosts:
/// there is no server behind wordbridge and there should not be one, and a
/// download that depends on infrastructure nobody is paying for is a feature
/// with an expiry date on it.
const kokoroV019 = (
  url:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'kokoro-en-v0_19.tar.bz2',
  sha256: '912804855a04745fa77a30be545b3f9a5d15c4d66db00b88cbcd4921df605ac7',
  downloadBytes: 319625534,
  installedBytes: 378000000,
  archiveRoot: 'kokoro-en-v0_19/',
);

/// What the install is doing, in the terms the screen says it in.
enum ModelPhase {
  /// Bytes are arriving. Resumable — closing the app does not lose them.
  downloading,

  /// Checking what arrived is what was published, before it is unpacked.
  verifying,

  /// Decompressing. The slow half on an older tablet, and it cannot be
  /// resumed, only started again.
  unpacking,

  installed,

  /// Stopped with the reason in [ModelProgress.detail]. Whatever was
  /// downloaded is kept, so trying again does not start from nothing.
  failed,
}

typedef ModelProgress = ({
  ModelPhase phase,
  int bytes,
  int totalBytes,
  String? detail,
});

/// Fetches, checks and installs the neural voice model.
///
/// **Documents, never the cache.** The OS empties cache directories when a
/// device runs short of space and it does not ask first. For a symbol pack
/// that is a slow morning; for the model that speaks every word on the board
/// it is a communication outage, arriving without warning, on the day the
/// tablet was fullest. `BackupService.folder` is in Documents for the same
/// reason and it is the same argument.
class VoiceModelStore {
  VoiceModelStore({
    this.published = kokoroV019,
    Future<Directory> Function()? documentsDirectory,
    http.Client Function()? client,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _client = client ?? http.Client.new;

  /// Which release this store fetches and checks against.
  final PublishedModel published;

  final Future<Directory> Function() _documentsDirectory;
  final http.Client Function() _client;

  /// Everything to do with the voice lives under one directory, so switching
  /// the feature off and reclaiming the disk is one deletion.
  static const folder = 'neural-voice';

  Future<Directory> _root() async =>
      Directory(p.join((await _documentsDirectory()).path, folder));

  /// Where an installed model sits, whether or not one is there.
  Future<VoiceModelFiles> files() async =>
      VoiceModelFiles(Directory(p.join((await _root()).path, 'model')));

  Future<bool> isInstalled() async => (await files()).arePresent;

  /// How much of the download is already on disk.
  ///
  /// Shown next to "resume", so a caregiver who stopped at 80% is told that
  /// rather than being offered the whole 305 MB again.
  Future<int> downloadedBytes() async {
    final part = File(p.join((await _root()).path, 'model.tar.bz2.part'));
    return part.existsSync() ? part.lengthSync() : 0;
  }

  /// What the voice is costing this tablet right now.
  Future<int> bytesOnDisk() async {
    final root = await _root();
    if (!root.existsSync()) return 0;
    var total = 0;
    for (final entry in root.listSync(recursive: true, followLinks: false)) {
      if (entry is File) total += entry.lengthSync();
    }
    return total;
  }

  /// Removes the model and everything downloaded toward it.
  ///
  /// Not the cache — that is the profile's baked words, which are worth
  /// keeping distinct: somebody freeing space may want the disk back without
  /// losing the twenty-seven minutes it took to bake.
  Future<void> deleteModel() async {
    final root = await _root();
    for (final name in ['model', 'model.tar.bz2.part', '.incoming']) {
      final path = p.join(root.path, name);
      final directory = Directory(path);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
        continue;
      }
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// The install running right now, if one is.
  ///
  /// Broadcast, and owned here rather than by whoever asked for it. A screen
  /// listening to an `async*` generator *is* that generator's only reason to
  /// run: cancelling the subscription ends it at the next `yield`, unwinding
  /// through the socket's `finally`. So a caregiver leaving the screen killed
  /// a 305 MB download that the same screen had told them was safe to leave.
  Stream<ModelProgress>? _running;

  /// The last thing the running install said.
  ///
  /// A broadcast stream tells a late listener nothing about what it missed,
  /// and a screen coming back to a download in progress has to be able to draw
  /// the bar it left.
  ModelProgress? get installProgress => _installProgress;
  ModelProgress? _installProgress;

  bool get isInstalling => _running != null;

  /// Downloads and installs, reporting as it goes.
  ///
  /// **Resumable, and it has to be.** Three hundred megabytes over a domestic
  /// connection is long enough that the app will be backgrounded, the tablet
  /// will sleep and somebody will walk out of range at least once. A download
  /// that starts again from nothing each time is one that never finishes on a
  /// slow connection, which is the connection most likely to be attached to
  /// the household this feature is for.
  ///
  /// Partial bytes are kept on failure for the same reason.
  ///
  /// Asking twice while one is running hands back the one already going, so a
  /// screen rebuilt or reopened cannot start a second download onto the same
  /// partial file.
  Stream<ModelProgress> install() {
    final running = _running;
    if (running != null) return running;

    final updates = StreamController<ModelProgress>.broadcast();
    final stream = _running = updates.stream;

    // Deliberately not awaited and deliberately not tied to a listener. The
    // work is the store's from here; the stream is only how it is watched.
    unawaited(() async {
      try {
        await for (final progress in _install()) {
          _installProgress = progress;
          updates.add(progress);
        }
      } finally {
        _running = null;
        await updates.close();
      }
    }());

    return stream;
  }

  Stream<ModelProgress> _install() async* {
    final root = await _root();
    root.createSync(recursive: true);
    final archive = File(p.join(root.path, 'model.tar.bz2.part'));

    try {
      // `await for` rather than `yield*`. A delegated stream's errors are
      // forwarded straight to whoever is listening, which would step around
      // the failure handling below and leave a caregiver with a crash where a
      // sentence explaining what to do next should be.
      await for (final progress in _download(archive)) {
        yield progress;
      }

      // Fewer bytes than were published means the connection ended early, not
      // that the wrong thing was served. The difference matters: one is
      // resumable and the other has to be thrown away, and treating the first
      // as the second loses 300 MB somebody has already waited for.
      final arrived = archive.existsSync() ? archive.lengthSync() : 0;
      if (arrived < published.downloadBytes) {
        yield (
          phase: ModelPhase.failed,
          bytes: arrived,
          totalBytes: published.downloadBytes,
          detail:
              'The download stopped early. What has arrived is kept, so '
              'carrying on will not start again from the beginning.',
        );
        return;
      }

      yield (
        phase: ModelPhase.verifying,
        bytes: published.downloadBytes,
        totalBytes: published.downloadBytes,
        detail: null,
      );
      final digest = await _digestOf(archive);
      if (digest != published.sha256) {
        // What arrived is not what was published. Keeping it would mean
        // resuming onto a file that can never verify, so this one goes.
        archive.deleteSync();
        yield (
          phase: ModelPhase.failed,
          bytes: 0,
          totalBytes: published.downloadBytes,
          detail:
              'The download did not match what was published, so it has not '
              'been installed. Try again.',
        );
        return;
      }

      await for (final progress in _unpack(archive, root)) {
        yield progress;
      }

      archive.deleteSync();
      yield (
        phase: ModelPhase.installed,
        bytes: published.installedBytes,
        totalBytes: published.installedBytes,
        detail: null,
      );
    } catch (e) {
      yield (
        phase: ModelPhase.failed,
        bytes: archive.existsSync() ? archive.lengthSync() : 0,
        totalBytes: published.downloadBytes,
        detail: '$e',
      );
    }
  }

  /// Streams the archive to disk, continuing from whatever is already there.
  Stream<ModelProgress> _download(File archive) async* {
    var have = archive.existsSync() ? archive.lengthSync() : 0;
    if (have >= published.downloadBytes) return;

    final client = _client();
    try {
      final request = http.Request('GET', Uri.parse(published.url));
      if (have > 0) request.headers['range'] = 'bytes=$have-';

      final response = await client.send(request);

      // A server that ignores the range header answers 200 with the whole
      // file. Taking that as a continuation would splice the start of the
      // archive onto the middle of it and fail verification 300 MB later.
      if (have > 0 && response.statusCode != 206) {
        have = 0;
        if (archive.existsSync()) archive.deleteSync();
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException(
          'The download server answered ${response.statusCode}.',
          uri: Uri.parse(published.url),
        );
      }

      final sink = archive.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          have += chunk.length;
          yield (
            phase: ModelPhase.downloading,
            bytes: have,
            totalBytes: published.downloadBytes,
            detail: null,
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  /// The archive's SHA-256, read in blocks.
  ///
  /// Streamed rather than read whole: 305 MB in one buffer on a 3 GB tablet is
  /// a plausible way to be killed while checking that nothing went wrong.
  Future<String> _digestOf(File archive) async =>
      (await sha256.bind(archive.openRead()).first).toString();

  /// Decompresses into a staging directory, then renames it into place.
  ///
  /// Off the main isolate because bzip2 in Dart is minutes of solid CPU on an
  /// A12, and a board frozen for minutes is a board somebody cannot speak on.
  ///
  /// The rename is what makes "installed" honest. Unpacking straight into the
  /// final directory leaves a tablet that ran out of space with three of the
  /// four files and a directory that looks finished.
  Stream<ModelProgress> _unpack(File archive, Directory root) async* {
    final staging = Directory(p.join(root.path, '.incoming'));
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);

    final progress = ReceivePort();
    final archivePath = archive.path;
    final stagingPath = staging.path;

    // Started from a scope that holds nothing else. A closure captures the
    // context it was made in rather than only the names it mentions, so an
    // `Isolate.run` written inline here would carry the ReceivePort sitting
    // beside it — which is unsendable, and refuses to start the isolate.
    final done = _extractOffThread(
      archivePath,
      stagingPath,
      published.archiveRoot,
      progress.sendPort,
    );

    final updates = StreamController<ModelProgress>();
    var written = 0;
    var decompressed = 0;

    void report() {
      // The larger of the two, because they are two halves of one job and the
      // second only starts as the first ends. A bar that went backwards
      // between them would read as something having gone wrong.
      final at = written > decompressed ? written : decompressed;
      updates.add((
        phase: ModelPhase.unpacking,
        bytes: at > published.installedBytes ? published.installedBytes : at,
        totalBytes: published.installedBytes,
        detail: null,
      ));
    }

    // Decompression is the slow half — minutes of solid bzip2 on an A12 — and
    // it is one call that cannot report on itself. What it can do is grow a
    // file, so that is what gets watched. Without this the bar stands still
    // through the longest part of the install, which reads as a tablet that
    // has stopped rather than one that is working.
    final tar = File('$archivePath.tar');
    final polling = Timer.periodic(const Duration(milliseconds: 400), (_) {
      decompressed = tar.existsSync() ? tar.lengthSync() : 0;
      report();
    });

    // The isolate sends a size per file and then null, in that order. Closing
    // on the sentinel rather than on `done` is what guarantees every size
    // arrived: a port closed the moment the isolate finished drops whatever
    // had not been delivered yet, which is most of them.
    progress.listen((Object? message) {
      if (message == null) {
        progress.close();
        updates.close();
        return;
      }
      written += message as int;
      report();
    });

    unawaited(
      done.then(
        (_) {},
        onError: (Object error, StackTrace stack) {
          // No sentinel is coming.
          progress.close();
          updates.addError(error, stack);
          updates.close();
        },
      ),
    );

    try {
      await for (final progress in updates.stream) {
        yield progress;
      }
    } finally {
      polling.cancel();
    }
    await done;

    final installed = Directory(p.join(root.path, 'model'));
    if (installed.existsSync()) installed.deleteSync(recursive: true);
    staging.renameSync(installed.path);

    if (!VoiceModelFiles(installed).arePresent) {
      throw const FileSystemException(
        'The archive unpacked without one of the files the engine needs.',
      );
    }
  }

  /// Starts [_extract] on its own isolate, holding only what can cross.
  static Future<void> _extractOffThread(
    String archivePath,
    String toPath,
    String archiveRoot,
    SendPort progress,
  ) => Isolate.run(() => _extract(archivePath, toPath, archiveRoot, progress));

  /// Runs in its own isolate: bzip2 to a plain tar, then the tar to disk.
  ///
  /// Two passes over a temporary file rather than one pass in memory. The
  /// decompressed archive is 361 MB and this device has 3 GB in total, most of
  /// which the board and the OS already want.
  static void _extract(
    String archivePath,
    String toPath,
    String archiveRoot,
    SendPort progress,
  ) {
    final tarPath = '$archivePath.tar';
    final input = InputFileStream(archivePath);
    final output = OutputFileStream(tarPath);
    try {
      BZip2Decoder().decodeStream(input, output);
    } finally {
      input.closeSync();
      output.closeSync();
    }

    final tar = InputFileStream(tarPath);
    try {
      // `storeData: false` gives entries with no content at all, and writing
      // one produces a file of zero bytes — an install that looks complete and
      // has four empty files in it. Left true, the entry's content is a lazy
      // view onto the tar on disk rather than a copy in memory, which is what
      // this device cannot spare.
      final entries = TarDecoder().decodeStream(tar);
      for (final entry in entries) {
        if (!entry.isFile) continue;
        var name = entry.name;
        if (name.startsWith(archiveRoot)) {
          name = name.substring(archiveRoot.length);
        }
        if (name.isEmpty || name.startsWith('.')) continue;

        // A tar may name anything it likes, including a path that climbs out
        // of the directory it is being unpacked into.
        final destination = p.normalize(p.join(toPath, name));
        if (!p.isWithin(toPath, destination)) continue;

        Directory(p.dirname(destination)).createSync(recursive: true);
        final sink = OutputFileStream(destination);
        try {
          entry.writeContent(sink);
        } finally {
          sink.closeSync();
        }
        // What landed, rather than what the header claimed. Entries are read
        // without their data held in memory, and the size a header reports is
        // not something the progress bar should depend on.
        progress.send(File(destination).lengthSync());
      }
      // Last, and only once everything above has been sent. The other side
      // closes on this rather than on the isolate ending, so nothing in
      // flight is dropped.
      progress.send(null);
    } finally {
      tar.closeSync();
      File(tarPath).deleteSync();
    }
  }
}
