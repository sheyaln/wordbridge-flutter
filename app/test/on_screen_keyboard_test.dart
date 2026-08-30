import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/grid/grid_geometry.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/on_screen_keyboard.dart';

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

class _ThrowingSpeech extends _RecordingSpeech {
  @override
  Future<void> speak(String text) async => throw StateError('no voice');
}

/// What the sheet gave back, and whether it has given anything back yet.
class _Opened {
  String? word;
  var closed = false;
}

/// The keyboard is for the words the board does not hold, and the thing it has
/// to get right is silence: a person spelling "drink" is saying one word, not
/// five letters, and a keyboard that reads the letters out has said something
/// nobody meant to say.
void main() {
  final everyKey = [for (final row in OnScreenKeyboard.rows) ...row];

  /// A tablet in landscape, which is what this runs on. A phone-sized default
  /// test window is narrower than the keys fit in.
  void useTablet(WidgetTester tester) {
    tester.view.physicalSize = const Size(2048, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester, {
    SpeechEngine? speech,
    void Function(String)? onWord,
    VoidCallback? onClose,
    Size? box,
  }) async {
    useTablet(tester);

    final keyboard = OnScreenKeyboard(
      speech: speech,
      onWord: onWord,
      onClose: onClose,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: box == null
              ? keyboard
              : Center(
                  child: SizedBox.fromSize(size: box, child: keyboard),
                ),
        ),
      ),
    );
  }

  Future<void> press(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(OnScreenKeyboard.keyFor(id)));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String word) async {
    for (final letter in word.split('')) {
      await press(tester, letter == ' ' ? OnScreenKeyboard.space : letter);
    }
  }

  /// What the field is showing, or null while it is empty.
  String? field(WidgetTester tester) {
    final found = find.byKey(OnScreenKeyboard.fieldKey);
    if (found.evaluate().isEmpty) return null;
    return tester.widget<Text>(found).data;
  }

  Rect rectOf(WidgetTester tester, String id) =>
      tester.getRect(find.byKey(OnScreenKeyboard.keyFor(id)));

  group('silence until the word is finished', () {
    testWidgets('not one letter is spoken on the way', (tester) async {
      final speech = _RecordingSpeech();
      await pump(tester, speech: speech);

      for (final letter in 'drink'.split('')) {
        await press(tester, letter);
        await tester.pump();
        expect(
          speech.spoken,
          isEmpty,
          reason:
              'the letter "$letter" was read out, so the room heard five '
              'noises instead of the word',
        );
      }

      await press(tester, OnScreenKeyboard.send);
      await tester.pump();

      expect(speech.spoken, ['drink']);
      expect(speech.started, isTrue);
    });

    testWidgets('and then it is said once, not twice', (tester) async {
      final speech = _RecordingSpeech();
      await pump(tester, speech: speech);

      await type(tester, 'drink');
      await press(tester, OnScreenKeyboard.send);
      await tester.pump(const Duration(seconds: 2));

      expect(speech.spoken, ['drink']);
    });

    testWidgets('the finished word reaches the caller', (tester) async {
      final words = <String>[];
      await pump(tester, speech: _RecordingSpeech(), onWord: words.add);

      await type(tester, 'drink');
      expect(words, isEmpty);

      await press(tester, OnScreenKeyboard.send);
      expect(words, ['drink']);
    });

    testWidgets('a spoken word leaves the field ready for the next', (
      tester,
    ) async {
      await pump(tester, speech: _RecordingSpeech());

      await type(tester, 'drink');
      await press(tester, OnScreenKeyboard.send);

      expect(field(tester), isNull);
    });
  });

  group('what has been typed', () {
    testWidgets('shows in the field, letter by letter', (tester) async {
      await pump(tester, speech: _RecordingSpeech());

      expect(field(tester), isNull);
      await type(tester, 'cat');
      expect(field(tester), 'cat');
    });

    testWidgets('backspace takes back the last letter only', (tester) async {
      await pump(tester, speech: _RecordingSpeech());

      await type(tester, 'cat');
      await press(tester, OnScreenKeyboard.backspace);

      expect(field(tester), 'ca');
    });

    testWidgets('backspace on an empty field does nothing', (tester) async {
      await pump(tester, speech: _RecordingSpeech());

      await press(tester, OnScreenKeyboard.backspace);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(field(tester), isNull);
    });

    testWidgets('space belongs to the word, not to the end of it', (
      tester,
    ) async {
      final speech = _RecordingSpeech();
      await pump(tester, speech: speech);

      await type(tester, 'ice cream');
      expect(field(tester), 'ice cream');

      await press(tester, OnScreenKeyboard.send);
      await tester.pump();

      expect(speech.spoken, ['ice cream']);
    });

    testWidgets('the apostrophe types', (tester) async {
      final speech = _RecordingSpeech();
      await pump(tester, speech: speech);

      await type(tester, "don't");
      await press(tester, OnScreenKeyboard.send);
      await tester.pump();

      expect(speech.spoken, ["don't"]);
    });
  });

  group('nothing to say', () {
    testWidgets('sending an empty field says nothing', (tester) async {
      final speech = _RecordingSpeech();
      final words = <String>[];
      await pump(tester, speech: speech, onWord: words.add);

      await press(tester, OnScreenKeyboard.send);
      await tester.pump(const Duration(seconds: 1));

      expect(speech.spoken, isEmpty);
      expect(words, isEmpty);
    });

    testWidgets('nor does a field holding only a space', (tester) async {
      final speech = _RecordingSpeech();
      final words = <String>[];
      await pump(tester, speech: speech, onWord: words.add);

      await press(tester, OnScreenKeyboard.space);
      await press(tester, OnScreenKeyboard.send);
      await tester.pump(const Duration(seconds: 1));

      expect(speech.spoken, isEmpty);
      expect(words, isEmpty);
    });
  });

  group('the keys', () {
    test('cover the alphabet, once each, and nothing else', () {
      expect(
        everyKey.toSet(),
        hasLength(everyKey.length),
        reason: 'one letter in two places is two places to learn for one key',
      );

      final letters = [
        for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++)
          String.fromCharCode(c),
      ];
      expect(everyKey, containsAll(letters));
      expect(
        everyKey,
        containsAll([
          "'",
          OnScreenKeyboard.space,
          OnScreenKeyboard.backspace,
          OnScreenKeyboard.send,
        ]),
      );

      expect(
        everyKey.where((id) => id.length == 1),
        hasLength(27),
        reason: '26 letters and an apostrophe; no number row',
      );
    });

    testWidgets('are all a comfortable target', (tester) async {
      await pump(tester, speech: _RecordingSpeech(), onClose: () {});

      for (final id in [...everyKey, OnScreenKeyboard.close]) {
        final size = tester.getSize(find.byKey(OnScreenKeyboard.keyFor(id)));
        expect(
          size.width,
          greaterThanOrEqualTo(GridGeometry.minTouchTarget),
          reason: '"$id" is narrower than a fingertip',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(GridGeometry.minTouchTarget),
          reason: '"$id" is shorter than a fingertip',
        );
      }
    });

    testWidgets('stay that size in a box too small for them', (tester) async {
      // Narrower and shorter than the keys fit in. They scroll rather than
      // shrinking: a mistyped letter is a word nobody said.
      await pump(tester, speech: _RecordingSpeech(), box: const Size(360, 320));

      for (final id in everyKey) {
        final size = tester.getSize(find.byKey(OnScreenKeyboard.keyFor(id)));
        expect(size.width, greaterThanOrEqualTo(GridGeometry.minTouchTarget));
        expect(size.height, greaterThanOrEqualTo(GridGeometry.minTouchTarget));
      }
    });

    testWidgets('do not move while a word is typed', (tester) async {
      Future<void> holdStill(Size? box) async {
        await pump(tester, speech: _RecordingSpeech(), box: box);

        final before = {for (final id in everyKey) id: rectOf(tester, id)};
        await type(tester, "don't");
        final after = {for (final id in everyKey) id: rectOf(tester, id)};

        expect(
          after,
          before,
          reason: 'a key that moved once is a key that has to be found again',
        );
      }

      await holdStill(null);
      // Again with no room to spare, where anything the field does with the
      // space it is given comes straight out of the keys.
      await holdStill(const Size(800, 440));
    });

    testWidgets('line up, row against row', (tester) async {
      await pump(tester, speech: _RecordingSpeech());

      final left = rectOf(tester, OnScreenKeyboard.rows.first.first).left;
      final right = rectOf(tester, OnScreenKeyboard.rows.first.last).right;

      for (final row in OnScreenKeyboard.rows) {
        expect(rectOf(tester, row.first).left, closeTo(left, 0.01));
        expect(rectOf(tester, row.last).right, closeTo(right, 0.01));
      }
    });
  });

  testWidgets('a speech engine that throws does not take it down', (
    tester,
  ) async {
    final words = <String>[];
    await pump(tester, speech: _ThrowingSpeech(), onWord: words.add);

    await type(tester, 'drink');
    await press(tester, OnScreenKeyboard.send);
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.takeException(),
      isNull,
      reason: 'a voice that failed must not also cost the person the board',
    );
    expect(words, ['drink']);
  });

  group('as a sheet', () {
    Future<_Opened> openSheet(WidgetTester tester, SpeechEngine speech) async {
      final opened = _Opened();
      useTablet(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  opened.word = await OnScreenKeyboard.show(
                    context,
                    speech: speech,
                  );
                  opened.closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('gives back the word that was said', (tester) async {
      final speech = _RecordingSpeech();
      final opened = await openSheet(tester, speech);

      await type(tester, 'cat');
      await press(tester, OnScreenKeyboard.send);
      await tester.pumpAndSettle();

      expect(opened.closed, isTrue);
      expect(opened.word, 'cat');
      expect(speech.spoken, ['cat']);
      expect(find.byType(OnScreenKeyboard), findsNothing);
    });

    testWidgets('gives back nothing when it is closed', (tester) async {
      final speech = _RecordingSpeech();
      final opened = await openSheet(tester, speech);

      await type(tester, 'cat');
      await press(tester, OnScreenKeyboard.close);
      await tester.pumpAndSettle();

      expect(opened.closed, isTrue);
      expect(opened.word, isNull);
      expect(speech.spoken, isEmpty);
      expect(find.byType(OnScreenKeyboard), findsNothing);
    });
  });
}
