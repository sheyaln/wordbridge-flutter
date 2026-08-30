import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/fallback_board.dart';
import 'package:wordbridge/main.dart';

class _RecordingSpeech implements SpeechEngine {
  final spoken = <String>[];
  var started = false;

  @override
  Future<void> init() async => started = true;
  @override
  Future<void> speak(String text) async => spoken.add(text);
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

/// A widget that throws where the board would be.
class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => throw StateError('the board broke');
}

/// §5 non-negotiable 6: a crash never leaves a user with nothing.
///
/// What Flutter does by default is a red box in debug and a grey one in
/// release. For a nonspeaking person that is a tablet that has stopped talking,
/// and there is no way for them to say so.
void main() {
  test('it speaks the words the board would never page away', () {
    // The two lists are written separately — this board cannot read the
    // vocabulary, because it exists for the case where reading things has
    // stopped working — so something has to hold them together. A word marked
    // essential is one a grid too small to hold it is refused over; that is the
    // same question this board is asking.
    final essential = {
      for (final band in homeBands)
        for (final item in band.items)
          if (item.essential) item.value.label,
      for (final item in pinnedQuestions)
        if (item.essential) item.value.label,
    };

    expect(
      fallbackWords.toSet(),
      essential,
      reason:
          'the crash board and the seed disagree about which words a person '
          'cannot be left without',
    );
  });

  testWidgets('a widget that throws is replaced, not reported', (tester) async {
    // Restored inside the body, not in a tearDown: the framework checks that a
    // test left ErrorWidget.builder alone, and it checks before tearDowns run.
    final was = ErrorWidget.builder;
    try {
      installFallbackBoard();
      await tester.pumpWidget(const MaterialApp(home: _Broken()));

      // The framework records the throw as well as rendering the replacement,
      // and an unconsumed record fails the test on its own.
      expect(tester.takeException(), isA<StateError>());

      expect(find.text('help'), findsOneWidget);
      expect(
        find.textContaining('Something went wrong'),
        findsOneWidget,
        reason:
            'an unfamiliar board with nothing said about it reads as a board '
            'that rearranged itself, which is the one thing this app never '
            'does',
      );
    } finally {
      ErrorWidget.builder = was;
    }
  });

  testWidgets('every word on it speaks', (tester) async {
    final speech = _RecordingSpeech();
    await tester.pumpWidget(FallbackBoard(speech: speech));

    for (final word in fallbackWords) {
      await tester.tap(find.text(word));
      await tester.pump();
    }

    expect(speech.spoken, fallbackWords);
    expect(speech.started, isTrue);
  });

  testWidgets('it draws with no ancestors at all', (tester) async {
    // ErrorWidget.builder inserts this wherever the throw happened, which can
    // be above the widget that would have provided a theme or a text
    // direction. A fallback board that needs a MaterialApp to render is one
    // that fails exactly when the MaterialApp is what failed.
    await tester.pumpWidget(FallbackBoard(speech: _RecordingSpeech()));

    expect(tester.takeException(), isNull);
    expect(find.text('stop'), findsOneWidget);
  });

  group('a wait the board cannot be drawn without', () {
    testWidgets('ends at the fallback board when it fails', (tester) async {
      // Both of the app's waits used to print the reason and stop there, which
      // hands somebody a tablet with an error message where their voice was.
      final failing = Future<int>.error(StateError('no database'));

      // Given something to catch it before the zone sees it as unhandled. The
      // rejection reaches the builder either way; without this the framework
      // records it and fails the test on the record alone.
      unawaited(failing.catchError((_) => 0));

      await tester.pumpWidget(
        MaterialApp(
          home: awaiting<int>(
            future: failing,
            then: (_) => const Text('the board'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('help'), findsOneWidget);
      expect(find.text('the board'), findsNothing);
    });

    testWidgets('shows the board when it arrives', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: awaiting<int>(
            future: Future<int>.value(1),
            then: (_) => const Text('the board'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('the board'), findsOneWidget);
      expect(find.text('help'), findsNothing);
    });
  });

  testWidgets('a speech engine that throws does not take it down', (
    tester,
  ) async {
    await tester.pumpWidget(FallbackBoard(speech: _ThrowingSpeech()));
    await tester.tap(find.text('help'));
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'a crash inside the crash board leaves nowhere else to go',
    );
  });
}

class _ThrowingSpeech extends _RecordingSpeech {
  @override
  Future<void> speak(String text) async => throw StateError('no voice');
}
