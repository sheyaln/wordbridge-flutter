import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/backup/backup_service.dart';
import 'package:wordbridge/features/backup/snapshot.dart';
import 'package:wordbridge/features/caregiver/about_screen.dart';
import 'package:wordbridge/features/caregiver/caregiver_home.dart';
import 'package:wordbridge/features/developer/developer_mode.dart';
import 'package:wordbridge/features/developer/developer_screen.dart';
import 'package:wordbridge/features/interop/board_files.dart';
import 'package:wordbridge/features/reporting/crash_store.dart';
import 'package:wordbridge/features/reporting/report.dart';
import 'package:wordbridge/features/usage/logger.dart';

/// Backups, board files and crashes without a disk under them, because a real
/// folder read started inside a widget test never comes back.
class _NoBackups extends BackupService {
  _NoBackups(super.db);

  @override
  Future<List<Snapshot>> snapshots() async => const [];

  @override
  Future<Snapshot?> sessionSnapshot() async => null;

  @override
  Future<SnapshotAttempt> takeSessionSnapshot() async =>
      (snapshot: null, problem: null);
}

class _NoBoardFiles extends BoardFileStore {
  _NoBoardFiles(super.db);

  @override
  Future<List<BoardFile>> files() async => const [];
}

class _NoCrashes extends CrashStore {
  @override
  Future<List<CrashRecord>> waiting() async => const [];
}

