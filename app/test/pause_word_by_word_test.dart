import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/quick_settings.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/usage/logger.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

/// Keeps the two kinds of speech apart, which is the whole subject here.
class _Speech implements SpeechEngine {
  final words = <String>[];
  final sentences = <String>[];

  @override
  Future<void> speak(String text) async => words.add(text);

  @override
  Future<void> speakUtterance(String text) async => sentences.add(text);

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

/// The covert half of a conversation (§4.88).
///
/// Word-by-word speech held quiet until the sentence is sent, so somebody who
/// normally hears each key can build one sentence without the room hearing it
/// being built.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;

  const profileId = 'p1';

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());

    final ts = nowMs();
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: 'Maya',
            vocabLevel: const Value(3),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(
      db,
      rows: 7,
      cols: 12,
      profileId: profileId,
    );
    settings = ProfileSettings(db, profileId);
    await settings.load();
  });

  Future<void> pumpBoard(WidgetTester tester, _Speech speech) async {
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
          profileId: profileId,
          vocabLevel: 3,
          settings: settings,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> teardownBoard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('pausing word-by-word', () {
    Future<void> openVolume(WidgetTester tester) async {
      await tester.tap(find.text(quickSettingsLabel));
      await settle(tester);
      await tester.tap(find.text('Volume'));
      await settle(tester);
    }

    testWidgets('is offered under the volume slider', (tester) async {
      await pumpBoard(tester, _Speech());
      await openVolume(tester);

      expect(find.text(pauseWordByWordLabel), findsOneWidget);

      await teardownBoard(tester);
    });

    testWidgets('and is not offered when the keys are silent already', (
      tester,
    ) async {
      // A control that does nothing is worse than no control: somebody presses
      // it, hears no change, and learns that this menu lies.
      await settings.set('speakEachWord', false);
      await pumpBoard(tester, _Speech());
      await openVolume(tester);

      expect(find.text(pauseWordByWordLabel), findsNothing);

      await teardownBoard(tester);
    });

    testWidgets('and the switch moves when it is pressed', (tester) async {
      // The control has to say what it did. It read `widget.paused`, which is
      // a snapshot taken when the route was built — the board went quiet and
      // the switch stayed off, which reads as a control that does not work.
      await pumpBoard(tester, _Speech());
      await openVolume(tester);

      bool switchIsOn() => tester.widget<Switch>(find.byType(Switch)).value;

      expect(switchIsOn(), isFalse);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(switchIsOn(), isTrue, reason: 'the switch did not move');

      // And back off again, from the same switch.
      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(switchIsOn(), isFalse);

      await teardownBoard(tester);
    });

    testWidgets('and it is still on when the menu is opened again', (
      tester,
    ) async {
      await pumpBoard(tester, _Speech());
      await openVolume(tester);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);

      await openVolume(tester);
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isTrue,
        reason: 'the menu forgot the pause it had set',
      );

      await teardownBoard(tester);
    });

    testWidgets('holds the keys quiet, and the sentence still speaks', (
      tester,
    ) async {
      final speech = _Speech();
      await pumpBoard(tester, speech);

      await tester.tap(find.text('I').first);
      await settle(tester);
      expect(speech.words, ['I'], reason: 'the board was quiet already');

      await openVolume(tester);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);

      await tester.tap(find.text('want').first);
      await settle(tester);

      expect(speech.words, ['I'], reason: '"want" was said out loud');
      expect(find.text('want'), findsWidgets, reason: 'the word was not added');

      await teardownBoard(tester);
    });

    testWidgets('says so on the bar, and the badge turns it back on', (
      tester,
    ) async {
      // Silence is the one state a person cannot tell apart from a broken
      // voice.
      final speech = _Speech();
      await pumpBoard(tester, speech);

      await openVolume(tester);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(find.text('Quiet'), findsOneWidget);

      await tester.tap(find.text('Quiet'));
      await settle(tester);

      expect(find.text('Quiet'), findsNothing);

      await tester.tap(find.text('I').first);
      await settle(tester);
      expect(speech.words, ['I'], reason: 'the keys did not speak again');

      await teardownBoard(tester);
    });

    testWidgets('and speaking the sentence ends it', (tester) async {
      final speech = _Speech();
      await pumpBoard(tester, speech);

      await tester.tap(find.text('I').first);
      await settle(tester);

      await openVolume(tester);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);

      await tester.tap(find.text('want').first);
      await settle(tester);
      expect(speech.words, ['I']);

      await tester.tap(find.byTooltip('Speak'));
      await settle(tester);

      expect(speech.sentences, hasLength(1));
      expect(find.text('Quiet'), findsNothing, reason: 'the pause outlived it');

      await tester.tap(find.text('go').first);
      await settle(tester);
      expect(speech.words, ['I', 'go'], reason: 'the keys are still quiet');

      await teardownBoard(tester);
    });
  });
}
