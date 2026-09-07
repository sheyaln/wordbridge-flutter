import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/morphology.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// Going back to a word already in the sentence and working on it (§4.76).
///
/// The bar used to grow at its end and nowhere else, so fixing the second word
/// of an eight-word sentence meant deleting six good ones to reach it. A
/// person building a sentence one tap at a time pays for that in minutes and
/// usually pays by giving up on the sentence instead.
///
/// The whole mechanism is one number — where the next word goes. Every
/// operation on the bar reads it, so the endings, the article repair, the
/// copula agreement and the contractions all follow the caret into the middle
/// of a sentence without knowing they have moved.
void main() {
  late UtteranceBar bar;

  setUp(() => bar = UtteranceBar());

  void say(List<String> words) {
    for (final w in words) {
      bar.add(w);
    }
  }

  group('with nobody editing', () {
    test('the bar is exactly what it always was', () {
      say(['I', 'want', 'more']);

      expect(bar.isEditingSegment, isFalse);
      expect(bar.text, 'I want more');
      expect(bar.caret, 3, reason: 'the caret follows the end of the bar');

      bar.backspace();
      expect(bar.text, 'I want');
    });

    test('a word lands at the end however long the sentence gets', () {
      say(['I', 'want', 'to', 'go']);
      bar.add('home');
      expect(bar.words, ['I', 'want', 'to', 'go', 'home']);
    });
  });

  group('selecting a word', () {
    test('puts the caret behind it', () {
      say(['go', 'to', 'the', 'shop']);
      bar.selectAt(0);

      expect(bar.isEditingSegment, isTrue);
      expect(bar.selectedIndex, 0);
      expect(bar.caret, 1);
    });

    test('tapping it again returns to the end', () {
      say(['go', 'to', 'the', 'shop']);
      bar.selectAt(0);
      bar.selectAt(0);

      expect(bar.isEditingSegment, isFalse);
      expect(bar.caret, 4);
    });

    test('a tap outside the sentence is the end of it', () {
      say(['go', 'home']);
      bar.selectAt(1);
      bar.selectAt(9);

      expect(bar.isEditingSegment, isFalse);
    });

    test('notifies, because the highlight has to move', () {
      var beats = 0;
      bar.addListener(() => beats++);
      say(['go', 'home']);
      final before = beats;

      bar.selectAt(0);
      expect(beats, before + 1);
      bar.toEnd();
      expect(beats, before + 2);
    });
  });

  group('editing where the caret is', () {
    test('delete takes the selected word and nothing else', () {
      say(['I', 'want', 'the', 'red', 'one']);
      bar.selectAt(3);
      bar.backspace();

      expect(bar.words, ['I', 'want', 'the', 'one']);
    });

    test('the next word lands where the deleted one was', () {
      // The repair this whole feature exists for: fix the third word without
      // touching the two after it.
      say(['I', 'want', 'the', 'red', 'one']);
      bar.selectAt(3);
      bar.backspace();
      bar.add('blue');

      expect(bar.text, 'I want the blue one');
    });

    test('a run of taps reads left to right, like it does at the end', () {
      say(['I', 'go', 'home']);
      bar.selectAt(0);
      bar.add('will');
      bar.add('not');

      expect(bar.text, 'I will not go home');
    });

    test('and the sentence can be carried on from the end afterwards', () {
      say(['go', 'shop']);
      bar.selectAt(0);
      bar.add('to');
      bar.toEnd();
      bar.add('now');

      expect(bar.text, 'go to shop now');
    });

    test('deleting the first word leaves the caret in front', () {
      say(['please', 'go', 'home']);
      bar.selectAt(0);
      bar.backspace();

      expect(bar.words, ['go', 'home']);
      expect(bar.caret, 0);
      expect(bar.selectedIndex, isNull, reason: 'nothing is behind the caret');

      bar.add('quickly');
      expect(bar.text, 'quickly go home');
    });

    test('deleting the last word left empties the bar and ends editing', () {
      say(['home']);
      bar.selectAt(0);
      bar.backspace();

      expect(bar.isEmpty, isTrue);
      expect(bar.isEditingSegment, isFalse);
    });

    test('clearing puts the caret back', () {
      say(['I', 'want', 'that']);
      bar.selectAt(0);
      bar.clear();

      expect(bar.isEmpty, isTrue);
      expect(bar.isEditingSegment, isFalse);
    });
  });

  group('the grammar engine follows the caret', () {
    test('an ending rewrites the selected word, not the last one', () {
      // "go +ing to the shop" is the example this was asked for.
      bar.add('go', pos: PartOfSpeech.verb);
      bar.add('to');
      bar.add('the');
      bar.add('shop');

      bar.selectAt(0);
      final inflected = bar.replaceLast(
        (w) => applyMorpheme(w, MorphemeKind.ing),
      );

      expect(inflected, 'going');
      expect(bar.text, 'going to the shop');
    });

    test('and the ending can be taken off and another put on', () {
      bar.add('go', pos: PartOfSpeech.verb);
      bar.add('home');

      bar.selectAt(0);
      bar.replaceLast((w) => applyMorpheme(w, MorphemeKind.ing));
      expect(bar.text, 'going home');

      bar.backspace();
      bar.add('went', pos: PartOfSpeech.verb);
      expect(bar.text, 'went home');
    });

    test('the article agrees with the word inserted after it', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      bar.add('want', pos: PartOfSpeech.verb);
      bar.add('a', pos: PartOfSpeech.determiner);
      bar.add('now');

      bar.selectAt(2);
      final repaired = bar.add('apple');

      expect(repaired, 'an', reason: 'the repair is spoken, so it is returned');
      expect(bar.text, 'I want an apple now');
    });

    test('the copula agrees with the subject in front of the caret', () {
      bar.add('they', pos: PartOfSpeech.pronoun);
      bar.add('here');

      bar.selectAt(0);
      final form = bar.addCopula(past: false, mode: CopulaMode.agree);

      expect(form, 'are');
      expect(bar.text, 'they are here');
    });

    test('a contraction collapses the pair the caret is at', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      bar.add('can', pos: PartOfSpeech.verb);
      bar.add('go', pos: PartOfSpeech.verb);

      bar.selectAt(1);
      final contracted = bar.contract('not');

      expect(contracted, "can't");
      expect(bar.text, "I can't go");
    });

    test('a numeral joins the numeral the caret is on', () {
      bar.add('1');
      bar.add('apples');

      bar.selectAt(0);
      expect(bar.joinNumber('5'), 'fifteen');
      expect(bar.words, ['15', 'apples']);
    });

    test('a mark lands at the caret rather than at the end', () {
      say(['stop', 'then', 'go']);
      bar.selectAt(0);
      bar.punctuate('!');

      expect(bar.text, 'stop! then go');
    });
  });
}
