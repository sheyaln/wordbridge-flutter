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
  });

  group('the examples that prompted this', () {
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