/// Developer mode has to be off, has to stay off, and has to be impossible to
/// arrive at while looking for something else.
///
/// An AAC user finds every visible control on the device they use all day, so
/// the way in is a five second hold on a line that advertises nothing, inside
/// caregiver mode, behind the PIN. What that buys is only worth having if the
/// mode is genuinely absent until somebody asks for it: no row on the settings
/// list, nothing on the board, and nothing drawn over it.
///
/// The other half is where the answer is kept. It is device scoped, in
/// `app_state` beside the caregiver gesture, and it survives a restart — which
/// is a deliberate difference from caregiver mode, and is safe only because
/// the board says so while it is on.
void main() {
  late WordbridgeDatabase db;

  setUp(() {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() => db.close());

  group('what a device says before anybody asks', () {
    test('developer mode is off', () async {
      final developer = DeveloperMode(db);
      await developer.load();

      expect(developer.enabled, isFalse);
      expect(
        developer.view,
        isNull,
        reason: 'the board was handed something to draw over itself',
      );
    });

    test('and a value nothing can parse is read as off', () async {
      // This is read on the way to the talk screen. A device that will not
      // open its board because a settings row is malformed is a device that
      // has stopped talking.
      await db
          .into(db.appState)
          .insert(
            AppStateCompanion.insert(
              key: developerModeKey,
              value: 'not json at all',
            ),
          );

      final developer = DeveloperMode(db);
      await developer.load();

      expect(developer.enabled, isFalse);
    });
  });

  group('where the answer is kept', () {
    test('in app_state, so it belongs to the device', () async {
      final developer = DeveloperMode(db);
      await developer.load();
      await developer.setEnabled(true);

      final row = await (db.select(
        db.appState,
      )..where((s) => s.key.equals(developerModeKey))).getSingleOrNull();

      expect(row, isNotNull);
      expect(jsonDecode(row!.value), containsPair('on', true));
      // Nothing about which person is speaking. Two profiles on one tablet
      // cannot sensibly disagree about whether it is a development tablet.
      expect(await db.select(db.profiles).get(), isEmpty);
    });

    test('and it is still on the next time the app opens', () async {
      // The difference from caregiver mode, on purpose. The session this most
      // needs to survive is the one that just ended in the crash being
      // investigated.
      final first = DeveloperMode(db);
      await first.load();
      await first.setEnabled(true);
      await first.set('cellState', true);

      final second = DeveloperMode(db);
      await second.load();

      expect(second.enabled, isTrue);
      expect(second.cellState, isTrue);
      expect(second.view, isNotNull);
    });

    test('and switching it off leaves the switches where they were', () async {
      final developer = DeveloperMode(db);
      await developer.load();
      await developer.setEnabled(true);
      await developer.set('pictureSource', true);
      await developer.setEnabled(false);

      expect(
        developer.view,
        isNull,
        reason: 'the board is still being drawn on',
      );
      expect(
        developer.pictureSource,
        isTrue,
        reason: 'the switches were thrown away with the mode',
      );
    });

    test('the hold is only armed when it is asked for', () async {
      final developer = DeveloperMode(db);
      await developer.load();
      await developer.setEnabled(true);

      expect(developer.view!.hold, DeveloperMode.hold);

      await developer.set('holdToInspect', false);
      expect(developer.view!.hold, isNull);
    });
  });

  group('the way in', () {
    Future<void> pumpAbout(
      WidgetTester tester, {
      DeveloperMode? developer,
    }) async {
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(developerMode: developer)),
      );
      await tester.pump();
    }

    /// Two pumps, not one: a ticker records its start time on the first frame
    /// after it is started, so a single long pump hands the controller an
    /// elapsed time of zero.
    Future<TestGesture> hold(WidgetTester tester, Duration duration) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Version $appVersion, build $appBuild')),
      );
      await tester.pump();
      await tester.pump(duration);
      return gesture;
    }

    testWidgets('does not exist on a build with no developer mode', (
      tester,
    ) async {
      await pumpAbout(tester);

      final gesture = await hold(tester, const Duration(seconds: 10));
      await gesture.up();
      await tester.pump();

      expect(find.text('Turn developer mode on?'), findsNothing);
    });

    testWidgets('is not a tap, and is not a short press', (tester) async {
      final developer = DeveloperMode(db);
      await developer.load();
      await pumpAbout(tester, developer: developer);

      await tester.tap(find.text('Version $appVersion, build $appBuild'));
      await tester.pump();
      expect(find.text('Turn developer mode on?'), findsNothing);

      final gesture = await hold(tester, const Duration(seconds: 3));
      await gesture.up();
      await tester.pump();

      expect(find.text('Turn developer mode on?'), findsNothing);
      expect(developer.enabled, isFalse);
    });

    testWidgets('is five seconds, and then a question', (tester) async {
      final developer = DeveloperMode(db);
      await developer.load();
      await pumpAbout(tester, developer: developer);

      final gesture = await hold(tester, const Duration(seconds: 6));
      await tester.pump();
      expect(find.text('Turn developer mode on?'), findsOneWidget);

      // A hold that arrived somewhere by accident is still one answer away
      // from leaving.
      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(developer.enabled, isFalse);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('and the question turns it on', (tester) async {
      final developer = DeveloperMode(db);
      await developer.load();
      await pumpAbout(tester, developer: developer);

      final gesture = await hold(tester, const Duration(seconds: 6));
      await tester.pump();
      await tester.tap(find.text('Turn it on'));
      await tester.pump();

      expect(developer.enabled, isTrue);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('and About then says so, and can put it back', (tester) async {
      final developer = DeveloperMode(db);
      await developer.load();
      await developer.setEnabled(true);
      await pumpAbout(tester, developer: developer);

      expect(find.text('Developer mode is on'), findsOneWidget);

      await tester.tap(find.text('Turn it off'));
      await tester.pump();

      expect(developer.enabled, isFalse);
    });
  });

  group('the settings list', () {
    late String vocabularyId;
    const profileId = 'p1';

    Future<void> pumpSettings(
      WidgetTester tester,
      DeveloperMode developer,
    ) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: CaregiverHome(
            db: db,
            vocabularyId: vocabularyId,
            profileId: profileId,
            logger: UsageLogger(db, deviceId: 'test'),
            backup: _NoBackups(db),
            boards: _NoBoardFiles(db),
            crashes: _NoCrashes(),
            developer: developer,
          ),
        ),
      );
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      await tester.tap(find.text('Settings'));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    setUp(() async {
      final ts = nowMs();
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: profileId,
              displayName: 'Maya',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      vocabularyId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    });

    testWidgets('carries no row for it until it is on', (tester) async {
      // A row standing here permanently is a row a caregiver reads on their
      // way past, and this is not addressed to them.
      final developer = DeveloperMode(db);
      await developer.load();

      await pumpSettings(tester, developer);
      expect(find.text('Developer'), findsNothing);

      await close(tester);
    });

    testWidgets('and opens onto the switches once it is', (tester) async {
      final developer = DeveloperMode(db);
      await developer.load();
      await developer.setEnabled(true);

      await pumpSettings(tester, developer);
      expect(find.text('Developer'), findsOneWidget);

      await tester.tap(find.text('Developer'));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byType(DeveloperScreen), findsOneWidget);
      expect(find.text('Row and column'), findsOneWidget);
      expect(find.text('Hold a location to open it'), findsOneWidget);
      expect(find.text('Check nothing has moved'), findsOneWidget);

      await close(tester);
    });
  });
}
