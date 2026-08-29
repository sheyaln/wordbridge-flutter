import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/prediction/word_prediction.dart';

/// Suggesting the next word without undoing anything else.
///
/// Prediction is the feature most able to damage this app, because the obvious
/// implementation — put the likely words where the finger already is — is
/// precisely what stops a motor plan forming. These tests are mostly about
/// what prediction is not allowed to do.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
  });
  tearDown(() async => db.close());

  WordPrediction predictor({int level = 3}) => WordPrediction(
    db,
    profileId: 'p1',
    vocabularyId: vocabId,
    vocabLevel: level,
  );

  Future<List<String>> suggest(
    WordPrediction p, {
    String? previous,
    PartOfSpeech? previousPos,
    int limit = 5,
  }) async => [
    for (final b in await p.suggest(
      previous: previous,
      previousPos: previousPos,
      limit: limit,
    ))
      b.message,
  ];

  /// The first button carrying this word. A word is allowed two locations on
  /// two boards, so this cannot ask for exactly one.
  Future<Button> buttonFor(String message) async => (await (db.select(
    db.buttons,
  )..where((b) => b.message.equals(message))).get()).first;

  group('what it offers', () {
    test('the word this user actually follows another with', () async {
      final p = predictor();
      await p.learn(['I', 'want', 'more']);
      await p.learn(['I', 'want', 'more']);
      await p.learn(['I', 'like', 'more']);

      final after = await suggest(p, previous: 'I', limit: 3);
      expect(after.first, 'want', reason: 'seen twice, "like" once');
    });

    test('a first word, from how the user opens sentences', () async {
      final p = predictor();
      await p.learn(['you', 'go']);
      await p.learn(['you', 'stop']);

      expect((await suggest(p, previous: null, limit: 3)).first, 'you');
    });

    test('the same order every time', () async {
      // Two words seen equally often must not trade places between rebuilds.
      // A list that reshuffles under a finger is the failure this whole app
      // is organised to avoid.
      final p = predictor();
      await p.learn(['I', 'go']);
      await p.learn(['I', 'like']);

      final first = await suggest(p, previous: 'I', limit: 4);
      for (var i = 0; i < 5; i++) {
        expect(await suggest(p, previous: 'I', limit: 4), first);
      }
    });

    test('sentence openers on day one, from the shipped set', () async {
      // Day one is not an empty strip and not a static one. Nothing is known
      // about this user yet, so the shipped set answers: the words English
      // sentences actually begin with.
      final suggestions = await suggest(predictor(), previous: null, limit: 5);

      expect(suggestions, hasLength(5));

      // The property, not the exact list. Naming every word here would make
      // this a lock on the shipped table rather than a check on it, and the
      // table is meant to be argued with.
      expect(suggestions.first, 'I');
      expect(suggestions, containsAll(['I', 'you']));

      for (final word in suggestions) {
        final button = await buttonFor(word);
        expect(button.isSystem, isFalse);
      }
    });

    test('it moves when the sentence does, before learning anything', () async {
      // The failure this replaced: the same five words after every word,
      // which is a decoration that costs grid height, not a prediction.
      final p = predictor();

      final start = await suggest(p, previous: null, limit: 5);
      final afterPronoun = await suggest(
        p,
        previous: 'I',
        previousPos: PartOfSpeech.pronoun,
        limit: 5,
      );
      final afterVerb = await suggest(
        p,
        previous: 'want',
        previousPos: PartOfSpeech.verb,
        limit: 5,
      );

      expect(afterPronoun, isNot(start));
      expect(afterVerb, isNot(afterPronoun));
      expect(afterPronoun.first, 'want', reason: 'a pronoun wants a verb');
      expect(afterVerb, contains('more'));
    });

    test('the shipped set never outranks what the user has said', () async {
      // "want" is what the shipped set puts after "I". If this person always
      // says "go", that has to win — a guess must never displace a fact.
      final p = predictor();
      for (var i = 0; i < 3; i++) {
        await p.learn(['I', 'go']);
      }

      final suggestions = await suggest(
        p,
        previous: 'I',
        previousPos: PartOfSpeech.pronoun,
        limit: 5,
      );
      expect(suggestions.first, 'go');
    });

    test('it tops up a thin history rather than showing one word', () async {
      final p = predictor();
      await p.learn(['I', 'want']);

      final suggestions = await suggest(p, previous: 'I', limit: 5);
      expect(suggestions.first, 'want');
      expect(suggestions, hasLength(5));
    });

    test('never the same word twice', () async {
      final p = predictor();
      await p.learn(['I', 'want']);
      await p.learn(['want']);

      final suggestions = await suggest(p, previous: 'I', limit: 5);
      expect(suggestions.toSet(), hasLength(suggestions.length));
    });
  });

  group('what it must never offer', () {
    test('a word the caregiver has hidden', () async {
      final p = predictor();
      await p.learn(['I', 'want']);

      await (db.update(db.buttons)..where((b) => b.message.equals('want')))
          .write(const ButtonsCompanion(hidden: Value(true)));

      expect(
        await suggest(p, previous: 'I', limit: 5),
        isNot(contains('want')),
      );
    });

    test('a word held back by level', () async {
      final p = predictor();
      await p.learn(['I', 'want']);

      await (db.update(db.buttons)..where((b) => b.message.equals('want')))
          .write(const ButtonsCompanion(vocabLevel: Value(3)));

      final gated = WordPrediction(
        db,
        profileId: 'p1',
        vocabularyId: vocabId,
        vocabLevel: 1,
      );
      expect(
        await suggest(gated, previous: 'I', limit: 5),
        isNot(contains('want')),
        reason:
            'the strip must not route around a decision to hold a word '
            'back; the level would stop meaning anything',
      );
    });

    test('a word that is on nobody\'s board', () async {
      final p = predictor();
      await p.learn(['I', 'zzzznotaword']);

      expect(
        await suggest(p, previous: 'I', limit: 5),
        isNot(contains('zzzznotaword')),
      );
    });

    test('navigation, endings, or anything that is not a word', () async {
      final suggestions = await suggest(predictor(), previous: null, limit: 8);

      for (final word in suggestions) {
        final button = await buttonFor(word);
        expect(button.action, ButtonAction.speak);
        expect(button.isSystem, isFalse);
      }
    });

    test('another profile\'s history', () async {
      // "juice" is not something the shipped set ever offers after "I", so if
      // p2 is shown it, it can only have come from p1.
      final p1 = predictor();
      for (var i = 0; i < 5; i++) {
        await p1.learn(['I', 'juice']);
      }
      expect(await suggest(p1, previous: 'I', limit: 5), contains('juice'));

      final other = WordPrediction(
        db,
        profileId: 'p2',
        vocabularyId: vocabId,
        vocabLevel: 3,
      );
      expect(
        await suggest(other, previous: 'I', limit: 5),
        isNot(contains('juice')),
      );
    });
  });

  group('what it stores', () {
    test('counts, not sentences', () async {
      final p = predictor();
      await p.learn(['I', 'want', 'more', 'juice']);

      final rows = await db.select(db.predictionPairs).get();

      // Every row is a pair and a number. There is no time, no order beyond
      // the pair, and nothing that says these four words were one sentence.
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.count, greaterThan(0));
      }
      expect(db.predictionPairs.$columns.map((c) => c.name).toSet(), {
        'profile_id',
        'previous',
        'word',
        'count',
      });
    });

    test('punctuation is not a word and is not learned', () async {
      await predictor().learn(['you', 'want', 'that', '?']);

      final words = (await db.select(db.predictionPairs).get()).map(
        (r) => r.word,
      );
      expect(words, isNot(contains('?')));
    });

    test('forgetting leaves nothing behind', () async {
      final p = predictor();
      await p.learn(['I', 'want']);
      expect(await p.hasLearnedAnything(), isTrue);

      await p.forget();

      expect(await p.hasLearnedAnything(), isFalse);
      expect(await db.select(db.predictionPairs).get(), isEmpty);
    });

    test('forgetting one profile leaves the other alone', () async {
      await predictor().learn(['I', 'want']);
      await WordPrediction(
        db,
        profileId: 'p2',
        vocabularyId: vocabId,
        vocabLevel: 3,
      ).learn(['you', 'go']);

      await forgetPredictions(db, 'p1');

      final left = await db.select(db.predictionPairs).get();
      expect(left, isNotEmpty);
      expect(left.every((r) => r.profileId == 'p2'), isTrue);
    });
  });

  group('the motor plan', () {
    test('learning does not move, hide, or add a single button', () async {
      Future<List<String>> snapshot() async {
        final rows =
            await (db.select(db.buttons).join([
                  innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
                ])..orderBy([
                  OrderingTerm.asc(db.cells.boardId),
                  OrderingTerm.asc(db.cells.row),
                  OrderingTerm.asc(db.cells.col),
                ]))
                .get();

        return [
          for (final row in rows)
            '${row.readTable(db.cells).boardId}'
                '/${row.readTable(db.cells).row}'
                ',${row.readTable(db.cells).col}'
                '=${row.readTable(db.buttons).message}'
                '${row.readTable(db.buttons).hidden ? ' (hidden)' : ''}',
        ];
      }

      final before = await snapshot();

      final p = predictor();
      for (var i = 0; i < 20; i++) {
        await p.learn(['I', 'want', 'more']);
        await suggest(p, previous: 'I');
      }

      expect(await snapshot(), before);
    });
  });
}
