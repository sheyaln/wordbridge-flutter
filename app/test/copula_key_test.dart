import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull;
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

class _RecordingSpeech implements SpeechEngine {
  final said = <String>[];

  @override
  Future<void> speak(String text) async => said.add(text);
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

/// The copula key as a finger reaches it, and what the room hears.
///
/// Every assertion here is about the audio rather than the bar. The unit tests
/// cover the grammar; what this covers is that the setting reaches the key at
/// all, and that the correction is spoken rather than only displayed. Both of
/// those have been silently dead in this codebase before while the unit tests
/// underneath them stayed green.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;
  late _RecordingSpeech speech;

  const profileId = 'p1';
  const rows = 7;
  const cols = 12;

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
            // The copula arrives at level 2, so a level-1 board has no key to
            // press.
            vocabLevel: const Value(3),
            settingsJson: Value(jsonEncode({'settleDelayMs': 0})),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(db, rows: rows, cols: cols);
    settings = ProfileSettings(db, profileId);
    await settings.load();
    speech = _RecordingSpeech();
  });

  // The database is deliberately not closed inside a widget test: closing it
  // waits on work the fake clock never runs.

  Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// Where a button sits, found by what it does rather than what it reads.
  Future<Cell> cellOf({
    ButtonAction action = ButtonAction.speak,
    String? message,
    String? label,
  }) async {
    final query = db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.buttons.action.equalsValue(action));

    if (message != null) query.where(db.buttons.message.equals(message));
    if (label != null) query.where(db.buttons.label.equals(label));

    final rows = await query.get();
    return rows.first.readTable(db.cells);
  }

  Future<void> tap(WidgetTester tester, Cell cell) async {
    await tester.tap(find.byKey(ValueKey('${cell.row}:${cell.col}')));
    await pumpFrames(tester);
  }

  testWidgets('a second press changes the form and says the new one', (
    tester,
  ) async {
    final copula = await cellOf(
      action: ButtonAction.morpheme,
      message: 'present',
    );

    await pumpTalkScreen(tester);
    await tap(tester, copula);
    await tap(tester, copula);

    expect(speech.said, ['is', 'are']);
  });

  testWidgets('the key is still there to be pressed a second time', (
    tester,
  ) async {
    final copula = await cellOf(
      action: ButtonAction.morpheme,
      message: 'present',
    );

    await pumpTalkScreen(tester);
    await tap(tester, copula);

    // Withheld keys are drawn without their label. A key that has gone blank
    // is one the second press lands on and nothing happens.
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('${copula.row}:${copula.col}')),
        matching: find.byType(Text),
      ),
    );
    expect(texts, isNotEmpty);
  });

  testWidgets('under the settling mode the correction is spoken', (
    tester,
  ) async {
    await settings.set('copulaMode', 'agree');

    final copula = await cellOf(
      action: ButtonAction.morpheme,
      message: 'present',
    );
    final you = await cellOf(label: 'you');

    await pumpTalkScreen(tester);
    await tap(tester, copula);
    await tap(tester, you);

    // Not "is" then "you", which is the sentence nobody said.
    expect(speech.said, ['is', 'are you']);
  });

  testWidgets('the question mark is on the bar, not on any board', (
    tester,
  ) async {
    // It marks the sentence rather than adding a word to it, so it lives where
    // the sentence lives and costs no location on any board.
    final onAnyBoard = await (db.select(
      db.buttons,
    )..where((b) => b.label.equals('?'))).get();
    expect(onAnyBoard, isEmpty);

    final you = await cellOf(label: 'you');

    await pumpTalkScreen(tester);
    await tap(tester, you);
    await tester.tap(find.byTooltip('Make it a question'));
    await pumpFrames(tester);

    // The whole sentence, because tone belongs to the sentence — hearing it is
    // the only thing that tells the user the mark did anything.
    expect(speech.said, ['you', 'you?']);
  });

  testWidgets('every board carries "how" in the pinned column', (tester) async {
    for (final board in await db.select(db.boards).get()) {
      final pinned =
          await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])..where(
                db.cells.boardId.equals(board.id) &
                    db.buttons.label.equals('how'),
              ))
              .get();

      expect(pinned, hasLength(1), reason: '"${board.name}" cannot ask how');
    }
  });

  testWidgets('a word that corrects nothing is spoken on its own', (
    tester,
  ) async {
    await settings.set('copulaMode', 'agree');

    final copula = await cellOf(
      action: ButtonAction.morpheme,
      message: 'present',
    );
    final it = await cellOf(label: 'it');

    await pumpTalkScreen(tester);
    await tap(tester, copula);
    await tap(tester, it);

    expect(speech.said, ['is', 'it']);
  });
}
