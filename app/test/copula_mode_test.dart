import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/utterance/morphology.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// Two ways to reach a form of "to be", and the sound each one makes.
///
/// One key holds am/is/are and one holds was/were, so something has to choose.
/// Both choices agree with a subject that is already in the bar; they part
/// company at the start of a question, where the subject has yet to be tapped.
///
/// The audio is the point of every assertion here. A board where the bar and
/// the speech disagree is worse than one that is simply wrong, because the
/// person using it has no way to find out.
void main() {
  late UtteranceBar bar;

  setUp(() => bar = UtteranceBar());

  String present() => bar.addCopula(past: false, mode: CopulaMode.toggle);
  String past() => bar.addCopula(past: true, mode: CopulaMode.toggle);

  group('pressing the key again changes the form in place', () {
    test('the present ring is is → are → am, and wraps', () {
      expect(present(), 'is');
      expect(present(), 'are');
      expect(present(), 'am');
      expect(present(), 'is');
      expect(bar.words, ['is']);
    });

    test('the past ring is was → were, and wraps', () {
      expect(past(), 'was');
      expect(past(), 'were');
      expect(past(), 'was');
      expect(bar.words, ['was']);
    });

    test('"are you ok?" is two presses and no correction', () {
      present();
      expect(present(), 'are');
      bar.add('you', pos: PartOfSpeech.pronoun);
      bar.add('ok', pos: PartOfSpeech.adjective);
      bar.punctuate('?');

      expect(bar.text, 'are you ok?');
    });

    test('the subject that arrives afterwards changes nothing', () {
      expect(present(), 'is');
      // The form was chosen by ear and out loud. Correcting it here would
      // overwrite a decision somebody made and heard themselves make.
      expect(bar.add('you', pos: PartOfSpeech.pronoun), isNull);
      expect(bar.text, 'is you');
    });
  });

  group('the first press still agrees, so mid-sentence needs no second', () {
    test('I am', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      expect(present(), 'am');
      expect(bar.text, 'I am');
    });

    test('they are', () {
      bar.add('they', pos: PartOfSpeech.pronoun);
      expect(present(), 'are');
    });

    test('we were', () {
      bar.add('we', pos: PartOfSpeech.pronoun);
      expect(past(), 'were');
    });

    test('a question word is not a subject', () {
      bar.add('what', pos: PartOfSpeech.question);
      expect(present(), 'is');
    });

    test('cycling from an agreed form keeps the ring order', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      expect(present(), 'am');
      expect(present(), 'is');
      expect(present(), 'are');
      expect(bar.text, 'I are');
    });
  });

  group('the other tense switches rather than stacking', () {
    test('"I am" pressed on the past key is "I was"', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      present();
      expect(past(), 'was');
      expect(bar.text, 'I was');
    });

    test('"they are" pressed on the past key is "they were"', () {
      bar.add('they', pos: PartOfSpeech.pronoun);
      present();
      expect(past(), 'were');
    });

    test('an opening "was" pressed on the present key is "is"', () {
      past();
      expect(present(), 'is');
      expect(bar.words, ['is']);
    });
  });

  group('the key stays reachable while it has something to change', () {
    /// The copula key's availability, wired as the talk screen wires it.
    bool copulaKeyShows({required bool cycles}) {
      final previous = bar.last;
      return grammarHelperApplies(
        kind: null,
        tense: 'present',
        previousText: previous?.text,
        previousPos: previous?.pos,
        previousInflected: previous?.inflected ?? false,
        atStart: previous == null,
        copulaCycles: cycles,
      );
    }

    test('a second press has somewhere to land', () {
      present();
      expect(copulaKeyShows(cycles: true), isTrue);
    });

    test('and does not when the form is settled instead', () {
      present();
      expect(copulaKeyShows(cycles: false), isFalse);
    });

    test('cycling does not open the key after an ordinary verb', () {
      bar.add('want', pos: PartOfSpeech.verb);
      expect(copulaKeyShows(cycles: true), isFalse);
    });
  });

  group('a correction is spoken, not made silently', () {
    test('the word that settles an opening copula reports the repair', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      expect(bar.add('you', pos: PartOfSpeech.pronoun), 'are');
      expect(bar.text, 'are you');
    });

    test('nothing is reported when the form was already right', () {
      bar.addCopula(past: false, mode: CopulaMode.agree);
      expect(bar.add('it', pos: PartOfSpeech.pronoun), isNull);
      expect(bar.text, 'is it');
    });

    test('the past copula reports its repair too', () {
      bar.addCopula(past: true, mode: CopulaMode.agree);
      expect(bar.add('we', pos: PartOfSpeech.pronoun), 'were');
    });

    test('an ordinary word reports nothing', () {
      bar.add('I', pos: PartOfSpeech.pronoun);
      expect(bar.add('want', pos: PartOfSpeech.verb), isNull);
    });

    test('the article reports its own correction', () {
      bar.add('a', pos: PartOfSpeech.determiner);
      expect(bar.add('apple', pos: PartOfSpeech.noun), 'an');
      expect(bar.text, 'an apple');
    });

    test('and reports nothing when "a" was already right', () {
      bar.add('a', pos: PartOfSpeech.determiner);
      expect(bar.add('drink', pos: PartOfSpeech.noun), isNull);
    });
  });

  group('the choice is kept per profile', () {
    late WordbridgeDatabase db;
    late ProfileSettings settings;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      final ts = nowMs();
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'p1',
              displayName: 'Maya',
              createdAt: ts,
              updatedAt: ts,
            ),
          );

      settings = ProfileSettings(db, 'p1');
      await settings.load();
    });

    tearDown(() => db.close());

    test('cycling is what a profile gets without being asked', () {
      expect(settings.copulaMode, CopulaMode.toggle);
    });

    test('the other answer survives being written and read back', () async {
      // The name written here and the key it is written under are what the
      // settings screen sends; a getter reading a different key would default
      // silently and the screen would report a choice the board never made.
      await settings.set('copulaMode', CopulaMode.agree.name);

      final reopened = ProfileSettings(db, 'p1');
      await reopened.load();

      expect(reopened.copulaMode, CopulaMode.agree);
    });
  });
}
