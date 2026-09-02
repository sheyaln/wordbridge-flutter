import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:wordbridge/features/speech/neural/voice_model.dart';

/// Serves [bytes], honoring a range request the way a release server does.
class _Server extends http.BaseClient {
  _Server(this.bytes, {this.ignoreRange = false, this.failAfter, this.gate});

  final Uint8List bytes;

  /// Some servers answer 200 with the whole file however you ask.
  final bool ignoreRange;

  /// Cuts the connection partway, which is what a tablet leaving the house
  /// does to a 305 MB download.
  final int? failAfter;

  /// Held open partway through the body, so a test can act on a download that
  /// is genuinely in flight rather than on one that raced it.
  final Future<void>? gate;

  /// Completes once the first piece is out and the gate is all that is left.
  final holding = Completer<void>();

  final requestedRanges = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final range = request.headers['range'];
    requestedRanges.add(range);

    var from = 0;
    if (range != null && !ignoreRange) {
      from = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
    }

    var body = bytes.sublist(from);
    var truncated = false;
    if (failAfter != null && body.length > failAfter!) {
      body = body.sublist(0, failAfter!);
      truncated = true;
    }

    final held = gate;
    Stream<List<int>> pieces() async* {
      if (held == null || body.length < 2) {
        yield body;
        if (!holding.isCompleted) holding.complete();
        return;
      }
      // One byte, then a wait somebody else ends. Whatever the test does next
      // happens with the socket open and the file half written.
      yield body.sublist(0, 1);
      if (!holding.isCompleted) holding.complete();
      await held;
      yield body.sublist(1);
    }

    return http.StreamedResponse(
      pieces(),
      range != null && !ignoreRange ? 206 : 200,
      contentLength: truncated ? null : body.length,
    );
  }
}

/// A tar.bz2 shaped like the published one: a single top-level directory with
/// the four things the engine needs inside it.
Uint8List archiveOf(Directory scratch, {int modelBytes = 4096}) {
  final source = Directory(p.join(scratch.path, 'kokoro-en-v0_19'))
    ..createSync(recursive: true);
  File(p.join(source.path, 'model.onnx'))
      .writeAsBytesSync(Uint8List(modelBytes)..fillRange(0, modelBytes, 3));
  File(p.join(source.path, 'voices.bin')).writeAsBytesSync(Uint8List(256));
  File(p.join(source.path, 'tokens.txt')).writeAsStringSync('a 1\n');
  final espeak = Directory(p.join(source.path, 'espeak-ng-data'))..createSync();
  File(p.join(espeak.path, 'en_dict')).writeAsBytesSync(Uint8List(64));

  final tar = TarEncoder().encode(
    createArchiveFromDirectory(scratch, includeDirName: false),
  );
  return Uint8List.fromList(BZip2Encoder().encode(tar));
}

