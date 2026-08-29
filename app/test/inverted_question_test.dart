import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/morphology.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// Questions that begin with the verb.
///
/// "are you ok?", "is it my turn?" — asking is a large part of what a voice is
/// for, and a board with no keyboard builds these from the copula key alone.
/// The question inverts subject and verb, so the copula is placed before there
/// is a subject to agree with: it lands in a provisional form and is settled
/// when the subject arrives, the same trade the article makes between "a" and
/// "an".
void main() {
  late UtteranceBar bar;

  setUp(() => bar = UtteranceBar());

  group('the subject settles the opening copula', () {
    test('are you', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'are you');
    });

    test('am I', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('I', pos: PartOfSpeech.pronoun);
      bar.add('finished', pos: PartOfSpeech.adjective);

      expect(bar.text, 'am I finished');
    });

    test('is it', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('it', pos: PartOfSpeech.pronoun);
      bar.add('my', pos: PartOfSpeech.determiner);
      bar.add('turn', pos: PartOfSpeech.noun);

      expect(bar.text, 'is it my turn');
    });

    test('are we', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('we', pos: PartOfSpeech.pronoun);
      bar.add('going', pos: PartOfSpeech.verb);
      bar.add('home', pos: PartOfSpeech.noun);

      expect(bar.text, 'are we going home');
    });

    test('were you', () {
      bar.addCopula(past: true, mode: CopulaMode.agree);
      bar.add('you', pos: PartOfSpeech.pronoun);
      bar.add('cross', pos: PartOfSpeech.adjective);

      expect(bar.text, 'were you cross');
    });

    test('was it', () {
      bar.addCopula(past: true, mode: CopulaMode.agree);
      bar.add('it', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'was it');
    });

    test('a noun subject takes the singular', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('mum', pos: PartOfSpeech.noun);
      bar.add('here', pos: PartOfSpeech.adverb);

      expect(bar.text, 'is mum here');
    });
  });

  group('a question word puts the subject after the verb too', () {
    test('what is that', () {
      bar.add('what', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('that', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'what is that');
    });

    test('where are you', () {
      bar.add('where', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'where are you');
    });

    test('who is it', () {
      bar.add('who', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('it', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'who is it');
    });

    test('when are we going', () {
      bar.add('when', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('we', pos: PartOfSpeech.pronoun);
      bar.add('going', pos: PartOfSpeech.verb);

      expect(bar.text, 'when are we going');
    });

    test('why is it broken', () {
      bar.add('why', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('it', pos: PartOfSpeech.pronoun);
      bar.add('broken', pos: PartOfSpeech.adjective);

      expect(bar.text, 'why is it broken');
    });

    test('where were you', () {
      bar.add('where', pos: PartOfSpeech.question);
      bar.addCopula(past: true, mode: CopulaMode.agree);
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'where were you');
    });

    test('what was that', () {
      bar.add('what', pos: PartOfSpeech.question);
      bar.addCopula(past: true, mode: CopulaMode.agree);
      bar.add('that', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'what was that');
    });

    test('where is mum', () {
      bar.add('where', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('mum', pos: PartOfSpeech.noun);

      expect(bar.text, 'where is mum');
    });

    test('the question word is not taken for the subject', () {
      // "who" reads plural to a rule that agrees with the word before it, and
      // "who are it" is what that costs.
      bar.add('who', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);

      expect(bar.words, ['who', 'is']);
    });

    test('where is everybody', () {
      bar.add('where', pos: PartOfSpeech.question);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('everybody', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'where is everybody');
    });
  });

  group('a copula tapped after its subject is left alone', () {
    test('I am hungry stays "am"', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('hungry', pos: PartOfSpeech.adjective);

      expect(bar.text, 'I am hungry');
    });

    test('it is you keeps the subject it agreed with', () {
      // Agreeing again with the word that follows would give "are".
      bar.add('it', pos: PartOfSpeech.pronoun);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'it is you');
    });

    test('they were it keeps the past plural', () {
      bar.add('they', pos: PartOfSpeech.pronoun);
      bar.addCopula(past: true, mode: CopulaMode.agree);
      bar.add('it', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'they were it');
    });
  });

  group('agreement stays with the copula that needs it', () {
    test('only the word straight after the copula settles it', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('it', pos: PartOfSpeech.pronoun);
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'is it you');
    });

    test('a word the copula cannot agree with leaves it as placed', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('ok', pos: PartOfSpeech.adjective);

      expect(bar.text, 'is ok');
    });

    test('backspacing the subject and choosing another agrees again', () {
      // One delete and one tap to correct the subject, not a rebuild.
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('you', pos: PartOfSpeech.pronoun);
      bar.backspace();
      bar.add('it', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'is it');
    });

    test('a copula tapped after its subject never re-agrees', () {
      bar.add('it', pos: PartOfSpeech.pronoun);
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('cold', pos: PartOfSpeech.adjective);
      bar.backspace();
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'it is you');
    });

    test('an ending on the opening copula still leaves it waiting', () {
      // "+ed" is offered after a verb, and the copula is one. Whatever tense
      // the key lands on, the subject is still to come.
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.replaceLast((w) => applyMorpheme(w, MorphemeKind.pastEd));
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'were you');
    });
  });

  test('the provisional form is what gets spoken on the tap', () {
    // Speech goes out on every tap, so the opening copula is heard before its
    // subject exists. The sentence is spoken again in full at the question
    // mark, which is where the settled form is heard.
    expect(bar.addCopula(past: false, mode: CopulaMode.agree), 'is');
    expect(UtteranceBar().addCopula(past: true, mode: CopulaMode.agree), 'was');
  });

  group('an article waits for a noun, not a verb', () {
    test('a copula landing after it leaves it alone', () {
      // The key is hidden after an article, so this is the board with the
      // contextual rules turned off. "an is" is not a repair anyone wanted.
      bar.add('a', pos: PartOfSpeech.determiner);
      bar.addCopula(past: false, mode: CopulaMode.agree);

      expect(bar.text, 'a is');
    });

    test('a noun still gets the repair', () {
      bar.add('a', pos: PartOfSpeech.determiner);
      bar.add('apple', pos: PartOfSpeech.noun);

      expect(bar.text, 'an apple');
    });
  });

  group('an ended sentence is not a word the grammar keys read', () {
    /// The copula key's availability, wired as the talk screen wires it.
    bool copulaKeyShows() {
      final previous = bar.last;
      return grammarHelperApplies(
        kind: null,
        tense: 'present',
        previousText: previous?.text,
        previousPos: previous?.pos,
        previousInflected: previous?.inflected ?? false,
        atStart: previous == null,
        copulaCycles: false,
      );
    }

    test('the copula key does not follow a mark', () {
      bar.add('more', pos: PartOfSpeech.determiner);
      bar.punctuate('?');

      expect(copulaKeyShows(), isFalse);
    });

    test('it does follow a question word', () {
      bar.add('what', pos: PartOfSpeech.question);

      expect(copulaKeyShows(), isTrue);
    });

    test('a copula landing after a mark opens a new sentence', () {
      bar.add('more', pos: PartOfSpeech.determiner);
      bar.punctuate('?');
      bar.addCopula(past: false, mode: CopulaMode.agree);
      bar.add('you', pos: PartOfSpeech.pronoun);

      expect(bar.text, 'more? are you');
    });
  });

  test('a question mark closes an inverted question', () {
    bar.addCopula(past: false, mode: CopulaMode.agree);
    bar.add('you', pos: PartOfSpeech.pronoun);
    bar.add('ok', pos: PartOfSpeech.adjective);
    bar.punctuate('?');

    expect(bar.text, 'are you ok?');
  });
}
