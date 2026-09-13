import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/utterance/pronunciation.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// Words the engine says wrong, respelled on the way to the voice (§4.86).
///
/// The board's label is what a person has learned to recognize and to reach
/// for. Fixing the sound by changing the label would fix the voice and break
/// the board, so only the string handed to the synthesizer changes.
void main() {
  group('the respellings', () {
    test('are what was actually reported wrong', () {
      expect(spokenForm('uh oh'), "u'h oh");
      expect(spokenForm('ow'), 'ouw');
    });

    test('and nothing else is touched', () {
      // A respelling is a guess about one engine on one platform. Guessing at
      // a word nobody has reported puts something nobody wrote into a person's
      // mouth, which is worse than a slightly odd vowel.
      for (final word in ['oops', 'yay', 'wow', 'huh', 'help', 'more', 'I']) {
        expect(spokenForm(word), isNull, reason: '"$word" got respelled');
      }
    });

    test('and a word with no respelling is handed over unchanged', () {
      expect(asSpoken('help'), 'help');
      expect(asSpoken('ow'), 'ouw');
    });

    test('matching ignores case and stray spaces', () {
      expect(spokenForm('  Ow '), 'ouw');
      expect(spokenForm('UH OH'), "u'h oh");
    });
  });

  group('the bar', () {
    test('shows the word and says the respelling', () {
      final bar = UtteranceBar();
      bar.add('ow');

      expect(bar.text, 'ow', reason: 'the board must still read "ow"');
      expect(bar.spokenText, 'ouw');
    });

    test('and mixes respelled and ordinary words in one sentence', () {
      final bar = UtteranceBar();
      bar.add('uh oh');
      bar.add('I');
      bar.add('need');
      bar.add('help');

      expect(bar.text, 'uh oh I need help');
      expect(bar.spokenText, "u'h oh I need help");
    });

    test('and backspacing takes the respelling with it', () {
      final bar = UtteranceBar();
      bar.add('ow');
      bar.backspace();
      bar.add('help');

      expect(bar.spokenText, 'help');
    });
  });
}
