import 'dart:io';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/backup/backup_service.dart';
import 'package:wordbridge/features/backup/snapshot.dart';

/// Getting a board back after something took it away.
///
/// The reported failure these are written against: an update flattens a
/// child's board and the family finds that the backup they believed in did not
/// carry the customisations. So the thing under test is not "a file was
/// written" — it is that every cell, every word, every hidden flag and every
/// vocabulary level comes back identical, and that a restore which cannot do
/// that leaves the board it was given alone.
///
/// The live database is in memory. `VACUUM INTO` writes a real file from an
/// in-memory database exactly as it does from a file-backed one, so nothing
/// here needs a temporary database file to be honest about what ships.
void main() {
  late Directory documents;
  late WordbridgeDatabase db;
  late BackupService backup;
  late String vocabId;

  /// Advances a second per call, so snapshots taken in one test are ordered
  /// without depending on how long a copy happens to take.
  late DateTime tick;
  DateTime clock() {
    tick = tick.add(const Duration(seconds: 1));
    return tick;
  }

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('wordbridge-backup');
    tick = DateTime.utc(2026, 1, 1);
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    backup = BackupService(
      db,
      documentsDirectory: () async => documents,
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  /// Every row in the database, per table, so a comparison can name what moved.
  Future<Map<String, Set<Object>>> everything() async => {
    'profiles': (await db.select(db.profiles).get()).toSet(),
    'vocabularies': (await db.select(db.vocabularies).get()).toSet(),
    'boards': (await db.select(db.boards).get()).toSet(),
    'cells': (await db.select(db.cells).get()).toSet(),
    'buttons': (await db.select(db.buttons).get()).toSet(),
    'symbols': (await db.select(db.symbols).get()).toSet(),
    'usageEvents': (await db.select(db.usageEvents).get()).toSet(),
    'editEvents': (await db.select(db.editEvents).get()).toSet(),
    'caregiverAuth': (await db.select(db.caregiverAuth).get()).toSet(),
    'appState': (await db.select(db.appState).get()).toSet(),
    'predictionPairs': (await db.select(db.predictionPairs).get()).toSet(),
    'syncMeta': (await db.select(db.syncMeta).get()).toSet(),
  };

  /// Customisations a caregiver would be devastated to lose, and history the
  /// remap warning is computed from.
  Future<void> personalise() async {
    final hide = (await db.select(db.buttons).get()).firstWhere(
      (b) => !b.isSystem,
    );
    await (db.update(db.buttons)..where((b) => b.id.equals(hide.id))).write(
      const ButtonsCompanion(hidden: Value(true), vocabLevel: Value(4)),
    );

    await (db.update(db.profiles)..where((p) => p.id.equals('default'))).write(
      const ProfilesCompanion(vocabLevel: Value(3)),
    );

    final cell = (await db.select(db.cells).get()).first;
    await db
        .into(db.usageEvents)
        .insert(
          UsageEventsCompanion.insert(
            deviceId: 'tablet',
            profileId: 'default',
            vocabularyId: vocabId,
            boardId: cell.boardId,
            cellId: cell.id,
            labelSnapshot: 'want',
            action: ButtonAction.speak,
            source: UsageSource.touch,
            sessionId: 'session',
            occurredAt: 1000,
          ),
        );
  }

  /// What "the latest update reset everything on my son's iPad" looks like
  /// from inside the database.
  Future<void> wreck() async {
    await db.delete(db.buttons).go();
    await db
        .update(db.cells)
        .write(const CellsCompanion(state: Value(CellState.emptyReserved)));
    await db
        .update(db.boards)
        .write(const BoardsCompanion(bandMap: Value(null)));
    await (db.update(db.profiles)..where((p) => p.id.equals('default'))).write(
      const ProfilesCompanion(vocabLevel: Value(1)),
    );
    await db.delete(db.usageEvents).go();
  }

  Future<Snapshot> take() async {
    final attempt = await backup.takeSnapshot();
    expect(attempt.problem, null, reason: 'the snapshot itself failed');
    return attempt.snapshot!;
  }

  /// Opens a snapshot outside the app, the way a corrupted or older file would
  /// arrive.
  void editSnapshot(Snapshot snapshot, void Function(raw.Database) change) {
    final handle = raw.sqlite3.open(snapshot.path);
    try {
      change(handle);
    } finally {
      handle.close();
    }
  }

  group('taking one', () {
    test('writes into documents, never the cache', () async {
      final snapshot = await take();

      expect(
        p.dirname(snapshot.path),
        p.join(documents.path, BackupService.folder),
        reason:
            'a backup the OS is free to evict when space runs short is not a '
            'backup',
      );
      expect(File(snapshot.path).existsSync(), isTrue);
      expect(snapshot.bytes, greaterThan(0));
      expect(snapshot.schemaVersion, db.schemaVersion);
    });

    test('is a database, not an export', () async {
      // The distinction the whole feature turns on. An OBF export carries
      // words; this has to carry the reserved cells and the levels too.
      final snapshot = await take();
      final handle = raw.sqlite3.open(snapshot.path);
      addTearDown(handle.close);

      final reserved = handle.select(
        "SELECT count(*) AS c FROM cells WHERE state = 'emptyReserved'",
      );
      expect(reserved.first['c'], greaterThan(0));

      final levels = handle.select(
        'SELECT count(DISTINCT vocab_level) AS c FROM buttons',
      );
      expect(levels.first['c'], greaterThan(1));
    });

    test('does not throw when the database is unavailable', () async {
      // Nothing may stand between a person and speech, including a backup
      // that has gone wrong.
      await db.close();

      late SnapshotAttempt attempt;
      expect(
        () async => attempt = await backup.takeSnapshot(),
        returnsNormally,
      );
      attempt = await backup.takeSnapshot();

      expect(attempt.snapshot, null);
      expect(attempt.problem, isNotNull);
      expect(backup.lastAttempt?.problem, isNotNull);
    });

    test('refuses to overwrite one taken in the same millisecond', () async {
      final frozen = DateTime.utc(2026, 6, 1, 9, 30);
      final fixed = BackupService(
        db,
        documentsDirectory: () async => documents,
        clock: () => frozen,
      );

      final first = await fixed.takeSnapshot();
      expect(first.snapshot, isNotNull);
      final bytes = File(first.snapshot!.path).lengthSync();

      final second = await fixed.takeSnapshot();
      expect(second.snapshot, null);
      expect(second.problem, contains('already exists'));
      expect(
        second.problem,
        isNot(contains('Sqlite')),
        reason: 'a caregiver was shown a database error instead of a reason',
      );
      expect(
        File(first.snapshot!.path).lengthSync(),
        bytes,
        reason: 'the earlier backup was overwritten',
      );
    });
  });

  group('listing', () {
    test('is newest first and carries what a screen needs', () async {
      final first = await take();
      final second = await take();

      final found = await backup.snapshots();
      expect(found.map((s) => s.path), [second.path, first.path]);
      expect(found.first.takenAt, second.takenAt);
      expect(found.first.schemaVersion, db.schemaVersion);
      expect(found.first.bytes, File(second.path).lengthSync());
    });

    test('leaves out anything that is not a snapshot', () async {
      await take();

      final folder = Directory(p.join(documents.path, BackupService.folder));
      // Something a caregiver dropped in, and something named like a snapshot
      // that is not one. Offering either as a way back is offering a dead end.
      // The impostor is long enough to have a header, so it is rejected for
      // not being a database rather than for being short.
      File(p.join(folder.path, 'notes.txt')).writeAsStringSync('hello');
      File(p.join(folder.path, snapshotFileName(DateTime.utc(2020))))
          .writeAsStringSync('not a database at all, ${'x' * 200}');

      expect(await backup.snapshots(), hasLength(1));
    });

    test('is empty before anything has been taken', () async {
      expect(await backup.snapshots(), isEmpty);
    });
  });

  group('restoring', () {
    test('puts every cell, word, hidden flag and level back', () async {
      await personalise();
      final before = await everything();

      final snapshot = await take();
      await wreck();

      expect(await db.select(db.buttons).get(), isEmpty);

      final attempt = await backup.restore(snapshot);
      expect(attempt.problem, null);
      expect(attempt.restored, isTrue);

      final after = await everything();
      for (final table in before.keys) {
        expect(
          after[table],
          before[table],
          reason: '$table did not come back the way it went in',
        );
      }
    });

    test('brings back the things an export would have dropped', () async {
      await personalise();
      final hidden = (await db.select(db.buttons).get()).firstWhere(
        (b) => b.hidden,
      );
      final reserved = (await db.select(db.cells).get())
          .where((c) => c.state == CellState.emptyReserved)
          .length;
      final bands = (await db.select(db.boards).get())
          .where((b) => b.bandMap != null)
          .length;

      // Otherwise the comparisons below hold nothing to nothing.
      expect(reserved, greaterThan(0));
      expect(bands, greaterThan(0));

      final snapshot = await take();
      await wreck();
      await backup.restore(snapshot);

      final back = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(hidden.id))).getSingle();
      expect(back.hidden, isTrue, reason: 'a hidden word came back visible');
      expect(back.vocabLevel, 4, reason: 'the level it is drawn at was lost');

      expect(
        (await db.select(db.cells).get())
            .where((c) => c.state == CellState.emptyReserved)
            .length,
        reserved,
        reason: 'reserved locations are what personal vocabulary grows into',
      );
      expect(
        (await db.select(db.boards).get())
            .where((b) => b.bandMap != null)
            .length,
        bands,
        reason: 'the grid has nothing to name its regions from',
      );
      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals('default'))).getSingle();
      expect(profile.vocabLevel, 3);
      expect(await db.select(db.usageEvents).get(), hasLength(1));
    });

    test('what the talk screen is watching refreshes', () async {
      final snapshot = await take();
      await wreck();

      var emissions = 0;
      final sub = db.select(db.buttons).watch().listen((_) => emissions++);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      emissions = 0;

      await backup.restore(snapshot);
      await pumpEventQueue();

      expect(
        emissions,
        greaterThan(0),
        reason: 'the board on screen would still be the flattened one',
      );
    });

    test('the log keeps working afterwards', () async {
      await personalise();
      final snapshot = await take();
      await db.delete(db.usageEvents).go();
      await backup.restore(snapshot);

      final cell = (await db.select(db.cells).get()).first;
      await db
          .into(db.usageEvents)
          .insert(
            UsageEventsCompanion.insert(
              deviceId: 'tablet',
              profileId: 'default',
              vocabularyId: vocabId,
              boardId: cell.boardId,
              cellId: cell.id,
              labelSnapshot: 'more',
              action: ButtonAction.speak,
              source: UsageSource.touch,
              sessionId: 'session',
              occurredAt: 2000,
            ),
          );

      expect(await db.select(db.usageEvents).get(), hasLength(2));
    });
  });

  group('a restore that cannot finish', () {
    test('leaves the board exactly as it was', () async {
      final snapshot = await take();

      // A snapshot that passes every check that can be made without touching
      // the board, and fails on the last table copied — after every word and
      // every location has already been written back. That is the failure
      // worth testing: one that stops early is obvious, and one that stops at
      // the end leaves a board that looks restored and is not.
      editSnapshot(
        snapshot,
        (handle) => handle.execute('DROP TABLE sync_meta'),
      );

      await wreck();
      final before = await everything();

      final attempt = await backup.restore(snapshot);
      expect(attempt.restored, isFalse);
      expect(attempt.problem, isNotNull);

      final after = await everything();
      for (final table in before.keys) {
        expect(
          after[table],
          before[table],
          reason: '$table was left half-restored',
        );
      }
    });

    test('a damaged snapshot is refused before anything is deleted', () async {
      final snapshot = await take();

      editSnapshot(
        snapshot,
        (handle) => handle.execute(
          "INSERT INTO buttons (id, cell_id, vocabulary_id, label, message, "
          "action, created_at, updated_at) VALUES ('orphan', 'nowhere', "
          "'$vocabId', 'x', 'x', 'speak', 1, 1)",
        ),
      );

      final before = await everything();
      final attempt = await backup.restore(snapshot);

      expect(attempt.restored, isFalse);
      expect(attempt.problem, contains('damaged'));
      expect(await everything(), before);
    });

    test('a snapshot from a newer version is refused with a reason', () async {
      final snapshot = await take();
      editSnapshot(snapshot, (handle) => handle.userVersion = 99);

      final before = await everything();
      final attempt = await backup.restore((
        path: snapshot.path,
        takenAt: snapshot.takenAt,
        bytes: snapshot.bytes,
        schemaVersion: 99,
      ));

      expect(attempt.restored, isFalse);
      expect(attempt.problem, contains('newer version'));
      expect(attempt.problem, contains('99'));
      expect(
        await everything(),
        before,
        reason: 'a snapshot it cannot read was half-applied anyway',
      );
    });

    test('a file that is not a database is refused', () async {
      final folder = Directory(p.join(documents.path, BackupService.folder));
      await folder.create(recursive: true);
      final path = p.join(folder.path, snapshotFileName(DateTime.utc(2025)));
      File(path).writeAsStringSync('this is not a database, ${'x' * 200}');

      final before = await everything();
      final attempt = await backup.restore((
        path: path,
        takenAt: DateTime.utc(2025),
        bytes: 22,
        schemaVersion: 6,
      ));

      expect(attempt.restored, isFalse);
      expect(attempt.problem, isNotNull);
      expect(await everything(), before);
    });

    test('does not block the next attempt', () async {
      // A caregiver who picks the wrong file and then the right one. If the
      // failed attempt left the snapshot attached to the live connection, the
      // one that would have worked is refused too.
      await personalise();
      final good = await take();
      final damaged = await take();
      editSnapshot(damaged, (handle) => handle.execute('DROP TABLE cells'));

      expect((await backup.restore(damaged)).restored, isFalse);

      await wreck();
      final attempt = await backup.restore(good);
      expect(attempt.problem, null);
      expect(attempt.restored, isTrue);
      expect(await db.select(db.buttons).get(), isNotEmpty);
    });

    test('a snapshot that has been deleted is refused', () async {
      final snapshot = await take();
      File(snapshot.path).deleteSync();

      final attempt = await backup.restore(snapshot);
      expect(attempt.restored, isFalse);
      expect(attempt.problem, isNotNull);
    });
  });

  group('a snapshot from before an update', () {
    /// Winds a snapshot back to schema 5, which had no `boards.band_map`.
    void makeItOlder(Snapshot snapshot) {
      editSnapshot(snapshot, (handle) {
        handle.execute('ALTER TABLE boards DROP COLUMN band_map');
        handle.userVersion = 5;
      });
    }

    test('is brought forward and restored', () async {
      // The case the feature exists for: the update that flattened the board
      // also moved the schema on, so the way back is an older file.
      await personalise();
      final snapshot = await take();
      makeItOlder(snapshot);

      await wreck();
      final attempt = await backup.restore(snapshot);

      expect(attempt.problem, null);
      expect(attempt.restored, isTrue);
      expect(await db.select(db.buttons).get(), isNotEmpty);
      expect(
        (await db.select(db.buttons).get()).where((b) => b.hidden),
        isNotEmpty,
        reason: 'a hidden word was lost crossing the version boundary',
      );
      // Version 5 never recorded band maps, so there are none to come back.
      for (final board in await db.select(db.boards).get()) {
        expect(board.bandMap, null);
      }
    });

    test('is left exactly as it was found', () async {
      final snapshot = await take();
      makeItOlder(snapshot);
      final bytes = File(snapshot.path).lengthSync();

      await backup.restore(snapshot);

      expect(await snapshotSchemaVersion(File(snapshot.path)), 5);
      expect(File(snapshot.path).lengthSync(), bytes);
      expect(
        Directory(p.join(documents.path, BackupService.folder))
            .listSync()
            .map((e) => p.basename(e.path)),
        [p.basename(snapshot.path)],
        reason: 'a working copy was left behind on the device',
      );
    });
  });

  group('retention', () {
    test('keeps the newest and deletes the oldest', () async {
      final taken = <Snapshot>[];
      for (var i = 0; i < BackupService.keep + 3; i++) {
        taken.add(await take());
      }

      final kept = await backup.snapshots();
      expect(kept, hasLength(BackupService.keep));
      expect(
        kept.map((s) => s.path),
        taken.reversed.take(BackupService.keep).map((s) => s.path),
        reason: 'retention did not delete the oldest, and only the oldest',
      );

      for (final gone in taken.take(3)) {
        expect(File(gone.path).existsSync(), isFalse);
      }
    });

    test('deletes nothing while there is room', () async {
      final taken = <Snapshot>[];
      for (var i = 0; i < BackupService.keep; i++) {
        taken.add(await take());
      }

      expect(await backup.snapshots(), hasLength(BackupService.keep));
      for (final snapshot in taken) {
        expect(File(snapshot.path).existsSync(), isTrue);
      }
    });

    test('spares one snapshot when asked to', () async {
      final taken = <Snapshot>[];
      for (var i = 0; i < BackupService.keep; i++) {
        taken.add(await take());
      }
      final oldest = taken.first;

      final attempt = await backup.takeSnapshot(doNotPrune: oldest.path);
      expect(attempt.problem, null);

      expect(
        File(oldest.path).existsSync(),
        isTrue,
        reason: 'the snapshot the caller asked to keep was pruned anyway',
      );
      expect(await backup.snapshots(), hasLength(BackupService.keep + 1));
    });
  });

  group('restoring with a copy of what it replaces', () {
    test('takes the copy before it replaces anything', () async {
      await personalise();
      final personalised = await everything();
      final before = await take();
      await wreck();

      final result = await restoreKeepingACopy(backup, before);
      expect(result.restored, isTrue);
      expect(await everything(), personalised);

      // Two: the one restored from, and the copy of the wrecked board.
      final all = await backup.snapshots();
      expect(all, hasLength(2));

      // The newer of the two holds the board as it stood a moment before the
      // restore — the wrecked one — rather than the board just put back. That
      // is the whole point of taking it.
      expect((await backup.restore(all.first)).restored, isTrue);
      expect(await db.select(db.buttons).get(), isEmpty);

      // And the one restored from is still there to go back to.
      expect((await backup.restore(before)).restored, isTrue);
      expect(await everything(), personalised);
    });

    test('spares the one being restored from', () async {
      // At capacity, the copy would otherwise push the oldest out — and the
      // oldest is exactly what a caregiver reaching that far back has chosen.
      final taken = <Snapshot>[];
      for (var i = 0; i < BackupService.keep; i++) {
        taken.add(await take());
      }
      final oldest = taken.first;

      final result = await restoreKeepingACopy(backup, oldest);

      expect(result.restored, isTrue);
      expect(File(oldest.path).existsSync(), isTrue);
    });

    test('a copy that fails does not refuse the restore', () async {
      // A caregiver asking for their board back is not told no because a
      // backup would not write. That is the failure this feature is against.
      final before = await take();
      await wreck();

      final blocked = BackupService(
        db,
        documentsDirectory: () async =>
            throw const FileSystemException('no room'),
        clock: clock,
      );

      final result = await restoreKeepingACopy(blocked, before);

      expect(result.restored, isTrue);
      expect(
        blocked.lastAttempt!.problem,
        isNotNull,
        reason: 'the copy failed silently and left no record of it',
      );
    });
  });

  group('snapshot names', () {
    test('round-trip the instant they were taken', () {
      final at = DateTime.utc(2026, 3, 9, 4, 5, 6, 78);
      expect(snapshotTakenAt(snapshotFileName(at)), at);
    });

    test('sort into the order they were taken', () {
      final names = [
        snapshotFileName(DateTime.utc(2026, 1, 2)),
        snapshotFileName(DateTime.utc(2025, 12, 31)),
        snapshotFileName(DateTime.utc(2026, 1, 1, 0, 0, 0, 500)),
      ]..sort();

      expect(names.map(snapshotTakenAt), [
        DateTime.utc(2025, 12, 31),
        DateTime.utc(2026, 1, 1, 0, 0, 0, 500),
        DateTime.utc(2026, 1, 2),
      ]);
    });

    test('are not claimed by anything else in the folder', () {
      expect(snapshotTakenAt('notes.txt'), null);
      expect(snapshotTakenAt('wordbridge-nonsense.db'), null);
      expect(snapshotTakenAt('wordbridge-2026-01-01.db'), null);
      expect(snapshotTakenAt('wordbridge-20260101TXX0000000Z.db'), null);
    });
  });
}
