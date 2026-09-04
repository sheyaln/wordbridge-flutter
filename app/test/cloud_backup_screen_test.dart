import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/backup/backup_service.dart';
import 'package:wordbridge/features/backup/cloud_backup.dart';
import 'package:wordbridge/features/backup/cloud_destination.dart';
import 'package:wordbridge/features/backup/snapshot.dart';
import 'package:wordbridge/features/caregiver/backups_screen.dart';
import 'package:wordbridge/features/profiles/profile_setup.dart';

/// Whether a family ever finds out that a copy off the tablet exists.
///
/// Whether the copy is real is `cloud_backup_test.dart`'s question, against the
/// service and a faked account. This one is about the two moments a person is
/// involved: the question at setup, and the screen they open on the day the
/// tablet is gone.
///
/// The failure it guards is the reported one — *"we lost months of custom
/// button and phrase building because we thought the iCloud backup would
/// protect us"*. Every part of that sentence is a screen's fault. So: the
/// question is put at setup rather than defaulted silently; the screen says
/// where a copy goes and who can read it in the same breath as offering it; a
/// date that could not be verified is not presented as one that was; a failure
/// from an unattended launch is read out rather than swallowed; and restoring
/// from the account states what it replaces first.
///
/// Nothing here reaches an account. Both the backups and the account are faked
/// whole — a widget test that touched either could only pass on one machine.
void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('the question at setup', () {
    /// A surface an iPad's worth of grid derives from, so the build button is
    /// reachable rather than disabled on an unusable geometry.
    Future<void> pumpSetup(
      WidgetTester tester, {
      bool isFirstRun = true,
    }) async {
      tester.view.physicalSize = const Size(2048, 1536);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileSetup(db: db, isFirstRun: isFirstRun),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> build(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Build the board'));
      await tester.tap(find.text('Build the board'));
      await tester.pumpAndSettle();
    }

    /// The setup list is long and built lazily, so a question further down it
    /// is not in the tree until somebody scrolls to it — as a caregiver does.
    ///
    /// Dragged by hand rather than through `scrollUntilVisible`, which takes
    /// the first Scrollable on the screen: on this one that is the name
    /// field's own, and it does not move.
    Future<void> reveal(WidgetTester tester, Finder target) async {
      for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    testWidgets('is put on the first run, already answered yes', (
      tester,
    ) async {
      await pumpSetup(tester);
      await reveal(tester, find.text('Keep a copy in ${cloudLabel()}'));

      expect(find.text('Keep a copy in ${cloudLabel()}'), findsOneWidget);
      expect(
        await CloudBackupStore(db).answer(),
        isNull,
        reason: 'the answer was stored before anybody gave one',
      );

      await build(tester);

      expect(await CloudBackupStore(db).answer(), isTrue);
    });

    testWidgets('takes no for an answer, and writes that down too', (
      tester,
    ) async {
      await pumpSetup(tester);
      await reveal(tester, find.text('Backups on this device only'));

      await tester.tap(find.text('Backups on this device only'));
      await tester.pumpAndSettle();
      await build(tester);

      expect(
        await CloudBackupStore(db).answer(),
        isFalse,
        reason: 'a no is not the same as never having been asked',
      );
    });

    testWidgets('says where the copy goes and who cannot read it', (
      tester,
    ) async {
      await pumpSetup(tester);
      await reveal(tester, find.text('Keep a copy in ${cloudLabel()}'));

      expect(
        find.textContaining('never receive it and cannot read it'),
        findsOneWidget,
      );

      await reveal(
        tester,
        find.textContaining('a record of what this person has said'),
      );
      expect(
        find.textContaining('a record of what this person has said'),
        findsOneWidget,
        reason: 'a copy of somebody\'s speech left the device unannounced',
      );
    });

    testWidgets('is not put again when a second person is added', (
      tester,
    ) async {
      // It belongs to the tablet rather than to the person, and a second
      // profile must not be able to answer it — including by accident, on a
      // screen where nobody was shown the question.
      await pumpSetup(tester, isFirstRun: false);
      await build(tester);

      expect(await CloudBackupStore(db).answer(), isNull);
    });
  });

  group('the backups screen', () {
    late _Backups backup;
    late _Cloud cloud;

    setUp(() {
      backup = _Backups(db);
      cloud = _Cloud(db);
    });

    Future<void> reveal(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(target, 120);
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, {bool withCloud = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BackupsScreen(
            db: db,
            backup: backup,
            cloud: withCloud ? cloud : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers the copy, and says where it goes', (tester) async {
      cloud.view_ = _view(on: false);
      await open(tester);

      expect(find.text('Keep a copy in iCloud'), findsOneWidget);
      expect(
        find.textContaining('we never receive them and cannot read them'),
        findsOneWidget,
      );
    });

    testWidgets('is not shown at all where nothing can reach an account', (
      tester,
    ) async {
      await open(tester, withCloud: false);

      expect(find.text('Keep a copy in iCloud'), findsNothing);
    });

    testWidgets('names the day the last copy went up', (tester) async {
      final at = DateTime.utc(2026, 8, 3, 14, 22);
      cloud.view_ = _view(lastCopiedUp: at, checked: true);
      await open(tester);

      expect(
        find.text('Last copied to iCloud ${snapshotWhen(at)}'),
        findsOneWidget,
      );
    });

    testWidgets('says so when nothing has ever gone up', (tester) async {
      cloud.view_ = _view();
      await open(tester);

      expect(find.text('Nothing copied to iCloud yet'), findsOneWidget);
    });

    testWidgets('does not present a date it could not check as one it did', (
      tester,
    ) async {
      final at = DateTime.utc(2026, 8, 3, 14, 22);
      cloud.view_ = _view(lastCopiedUp: at, reachable: false);
      await open(tester);

      expect(
        find.text(
          'Last copied to iCloud ${snapshotWhen(at)}, as far as this '
          'tablet knows',
        ),
        findsOneWidget,
      );
    });

    testWidgets('reads out a failure from a launch nobody was watching', (
      tester,
    ) async {
      cloud.view_ = _view(problem: 'There is no room left in iCloud.');
      await open(tester);

      expect(find.text('There is no room left in iCloud.'), findsOneWidget);
    });

    testWidgets('turning it on copies up there and then', (tester) async {
      cloud.view_ = _view(on: false);
      await open(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(cloud.order, ['turned on', 'copied up']);
    });

    testWidgets('turning it off does not touch what is in the account', (
      tester,
    ) async {
      cloud.view_ = _view(backups: [_copyAt(DateTime.utc(2026, 8, 3, 14, 22))]);
      await open(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(cloud.order, ['turned off']);
      expect(cloud.forgotten, isFalse);
    });

    group('restoring from the account', () {
      final at = DateTime.utc(2026, 8, 3, 14, 22);

      Future<void> tapTheCopy(WidgetTester tester) async {
        cloud.view_ = _view(backups: [_copyAt(at)]);
        await open(tester);

        await reveal(tester, find.byIcon(Icons.cloud_download_outlined));
        await tester.tap(find.byIcon(Icons.cloud_download_outlined));
        await tester.pumpAndSettle();
      }

      testWidgets('states what it would replace, and where it came from', (
        tester,
      ) async {
        await tapTheCopy(tester);

        expect(
          find.textContaining('will be replaced by the copy in iCloud'),
          findsOneWidget,
        );
        expect(
          find.textContaining('saved on this device first'),
          findsOneWidget,
        );
        expect(cloud.restored, isEmpty, reason: 'it restored before asking');
      });

      testWidgets('and leaves the board alone if they back out', (
        tester,
      ) async {
        await tapTheCopy(tester);

        await tester.tap(find.text('Leave the board as it is'));
        await tester.pumpAndSettle();

        expect(cloud.restored, isEmpty);
      });

      testWidgets('goes ahead once they have agreed', (tester) async {
        await tapTheCopy(tester);

        await tester.tap(find.text('Put this board back'));
        await tester.pumpAndSettle();

        expect(cloud.restored.single.takenAt, at);
      });

      testWidgets('a refusal is read out rather than swallowed', (
        tester,
      ) async {
        cloud.refuseRestore = 'That backup is no longer in iCloud.';
        await tapTheCopy(tester);

        await tester.tap(find.text('Put this board back'));
        await tester.pumpAndSettle();

        expect(
          find.text('That backup is no longer in iCloud.'),
          findsOneWidget,
        );
      });
    });

    group('taking the copies back out', () {
      Future<void> tapRemove(WidgetTester tester) async {
        cloud.view_ = _view(
          backups: [_copyAt(DateTime.utc(2026, 8, 3, 14, 22))],
        );
        await open(tester);

        await reveal(tester, find.text('Remove every copy from iCloud'));
        await tester.tap(find.text('Remove every copy from iCloud'));
        await tester.pumpAndSettle();
      }

      testWidgets('asks first, and says what survives it', (tester) async {
        await tapRemove(tester);

        expect(
          find.textContaining(
            'The board on this device and the backups on '
            'this device are untouched.',
          ),
          findsOneWidget,
        );
        expect(cloud.forgotten, isFalse);
      });

      testWidgets('empties the account once agreed', (tester) async {
        await tapRemove(tester);

        await tester.tap(find.text('Delete them'));
        await tester.pumpAndSettle();

        expect(cloud.forgotten, isTrue);
      });
    });
  });
}

CloudView _view({
  bool on = true,
  bool reachable = true,
  DateTime? lastCopiedUp,
  bool checked = true,
  List<CloudBackup> backups = const [],
  String? problem,
}) => (
  answered: true,
  on: on,
  label: 'iCloud',
  reachable: reachable,
  lastCopiedUp: lastCopiedUp ?? backups.firstOrNull?.takenAt,
  checked: checked && reachable,
  backups: backups,
  problem: problem,
);

CloudBackup _copyAt(DateTime takenAt) => (
  id: snapshotFileName(takenAt),
  name: snapshotFileName(takenAt),
  takenAt: takenAt,
  bytes: 2048,
);

/// The backups, without a disk under them.
///
/// A widget test runs on a fake clock, and a real folder read started inside
/// one never comes back — the test hangs at teardown waiting for it.
class _Backups extends BackupService {
  _Backups(super.db);

  @override
  Future<List<Snapshot>> snapshots() async => const [];

  @override
  Future<Snapshot?> sessionSnapshot() async => null;

  @override
  Future<SnapshotAttempt> takeSessionSnapshot() async =>
      (snapshot: null, problem: null);

  @override
  Future<SnapshotAttempt> takeSnapshot({String? doNotPrune}) async =>
      (snapshot: null, problem: null);
}

/// The account, without an account under it.
///
/// It records what the screen asked it to do and in what order, which is the
/// part the screen is responsible for. What any of it does to a board is
/// tested against the real service in `cloud_backup_test.dart`.
class _Cloud extends CloudBackupService {
  _Cloud(WordbridgeDatabase db)
    : super(
        backup: BackupService(db),
        store: CloudBackupStore(db),
        destination: _NoAccount(),
      );

  CloudView view_ = _view();

  final List<String> order = [];
  final List<CloudBackup> restored = [];
  bool forgotten = false;
  String? refuseRestore;

  @override
  String get label => 'iCloud';

  @override
  Future<bool> get on async => view_.on;

  @override
  Future<CloudView> view() async => view_;

  @override
  Future<void> turnOn() async {
    order.add('turned on');
    view_ = _view(on: true, backups: view_.backups);
  }

  @override
  Future<void> turnOff() async {
    order.add('turned off');
    view_ = _view(on: false, backups: view_.backups);
  }

  @override
  Future<CloudAttempt?> keepUpToDate() async {
    order.add('copied up');
    return null;
  }

  @override
  Future<RestoreAttempt> restore(CloudBackup copy) async {
    restored.add(copy);
    if (refuseRestore != null) {
      return (restored: false, problem: refuseRestore);
    }
    return (restored: true, problem: null);
  }

  @override
  Future<String?> forget() async {
    forgotten = true;
    view_ = _view(on: false);
    return null;
  }
}

/// Never reached. [_Cloud] overrides everything that would use it, and this is
/// here so that constructing one cannot open a channel to a platform.
class _NoAccount implements CloudDestination {
  @override
  String get label => 'iCloud';

  @override
  Future<CloudStatus> status() async =>
      (reachable: false, problem: 'No account.');

  @override
  Future<List<CloudBackup>> list() async => const [];

  @override
  Future<CloudBackup> upload(Object file, String name) =>
      throw UnimplementedError();

  @override
  Future<void> download(CloudBackup backup, Object to) =>
      throw UnimplementedError();

  @override
  Future<void> delete(CloudBackup backup) => throw UnimplementedError();
}
