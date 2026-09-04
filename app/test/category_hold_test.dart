import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
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

class _SilentSpeech implements SpeechEngine {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

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

/// Holding the cycle key to see every category at once.
///
/// The key turns the wheel one page per press, which suits somebody who knows
/// where they are going and strands somebody hunting: the categories past the
/// first page are behind presses that show nothing about what is there.
///
/// The thing this must not cost is the rest of the board. A hold is how an AAC
/// user with a slow or unsteady reach presses *any* key, and if holding a word
/// did something other than say it, the board would be punishing exactly the
/// motor difficulty it exists to accommodate. So the gesture is wired to one
/// key and every other location is left with no long-press handler at all.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    // 7x12: the smallest shipped grid, and the only size where the categories
    // outnumber the keys and a cycle key exists at all. At 9x15 and above they
    // all fit and there is nothing to cycle.
    vocabularyId = await seedCoreBoardSet(db, rows: 7, cols: 12);
  });

  // Deliberately not closed: closing inside a widget test waits on work the
  // fake clock never runs.

  Future<void> pumpBoard(WidgetTester tester, _SilentSpeech speech) async {
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
          profileId: 'p1',
          vocabLevel: 3,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> teardownBoard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('holding the cycle key shows every category', (tester) async {
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    final key = find.text(cycleCategoriesLabel);
    expect(key, findsOneWidget, reason: 'the cycle key is not on this board');

    await tester.longPress(key);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('All categories'), findsOneWidget);
    for (final name in ['people', 'food', 'play', 'numbers', 'objects']) {
      expect(
        find.text(name),
        findsWidgets,
        reason:
            '"$name" is reachable by pressing the key the right number of '
            'times and cannot be found by looking',
      );
    }

    await teardownBoard(tester);
  });

  testWidgets('holding an ordinary word only says it', (tester) async {
    // The gesture an unsteady hand makes on every key it presses.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    final word = find.text('want');
    expect(word, findsOneWidget, reason: 'the premise');

    await tester.longPress(word);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('All categories'),
      findsNothing,
      reason: 'a slow press on a word opened something',
    );
    expect(
      speech.spoken,
      contains('want'),
      reason: 'a slow press on a word failed to say it',
    );

    await teardownBoard(tester);
  });
}
