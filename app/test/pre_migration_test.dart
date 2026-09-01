import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/backup/backup_service.dart';
import 'package:wordbridge/features/backup/pre_migration.dart';
import 'package:wordbridge/features/backup/snapshot.dart';

/// The launch after an update, which is the moment the whole backup feature
/// exists for.
///
/// *"Latest update reset everything on my sons ipad."* A backup taken after the
/// migration has already run is a backup of the flattened board. So what is
/// under test here is the ordering: a copy exists before drift is allowed near
/// the file, it holds what the file held, and no other launch pays for it.
void main() {
  late Directory documents;
  late Directory home;
  late File file;
  late WordbridgeDatabase db;
  late BackupService backup;

  late DateTime tick;
  DateTime clock() {
    tick = tick.add(const Duration(seconds: 1));
    return tick;
  }

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('wordbridge-premigrate');
    home = await Directory.systemTemp.createTemp('wordbridge-db');
    file = File(p.join(home.path, 'wordbridge.sqlite'));
    tick = DateTime.utc(2026, 1, 1);

    // Stands in for the live app database. Nothing in these tests queries it;
    // it is here because the service takes one, and because `snapshotFile`
    // must not be reaching for it.
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    backup = BackupService(
      db,
      documentsDirectory: () async => documents,
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
    for (final dir in [documents, home]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  /// A device's database as it stands before an update: a real SQLite file
  /// carrying a real board, stamped with the version that wrote it.
  ///
  /// Built with raw sqlite3 rather than by opening it with drift, because
  /// opening it with drift is the thing that must not have happened yet.
  void writeDeviceDatabase({required int version, String word = 'want'}) {
    final handle = raw.sqlite3.open(file.path);
    try {
      handle.execute('CREATE TABLE IF NOT EXISTS buttons (label TEXT)');
      handle.execute('INSERT INTO buttons (label) VALUES (?)', [word]);
      handle.execute('PRAGMA user_version = $version');
    } finally {
      handle.close();
    }
  }

  Future<PreMigrationResult> check({int appVersion = 6}) =>
      snapshotBeforeMigration(
        database: () async => file,
        appVersion: appVersion,
        backup: backup,
      );

  Future<List<String>> snapshotFiles() async => [
    for (final e in documents.listSync(recursive: true))
      if (e is File && snapshotTakenAt(e.path) != null) e.path,
  ];

  group('a database older than the app about to open it', () {
    test('is copied before anything migrates it', () async {
      writeDeviceDatabase(version: 5);

      final result = await check();

      expect(result.outcome, PreMigrationOutcome.snapshotTaken);
      expect(result.attempt!.problem, null);
      expect(await snapshotFiles(), hasLength(1));
    });

    test('the copy is the board as it was, at the version it was', () async {
      // The point of the whole thing. A copy that carries the post-update
      // board, or that loses what was in it, is not a way back.
      writeDeviceDatabase(version: 5, word: 'biscuit');

      final result = await check();
      final snapshot = result.attempt!.snapshot!;

      expect(snapshot.schemaVersion, 5);

      final handle = raw.sqlite3.open(snapshot.path);
      addTearDown(handle.close);
      expect(
        handle.select('SELECT label FROM buttons').map((r) => r['label']),
        ['biscuit'],
        reason: 'the snapshot did not carry what was on the device',
      );
    });

    test('leaves the device database exactly where it was', () async {
      // A copy, not a move. The app is about to open this file.
      writeDeviceDatabase(version: 5);
      final before = await file.readAsBytes();

      await check();

      expect(file.existsSync(), isTrue);
      expect(await file.readAsBytes(), before);
      expect(await snapshotSchemaVersion(file), 5);
    });

    test('is written by opening it, not by copying its bytes', () async {
      // The distinction the design turns on. A plain byte copy carries a
      // database exactly as it sits, including whatever a run that was killed
      // mid-write left behind; opening it is what performs the recovery. That
      // is not directly observable from inside one process, but the other
      // thing opening it does is: `VACUUM INTO` rebuilds the file, so a source
      // carrying freed pages produces a smaller snapshot than itself. A copy
      // could not.
      final handle = raw.sqlite3.open(file.path);
      handle.execute('CREATE TABLE buttons (label TEXT)');
      for (var i = 0; i < 2000; i++) {
        handle.execute('INSERT INTO buttons (label) VALUES (?)', ['word $i']);
      }
      handle.execute('DELETE FROM buttons WHERE rowid > 5');
      handle.execute('PRAGMA user_version = 5');
      handle.close();

      final sourceBytes = await file.length();
      final result = await check();
      final snapshot = result.attempt!.snapshot!;

      expect(
        snapshot.bytes,
        lessThan(sourceBytes),
        reason: 'the snapshot is the same size as the file, so it was copied',
      );

      final reopened = raw.sqlite3.open(snapshot.path);
      addTearDown(reopened.close);
      expect(reopened.select('SELECT label FROM buttons'), hasLength(5));
    });

    test('is unbothered by a stray journal beside the database', () async {
      writeDeviceDatabase(version: 5);
      await File('${file.path}-journal').writeAsBytes(List.filled(512, 0));

      final result = await check();

      expect(result.outcome, PreMigrationOutcome.snapshotTaken);
      expect(result.attempt!.problem, null);
    });
  });

  group('against a real board on a real file', () {
    /// A device's database as drift actually writes it: the whole board, in
    /// the file the app opens, closed the way a previous launch left it.
    Future<void> writeRealBoard() async {
      final device = WordbridgeDatabase.forTesting(NativeDatabase(file));
      await seedCoreBoardSet(device, rows: 7, cols: 12);
      await device.close();
    }

    test('is left alone when the app has not moved on', () async {
      await writeRealBoard();
      expect(await snapshotSchemaVersion(file), db.schemaVersion);

      final result = await check(appVersion: db.schemaVersion);

      expect(result.outcome, PreMigrationOutcome.upToDate);
      expect(await snapshotFiles(), isEmpty);
    });

    test('is copied whole when the next version arrives', () async {
      // The release after this one, which is when the copy is taken. What has
      // to survive it is the board — not a file of the right size, the words
      // and the locations somebody has learned.
      await writeRealBoard();

      final result = await check(appVersion: db.schemaVersion + 1);
      expect(result.outcome, PreMigrationOutcome.snapshotTaken);

      final snapshot = result.attempt!.snapshot!;
      expect(snapshot.schemaVersion, db.schemaVersion);

      final copy = WordbridgeDatabase.forTesting(
        NativeDatabase(File(snapshot.path)),
      );
      addTearDown(copy.close);

      final live = WordbridgeDatabase.forTesting(NativeDatabase(file));
      addTearDown(live.close);

      expect(
        (await copy.select(copy.cells).get()).length,
        (await live.select(live.cells).get()).length,
        reason: 'the snapshot lost locations, which is the motor plan',
      );
      expect(
        {for (final b in await copy.select(copy.buttons).get()) b.label},
        {for (final b in await live.select(live.buttons).get()) b.label},
        reason: 'the snapshot lost words',
      );
    });
  });

  group('a launch with nothing to do', () {
    test('a database already at this version is left alone', () async {
      writeDeviceDatabase(version: 6);

      final result = await check();

      expect(result.outcome, PreMigrationOutcome.upToDate);
      expect(await snapshotFiles(), isEmpty);
    });

    test('the first launch of all has nothing to lose', () async {
      expect(file.existsSync(), isFalse, reason: 'the premise');

      final result = await check();

      expect(result.outcome, PreMigrationOutcome.firstLaunch);
      expect(await snapshotFiles(), isEmpty);
    });

    test('a file that is not a database is not guessed at', () async {
      await file.writeAsString('not a database');

      final result = await check();

      expect(result.outcome, PreMigrationOutcome.unrecognized);
      expect(await snapshotFiles(), isEmpty);
    });

    test('a database from a newer app is not copied either', () async {
      // Downgrade rather than upgrade. Drift will refuse the file; a snapshot
      // taken here would sit in the list claiming to be a way back from
      // something this app cannot read.
      writeDeviceDatabase(version: 9);

      final result = await check();

      expect(result.outcome, PreMigrationOutcome.upToDate);
      expect(await snapshotFiles(), isEmpty);
    });
  });

  group('a backup that cannot be taken', () {
    test('does not stop the app from starting', () async {
      // The rule the whole feature is under: a device that will not launch has
      // stopped being a communication device, and the backup is the thing
      // guarding against that, not a reason for it.
      final result = await snapshotBeforeMigration(
        database: () async => throw const FileSystemException('no documents'),
        appVersion: 6,
        backup: backup,
      );

      expect(result.outcome, PreMigrationOutcome.snapshotFailed);
      expect(result.attempt!.problem, isNotNull);
    });

    test('says so rather than reporting a snapshot it did not take', () async {
      writeDeviceDatabase(version: 5);

      // Somewhere to write it: the folder's path is taken by a file.
      final blocked = BackupService(
        db,
        documentsDirectory: () async => Directory(p.join(home.path, 'wall')),
        clock: clock,
      );
      await File(p.join(home.path, 'wall')).writeAsString('in the way');

      final result = await snapshotBeforeMigration(
        database: () async => file,
        appVersion: 6,
        backup: blocked,
      );

      expect(result.outcome, PreMigrationOutcome.snapshotFailed);
      expect(result.attempt!.snapshot, null);
      expect(result.attempt!.problem, isNotNull);
    });
  });
}
