import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/features/backup/recovery.dart';
import 'package:wordbridge/features/backup/snapshot.dart';

/// The way back for a tablet whose database will not open.
///
/// `BackupService.restore` copies table by table through the live connection,
/// which is the right restore and is unavailable in exactly the case that
/// leaves a nonspeaking person with fourteen words: there is no connection.
/// So everything here is about files — what is offered, what is refused, and
/// what is kept when a board is displaced.
void main() {
  late Directory documents;
  late Directory backups;
  late File board;

  /// One instant per call, so files written in one test order themselves.
  late DateTime tick;
  DateTime clock() {
    tick = tick.add(const Duration(seconds: 1));
    return tick;
  }

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('wordbridge-recovery');
    backups = Directory(p.join(documents.path, snapshotFolder));
    await backups.create(recursive: true);
    board = File(p.join(documents.path, 'wordbridge.sqlite'));
    tick = DateTime.utc(2026, 1, 1);
  });

  tearDown(() async {
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  BoardRecovery recovery({int appSchemaVersion = 9}) => BoardRecovery(
    () async => board,
    appSchemaVersion: appSchemaVersion,
    documentsDirectory: () async => documents,
    clock: clock,
  );

  /// A file with the header [snapshotSchemaVersion] reads, and nothing else.
  ///
  /// The recovery path never opens a database — it reads the hundred-byte
  /// header, precisely so that a folder holding one truncated file still
  /// produces a list. A real database here would test drift instead.
  Future<File> writeDatabase(
    File file, {
    int version = 9,
    String body = '',
  }) async {
    final header = Uint8List(100);
    const magic = 'SQLite format 3\x00';
    for (var i = 0; i < magic.length; i++) {
      header[i] = magic.codeUnitAt(i);
    }
    header[60] = (version >> 24) & 0xFF;
    header[61] = (version >> 16) & 0xFF;
    header[62] = (version >> 8) & 0xFF;
    header[63] = version & 0xFF;

    await file.create(recursive: true);
    await file.writeAsBytes([...header, ...body.codeUnits]);
    return file;
  }

  Future<File> writeSnapshot(DateTime takenAt, {int version = 9}) =>
      writeDatabase(
        File(p.join(backups.path, snapshotFileName(takenAt))),
        version: version,
        body: 'taken at $takenAt',
      );

  group('what a caregiver is offered', () {
    test('is every backup on the tablet, newest first', () async {
      await writeSnapshot(DateTime.utc(2026, 8, 1, 9));
      await writeSnapshot(DateTime.utc(2026, 8, 3, 14, 22));

      final found = await recovery().options();

      expect(found.problem, isNull);
      expect(
        [for (final option in found.options) option.snapshot.takenAt],
        [DateTime.utc(2026, 8, 3, 14, 22), DateTime.utc(2026, 8, 1, 9)],
      );
      expect(found.options.every((option) => option.usable), isTrue);
    });

    test('includes the copy taken when settings were last opened', () async {
      await writeDatabase(File(p.join(backups.path, sessionSnapshotFileName)));

      final found = await recovery().options();

      expect(found.options, hasLength(1));
      expect(
        found.options.single.snapshot.path,
        endsWith(sessionSnapshotFileName),
        reason:
            'the caregiver list keeps this out because it is a way back from '
            'one sitting; here any openable board beats fourteen words',
      );
    });

    test('leaves out whatever else is in the folder', () async {
      await File(p.join(backups.path, 'holiday.jpg')).writeAsString('not a db');
      await File(
        p.join(backups.path, snapshotFileName(DateTime.utc(2026, 8, 1))),
      ).writeAsString('truncated');

      expect((await recovery().options()).options, isEmpty);
    });

    test(
      'names a backup this build cannot read instead of hiding it',
      () async {
        await writeSnapshot(DateTime.utc(2026, 8, 3), version: 12);

        final option = (await recovery().options()).options.single;

        expect(option.usable, isFalse);
        expect(option.refusal, contains('newer version'));
        expect(option.refusal, contains('backup 12'));
        expect(option.refusal, contains('this app reads 9'));
      },
    );

    test('says so when the folder cannot be read', () async {
      final broken = BoardRecovery(
        () async => board,
        appSchemaVersion: 9,
        documentsDirectory: () async => throw StateError('no documents'),
      );

      final found = await broken.options();

      expect(found.options, isEmpty);
      expect(found.problem, contains('could not be listed'));
    });

    test('is empty rather than a failure on a tablet with no folder', () async {
      await backups.delete(recursive: true);

      final found = await recovery().options();

      expect(found.options, isEmpty);
      expect(found.problem, isNull);
    });
  });

  group('putting a backup back', () {
    test('leaves it where drift looks', () async {
      await writeDatabase(board, body: 'the board that will not open');
      final snapshot = (await recovery().options()).options;
      expect(snapshot, isEmpty);

      await writeSnapshot(DateTime.utc(2026, 8, 3, 14, 22));
      final option = (await recovery().options()).options.single;

      final result = await recovery().restore(option.snapshot);

      expect(result.done, isTrue);
      expect(result.problem, isNull);
      expect(
        await board.readAsString(),
        await File(option.snapshot.path).readAsString(),
      );
    });

    test('keeps the board it displaces', () async {
      await writeDatabase(board, body: 'everything since the last backup');
      await writeSnapshot(DateTime.utc(2026, 8, 3));

      final option = (await recovery().options()).options.single;
      await recovery().restore(option.snapshot);

      final kept = backups
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).contains('unopened'))
          .toList();

      expect(kept, hasLength(1));
      expect(
        kept.single.readAsStringSync(),
        contains('everything since the last backup'),
      );
      expect(
        snapshotTakenAt(kept.single.path),
        isNull,
        reason:
            'a board that would not open is not a way back, so it must not '
            'appear in a list of dates or be reached by the prune',
      );
    });

    test('takes the journals with the board it sets aside', () async {
      await writeDatabase(board, body: 'the board');
      await File('${board.path}-wal').writeAsString('write ahead log');
      await File('${board.path}-shm').writeAsString('shared memory');
      await writeSnapshot(DateTime.utc(2026, 8, 3));

      final option = (await recovery().options()).options.single;
      await recovery().restore(option.snapshot);

      expect(
        File('${board.path}-wal').existsSync(),
        isFalse,
        reason:
            'a log left behind describes the board that was moved away, and '
            'SQLite would find it beside the one that replaced it',
      );
      expect(File('${board.path}-shm').existsSync(), isFalse);
      expect(
        backups.listSync().whereType<File>().map((f) => p.basename(f.path)),
        containsAll([
          predicate<String>(
            (n) => n.contains('unopened') && n.endsWith('-wal'),
          ),
          predicate<String>(
            (n) => n.contains('unopened') && n.endsWith('-shm'),
          ),
        ]),
      );
    });

    test('refuses one written by a newer build and changes nothing', () async {
      await writeDatabase(board, body: 'the board that will not open');
      await writeSnapshot(DateTime.utc(2026, 8, 3), version: 12);

      final option = (await recovery().options()).options.single;
      final result = await recovery().restore(option.snapshot);

      expect(result.done, isFalse);
      expect(result.problem, contains('Nothing has been changed'));
      expect(
        await board.readAsString(),
        contains('the board that will not open'),
      );
    });

    test('refuses a file that is not a database', () async {
      final impostor = File(
        p.join(backups.path, snapshotFileName(DateTime.utc(2026, 8, 3))),
      );
      await impostor.writeAsString('not a database');

      final result = await recovery().restore((
        path: impostor.path,
        takenAt: DateTime.utc(2026, 8, 3),
        bytes: 14,
        schemaVersion: 9,
      ));

      expect(result.done, isFalse);
      expect(result.problem, contains('not a Wordbridge AAC backup'));
    });

    test('says so when the backup has gone', () async {
      final result = await recovery().restore((
        path: p.join(backups.path, 'wordbridge-20260803T000000000Z.db'),
        takenAt: DateTime.utc(2026, 8, 3),
        bytes: 100,
        schemaVersion: 9,
      ));

      expect(result.done, isFalse);
      expect(result.problem, contains('no longer on this tablet'));
    });
  });

  group('building a new board', () {
    test('leaves nothing for drift to open', () async {
      await writeDatabase(board, body: 'the board that will not open');

      final result = await recovery().startAgain();

      expect(result.done, isTrue);
      expect(
        board.existsSync(),
        isFalse,
        reason:
            'the next launch has to reach setup, which it does by finding '
            'no file',
      );
    });

    test('keeps the board it sets aside', () async {
      await writeDatabase(board, body: 'months of work');

      await recovery().startAgain();

      final kept = backups.listSync().whereType<File>().single;
      expect(kept.readAsStringSync(), contains('months of work'));
    });

    test('works on a tablet that has no database yet', () async {
      final result = await recovery().startAgain();

      expect(
        result.done,
        isTrue,
        reason:
            'a first run that failed partway has nothing to set aside and '
            'still needs the way out',
      );
    });
  });
}
