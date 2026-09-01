import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/backup/backup_service.dart';
import 'package:wordbridge/features/backup/snapshot.dart';
import 'package:wordbridge/features/caregiver/backups_screen.dart';

/// The screen a caregiver reaches for on the day something went wrong.
///
/// Whether a restore actually returns the board is `backup_test.dart`'s
/// question, against the real service and a real folder. This one is about
/// whether a person can find their way back through it: that the screen says
/// when the last backup was, that it says so when there has never been one,
/// and that agreeing to a restore is a decision made after being told what it
/// replaces rather than a tap.
///
/// The snapshots are held in memory rather than on disk, and not for speed. A
/// widget test runs on a fake clock, and a real folder read started inside one
/// never comes back — the test hangs at teardown waiting for it. So the disk
/// is somewhere else, and what is under test here is what the caregiver is
/// shown and what their answer sets off.
void main() {
  late WordbridgeDatabase db;
  late _Backups backup;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    backup = _Backups(db);
  });

  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupsScreen(db: db, backup: backup),
      ),
    );
    await tester.pumpAndSettle();
  }

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

  testWidgets('says so when there has never been a backup', (tester) async {
    await open(tester);

    expect(find.text('Never backed up'), findsOneWidget);
    expect(find.text('No backups yet'), findsOneWidget);
  });

  testWidgets('names the day and time of the most recent one', (tester) async {
    backup.kept = [_snapshotAt(DateTime.utc(2026, 8, 3, 14, 22))];
    await open(tester);

    final when = snapshotWhen(DateTime.utc(2026, 8, 3, 14, 22));
    expect(find.text('Last backed up $when'), findsOneWidget);
    expect(find.text(when), findsOneWidget, reason: 'and again in the list');
  });

  testWidgets('backing up now puts one in the list', (tester) async {
    await open(tester);
    expect(find.text('Never backed up'), findsOneWidget);

    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();

    expect(backup.taken, hasLength(1));
    expect(find.text('Never backed up'), findsNothing);
  });

  testWidgets('a backup that will not write says why', (tester) async {
    backup.problem = 'no room on this device';
    await open(tester);

    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no room on this device'), findsOneWidget);
  });

  testWidgets('a folder that cannot be read is reported, not thrown', (
    tester,
  ) async {
    // The worst position this screen has to handle. Throwing here would put
    // the fallback board over the one place that could explain it.
    backup.unreadable = true;
    await open(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('could not be read'), findsOneWidget);
  });

  group('choosing a backup', () {
    /// Gets as far as the question, which is where every one of these starts.
    Future<void> askToRestore(WidgetTester tester) async {
      backup.kept = [_snapshotAt(DateTime.utc(2026, 8, 3, 14, 22))];
      await addWord('biscuit');
      await open(tester);

      await tester.tap(find.byIcon(Icons.restore));
      await tester.pumpAndSettle();
    }

    testWidgets('says what it would replace before doing it', (tester) async {
      await askToRestore(tester);

      expect(find.textContaining('will be replaced'), findsOneWidget);
      expect(
        find.textContaining('goes with it'),
        findsOneWidget,
        reason: 'the cost of the restore is not stated',
      );
      expect(
        backup.restored,
        isEmpty,
        reason: 'the board was replaced while the caregiver was being asked',
      );
    });

    testWidgets('backing out of the question changes nothing', (tester) async {
      await askToRestore(tester);

      await tester.tap(find.text('Leave the board as it is'));
      await tester.pumpAndSettle();

      expect(backup.restored, isEmpty);
      expect(backup.taken, isEmpty, reason: 'a copy was taken for nothing');
    });

    testWidgets('agreeing puts that one back', (tester) async {
      await askToRestore(tester);

      await tester.tap(find.text('Put this board back'));
      await tester.pumpAndSettle();

      expect(backup.restored.single.takenAt, DateTime.utc(2026, 8, 3, 14, 22));
      expect(find.textContaining('back the way it was'), findsOneWidget);
    });

    testWidgets('keeps a copy of what it replaced, first', (tester) async {
      // The thing that makes trying a date safe. A caregiver who picks the
      // wrong one has somewhere to go, and it is the board they had a moment
      // ago rather than a week ago.
      await askToRestore(tester);

      await tester.tap(find.text('Put this board back'));
      await tester.pumpAndSettle();

      expect(backup.order, ['took', 'restored']);
      expect(
        backup.taken.single,
        backup.kept.last.path,
        reason:
            'the snapshot being restored from was left open to the prune, so '
            'a full device would drop the one the caregiver chose',
      );
    });

    testWidgets('a restore that is refused says why', (tester) async {
      backup.refuseRestore = 'That backup is no longer on this device.';
      await askToRestore(tester);

      await tester.tap(find.text('Put this board back'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no longer on this device'), findsOneWidget);
      expect(find.textContaining('back the way it was'), findsNothing);
    });
  });

  /// §4.41 part 4b. What §4.42 asked for as a Save button, without
  /// re-introducing the uncommitted work §1's four parents lost.
  group('putting the board back the way it was found', () {
    const row = 'Restore to when settings were opened';

    testWidgets('is not offered where no copy was taken', (tester) async {
      await open(tester);

      expect(find.text(row), findsNothing);
    });

    testWidgets('and names the moment caregiver mode was opened', (
      tester,
    ) async {
      backup.session = _snapshotAt(DateTime.utc(2026, 8, 30, 10, 15));
      await open(tester);

      expect(find.text(row), findsOneWidget);
      expect(
        find.textContaining(snapshotWhen(backup.session!.takenAt)),
        findsWidgets,
      );
    });

    testWidgets('says what it costs before it does it', (tester) async {
      backup.session = _snapshotAt(DateTime.utc(2026, 8, 30, 10, 15));
      await open(tester);

      await tester.tap(find.text(row));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('goes back to how it stood'), findsOneWidget);

      // And backing out of the question changes nothing.
      await tester.tap(find.text('Keep the changes'));
      await tester.pumpAndSettle();
      expect(backup.restored, isEmpty);
    });

    testWidgets('copies the board before replacing it', (tester) async {
      // The same rule as every other restore: a caregiver who puts it back and
      // then wants their changes has one way left, and this is it.
      backup.session = _snapshotAt(DateTime.utc(2026, 8, 30, 10, 15));
      await open(tester);

      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Put it back'));
      await tester.pumpAndSettle();

      expect(backup.order, ['took', 'restored']);
      expect(backup.restored.single.takenAt, backup.session!.takenAt);
      expect(
        backup.taken.single,
        backup.session!.path,
        reason: 'the copy pushed the session snapshot out of the ring',
      );
    });

    testWidgets('and a refusal is read out rather than swallowed', (
      tester,
    ) async {
      backup.session = _snapshotAt(DateTime.utc(2026, 8, 30, 10, 15));
      backup.refuseRestore = 'That copy is no longer on this device.';
      await open(tester);

      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Put it back'));
      await tester.pumpAndSettle();

      expect(
        find.text('That copy is no longer on this device.'),
        findsOneWidget,
      );
    });
  });

  group('what the caregiver is told', () {
    test('the count is words and boards, not rows', () async {
      final board = await describeBoard(db);

      expect(board.words, greaterThan(0));
      expect(board.boards, greaterThan(1));

      final buttons = await db.select(db.buttons).get();
      expect(
        board.words,
        lessThan(buttons.length),
        reason: 'the system keys were counted as words the caregiver added',
      );
    });

    test('the warning names both, and the way back', () {
      final text = restoreWarning(
        board: (words: 412, boards: 8),
        snapshot: _snapshotAt(DateTime.utc(2026, 8, 3, 14, 22)),
      );

      expect(text, contains('412 words'));
      expect(text, contains('8 boards'));
      expect(text, contains('saved first'));
    });

    test('one of a thing is not "1 words"', () {
      final text = restoreWarning(
        board: (words: 1, boards: 1),
        snapshot: _snapshotAt(DateTime.utc(2026, 8, 3)),
      );

      expect(text, contains('1 word across 1 board'));
    });

    test('the time shown is the caregiver\'s, not UTC', () {
      // Stored in UTC so the filename sorts and survives a round trip through
      // a file manager. Shown local, because a date they do not recognize is
      // one they cannot choose by.
      final at = DateTime.utc(2026, 8, 3, 14, 22);
      final local = at.toLocal();

      expect(
        snapshotWhen(at),
        '${local.day} Aug ${local.year}, '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}',
      );
    });

    test('a size is readable rather than exact', () {
      expect(snapshotSize(512), '512 bytes');
      expect(snapshotSize(4096), '4 KB');
      expect(snapshotSize(3 * 1024 * 1024), '3.0 MB');
    });

    test('"never backed up" is a sentence, not an empty list', () {
      expect(lastBackedUp(const []), 'Never backed up');
      expect(
        lastBackedUp([_snapshotAt(DateTime.utc(2026, 8, 3, 9))]),
        startsWith('Last backed up 3 Aug 2026'),
      );
    });
  });
}

