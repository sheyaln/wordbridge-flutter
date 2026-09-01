import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/contractions.dart';
import 'package:wordbridge/features/utterance/morphology.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// §4.42. "can" and "not" spoken as "can't", as a setting rather than a rule.
///
/// The same shape as the "a" → "an" repair: the user cannot know how the
/// sentence will continue when they press the first word, so the sentence is
/// corrected behind them once it does. What is different is that this one
/// *removes* a word rather than correcting one.
void main() {
  late UtteranceBar bar;

  setUp(() => bar = UtteranceBar());

  group('which pairs English contracts', () {
    test('the modals', () {
      expect(contractionFor('can'), "can't");
      expect(contractionFor('will'), "won't");
      expect(contractionFor('could'), "couldn't");
      expect(contractionFor('should'), "shouldn't");
      expect(contractionFor('would'), "wouldn't");
    });

    test('the forms of "to be", present and past', () {
      expect(contractionFor('is'), "isn't");
      expect(contractionFor('are'), "aren't");
      expect(contractionFor('was'), "wasn't");
      expect(contractionFor('were'), "weren't");
    });

    test('the auxiliaries', () {
      expect(contractionFor('do'), "don't");
      expect(contractionFor('does'), "doesn't");
      expect(contractionFor('did'), "didn't");
      expect(contractionFor('have'), "haven't");
      expect(contractionFor('has'), "hasn't");
      expect(contractionFor('had'), "hadn't");
    });

    test('but not "am", which English contracts at the other end', () {
      // "I am not" becomes "I'm not". "amn't" is not a word anybody says, and
      // contracting the subject is a different rule reaching further back.
      expect(contractionFor('am'), isNull);
    });

    test('and not an ordinary word', () {
      expect(contractionFor('want'), isNull);
      expect(contractionFor('apple'), isNull);
      expect(contractionFor(''), isNull);
    });

    test('however it was capitalized or spaced', () {
      expect(contractionFor('  Can '), "can't");
    });

    test('and "not" is the word it joins to', () {
      expect(isNegation('not'), isTrue);
      expect(isNegation(' NOT '), isTrue);
      expect(isNegation('no'), isFalse);
    });
  });

  group('joining the pair in the sentence', () {
    test('collapses the two into one and says the contraction', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      bar.add('can', pos: PartOfSpeech.verb);

      expect(bar.contract('not'), "can't");
      expect(bar.text, "I can't");
    });

    test('and the word pressed is not added on top of it', () {
      bar.add('can', pos: PartOfSpeech.verb);
      bar.contract('not');

      expect(bar.text, isNot(contains('not ')));
      expect(bar.text, "can't");
    });

    test('leaves a pair English does not contract alone', () {
      bar.add('want', pos: PartOfSpeech.verb);

      expect(bar.contract('not'), isNull);
      expect(
        bar.text,
        'want',
        reason: 'a refused contraction added the word anyway',
      );
    });

    test('and refuses anything that is not "not"', () {
      bar.add('can', pos: PartOfSpeech.verb);

      expect(bar.contract('go'), isNull);
      expect(bar.text, 'can');
    });

    test('an empty sentence has nothing to join to', () {
      expect(bar.contract('not'), isNull);
      expect(bar.text, isEmpty);
    });

    test('a copula still waiting for its subject is left alone', () {
      // "is" at the front of a question has not agreed with anything yet
      // (§4.10), and "isn't" is outside the ring the repair would correct —
      // so contracting here would strand "isn't you" where "aren't you" goes.
      bar.addCopula(past: false, mode: CopulaMode.agree);
      expect(bar.text, 'is', reason: 'the premise');

      expect(bar.contract('not'), isNull);
      expect(bar.add('you', pos: PartOfSpeech.pronoun), 'are');
      expect(bar.text, 'are you');
    });

    test('but one that has already agreed contracts', () {
      bar.add('it', pos: PartOfSpeech.pronoun);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      expect(bar.text, 'it is', reason: 'the premise');

      expect(bar.contract('not'), "isn't");
      expect(bar.text, "it isn't");
    });

    test('and the word-ending keys are not offered on top of it', () {
      bar.add('do', pos: PartOfSpeech.verb);
      bar.contract('not');

      // A contraction is a finished word. Offering "+ed" after "don't" is a
      // key that would build "don'ted" out of it.
      expect(
        grammarHelperApplies(
          kind: MorphemeKind.pastEd,
          tense: 'pastEd',
          previousText: bar.last!.text,
          previousPos: bar.last!.pos,
          previousInflected: bar.last!.inflected,
          atStart: false,
          copulaCycles: true,
        ),
        isFalse,
      );
    });
  });

  group('taking it back', () {
    test('deleting the contraction removes the whole pair', () {
      // Both words became one entry, so one backspace takes both. That is the
      // honest behavior: what is on the screen is one word.
      bar.add('I', pos: PartOfSpeech.pronoun);
      bar.add('can', pos: PartOfSpeech.verb);
      bar.contract('not');

      bar.backspace();
      expect(bar.text, 'I');
    });
  });
}