void main() {
  late Directory documents;
  late Directory scratch;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('wordbridge-model');
    scratch = Directory.systemTemp.createTempSync('wordbridge-archive');
  });

  tearDown(() {
    for (final d in [documents, scratch]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<Directory> where() async => documents;

  /// A store pointed at a test archive rather than the release asset. The
  /// digest travels with the bytes, which is the point of naming the release
  /// as one value.
  VoiceModelStore storeServing(_Server server, {String? digest}) =>
      VoiceModelStore(
        published: (
          url: kokoroV019.url,
          sha256: digest ?? sha256.convert(server.bytes).toString(),
          downloadBytes: server.bytes.length,
          installedBytes: server.bytes.length * 2,
          archiveRoot: kokoroV019.archiveRoot,
        ),
        documentsDirectory: where,
        client: () => server,
      );

  test('it downloads, checks, unpacks, and only then says installed', () async {
    // The unpack runs in its own isolate, so this also covers what can and
    // cannot cross that boundary — a closure that captures the wrong half of
    // a port fails here and nowhere else.
    final bytes = archiveOf(scratch);
    final store = storeServing(_Server(bytes));

    final phases = <ModelPhase>[];
    await for (final progress in store.install()) {
      phases.add(progress.phase);
    }

    expect(phases, contains(ModelPhase.downloading));
    expect(phases, contains(ModelPhase.verifying));
    expect(phases.last, ModelPhase.installed);
    expect(await store.isInstalled(), isTrue);

    final files = await store.files();
    expect(files.model.existsSync(), isTrue);
    expect(files.voices.existsSync(), isTrue);
    expect(files.tokens.existsSync(), isTrue);
    expect(files.espeakData.existsSync(), isTrue);
  });

  test('unpacking reports as it goes, not all at the end', () async {
    // Decompression is minutes of solid bzip2 on the floor device, and it is
    // one call that cannot report on itself. A bar that stands still through
    // the longest part of an install reads as a tablet that has stopped.
    final bytes = archiveOf(scratch, modelBytes: 512 * 1024);
    final store = storeServing(_Server(bytes));

    final unpacking = <int>[];
    await for (final progress in store.install()) {
      if (progress.phase == ModelPhase.unpacking) {
        unpacking.add(progress.bytes);
      }
    }

    expect(unpacking, isNotEmpty, reason: 'the unpack has to say something');
    expect(
      unpacking.last,
      greaterThan(0),
      reason: 'and it has to have got somewhere by the end',
    );
    // Never backwards: the two halves of the job are reported as one bar.
    for (var i = 1; i < unpacking.length; i++) {
      expect(unpacking[i], greaterThanOrEqualTo(unpacking[i - 1]));
    }
  });

  test('an unpack that fails does not report itself installed', () async {
    // A tablet that ran out of space partway leaves a directory that looks
    // finished. The rename into place is what makes "installed" honest.
    final source = Directory(p.join(scratch.path, 'kokoro-en-v0_19'))
      ..createSync(recursive: true);
    File(p.join(source.path, 'model.onnx')).writeAsBytesSync(Uint8List(64));
    // No voices.bin, no tokens.txt, no espeak data.

    final bytes = Uint8List.fromList(
      BZip2Encoder().encode(
        TarEncoder().encode(
          createArchiveFromDirectory(scratch, includeDirName: false),
        ),
      ),
    );

    final store = storeServing(_Server(bytes));
    final last = await store.install().last;

    expect(last.phase, ModelPhase.failed);
    expect(await store.isInstalled(), isFalse);
  });

  test('the files that arrive have what was in the archive', () async {
    // An entry read without its content writes a file of zero bytes, which
    // passes any check that only asks whether the file is there — and gives a
    // model that will not load, reported three screens from the cause.
    final bytes = archiveOf(scratch, modelBytes: 8192);
    final store = storeServing(_Server(bytes));
    await store.install().drain<void>();

    final files = await store.files();
    expect(files.model.lengthSync(), 8192);
    expect(files.voices.lengthSync(), 256);
    expect(files.tokens.readAsStringSync(), 'a 1\n');
    expect(files.espeakData.listSync(), isNotEmpty);
  });

  test('the archive is deleted once it is unpacked', () async {
    final bytes = archiveOf(scratch);
    final store = storeServing(_Server(bytes));
    await store.install().drain<void>();

    expect(await store.downloadedBytes(), 0);
    // Only the unpacked model is left, not the archive as well.
    expect(await store.bytesOnDisk(), lessThan(bytes.length + 4096 + 4096));
  });

  test('something other than what was published is refused', () async {
    final bytes = archiveOf(scratch);
    final store = storeServing(
      _Server(bytes),
      digest: 'not the digest of anything that was ever published',
    );

    final failure = await store.install().last;
    expect(failure.phase, ModelPhase.failed);
    expect(failure.detail, contains('did not match what was published'));
    expect(await store.isInstalled(), isFalse);
    // The bad bytes go, so a resume cannot land on a file that can never
    // verify.
    expect(await store.downloadedBytes(), 0);
  });

  test('an interrupted download resumes rather than starting again', () async {
    // 305 MB over a domestic connection is long enough that the tablet will be
    // backgrounded, will sleep, and will walk out of range at least once.
    final bytes = archiveOf(scratch);
    final half = bytes.length ~/ 2;

    final cut = _Server(bytes, failAfter: half);
    final store = storeServing(cut);
    final stopped = await store.install().last;
    expect(stopped.phase, ModelPhase.failed);
    expect(await store.downloadedBytes(), half);

    final rest = _Server(bytes);
    final again = storeServing(rest);
    final finished = await again.install().last;

    expect(rest.requestedRanges.single, 'bytes=$half-');
    expect(finished.phase, ModelPhase.installed);
    expect(await again.isInstalled(), isTrue);
  });

  test(
    'a server that ignores the range header does not corrupt the file',
    () async {
      // Answering 200 with the whole file is legal. Appending that onto a
      // half-finished download splices the start of the archive onto its middle
      // and fails verification 300 MB later.
      final bytes = archiveOf(scratch);
      final half = bytes.length ~/ 2;

      final cut = _Server(bytes, failAfter: half);
      await storeServing(cut).install().drain<void>();

      final whole = _Server(bytes, ignoreRange: true);
      final store = storeServing(whole);
      final finished = await store.install().last;

      expect(finished.phase, ModelPhase.installed);
      expect(await store.isInstalled(), isTrue);
    },
  );

  test('deleting gives the disk back and leaves the cache alone', () async {
    final bytes = archiveOf(scratch);
    final store = storeServing(_Server(bytes));
    await store.install().drain<void>();

    // Somebody freeing space may want the disk without losing the half hour
    // it took to bake.
    final clips = Directory(
      p.join(documents.path, VoiceModelStore.folder, 'clips'),
    )..createSync(recursive: true);
    File(p.join(clips.path, 'af_bella-r100.pack'))
        .writeAsBytesSync(Uint8List(1024));

    await store.deleteModel();

    expect(await store.isInstalled(), isFalse);
    expect(File(p.join(clips.path, 'af_bella-r100.pack')).existsSync(), isTrue);
  });

  test(
    'a tar naming a path outside the directory does not escape it',
    () async {
      final source = Directory(p.join(scratch.path, 'kokoro-en-v0_19'))
        ..createSync(recursive: true);
      File(p.join(source.path, 'model.onnx')).writeAsBytesSync(Uint8List(64));
      File(p.join(source.path, 'voices.bin')).writeAsBytesSync(Uint8List(64));
      File(p.join(source.path, 'tokens.txt')).writeAsStringSync('a 1\n');
      Directory(p.join(source.path, 'espeak-ng-data')).createSync();
      File(p.join(source.path, 'espeak-ng-data', 'en_dict'))
          .writeAsBytesSync(Uint8List(8));

      final archive = createArchiveFromDirectory(scratch, includeDirName: false)
        ..addFile(
          ArchiveFile.bytes('../escaped.txt', Uint8List.fromList([1, 2, 3])),
        );
      final bytes = Uint8List.fromList(
        BZip2Encoder().encode(TarEncoder().encode(archive)),
      );

      final store = storeServing(_Server(bytes));
      await store.install().drain<void>();

      expect(await store.isInstalled(), isTrue);
      expect(
        File(p.join(documents.path, VoiceModelStore.folder, 'escaped.txt'))
            .existsSync(),
        isFalse,
      );
    },
  );

  /// §4.62. The download belongs to the store, not to whoever is watching it.
  ///
  /// `install()` used to be an `async*` generator, which meant the screen
  /// listening to it *was* its reason to run: cancelling that subscription
  /// ended the generator at its next `yield` and closed the socket on the way
  /// out. So leaving the screen abandoned 305 MB — under a tile that had said
  /// it was safe to leave.
  group('an install nobody is watching', () {
    test('carries on after the only listener goes away', () async {
      final release = Completer<void>();
      final server = _Server(archiveOf(scratch), gate: release.future);
      final store = storeServing(server);

      final subscription = store.install().listen(null);

      // Held open with one byte written, which is where a caregiver backs out
      // of the screen.
      await server.holding.future;
      expect(store.isInstalling, isTrue, reason: 'the premise');

      await subscription.cancel();
      expect(
        store.isInstalling,
        isTrue,
        reason: 'cancelling a watcher must not end the download',
      );

      // Nothing is listening from here. If the work were the listener's, this
      // is where 305 MB would be silently dropped.
      release.complete();
      while (store.isInstalling) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(await store.isInstalled(), isTrue);
      expect(store.installProgress?.phase, ModelPhase.installed);
    });

    test('is handed back rather than started twice', () async {
      // Two downloads appending to one partial file interleave their bytes
      // into an archive that can never verify — and the second 305 MB is spent
      // producing it.
      final release = Completer<void>();
      final server = _Server(archiveOf(scratch), gate: release.future);
      final store = storeServing(server);

      final first = store.install();
      await server.holding.future;
      final second = store.install();
      expect(identical(first, second), isTrue);

      release.complete();
      await second.drain<void>();

      expect(await store.isInstalled(), isTrue);
      expect(
        server.requestedRanges,
        hasLength(1),
        reason: 'one download, however many times it was asked for',
      );
    });

    test('remembers where it got to, for a screen coming back', () async {
      // A broadcast stream tells a late listener nothing about what it missed,
      // and a caregiver returning to a download in progress has to see the bar
      // where they left it rather than an offer to start again.
      final release = Completer<void>();
      final server = _Server(archiveOf(scratch), gate: release.future);
      final store = storeServing(server);

      expect(store.isInstalling, isFalse);
      expect(store.installProgress, isNull);

      final subscription = store.install().listen(null);
      await server.holding.future;
      // Reported, not merely sent.
      while (store.installProgress == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(store.installProgress!.phase, ModelPhase.downloading);
      expect(store.installProgress!.bytes, greaterThan(0));

      await subscription.cancel();
      release.complete();
      while (store.isInstalling) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(store.isInstalling, isFalse);
    });
  });
}
