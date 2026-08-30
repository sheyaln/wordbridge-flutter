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

    // Both marks sit behind one control, which always opens. A button that
    // applied the last one on a plain press would be one press sometimes and
    // two others, decided by something the person cannot see.
    await tester.tap(find.byTooltip('End the sentence'));
    await pumpFrames(tester);
    await tester.tap(find.text('Make it a question'));
    await pumpFrames(tester);

    // The whole sentence, because tone belongs to the sentence — hearing it is
    // the only thing that tells the user the mark did anything.
    expect(speech.said, ['you', 'you?']);
  });

  testWidgets('and the exclamation mark is beside it', (tester) async {
    final onAnyBoard = await (db.select(
      db.buttons,
    )..where((b) => b.label.equals('!'))).get();
    expect(onAnyBoard, isEmpty);

    final you = await cellOf(label: 'you');

    await pumpTalkScreen(tester);
    await tap(tester, you);
    await tester.tap(find.byTooltip('End the sentence'));
    await pumpFrames(tester);
    await tester.tap(find.text('Say it like you mean it'));
    await pumpFrames(tester);

    expect(speech.said, ['you', 'you!']);
  });

  testWidgets('a typed word joins the sentence, and is not said twice', (
    tester,
  ) async {
    // The typing screen says the finished word as it hands it over — that is
    // the feedback that the typing worked. Saying it again on arrival would
    // make one word two, and a person who typed once would be heard twice.
    final you = await cellOf(label: 'you');

    await pumpTalkScreen(tester);
    await tap(tester, you);

    await tester.tap(find.byTooltip('Another way to a word'));
    await pumpFrames(tester);
    await tester.tap(find.text('Type a word'));
    await pumpFrames(tester);

    await tester.enterText(find.byType(TextField), 'ben');
    await pumpFrames(tester);
    expect(speech.said, [
      'you',
    ], reason: 'something was spoken while the word was still being typed');

    await tester.tap(find.text('Say it and add it'));
    await pumpFrames(tester);

    expect(speech.said, [
      'you',
      'ben',
    ], reason: 'the word arrived already spoken and was spoken again');

    // And it is in the sentence, so the next thing said carries it.
    await tester.tap(find.byTooltip('Speak'));
    await pumpFrames(tester);
    expect(speech.said.last, 'you ben');
  });

  testWidgets('backing out of typing leaves the sentence alone', (
    tester,
  ) async {
    final you = await cellOf(label: 'you');

    await pumpTalkScreen(tester);
    await tap(tester, you);

    await tester.tap(find.byTooltip('Another way to a word'));
    await pumpFrames(tester);
    await tester.tap(find.text('Type a word'));
    await pumpFrames(tester);

    await tester.enterText(find.byType(TextField), 'ben');
    await tester.tap(find.byTooltip('Back to the board'));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('Speak'));
    await pumpFrames(tester);

    expect(speech.said, [
      'you',
      'you',
    ], reason: 'a word nobody finished was put into the sentence anyway');
  });

  testWidgets('an empty field has nothing to say', (tester) async {
    await pumpTalkScreen(tester);

    await tester.tap(find.byTooltip('Another way to a word'));
    await pumpFrames(tester);
    await tester.tap(find.text('Type a word'));
    await pumpFrames(tester);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    // And the return key is the other way in. A keyboard set up for another
    // language may not put "done" where this one expects it, so both routes
    // have to refuse an empty field rather than only the one on screen.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);

    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'the return key closed the screen without a word to show for it',
    );
    expect(speech.said, isEmpty);
  });

  testWidgets('the control shows both marks it carries', (tester) async {
    // One of them on the face would read as a key that does that one thing,
    // and somebody who wanted the other would have no reason to press it.
    await pumpTalkScreen(tester);

    // Scoped to this control: the bar now carries a second one beside it.
    final face = tester.widget<Text>(
      find.descendant(
        of: find.byTooltip('End the sentence'),
        matching: find.byType(Text),
      ),
    );

    expect(face.data, contains('?'));
    expect(face.data, contains('!'));
  });

  testWidgets('the control does nothing on an empty sentence', (tester) async {
    // A lone mark is not a sentence, and a control that opens onto choices
    // that do nothing teaches that pressing things is pointless.
    await pumpTalkScreen(tester);

    final button = tester.widget<PopupMenuButton<String>>(
      find.descendant(
        of: find.byTooltip('End the sentence'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    expect(button.enabled, isFalse);

    // And it has to look it. A control that refuses a press while looking
    // exactly like one that works teaches that pressing things is a gamble.
    final face = tester.widget<Text>(
      find.descendant(
        of: find.byTooltip('End the sentence'),
        matching: find.byType(Text),
      ),
    );
    expect(face.style!.color, Colors.black12);
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