Snapshot _snapshotAt(DateTime takenAt) => (
  path: 'backup-${takenAt.toIso8601String()}.db',
  takenAt: takenAt,
  bytes: 2048,
  schemaVersion: 6,
);

/// The backups, without a disk under them.
///
/// It records what it was asked to do and in what order, which is the part the
/// screen is responsible for. What a restore does to a board is tested against
/// the real service in `backup_test.dart`.
class _Backups extends BackupService {
  _Backups(super.db);

  List<Snapshot> kept = [];

  /// Every `doNotPrune` this was asked to spare, in order.
  final List<String?> taken = [];
  final List<Snapshot> restored = [];
  final List<String> order = [];

  /// A snapshot that will not write, reported rather than thrown.
  String? problem;

  /// A folder that cannot be listed at all.
  bool unreadable = false;

  String? refuseRestore;

  /// The copy caregiver mode takes on the way in, or null where there is none.
  Snapshot? session;

  @override
  Future<Snapshot?> sessionSnapshot() async => session;

  @override
  Future<SnapshotAttempt> takeSessionSnapshot() async {
    order.add('took the session copy');
    return (snapshot: session, problem: null);
  }

  @override
  Future<List<Snapshot>> snapshots() async {
    if (unreadable) throw const FileSystemException('no such directory');
    return kept;
  }

  @override
  Future<SnapshotAttempt> takeSnapshot({String? doNotPrune}) async {
    taken.add(doNotPrune);
    order.add('took');
    if (problem != null) return (snapshot: null, problem: problem);

    final snapshot = _snapshotAt(DateTime.utc(2026, 8, 4, 9));
    kept = [snapshot, ...kept];
    return (snapshot: snapshot, problem: null);
  }

  @override
  Future<RestoreAttempt> restore(Snapshot snapshot) async {
    restored.add(snapshot);
    order.add('restored');
    if (refuseRestore != null) {
      return (restored: false, problem: refuseRestore);
    }
    return (restored: true, problem: null);
  }
}
