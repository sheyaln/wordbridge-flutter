import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/morphology.dart';

void main() {
  String past(String w) => applyMorpheme(w, MorphemeKind.pastEd);
  String plural(String w) => applyMorpheme(w, MorphemeKind.pluralS);
  String ing(String w) => applyMorpheme(w, MorphemeKind.ing);

  group('past tense', () {
    test('irregulars are looked up, not derived', () {
      // The whole reason this file exists: a suffix rule produces "maked",
      // and a board that says "maked" teaches it to someone who will repeat
      // it and may not be corrected.
      expect(past('make'), 'made');
      expect(past('go'), 'went');
      expect(past('eat'), 'ate');
      expect(past('run'), 'ran');
      expect(past('drink'), 'drank');
      expect(past('do'), 'did');
    });

    test('unchanging pasts stay unchanged', () {
      expect(past('put'), 'put');
      expect(past('read'), 'read');
      expect(past('hurt'), 'hurt');
    });

    test('regular verbs take -ed', () {
      expect(past('want'), 'wanted');
      expect(past('help'), 'helped');
      expect(past('play'), 'played');
    });

    test('a final e is not doubled', () {
      expect(past('like'), 'liked');
      expect(past('dance'), 'danced');
      expect(past('love'), 'loved');
    });

    test('a final consonant doubles after a short vowel', () {
      expect(past('stop'), 'stopped');
      expect(past('hug'), 'hugged');
    });

    test('a consonant plus y becomes -ied', () {
      expect(past('carry'), 'carried');
      expect(past('try'), 'tried');
    });

    test('a vowel plus y just takes -ed', () {
      expect(past('play'), 'played');
      expect(past('enjoy'), 'enjoyed');
    });
  });

  group('plural and third person', () {
    test('regular words take -s', () {
      expect(plural('toy'), 'toys');
      expect(plural('want'), 'wants');
    });

    test('sibilants take -es', () {
      expect(plural('bus'), 'buses');
      expect(plural('box'), 'boxes');
      expect(plural('watch'), 'watches');
    });

    test('a consonant plus y becomes -ies', () {
      expect(plural('baby'), 'babies');
    });

    test('irregulars are looked up', () {
      expect(plural('child'), 'children');
      expect(plural('foot'), 'feet');
      expect(plural('go'), 'goes');
      expect(plural('do'), 'does');
    });
  });

  group('continuous', () {
    test('regular verbs take -ing', () {
      expect(ing('want'), 'wanting');
      expect(ing('play'), 'playing');
    });

    test('a silent e is dropped', () {
      expect(ing('make'), 'making');
      expect(ing('dance'), 'dancing');
    });

    test('a double e is kept', () {
      expect(ing('see'), 'seeing');
    });

    test('a final consonant doubles after a short vowel', () {
      expect(ing('run'), 'running');
      expect(ing('stop'), 'stopping');
    });
  });

  group('possessive', () {
    test('adds an apostrophe s', () {
      expect(applyMorpheme('mum', MorphemeKind.possessive), "mum's");
    });

    test('a word already ending in s takes only an apostrophe', () {
      expect(applyMorpheme('James', MorphemeKind.possessive), "James'");
    });
  });

  group('comparatives', () {
    test('regular and irregular', () {
      expect(applyMorpheme('good', MorphemeKind.comparativeEr), 'better');
      expect(applyMorpheme('good', MorphemeKind.superlativeEst), 'best');
      expect(applyMorpheme('cold', MorphemeKind.comparativeEr), 'colder');
      expect(applyMorpheme('happy', MorphemeKind.comparativeEr), 'happier');
    });
  });

  group('capitalisation', () {
    test('a capitalised word stays capitalised', () {
      expect(applyMorpheme('Maya', MorphemeKind.possessive), "Maya's");
    });

    test('"I" does not come back lowercase', () {
      expect(applyMorpheme('I', MorphemeKind.possessive), "I's");
    });
  });

  group('the copula agrees with its subject', () {
    test('present', () {
      // The point of agreement: "I" + the button gives a correct sentence,
      // not a correct word beside a wrong one.
      expect(copulaFor('I', past: false), 'am');
      expect(copulaFor('he', past: false), 'is');
      expect(copulaFor('she', past: false), 'is');
      expect(copulaFor('it', past: false), 'is');
      expect(copulaFor('you', past: false), 'are');
      expect(copulaFor('they', past: false), 'are');
    });

    test('past', () {
      expect(copulaFor('I', past: true), 'was');
      expect(copulaFor('he', past: true), 'was');
      expect(copulaFor('you', past: true), 'were');
      expect(copulaFor('they', past: true), 'were');
    });

    test('an unknown or absent subject falls back to the safe form', () {
      expect(copulaFor(null, past: false), 'is');
      expect(copulaFor('mum', past: false), 'is');
      expect(copulaFor(null, past: true), 'was');
    });

    test('the -body pronouns are singular', () {
      // They sit on the same row as "us" and "them" and read like a crowd,
      // but "everybody is here" is the sentence.
      expect(copulaFor('everybody', past: false), 'is');
      expect(copulaFor('somebody', past: false), 'is');
      expect(copulaFor('nobody', past: false), 'is');
      expect(copulaFor('everybody', past: true), 'was');
      expect(copulaFor('people', past: false), 'are');
    });

    test('a subject that arrives after the verb still settles the form', () {
      // A yes/no question inverts the two, so the copula is placed with
      // nothing yet to agree with.
      expect(copulaAgreeingWith('is', 'you'), 'are');
      expect(copulaAgreeingWith('is', 'I'), 'am');
      expect(copulaAgreeingWith('is', 'we'), 'are');
      expect(copulaAgreeingWith('is', 'they'), 'are');
      expect(copulaAgreeingWith('is', 'it'), 'is');
      expect(copulaAgreeingWith('is', 'mum'), 'is');
    });

    test('the placed form carries the tense', () {
      expect(copulaAgreeingWith('was', 'you'), 'were');
      expect(copulaAgreeingWith('was', 'it'), 'was');
      expect(copulaAgreeingWith('was', 'I'), 'was');
      expect(copulaAgreeingWith('were', 'it'), 'was');
      expect(copulaAgreeingWith('am', 'they'), 'are');
    });

    test('a word that is not a form of "to be" is left alone', () {
      // The bar settles only what the copula key placed. Anything else is a
      // word the user chose and it stays as tapped.
      expect(copulaAgreeingWith('want', 'you'), isNull);
      expect(copulaAgreeingWith('a', 'you'), isNull);
      expect(copulaAgreeingWith('', 'you'), isNull);
    });
  });

  _grammarTests();

  group('the forms this exists to produce', () {
    test('I am', () {
      expect('I ${copulaFor('I', past: false)}', 'I am');
    });

    test('I wanted', () {
      expect('I ${past('want')}', 'I wanted');
    });

    test('he made', () {
      expect('he ${past('make')}', 'he made');
    });
  });
}

