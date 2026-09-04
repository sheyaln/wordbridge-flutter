import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/backup/backup_service.dart';
import 'package:wordbridge/features/backup/cloud_backup.dart';
import 'package:wordbridge/features/backup/cloud_destination.dart';
import 'package:wordbridge/features/backup/snapshot.dart';

/// Getting a board back after the tablet it was on is gone.
///
/// A local backup answers "the update flattened the board". It answers nothing
/// at all for the tablet that was dropped, lost or replaced, and that is the
/// same family losing the same months of work by a different route. So what is
/// under test here is that a copy in the family's own account is a real backup:
/// the identical database file, listed with a date, and restorable onto a
/// device that has never held it.
///
/// The three failures it exists against, in the order they cost the most:
///
///  * A copy that is not the board. The bytes in the account are compared with
///    the bytes on disk, and a download that arrives short is refused rather
///    than restored over a working board.
///  * A backup that stopped silently. Uploads happen at launch with nobody
///    watching, so a failure has to survive until somebody opens the screen.
///  * A mirror that runs the wrong way. A replacement tablet has no local
///    snapshots, and the copies in the account are the only board left; nothing
///    may delete them for not being on the device.
///
/// The account is faked whole. Nothing here signs in to anything, opens a
/// socket, or needs a platform to answer — a test that did could only run on
/// somebody's own machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late WordbridgeDatabase db;
  late BackupService backup;
  late _Account account;
  late CloudBackupService cloud;
  late String vocabId;

  /// Advances a second per call, so snapshots taken in one test are ordered
  /// without depending on how long a copy happens to take.
  late DateTime tick;
  DateTime clock() {
    tick = tick.add(const Duration(seconds: 1));
    return tick;
  }

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('wordbridge-cloud');
    tick = DateTime.utc(2026, 1, 1);
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    backup = BackupService(
      db,
      documentsDirectory: () async => documents,
      clock: clock,
    );
    account = _Account();
    cloud = CloudBackupService(
      backup: backup,
      store: CloudBackupStore(db),
      destination: account,
      clock: clock,
    );
    await cloud.turnOn();
  });

  tearDown(() async {
    await db.close();
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  /// A word a caregiver added, and would be devastated to lose twice.
  Future<void> addWord(String label) async {
    final cell = (await (db.select(
      db.cells,
    )..where((c) => c.state.equalsValue(CellState.emptyReserved))).get()).first;

    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: label,
    );
  }

  Future<bool> hasWord(String label) async => (await (db.select(
    db.buttons,
  )..where((b) => b.label.equals(label))).get()).isNotEmpty;

  /// Everything on this device forgotten, as it is on a replacement tablet.
  Future<void> loseTheTablet() async {
    for (final entry in Directory(
      p.join(documents.path, BackupService.folder),
    ).listSync()) {
      entry.deleteSync();
    }
  }

  group('the copy in the account', () {
    test('is the same file, byte for byte', () async {
      await addWord('trampoline');
      final attempt = await cloud.backUpNow();

      expect(attempt.snapshot, isNotNull);
      expect(attempt.copy, isNotNull);
      expect(
        account.files[attempt.copy!.name],
        File(attempt.snapshot!.path).readAsBytesSync(),
        reason: 'the account holds something other than the snapshot',
      );
    });

    test('is named the same, so its date survives the trip', () async {
      final attempt = await cloud.backUpNow();

      expect(
        snapshotTakenAt(attempt.copy!.name),
        attempt.snapshot!.takenAt,
        reason: 'a copy that loses its date cannot be chosen between',
      );
    });

    test('is not written again on the next run', () async {
      await cloud.backUpNow();
      final first = List.of(account.uploaded);

      await cloud.keepUpToDate();

      expect(account.uploaded, first);
    });

    test('carries up everything the device already had, not just one', () async {
      // Switching this on for the first time is somebody saying "keep what I
      // have safe", and their board's history is the five dates already on the
      // tablet.
      await cloud.turnOff();
      for (var i = 0; i < 3; i++) {
        await backup.takeSnapshot();
      }

      await cloud.turnOn();
      await cloud.keepUpToDate();

      expect(account.files, hasLength(3));
    });

    test('is never written when nobody has been asked', () async {
      final unasked = CloudBackupService(
        backup: backup,
        store: CloudBackupStore(db),
        destination: account,
        clock: clock,
      );
      await CloudBackupStore(db).forget();
      await (db.delete(
        db.appState,
      )..where((s) => s.key.equals(CloudBackupStore.answerKey))).go();

      expect(await unasked.keepUpToDate(), isNull);
      expect(account.uploaded, isEmpty);
    });

    test('is never written when the answer was no', () async {
      await cloud.turnOff();

      expect(await cloud.keepUpToDate(), isNull);
      expect(account.uploaded, isEmpty);
    });
  });

  group('restoring onto a tablet that never held the board', () {
    test('brings the words back', () async {
      await addWord('trampoline');
      await cloud.backUpNow();

      await (db.delete(
        db.buttons,
      )..where((b) => b.label.equals('trampoline'))).go();
      await loseTheTablet();
      expect(await hasWord('trampoline'), isFalse);

      final copies = await cloud.list();
      expect(copies, hasLength(1));

      final result = await cloud.restore(copies.single);

      expect(result.problem, isNull);
      expect(result.restored, isTrue);
      expect(await hasWord('trampoline'), isTrue);
    });

    test('keeps a copy of the board it replaced', () async {
      await cloud.backUpNow();
      await addWord('afterwards');
      await loseTheTablet();

      await cloud.restore((await cloud.list()).single);

      final kept = await backup.snapshots();
      expect(
        kept.length,
        greaterThan(1),
        reason: 'the board that was there is not recoverable',
      );
    });

    test('leaves the fetched copy on the device to be reused', () async {
      await cloud.backUpNow();
      final copy = (await cloud.list()).single;
      await loseTheTablet();

      await cloud.restore(copy);

      expect(
        (await backup.snapshots()).map((s) => p.basename(s.path)),
        contains(copy.name),
      );
    });

    test(
      'refuses one that arrived short, and leaves the board alone',
      () async {
        await addWord('trampoline');
        await cloud.backUpNow();
        await (db.delete(
          db.buttons,
        )..where((b) => b.label.equals('trampoline'))).go();
        await loseTheTablet();

        account.truncateDownloads = true;
        final result = await cloud.restore((await cloud.list()).single);

        expect(result.restored, isFalse);
        expect(result.problem, contains('Nothing has been changed'));
        expect(await hasWord('trampoline'), isFalse);
        expect(
          await backup.snapshots(),
          isEmpty,
          reason:
              'a file that is not a database was left to be found and trusted',
        );
      },
    );

    test('says so when the account refuses, rather than throwing', () async {
      await cloud.backUpNow();
      final copy = (await cloud.list()).single;
      account.reachable = false;

      final result = await cloud.restore(copy);

      expect(result.restored, isFalse);
      expect(result.problem, contains('iCloud'));
    });
  });

  group('a backup that stopped', () {
    test('is readable long after the launch that failed', () async {
      account.refuseUpload = const CloudRefusal('There is no room left.');
      await cloud.keepUpToDate();

      // A new service, as a screen opened days later would build.
      final later = CloudBackupService(
        backup: backup,
        store: CloudBackupStore(db),
        destination: account,
        clock: clock,
      );

      expect((await later.view()).problem, 'There is no room left.');
    });

    test('stops being reported once a copy gets through', () async {
      account.refuseUpload = const CloudRefusal('There is no room left.');
      await cloud.backUpNow();
      expect((await cloud.view()).problem, isNotNull);

      account.refuseUpload = null;
      await cloud.backUpNow();

      expect((await cloud.view()).problem, isNull);
    });

    test('does not stop the backup on the tablet', () async {
      account.refuseUpload = const CloudRefusal('There is no room left.');

      final attempt = await cloud.backUpNow();

      expect(attempt.snapshot, isNotNull);
      expect(attempt.problem, isNotNull);
      expect(await backup.snapshots(), hasLength(1));
    });

    test('names what to do when the tablet is not signed in', () async {
      account.reachable = false;

      final view = await cloud.view();

      expect(view.reachable, isFalse);
      expect(view.problem, contains('Sign in'));
    });
  });

  group('what the screen is told the date is', () {
    test('comes from the account itself when it can be read', () async {
      await cloud.backUpNow();
      final view = await cloud.view();

      expect(view.checked, isTrue);
      expect(view.lastCopiedUp, (await cloud.list()).single.takenAt);
    });

    test('falls back to what this device remembers, and says so', () async {
      await cloud.backUpNow();
      account.reachable = false;

      final view = await cloud.view();

      expect(view.checked, isFalse);
      expect(view.lastCopiedUp, isNotNull);
    });

    test('is nothing at all before the first copy', () async {
      expect((await cloud.view()).lastCopiedUp, isNull);
    });
  });

  group('how many are kept', () {
    test('the account is trimmed to the same number as the device', () async {
      for (var i = 0; i < BackupService.keep + 3; i++) {
        await cloud.backUpNow();
      }

      expect(account.files, hasLength(BackupService.keep));
      expect(await backup.snapshots(), hasLength(BackupService.keep));
    });

    test('nothing is removed for being missing from the device', () async {
      await cloud.backUpNow();
      final held = Set.of(account.files.keys);

      await loseTheTablet();
      await cloud.keepUpToDate();

      expect(
        account.files.keys,
        containsAll(held),
        reason: 'a replacement tablet wiped the only board left',
      );
      expect(account.deleted, isEmpty);
    });
  });

  group('the unattended copy at launch', () {
    test('takes a fresh one when the newest is a day old', () async {
      await cloud.backUpNow();
      tick = tick.add(CloudBackupService.between);

      final attempt = await cloud.keepUpToDate();

      expect(attempt?.snapshot, isNotNull);
      expect(await backup.snapshots(), hasLength(2));
    });

    test('leaves the ring alone when one was taken this morning', () async {
      await cloud.backUpNow();

      final attempt = await cloud.keepUpToDate();

      expect(attempt, isNull);
      expect(await backup.snapshots(), hasLength(1));
    });

    test('carries up the copy an update took, whatever the interval', () async {
      // What `snapshotBeforeMigration` leaves behind: a snapshot of the board
      // as it was before the update that is about to change it. It is the one
      // that matters most and it must not wait for a day to pass.
      await backup.takeSnapshot();
      expect(account.uploaded, isEmpty);

      await cloud.keepUpToDate();

      expect(account.uploaded, hasLength(1));
    });
  });

  group('turning it off', () {
    test('leaves what is already in the account where it is', () async {
      await cloud.backUpNow();

      await cloud.turnOff();

      expect(account.files, hasLength(1));
      expect(account.deleted, isEmpty);
    });

    test(
      'removing them is a separate act, and it empties the account',
      () async {
        await cloud.backUpNow();

        expect(await cloud.forget(), isNull);

        expect(account.files, isEmpty);
        expect(await cloud.on, isFalse);
        expect((await cloud.view()).lastCopiedUp, isNull);
      },
    );

    test('the board on the tablet survives it', () async {
      await addWord('trampoline');
      await cloud.backUpNow();

      await cloud.forget();

      expect(await hasWord('trampoline'), isTrue);
      expect(await backup.snapshots(), hasLength(1));
    });
  });

  group('switching it on', () {
    test('asks the platform for a folder only when there is not one', () async {
      await cloud.turnOn();
      expect(account.connects, 0, reason: 'a picker was opened for nothing');

      account.reachable = false;
      await cloud.turnOn();

      expect(account.connects, 1);
      expect(await cloud.on, isTrue);
    });

    test(
      'a picker somebody dismissed leaves the reason on the screen',
      () async {
        account.reachable = false;
        account.connectSucceeds = false;

        await cloud.turnOn();

        expect(
          await cloud.on,
          isTrue,
          reason: 'the answer they gave was thrown away',
        );
        expect((await cloud.view()).problem, isNotNull);
      },
    );

    test('nothing at launch ever opens one', () async {
      account.reachable = false;

      await cloud.keepUpToDate();

      expect(account.connects, 0);
    });
  });

  group('the platform side', () {
    const channel = MethodChannel(PlatformCloudDestination.channelName);
    late PlatformCloudDestination destination;

    void answer(Future<Object?>? Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    setUp(() {
      destination = PlatformCloudDestination(channel: channel, label: 'iCloud');
    });

    tearDown(() => answer(null));

    test('leaves alone anything in the folder that is not ours', () async {
      answer(
        (call) async => [
          {
            'id': '1',
            'name': snapshotFileName(DateTime.utc(2026, 8, 3)),
            'bytes': 10,
          },
          {'id': '2', 'name': 'holiday.jpg', 'bytes': 20},
        ],
      );

      final found = await destination.list();

      expect(found, hasLength(1));
      expect(found.single.takenAt, DateTime.utc(2026, 8, 3));
    });

    test('turns a platform code into a sentence a parent can act on', () async {
      answer((call) async => throw PlatformException(code: 'signIn'));

      await expectLater(
        destination.list(),
        throwsA(
          isA<CloudRefusal>().having(
            (e) => e.message,
            'message',
            contains('Sign in'),
          ),
        ),
      );
    });

    test(
      'a build with no cloud implementation says so, and does not crash',
      () async {
        answer(null);

        final status = await destination.status();

        expect(status.reachable, isFalse);
        expect(status.problem, PlatformCloudDestination.notAvailableHere);
      },
    );

    test('takes the name the platform actually filed it under', () async {
      // A document provider is free to rename a file it creates, and the date
      // a caregiver chooses by lives in that name.
      final asked = snapshotFileName(DateTime.utc(2026, 8, 3));
      answer((call) async => {'id': 'doc-1', 'name': asked, 'bytes': 2048});

      final written = await destination.upload(File('unused'), asked);

      expect(written.name, asked);
      expect(written.takenAt, DateTime.utc(2026, 8, 3));
    });

    test('and refuses one it filed under a name with no date in it', () async {
      answer(
        (call) async => {
          'id': 'doc-1',
          'name': 'wordbridge-20260803T000000000Z (1).db',
          'bytes': 2048,
        },
      );

      await expectLater(
        destination.upload(
          File('unused'),
          snapshotFileName(DateTime.utc(2026, 8, 3)),
        ),
        throwsA(isA<CloudRefusal>()),
        reason: 'a copy nothing will ever list was reported as a backup',
      );
    });

    test('and refuses a folder it was never given', () async {
      answer((call) async => throw PlatformException(code: 'folder'));

      final connected = await destination.connect();

      expect(connected.reachable, isFalse);
      expect(connected.problem, contains('No folder has been chosen'));
    });
  });
}

/// The family's account, with no account and no network under it.
///
/// It holds the bytes it was handed, which is the only way a test can check
/// that what is in the account is the board rather than something that was
/// named like it.
class _Account implements CloudDestination {
  @override
  final String label = 'iCloud';

  final Map<String, Uint8List> files = {};
  final List<String> uploaded = [];
  final List<String> deleted = [];

  bool reachable = true;
  CloudRefusal? refuseUpload;

  /// How many times somebody was asked for whatever the platform needs — a
  /// folder, on Android. Never at launch, only when the switch is thrown.
  int connects = 0;

  /// Whether being asked actually produces one.
  bool connectSucceeds = true;

  /// A download that stops halfway, which is what a tablet losing its
  /// connection mid-restore actually produces.
  bool truncateDownloads = false;

  void _reachable() {
    if (!reachable) throw CloudRefusal(notSignedIn(label));
  }

  @override
  Future<CloudStatus> status() async =>
      (reachable: reachable, problem: reachable ? null : notSignedIn(label));

  @override
  Future<CloudStatus> connect() async {
    connects++;
    if (connectSucceeds) reachable = true;
    return status();
  }

  @override
  Future<List<CloudBackup>> list() async {
    _reachable();

    final found = <CloudBackup>[];
    for (final entry in files.entries) {
      final takenAt = snapshotTakenAt(entry.key);
      if (takenAt == null) continue;
      found.add((
        id: entry.key,
        name: entry.key,
        takenAt: takenAt,
        bytes: entry.value.length,
      ));
    }

    found.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return found;
  }

  @override
  Future<CloudBackup> upload(File file, String name) async {
    _reachable();
    if (refuseUpload != null) throw refuseUpload!;

    final bytes = await file.readAsBytes();
    files[name] = bytes;
    uploaded.add(name);

    return (
      id: name,
      name: name,
      takenAt: snapshotTakenAt(name)!,
      bytes: bytes.length,
    );
  }

  @override
  Future<void> download(CloudBackup backup, File to) async {
    _reachable();

    final bytes = files[backup.id];
    if (bytes == null) throw const CloudRefusal('That backup is gone.');

    await to.writeAsBytes(
      truncateDownloads ? bytes.sublist(0, bytes.length ~/ 3) : bytes,
    );
  }

  @override
  Future<void> delete(CloudBackup backup) async {
    _reachable();
    files.remove(backup.id);
    deleted.add(backup.id);
  }
}
