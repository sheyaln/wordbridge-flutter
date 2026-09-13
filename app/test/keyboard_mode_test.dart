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
import 'package:wordbridge/features/talk/keyboard_mode.dart';
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

/// Typing for as long as somebody wants to (§4.87).
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

  /// Opens the menu on the bar that holds find, type and the keyboard.
  Future<void> openKeyboard(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.search_rounded));
    await settle(tester);
    await tester.tap(find.text('Keyboard'));
    await settle(tester);
  }

  group('keyboard mode', () {
    testWidgets(
      'is reached from the bar, beside the other two ways to a word',
      (tester) async {
        await pumpBoard(tester, _Speech());

        await tester.tap(find.byIcon(Icons.search_rounded));
        await settle(tester);

        // The two that were already there keep their places, and this one is
        // last — a menu that reordered under somebody who had learned it is the
        // displacement this app refuses everywhere else.
        expect(find.text('Find a word'), findsOneWidget);
        expect(find.text('Type a word'), findsOneWidget);
        expect(find.text('Keyboard'), findsOneWidget);

        await tester.tap(find.text('Keyboard'));
        await settle(tester);

        expect(find.byType(KeyboardMode), findsOneWidget);

        await teardownBoard(tester);
      },
    );

    testWidgets('sends what was typed as one entry, not one per word', (
      tester,
    ) async {
      // The keypad's rule. What somebody composed in the field is one thing
      // they meant, and the bar's delete key should take that back rather
      // than leave them pressing it five times.
      final speech = _Speech();
      await pumpBoard(tester, speech);
      await openKeyboard(tester);

      await tester.enterText(find.byType(TextField), 'the bus was late');
      await settle(tester);
      await tester.tap(find.text('Add to sentence'));
      await settle(tester);

      expect(find.text('the bus was late'), findsWidgets);
      expect(speech.words, ['the bus was late']);

      // One delete takes the whole phrase back.
      await tester.tap(find.byTooltip('Delete last'));
      await settle(tester);
      expect(find.text('Nothing said yet'), findsOneWidget);

      await teardownBoard(tester);
    });

    testWidgets('stays open after a send, which is the point of it', (
      tester,
    ) async {
      final speech = _Speech();
      await pumpBoard(tester, speech);
      await openKeyboard(tester);

      await tester.enterText(find.byType(TextField), 'hello');
      await settle(tester);
      await tester.tap(find.text('Add to sentence'));
      await settle(tester);

      expect(find.byType(KeyboardMode), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: 'the field kept what was already sent',
      );

      await tester.enterText(find.byType(TextField), 'again');
      await settle(tester);
      await tester.tap(find.text('Add to sentence'));
      await settle(tester);

      expect(speech.words, ['hello', 'again']);

      await teardownBoard(tester);
    });

    testWidgets('says the sentence, and sends the field first', (tester) async {
      // Somebody who typed a last word and pressed speak meant that word to
      // be in the sentence.
      final speech = _Speech();
      await pumpBoard(tester, speech);
      await openKeyboard(tester);

      await tester.enterText(find.byType(TextField), 'I am ready');
      await settle(tester);
      await tester.tap(find.text('Say it'));
      await settle(tester);

      expect(speech.sentences, ['I am ready']);

      await teardownBoard(tester);
    });

    testWidgets('the sentence survives closing it', (tester) async {
      // A sentence started by typing and finished by tapping is the case this
      // screen is built around.
      final speech = _Speech();
      await pumpBoard(tester, speech);
      await openKeyboard(tester);

      await tester.enterText(find.byType(TextField), 'my sister');
      await settle(tester);
      await tester.tap(find.text('Add to sentence'));
      await settle(tester);

      expect(find.byTooltip('Back to the board'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to the board'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(KeyboardMode), findsNothing);
      expect(find.text('my sister'), findsWidgets, reason: 'the sentence went');

      await teardownBoard(tester);
    });

    testWidgets('the autocorrect toggle reaches the keyboard, and is kept', (
      tester,
    ) async {
      final speech = _Speech();
      await pumpBoard(tester, speech);
      await openKeyboard(tester);

      TextField field() => tester.widget<TextField>(find.byType(TextField));

      expect(field().autocorrect, isTrue);
      expect(field().enableSuggestions, isTrue);

      await tester.tap(find.text('Autocorrect on'));
      await settle(tester);

      expect(field().autocorrect, isFalse);
      expect(field().enableSuggestions, isFalse);
      expect(find.text('Autocorrect off'), findsOneWidget);
      expect(settings.keyboardAutocorrect, isFalse);

      await teardownBoard(tester);
    });

    testWidgets('and the typing screen reads the same setting', (tester) async {
      // One keyboard doing one job. Somebody who turned it off in one has
      // said what they want.
      await settings.set('keyboardAutocorrect', false);

      final speech = _Speech();
      await pumpBoard(tester, speech);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await settle(tester);
      await tester.tap(find.text('Type a word'));
      await settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      expect(find.text('Autocorrect off'), findsOneWidget);

      await teardownBoard(tester);
    });
  });
}