void _grammarTests() {
  bool applies({
    MorphemeKind? kind,
    String tense = '',
    PartOfSpeech? after,
    String? text,
    bool inflected = false,
    bool atStart = false,
  }) => grammarHelperApplies(
    kind: kind,
    tense: tense,
    previousText: text,
    previousPos: after,
    previousInflected: inflected,
    atStart: atStart,
  );

  group('endings appear only where they apply', () {
    test('no ending is offered before a word has been said', () {
      // "+ed" with no verb to attach it to does nothing, so it is not shown.
      // The start of the sentence settles that on its own, whatever part of
      // speech is passed alongside it.
      for (final kind in MorphemeKind.values) {
        for (final pos in [null, ...PartOfSpeech.values]) {
          expect(
            applies(kind: kind, after: pos, atStart: true),
            isFalse,
            reason: '$kind at the start of a sentence, after $pos',
          );
        }
      }
    });

    test('tense endings follow a verb and nothing else', () {
      expect(
        applies(kind: MorphemeKind.pastEd, after: PartOfSpeech.verb),
        isTrue,
      );
      expect(applies(kind: MorphemeKind.ing, after: PartOfSpeech.verb), isTrue);

      for (final pos in [
        PartOfSpeech.noun,
        PartOfSpeech.pronoun,
        PartOfSpeech.preposition,
        PartOfSpeech.question,
        PartOfSpeech.negation,
      ]) {
        expect(applies(kind: MorphemeKind.pastEd, after: pos), isFalse);
      }
    });

    test('plural s serves both nouns and verbs', () {
      expect(
        applies(kind: MorphemeKind.pluralS, after: PartOfSpeech.noun),
        isTrue,
      );
      expect(
        applies(kind: MorphemeKind.pluralS, after: PartOfSpeech.verb),
        isTrue,
      );
      expect(
        applies(kind: MorphemeKind.pluralS, after: PartOfSpeech.preposition),
        isFalse,
      );
    });

    test('possessive follows something that can own', () {
      expect(
        applies(kind: MorphemeKind.possessive, after: PartOfSpeech.noun),
        isTrue,
      );
      expect(
        applies(kind: MorphemeKind.possessive, after: PartOfSpeech.pronoun),
        isTrue,
      );
      expect(
        applies(kind: MorphemeKind.possessive, after: PartOfSpeech.verb),
        isFalse,
      );
    });

    test('a suffix cannot be applied twice', () {
      // Otherwise "want" becomes "wanted" becomes "wanteded".
      expect(
        applies(
          kind: MorphemeKind.pastEd,
          after: PartOfSpeech.verb,
          inflected: true,
        ),
        isFalse,
      );
    });
  });

  group('the copula follows a subject', () {
    test('or opens the sentence, where the subject follows it', () {
      // "are you ok?" — a yes/no question inverts subject and verb, so the
      // key has to be there before anything has been said.
      expect(applies(kind: null, tense: 'present', atStart: true), isTrue);
      expect(applies(kind: null, tense: 'past', atStart: true), isTrue);
    });

    test('after a pronoun or noun', () {
      expect(
        applies(kind: null, tense: 'present', after: PartOfSpeech.pronoun),
        isTrue,
      );
      expect(
        applies(kind: null, tense: 'past', after: PartOfSpeech.noun),
        isTrue,
      );
    });

    test('never after a verb', () {
      // "want is" is not a sentence anyone means to build.
      expect(
        applies(kind: null, tense: 'present', after: PartOfSpeech.verb),
        isFalse,
      );
    });

    test('after a question word, which the subject follows', () {
      // "what is that?", "where are you?" — the commonest questions there
      // are, and the board builds them from this key.
      expect(
        applies(kind: null, tense: 'present', after: PartOfSpeech.question),
        isTrue,
      );
      expect(
        applies(kind: null, tense: 'past', after: PartOfSpeech.question),
        isTrue,
      );
    });

    test('after a determiner that stands for a thing, and no other', () {
      // "this is mine" is a sentence. "a is" and "more is" are not: those are
      // waiting for a noun.
      expect(
        applies(
          kind: null,
          tense: 'present',
          after: PartOfSpeech.determiner,
          text: 'this',
        ),
        isTrue,
      );

      for (final word in ['a', 'an', 'the', 'more', 'some', 'all']) {
        expect(
          applies(
            kind: null,
            tense: 'present',
            after: PartOfSpeech.determiner,
            text: word,
          ),
          isFalse,
          reason: '"$word is" is not a sentence',
        );
      }
    });
  });

  group('articles', () {
    test('open a sentence', () {
      expect(applies(tense: 'article', atStart: true), isTrue);
    });

    test('follow a verb or preposition', () {
      expect(applies(tense: 'article', after: PartOfSpeech.verb), isTrue);
      expect(
        applies(tense: 'article', after: PartOfSpeech.preposition),
        isTrue,
      );
    });

    test('do not stack on a noun already introduced', () {
      expect(applies(tense: 'article', after: PartOfSpeech.noun), isFalse);
    });
  });
}
