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
/// 345 MB of weights and the phonemiser's data has a directory, a size, and no
/// voice — and it reports exactly the same way as a build that never worked,
/// which is a day nobody gets back.
class VoiceModelFiles {
  VoiceModelFiles(this.root);

  final Directory root;

  File get model => File(p.join(root.path, 'model.onnx'));
  File get voices => File(p.join(root.path, 'voices.bin'));
  File get tokens => File(p.join(root.path, 'tokens.txt'));
  Directory get espeakData => Directory(p.join(root.path, 'espeak-ng-data'));
  File get licence => File(p.join(root.path, 'LICENSE'));

  bool get arePresent =>
      model.existsSync() &&
      voices.existsSync() &&
      tokens.existsSync() &&
      espeakData.existsSync();
}

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
    Future<Directory> Function()? documentsDirectory,
    http.Client Function()? client,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _client = client ?? http.Client.new;

  final Future<Directory> Function() _documentsDirectory;
  final http.Client Function() _client;

  /// Everything to do with the voice lives under one directory, so switching
  /// the feature off and reclaiming the disk is one deletion.
  static const folder = 'neural-voice';

  /// Kokoro-82M v0.19, as `sherpa-onnx` publishes it.
  ///
  /// A release asset with a fixed URL rather than anything this project hosts:
  /// there is no server behind wordbridge and there should not be one, and a
  /// download that depends on infrastructure nobody is paying for is a feature
  /// with a expiry date on it.
  static const downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'kokoro-en-v0_19.tar.bz2';

  /// What the screen says before anybody agrees to it.
  ///
  /// Both numbers, because they are different questions: [downloadBytes] is
  /// what it costs somebody's data allowance and [installedBytes] is what it
  /// costs their tablet for good. Peak use is briefly the sum, while the
  /// archive and its contents are both on disk.
  static const downloadBytes = 319625534;
  static const installedBytes = 378000000;

  /// The published archive, checked before a byte of it is unpacked.
  ///
  /// This is the voice a person will speak in for years. A truncated download
  /// or a mirror serving something else has to fail here, loudly, rather than
  /// as a model that loads and says something nobody chose.
  static const sha256Digest =
      '912804855a04745fa77a30be545b3f9a5d15c4d66db00b88cbcd4921df605ac7';

  /// The archive's own top-level directory, stripped on the way out so the
  /// paths do not carry a model version nothing else knows about.
  static const _archiveRoot = 'kokoro-en-v0_19/';

  Future<Directory> _root() async => Directory(
    p.join((await _documentsDirectory()).path, folder),
  );

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

  /// Removes the model and everything downloaded towards it.
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
  Stream<ModelProgress> install() async* {
    final root = await _root();
    root.createSync(recursive: true);
    final archive = File(p.join(root.path, 'model.tar.bz2.part'));

    try {
      yield* _download(archive);

      yield (
        phase: ModelPhase.verifying,
        bytes: downloadBytes,
        totalBytes: downloadBytes,
        detail: null,
      );
      final digest = await _digestOf(archive);
      if (digest != sha256Digest) {
        // What arrived is not what was published. Keeping it would mean
        // resuming onto a file that can never verify, so this one goes.
        archive.deleteSync();
        yield (
          phase: ModelPhase.failed,
          bytes: 0,
          totalBytes: downloadBytes,
          detail:
              'The download did not match what was published, so it has not '
              'been installed. Try again.',
        );
        return;
      }

      yield* _unpack(archive, root);

      archive.deleteSync();
      yield (
        phase: ModelPhase.installed,
        bytes: installedBytes,
        totalBytes: installedBytes,
        detail: null,
      );
    } catch (e) {
      yield (
        phase: ModelPhase.failed,
        bytes: archive.existsSync() ? archive.lengthSync() : 0,
        totalBytes: downloadBytes,
        detail: '$e',
      );
    }
  }

  /// Streams the archive to disk, continuing from whatever is already there.
  Stream<ModelProgress> _download(File archive) async* {
    var have = archive.existsSync() ? archive.lengthSync() : 0;
    if (have >= downloadBytes) return;

    final client = _client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
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
          uri: Uri.parse(downloadUrl),
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
            totalBytes: downloadBytes,
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

    final done = Isolate.run(() {
      _extract(archivePath, stagingPath, progress.sendPort);
    });

    var bytes = 0;
    final updates = StreamController<ModelProgress>();
    progress.listen((Object? message) {
      bytes += message! as int;
      updates.add((
        phase: ModelPhase.unpacking,
        bytes: bytes,
        totalBytes: installedBytes,
        detail: null,
      ));
    });
    unawaited(
      done.whenComplete(() {
        progress.close();
        updates.close();
      }),
    );

    yield* updates.stream;
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

  /// Runs in its own isolate: bzip2 to a plain tar, then the tar to disk.
  ///
  /// Two passes over a temporary file rather than one pass in memory. The
  /// decompressed archive is 361 MB and this device has 3 GB in total, most of
  /// which the board and the OS already want.
  static void _extract(String archivePath, String toPath, SendPort progress) {
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
      final entries = TarDecoder().decodeStream(tar, storeData: false);
      for (final entry in entries) {
        if (!entry.isFile) continue;
        var name = entry.name;
        if (name.startsWith(_archiveRoot)) {
          name = name.substring(_archiveRoot.length);
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
        progress.send(entry.size);
      }
    } finally {
      tar.closeSync();
      File(tarPath).deleteSync();
    }
  }
}
