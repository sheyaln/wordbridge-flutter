import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/usage/logger.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

class _Speech implements SpeechEngine {
  final said = <String>[];

  @override
  Future<void> speak(String text) async => said.add(text);
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

/// §4.42's view-all: a caregiver seeing the whole board and then leaving it
/// exactly as it was.
///
/// The two things it must do are in tension and both matter. It has to show
/// words the board is deliberately not showing, and it must not write anything
/// down while doing it — no level raised, nothing unhidden. What makes that
/// safe rather than a hole in §5 non-negotiable 8 is that everything it shows
/// becomes visible, so everything it shows may speak.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;
  late _Speech speech;

  const profileId = 'p1';

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );

    final ts = nowMs();
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: 'Maya',
            settingsJson: Value(jsonEncode({'settleDelayMs': 0})),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    settings = ProfileSettings(db, profileId);
    await settings.load();
    speech = _Speech();
  });

  Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Level 1, so most of the shipped vocabulary is off the board.
  Future<void> pumpTalkScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: TalkScreen(
          db: db,
          speech: speech,
          vocabularyId: vocabularyId,
          logger: UsageLogger(db, deviceId: 'test'),
          auth: PinAuth(db, storage: _FakeSecretStore()),
          settings: settings,
          profileId: profileId,
          vocabLevel: 1,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  TalkScreenState state(WidgetTester tester) =>
      tester.state<TalkScreenState>(find.byType(TalkScreen));

  /// A word on the home board that level 1 does not draw.
  Future<Button> aboveLevelOne() async {
    final rows =
        await (db.select(db.buttons)
              ..where((b) => b.vocabularyId.equals(vocabularyId))
              ..where((b) => b.vocabLevel.isBiggerThanValue(1))
              ..where((b) => b.hidden.equals(false)))
            .get();

    final boards = {for (final b in await db.select(db.boards).get()) b.id: b};
    final cells = {for (final c in await db.select(db.cells).get()) c.id: c};

    return rows.firstWhere((b) {
      final cell = cells[b.cellId];
      return cell != null && boards[cell.boardId]?.kind == BoardKind.root;
    }, orElse: () => throw StateError('this grid draws everything at level 1'));
  }

  group('what the board draws', () {
    testWidgets('a word above the level is not there to begin with', (
      tester,
    ) async {
      final word = await aboveLevelOne();
      await pumpTalkScreen(tester);

      expect(find.text(word.label), findsNothing);
    });

    testWidgets('and is there once every word is shown', (tester) async {
      final word = await aboveLevelOne();
      await pumpTalkScreen(tester);

      state(tester).setViewAll(true);
      await pumpFrames(tester);

      expect(find.text(word.label), findsOneWidget);
    });

    testWidgets('so is a word somebody hid', (tester) async {
      final word = await aboveLevelOne();
      await (db.update(db.buttons)..where((b) => b.id.equals(word.id))).write(
        const ButtonsCompanion(hidden: Value(true), vocabLevel: Value(1)),
      );

      await pumpTalkScreen(tester);
      expect(find.text(word.label), findsNothing, reason: 'the premise');

      state(tester).setViewAll(true);
      await pumpFrames(tester);

      expect(find.text(word.label), findsOneWidget);
    });

    testWidgets('and a reserved location stays empty, having nothing on it', (
      tester,
    ) async {
      final before = await db.select(db.cells).get();
      final reserved = before
          .where((c) => c.state == CellState.emptyReserved)
          .length;
      expect(reserved, greaterThan(0), reason: 'the premise');

      await pumpTalkScreen(tester);
      state(tester).setViewAll(true);
      await pumpFrames(tester);

      // Nothing invented a word for a location that has none.
      expect(await db.select(db.cells).get(), before);
    });
  });

  group('what it must not do', () {
    testWidgets('write anything down', (tester) async {
      final buttons = await db.select(db.buttons).get();
      final profile = await db.select(db.profiles).get();

      await pumpTalkScreen(tester);
      state(tester).setViewAll(true);
      await pumpFrames(tester);

      // No level raised, nothing unhidden. The whole value of this is that the
      // board can be looked at and left exactly as it was.
      expect(await db.select(db.buttons).get(), buttons);
      expect(await db.select(db.profiles).get(), profile);
    });

    testWidgets('or outlast being turned off', (tester) async {
      final word = await aboveLevelOne();
      await pumpTalkScreen(tester);

      state(tester).setViewAll(true);
      await pumpFrames(tester);
      expect(find.text(word.label), findsOneWidget, reason: 'the premise');

      state(tester).setViewAll(false);
      await pumpFrames(tester);

      expect(find.text(word.label), findsNothing);
    });
  });

  group('the board says it is doing it', () {
    testWidgets('nothing while it is off', (tester) async {
      await pumpTalkScreen(tester);

      expect(
        find.text('Showing every word, including hidden ones'),
        findsNothing,
      );
    });

    testWidgets('and a strip that can turn it off from where it is seen', (
      tester,
    ) async {
      final word = await aboveLevelOne();
      await pumpTalkScreen(tester);

      state(tester).setViewAll(true);
      await pumpFrames(tester);
      expect(
        find.text('Showing every word, including hidden ones'),
        findsOneWidget,
      );

      await tester.tap(find.text('Stop'));
      await pumpFrames(tester);

      expect(
        find.text('Showing every word, including hidden ones'),
        findsNothing,
      );
      expect(find.text(word.label), findsNothing);
    });
  });

  group('what it is for', () {
    testWidgets('a word it reveals can be pressed and speaks', (tester) async {
      // §5 non-negotiable 8 is "a location the user cannot see never speaks".
      // This makes them visible, so they may — and a word drawn but inert
      // would be the worse failure of the two.
      final word = await aboveLevelOne();
      await pumpTalkScreen(tester);

      state(tester).setViewAll(true);
      await pumpFrames(tester);

      await tester.tap(find.text(word.label));
      await pumpFrames(tester);

      expect(speech.said, isNotEmpty);
    });
  });
}
