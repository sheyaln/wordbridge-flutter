import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/contractions.dart';
import 'package:wordbridge/features/utterance/morphology.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// §4.42. Two pressed words spoken as the one word English says — "can" and
/// "not" as "can't", "I" and "am" as "I'm" — as a setting rather than a rule.
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
      expect(contractionOf('can', 'not'), "can't");
      expect(contractionOf('will', 'not'), "won't");
      expect(contractionOf('could', 'not'), "couldn't");
      expect(contractionOf('should', 'not'), "shouldn't");
      expect(contractionOf('would', 'not'), "wouldn't");
    });

    test('the forms of "to be", present and past', () {
      expect(contractionOf('is', 'not'), "isn't");
      expect(contractionOf('are', 'not'), "aren't");
      expect(contractionOf('was', 'not'), "wasn't");
      expect(contractionOf('were', 'not'), "weren't");
    });

    test('the auxiliaries', () {
      expect(contractionOf('do', 'not'), "don't");
      expect(contractionOf('does', 'not'), "doesn't");
      expect(contractionOf('did', 'not'), "didn't");
      expect(contractionOf('have', 'not'), "haven't");
      expect(contractionOf('has', 'not'), "hasn't");
      expect(contractionOf('had', 'not'), "hadn't");
    });

    test('but not "am", which English contracts at the other end', () {
      // "I am not" becomes "I'm not". "amn't" is not a word anybody says, and
      // contracting the subject is a different rule reaching further back.
      expect(contractionOf('am', 'not'), isNull);
    });

    test('and not an ordinary word', () {
      expect(contractionOf('want', 'not'), isNull);
      expect(contractionOf('apple', 'not'), isNull);
      expect(contractionOf('', 'not'), isNull);
    });

    test('however it was spaced, keeping the case that was pressed', () {
      expect(contractionOf('  Can ', 'not'), "Can't");
      expect(contractionOf(' can ', ' NOT '), "can't");
    });

    test('and "not" is a word that joins to what is in front of it', () {
      expect(canFollowInContraction('not'), isTrue);
      expect(canFollowInContraction(' NOT '), isTrue);
      expect(canFollowInContraction('no'), isFalse);
    });

    test('the subject pairs, which is the half a board presses far more', () {
      // A user builds "I am hungry" one key at a time and used to hear it
      // said that way, in a register nobody speaks in.
      expect(contractionOf('I', 'am'), "I'm");
      expect(contractionOf('you', 'are'), "you're");
      expect(contractionOf('we', 'are'), "we're");
      expect(contractionOf('they', 'will'), "they'll");
      expect(contractionOf('she', 'would'), "she'd");
      expect(contractionOf('it', 'is'), "it's");
    });

    test('the ones a question is built out of', () {
      expect(contractionOf('what', 'is'), "what's");
      expect(contractionOf('where', 'is'), "where's");
      expect(contractionOf('who', 'are'), "who're");
      expect(contractionOf('there', 'is'), "there's");
      expect(contractionOf('that', 'is'), "that's");
      expect(contractionOf('let', 'us'), "let's");
    });

    test('but not "have", which a board cannot tell apart from owning', () {
      // "I've eaten" is the perfect auxiliary; "I have a drink" is
      // possession, and both are pressed the same way. Saying "I've a drink"
      // for a request is worse than leaving the pair alone.
      expect(contractionOf('I', 'have'), isNull);
      expect(contractionOf('they', 'have'), isNull);
    });

    test('the case of the key pressed survives', () {
      // A board whose keys are capitalized must not start saying "i'm".
      expect(contractionOf('You', 'are'), "You're");
      expect(contractionOf('What', 'is'), "What's");
      expect(contractionOf('i', 'am'), "I'm", reason: '"I" carries its case');
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

    test('and refuses a word that joins to nothing', () {
      bar.add('can', pos: PartOfSpeech.verb);

      expect(bar.contract('go'), isNull);
      expect(bar.text, 'can');
    });

    test('joins a subject to the auxiliary after it', () {
      bar.add('I', pos: PartOfSpeech.pronoun);

      expect(bar.contract('am'), "I'm");
      expect(bar.text, "I'm");
    });

    test('and leaves a pair that only looks like one alone', () {
      // "can" then "am" is not a pair English joins, and the board must not
      // invent one out of two words that each belong to a pair.
      bar.add('can', pos: PartOfSpeech.verb);

      expect(bar.contract('am'), isNull);
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
