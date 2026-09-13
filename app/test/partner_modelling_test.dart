import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/caregiver_gesture.dart';
import 'package:wordbridge/features/auth/corner_hold_target.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/editor/remap.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/usage/logger.dart';
import 'package:wordbridge/features/usage/modelling_session.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

class _SilentSpeech implements SpeechEngine {
  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> speakUtterance(String text) => speak(text);
  @override
  Future<void> init() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<List<VoiceOption>> voices() async => const [];
  @override
  Future<void> useVoice(VoiceOption voice) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVolume(double volume) async {}
}

/// A partner demonstrating on the user's board, and the log telling the two
/// people apart.
///
/// Aided language modelling is what a communication partner is meant to be
/// doing constantly, and at the screen it is identical to use: same locations,
/// same speech. The only thing that may differ is whose practice the taps are
/// counted as — and everything that reasons about what the *user* has learned
/// hangs off that count, the remap warning first among them.
void main() {
  group('a stretch of modelling', () {
    test('is off until somebody says otherwise', () {
      final session = ModellingSession();

      expect(session.active, isFalse);
      expect(session.remaining, isNull);
    });

    test('runs from the moment it begins', () {
      final session = ModellingSession();
      session.begin();

      expect(session.active, isTrue);
    });

    test('lapses on its own when nobody ends it', () async {
      final session = ModellingSession(
        window: const Duration(milliseconds: 200),
      );
      session.begin();

      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(
        session.active,
        isFalse,
        reason:
            'a partner who forgets leaves the board recording the user of it '
            'as somebody else',
      );
      expect(session.remaining, isNull);
    });

    test('is not held open by the selections made during it', () async {
      final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      final logger = UsageLogger(db, deviceId: 'test')..enabled = true;
      final session = ModellingSession(
        window: const Duration(milliseconds: 300),
      );
      session.begin();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      logger.log(
        profileId: 'p1',
        vocabularyId: 'v1',
        boardId: 'b1',
        cellId: 'c1',
        label: 'eat',
        action: ButtonAction.speak,
        source: UsageSource.touch,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(
        session.active,
        isFalse,
        reason:
            'taps arriving during a stretch are the partner\'s by definition, '
            'so treating them as proof the partner is still there keeps the '
            'mode alive on the very taps that should end it',
      );

      await logger.dispose();
      await db.close();
    });

    test('tells whoever asks how much of it is left', () {
      final session = ModellingSession(window: const Duration(minutes: 10));
      session.begin();

      expect(session.remaining, isNotNull);
      expect(session.remaining!.inMinutes, greaterThanOrEqualTo(9));

      session.end();

      expect(session.remaining, isNull);
    });
  });

  group('what the log says happened', () {
    late WordbridgeDatabase db;
    late UsageLogger logger;

    setUp(() {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      logger = UsageLogger(db, deviceId: 'test')..enabled = true;
    });

    tearDown(() async {
      await logger.dispose();
      await db.close();
    });

    Future<List<UsageSource>> sources() async {
      await logger.flush();
      final rows = await db.select(db.usageEvents).get();
      return [for (final r in rows) r.source];
    }

    void tap({UsageSource source = UsageSource.touch}) => logger.log(
      profileId: 'p1',
      vocabularyId: 'v1',
      boardId: 'b1',
      cellId: 'c1',
      buttonId: 'btn',
      label: 'eat',
      action: ButtonAction.speak,
      source: source,
    );

    test('a tap made while modelling belongs to the partner', () async {
      logger.modelling.begin();
      tap();

      expect(await sources(), [UsageSource.partnerModel]);
    });

    test('so does a word taken off the prediction strip', () async {
      logger.modelling.begin();
      tap(source: UsageSource.prediction);

      expect(
        await sources(),
        [UsageSource.partnerModel],
        reason:
            'every route to a word goes through one rule, so no call site can '
            'attribute a partner\'s selection to the user by forgetting',
      );
    });

    test('taps belong to the user again once the stretch ends', () async {
      logger.modelling.begin();
      tap();
      logger.modelling.end();
      tap();

      expect(await sources(), [UsageSource.partnerModel, UsageSource.touch]);
    });

    test('taps belong to the user when nobody is modelling', () async {
      tap();

      expect(await sources(), [UsageSource.touch]);
    });
  });

  group('the warning shown before a word is moved', () {
    late WordbridgeDatabase db;
    late RemapService remap;
    late UsageLogger logger;
    late String vocabId;
    late String boardId;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      remap = RemapService(db);
      logger = UsageLogger(db, deviceId: 'test')..enabled = true;

      vocabId = newId();
      final ts = nowMs();
      await db
          .into(db.vocabularies)
          .insert(
            VocabulariesCompanion.insert(
              id: vocabId,
              name: 'test',
              gridRows: 7,
              gridCols: 12,
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      boardId = await materializeBoard(
        db,
        vocabularyId: vocabId,
        name: 'home',
        kind: BoardKind.root,
      );
    });

    tearDown(() async {
      await logger.dispose();
      await db.close();
    });

    Future<String> placeEat() async {
      final cell = await cellAt(db, boardId: boardId, row: 0, col: 0);
      return placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'eat',
        message: 'eat',
      );
    }

    Future<void> tapFifty(String buttonId) async {
      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(buttonId))).getSingle();

      for (var i = 0; i < 50; i++) {
        logger.log(
          profileId: 'p1',
          vocabularyId: vocabId,
          boardId: boardId,
          cellId: button.cellId!,
          buttonId: buttonId,
          label: 'eat',
          action: ButtonAction.speak,
          source: UsageSource.touch,
        );
      }
      await logger.flush();
    }

    test('counts the taps a user made', () async {
      final id = await placeEat();
      await tapFifty(id);

      expect(await remap.warningFor(id, userName: 'Maya'), contains('50'));
    });

    test('counts none of the taps a partner made demonstrating', () async {
      final id = await placeEat();
      logger.modelling.begin();
      await tapFifty(id);

      expect(
        await remap.warningFor(id, userName: 'Maya'),
        isNull,
        reason:
            'the sentence reads "Maya has tapped this location N times", and a '
            'number holding her mother\'s taps makes the one screen this app '
            'exists for say something untrue',
      );
    });

    test('counts a partner\'s taps and a user\'s separately', () async {
      final id = await placeEat();
      logger.modelling.begin();
      await tapFifty(id);
      logger.modelling.end();
      await tapFifty(id);

      final warning = await remap.warningFor(id, userName: 'Maya');

      expect(warning, contains('50'));
      expect(warning, isNot(contains('100')));
    });
  });

  group('on the board', () {
    late WordbridgeDatabase db;
    late String vocabId;
    late UsageLogger logger;
    late ProfileSettings settings;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      vocabId = await seedCoreBoardSet(db);
      logger = UsageLogger(db, deviceId: 'test')..enabled = true;

      final ts = nowMs();
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'p1',
              displayName: 'Maya',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      settings = ProfileSettings(db, 'p1');
    });

    /// Drift keeps a timer alive for as long as a query stream exists, and
    /// `flutter_test` asserts no timers are pending at the end of the test
    /// body — before any `tearDown` runs. So the tree comes down here.
    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    }

    Future<void> pumpBoard(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2048, 1536);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: TalkScreen(
            db: db,
            speech: _SilentSpeech(),
            vocabularyId: vocabId,
            logger: logger,
            auth: PinAuth(db, storage: _FakeSecretStore()),
            settings: settings,
            profileId: 'p1',
            userName: 'Maya',
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// Lets a spoken sentence reach the database: the delayed flush the log
    /// arms, and the real turns the write itself needs.
    Future<void> settleWrites(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    /// The gesture a partner already knows, held until it opens something.
    Future<void> holdTheCorner(WidgetTester tester) async {
      expect(find.byType(CornerHoldTarget), findsOneWidget);
      final hold = await tester.startGesture(caregiverGestureRect.center);
      await tester.pump();
      await tester.pump(CaregiverEntry.defaultCornerHold);
      await tester.pump(const Duration(milliseconds: 50));
      await hold.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Makes that gesture, and takes the offer.
    Future<void> startModelling(WidgetTester tester) async {
      await holdTheCorner(tester);

      await tester.tap(find.text('I am modelling'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the way in is the gesture, and it asks for no PIN', (
      tester,
    ) async {
      await pumpBoard(tester);
      await startModelling(tester);

      expect(logger.modelling.active, isTrue);
      expect(
        find.byType(TextField),
        findsNothing,
        reason:
            'a PIN in front of something a partner does many times a day, '
            'mid-sentence, is a mode nobody turns on — and a mode nobody turns '
            'on records their sentences as the user\'s practice',
      );

      await finish(tester);
    });

    testWidgets('a word tapped during it is logged as the partner\'s', (
      tester,
    ) async {
      await pumpBoard(tester);
      await startModelling(tester);

      await tester.tap(
        find.descendant(of: find.byType(GridSurface), matching: find.text('I')),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settleWrites(tester);

      final rows = await db.select(db.usageEvents).get();

      expect(rows, hasLength(1));
      expect(rows.single.source, UsageSource.partnerModel);

      await finish(tester);
    });

    testWidgets('the board says so, without moving a single key', (
      tester,
    ) async {
      await pumpBoard(tester);
      final before = tester.getRect(find.byType(GridSurface));

      await startModelling(tester);

      expect(find.text('Modelling'), findsOneWidget);
      expect(
        tester.getRect(find.byType(GridSurface)),
        before,
        reason:
            'a partner demonstrating on a board whose keys have all shifted is '
            'demonstrating the wrong board',
      );

      await finish(tester);
    });

    testWidgets('one tap on the badge ends it', (tester) async {
      await pumpBoard(tester);
      await startModelling(tester);

      await tester.tap(find.text('Modelling'));
      await tester.pump();

      expect(logger.modelling.active, isFalse);
      expect(find.text('Modelling'), findsNothing);

      await finish(tester);
    });

    testWidgets('the app leaving the foreground ends it', (tester) async {
      await pumpBoard(tester);
      await startModelling(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(
        logger.modelling.active,
        isFalse,
        reason:
            'the commonest end is a partner handing the device back and '
            'putting it down, which is a background rather than a decision',
      );

      await finish(tester);
    });

    testWidgets('the board going away ends it', (tester) async {
      await pumpBoard(tester);
      await startModelling(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));

      expect(logger.modelling.active, isFalse);

      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('the caregiver gesture still reaches the settings', (
      tester,
    ) async {
      await pumpBoard(tester);

      await holdTheCorner(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(CornerHoldTarget), findsOneWidget);

      await finish(tester);
    });

    testWidgets('prediction does not learn the partner\'s sentence', (
      tester,
    ) async {
      await settings.load();
      await settings.set('prediction', true);
      await pumpBoard(tester);
      await startModelling(tester);

      await tester.tap(
        find.descendant(of: find.byType(GridSurface), matching: find.text('I')),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byTooltip('Speak'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settleWrites(tester);

      expect(
        await db.select(db.predictionPairs).get(),
        isEmpty,
        reason:
            'a strip trained on the partner offers the user the partner\'s '
            'next word',
      );

      await finish(tester);
    });

    testWidgets('prediction learns the user\'s own sentence', (tester) async {
      await settings.load();
      await settings.set('prediction', true);
      await pumpBoard(tester);

      await tester.tap(
        find.descendant(of: find.byType(GridSurface), matching: find.text('I')),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byTooltip('Speak'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settleWrites(tester);

      expect(await db.select(db.predictionPairs).get(), isNotEmpty);

      await finish(tester);
    });
  });
}
