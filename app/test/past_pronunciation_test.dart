import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/morphology.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// Words written one way and said another (§4.84).
///
/// The past of `read` is spelled `read` and pronounced `red`. Getting the
/// spelling right and the sound wrong is the whole of the failure here: this
/// app exists for the saying, and a board that says "reed" when somebody meant
/// the past tense has said a different word out loud.
void main() {
  group('the past of "read"', () {
    test('is still spelled "read"', () {
      expect(applyMorpheme('read', MorphemeKind.pastEd), 'read');
    });

    test('and is said "red"', () {
      expect(pastPronunciation('read'), 'red');
    });

    test('and nothing else is respelled', () {
      // Deliberately tiny: a respelling that guesses puts a word nobody wrote
      // into somebody's mouth.
      for (final word in ['walk', 'go', 'eat', 'win', 'play', 'lose']) {
        expect(
          pastPronunciation(word),
          isNull,
          reason: '"$word" got respelled',
        );
      }
    });
  });

  group('the bar', () {
    test('shows the spelling and says the sound', () {
      final bar = UtteranceBar();
      bar.add('I');
      bar.add('read', pos: PartOfSpeech.verb);
      bar.replaceLast(
        (w) => applyMorpheme(w, MorphemeKind.pastEd),
        saidAs: pastPronunciation,
      );
      bar.add('a');
      bar.add('book');

      expect(bar.text, 'I read a book');
      expect(bar.spokenText, 'I red a book');
    });

    test('and an ordinary word reads the same either way', () {
      final bar = UtteranceBar();
      bar.add('I');
      bar.add('walk', pos: PartOfSpeech.verb);
      bar.replaceLast(
        (w) => applyMorpheme(w, MorphemeKind.pastEd),
        saidAs: pastPronunciation,
      );

      expect(bar.text, 'I walked');
      expect(bar.spokenText, bar.text);
    });

    test('and a sentence with nothing inflected is unchanged', () {
      final bar = UtteranceBar();
      bar.add('I');
      bar.add('want');
      bar.add('juice');

      expect(bar.spokenText, bar.text);
    });

    test('backspacing the inflected word takes its pronunciation with it', () {
      final bar = UtteranceBar();
      bar.add('I');
      bar.add('read', pos: PartOfSpeech.verb);
      bar.replaceLast(
        (w) => applyMorpheme(w, MorphemeKind.pastEd),
        saidAs: pastPronunciation,
      );
      bar.backspace();

      expect(bar.spokenText, 'I');
    });
  });
}
