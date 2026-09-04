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
    late _Picker picker;

    setUp(() => picker = _Picker());

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
          home: ProfileSetup(db: db, isFirstRun: isFirstRun, cloud: picker),
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

    testWidgets('offers a folder too, where the tablet has one to offer', (
      tester,
    ) async {
      await pumpSetup(tester);
      await reveal(tester, find.text('Keep a copy in $unpickedFolder'));

      expect(find.text('Keep a copy in $unpickedFolder'), findsOneWidget);
      expect(
        find.textContaining('Google Drive, Dropbox, OneDrive'),
        findsOneWidget,
      );
      expect(
        find.textContaining('holds no sign-in for any of them'),
        findsOneWidget,
        reason: 'a place was offered without saying what it costs',
      );
    });

    testWidgets('asks for the folder the moment it is chosen', (tester) async {
      // Left for the Backups screen, a folder answer with no folder behind it
      // is the same as no answer — and nobody would find that out until the
      // day the tablet was gone.
      await pumpSetup(tester);
      await reveal(tester, find.text('Keep a copy in $unpickedFolder'));

      await tester.tap(find.text('Keep a copy in $unpickedFolder'));
      await tester.pumpAndSettle();

      expect(picker.asked, [CloudPlace.folder]);
      expect(find.text('Keep a copy in Google Drive'), findsOneWidget);

      await build(tester);

      expect(await CloudBackupStore(db).answer(), isTrue);
    });

    testWidgets('and a picker nobody finished says so there and then', (
      tester,
    ) async {
      picker.folderName = null;
      await pumpSetup(tester);
      await reveal(tester, find.text('Keep a copy in $unpickedFolder'));

      await tester.tap(find.text('Keep a copy in $unpickedFolder'));
      await tester.pumpAndSettle();

      expect(find.text(noFolderChosen), findsOneWidget);
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

    testWidgets('still offers to delete copies after it is switched off', (
      tester,
    ) async {
      cloud.view_ = _view(
        on: false,
        backups: [_copyAt(DateTime.utc(2026, 8, 3, 14, 22))],
      );
      await open(tester);

      await reveal(tester, find.text('Remove every copy from iCloud'));

      expect(find.text('Remove every copy from iCloud'), findsOneWidget);
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

    group('where the copies go', () {
      testWidgets('offers both places where the tablet has two', (
        tester,
      ) async {
        cloud.view_ = _view();
        await open(tester);

        await reveal(tester, find.text('A folder you choose'));

        expect(find.text('Where the copies go'), findsOneWidget);
        expect(find.text('A folder you choose'), findsOneWidget);
      });

      testWidgets('says what changing it leaves behind, before it does', (
        tester,
      ) async {
        cloud.view_ = _view(
          backups: [_copyAt(DateTime.utc(2026, 8, 3, 14, 22))],
        );
        await open(tester);

        await reveal(tester, find.text('A folder you choose'));
        await tester.tap(find.text('A folder you choose'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('The one copy already in iCloud stays'),
          findsOneWidget,
        );
        expect(
          find.textContaining('delete them in iCloud itself'),
          findsOneWidget,
          reason: 'it did not say how to get rid of what it left',
        );
        expect(cloud.sentTo, isEmpty, reason: 'it moved before asking');
      });

      testWidgets('and moves them once they have agreed', (tester) async {
        cloud.view_ = _view(
          backups: [_copyAt(DateTime.utc(2026, 8, 3, 14, 22))],
        );
        await open(tester);

        await reveal(tester, find.text('A folder you choose'));
        await tester.tap(find.text('A folder you choose'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Change where they go'));
        await tester.pumpAndSettle();

        expect(cloud.sentTo, [CloudPlace.folder]);
      });

      testWidgets('goes straight there when there is nothing to leave', (
        tester,
      ) async {
        // A confirmation about nothing is what teaches somebody to dismiss
        // the one that is about their child's recorded speech.
        cloud.view_ = _view();
        await open(tester);

        await reveal(tester, find.text('A folder you choose'));
        await tester.tap(find.text('A folder you choose'));
        await tester.pumpAndSettle();

        expect(cloud.sentTo, [CloudPlace.folder]);
      });

      testWidgets('keeps saying where the older copies were left', (
        tester,
      ) async {
        cloud.view_ = _view(
          label: 'Google Drive',
          place: CloudPlace.folder,
          leftBehind: 'iCloud',
        );
        await open(tester);

        await reveal(tester, find.text('Older copies are still in iCloud'));

        expect(find.text('Older copies are still in iCloud'), findsOneWidget);
      });

      testWidgets('offers the picker again for a folder that has gone', (
        tester,
      ) async {
        cloud.view_ = _view(
          label: 'Google Drive',
          place: CloudPlace.folder,
          reachable: false,
          problem: folderGone('Google Drive'),
        );
        await open(tester);

        expect(find.text(folderGone('Google Drive')), findsOneWidget);

        await reveal(tester, find.text('Choose a different folder'));
        await tester.tap(find.text('Choose a different folder'));
        await tester.pumpAndSettle();

        expect(cloud.sentTo, [CloudPlace.folder]);
        expect(
          cloud.picked,
          isTrue,
          reason: 'the only way back was switching the whole thing off',
        );
      });
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
  String label = 'iCloud',
  CloudPlace place = CloudPlace.account,
  List<CloudPlace> places = const [CloudPlace.account, CloudPlace.folder],
  String? leftBehind,
  DateTime? lastCopiedUp,
  bool checked = true,
  List<CloudBackup> backups = const [],
  String? problem,
}) => (
  answered: true,
  on: on,
  label: label,
  place: place,
  places: places,
  leftBehind: leftBehind,
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
  final List<CloudPlace> sentTo = [];
  bool picked = false;
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
  Future<CloudAttempt> sendTo(CloudPlace place, {bool pick = false}) async {
    sentTo.add(place);
    picked = picked || pick;
    view_ = _view(
      on: view_.on,
      place: place,
      label: place == CloudPlace.folder ? 'Google Drive' : 'iCloud',
      leftBehind: place == CloudPlace.folder ? 'iCloud' : null,
    );
    return (snapshot: null, copy: null, problem: null);
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
  CloudPlace get place => CloudPlace.account;

  @override
  List<CloudPlace> get places => const [];

  @override
  Future<CloudStatus> status() async =>
      (reachable: false, problem: 'No account.');

  @override
  Future<CloudStatus> connect() async =>
      (reachable: false, problem: 'No account.');

  @override
  Future<CloudStatus> use(CloudPlace place, {bool pick = false}) async =>
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

/// The platform's answer to being asked for a place, with no platform under it.
///
/// The setup screen can open a folder picker, and a test that reached a real
/// one would be a test that only passes on a tablet somebody is holding.
class _Picker implements CloudDestination {
  @override
  String label = 'iCloud';

  @override
  CloudPlace place = CloudPlace.account;

  @override
  List<CloudPlace> places = const [CloudPlace.account, CloudPlace.folder];

  final List<CloudPlace> asked = [];

  /// What the picker would name the folder, or null where it is dismissed.
  String? folderName = 'Google Drive';

  @override
  Future<CloudStatus> use(CloudPlace to, {bool pick = false}) async {
    asked.add(to);
    if (to == CloudPlace.folder && folderName == null) {
      return (reachable: false, problem: noFolderChosen);
    }

    place = to;
    label = to == CloudPlace.folder ? folderName! : 'iCloud';
    return (reachable: true, problem: null);
  }

  @override
  Future<CloudStatus> status() async => (reachable: true, problem: null);

  @override
  Future<CloudStatus> connect() async => status();

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
