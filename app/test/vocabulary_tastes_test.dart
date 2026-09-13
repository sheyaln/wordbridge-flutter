import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/db/seed/vocabulary_top_up.dart';
import 'package:wordbridge/db/tables.dart';

import 'vocabulary_top_up_test.dart' show positions;

/// Tastes, an American sweet, a scale that has a bottom, and a pair of
/// opposites (§4.82).
void main() {
  late WordbridgeDatabase db;

  setUp(() {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  /// Every label in the set, and every board page it appears on.
  ///
  /// A set per word, not one board: `right` is on the root board as a
  /// direction and on `feelings` as the opposite of wrong, and `light` is on
  /// two boards for two meanings. Keying one board to a label silently keeps
  /// whichever row came back last, which reads as a word having moved.
  /// Where each word sits on one board, by label.
  Future<Map<String, ({int row, int col})>> placesOn(
    String vocabId,
    String boardName,
  ) async {
    // Every page of it. A board that overflowed is "doing", "doing 2" — the
    // same board continued — and a word on page two is still on that board.
    final pages =
        await (db.select(db.boards)
              ..where((b) => b.vocabularyId.equals(vocabId))
              ..where(
                (b) => b.name.equals(boardName) | b.name.like('$boardName %'),
              ))
            .get();

    final rows = await (db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.cells.boardId.isIn(pages.map((b) => b.id).toList()))).get();

    return {
      for (final r in rows)
        r.readTable(db.buttons).label: (
          row: r.readTable(db.cells).row,
          col: r.readTable(db.cells).col,
        ),
    };
  }

  Future<Map<String, Set<String>>> wordsIn(String vocabId) async {
    final names = {
      for (final b in await (db.select(
        db.boards,
      )..where((b) => b.vocabularyId.equals(vocabId))).get())
        b.id: b.name,
    };
    final rows = await (db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.buttons.vocabularyId.equals(vocabId))).get();

    final out = <String, Set<String>>{};
    for (final r in rows) {
      out
          .putIfAbsent(r.readTable(db.buttons).label, () => <String>{})
          .add(names[r.readTable(db.cells).boardId]!);
    }
    return out;
  }

  group('the four tastes', () {
    test('are on the food board', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      for (final taste in ['sweet', 'sour', 'bitter', 'salty']) {
        expect(
          words[taste]?.any((b) => b.startsWith('food')),
          isTrue,
          reason: '"$taste" is missing',
        );
      }
    });

    test(
      'on the row that answers "what is it like", not the verb row',
      () async {
        // They are adjectives, and the row they are on is the adjective row. A
        // describing word in the middle of the verbs would be the one button on
        // that row whose color meant something different.
        final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

        final boards = await (db.select(
          db.boards,
        )..where((b) => b.vocabularyId.equals(vocabId))).get();
        final food = boards.firstWhere((b) => b.name == 'food');

        final rows = await (db.select(db.buttons).join([
          innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
        ])..where(db.cells.boardId.equals(food.id))).get();

        final rowOf = {
          for (final r in rows)
            r.readTable(db.buttons).label: r.readTable(db.cells).row,
        };

        expect(rowOf['sweet'], rowOf['yummy']);
        expect(rowOf['sour'], rowOf['yummy']);
        expect(rowOf['bitter'], rowOf['yummy']);
        expect(rowOf['salty'], rowOf['yummy']);
        expect(
          rowOf['sweet'],
          isNot(rowOf['spill']),
          reason: 'a describing word landed on the verb row',
        );
      },
    );

    test('and they displaced nothing on the food board', () async {
      // The row had six words and twelve columns. Four more fit on it, which
      // is why this addition costs nothing — asserted rather than assumed.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      for (final word in [
        'hungry',
        'thirsty',
        'yummy',
        'yucky',
        'hot',
        'cold',
        'spill',
        'taste',
        'apple',
        'bread',
      ]) {
        expect(
          words[word],
          contains('food'),
          reason: '"$word" left page one of the food board',
        );
      }
    });
  });

  group('candy', () {
    test('is what the board says, and "sweets" is not on it', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['candy'], isNotNull);
      expect(words['sweets'], isNull, reason: 'the board still speaks British');
    });

    test('renames a board that already said "sweets", in place', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

      // Wind it back to what shipped before.
      await (db.update(db.buttons)
            ..where((b) => b.label.equals('candy') & b.isSystem.equals(false)))
          .write(
            const ButtonsCompanion(
              label: Value('sweets'),
              message: Value('sweets'),
            ),
          );

      final before = await positions(db);
      final result = await topUpVocabulary(db, vocabularyId: vocabId);

      expect(result.renamed, contains((from: 'sweets', to: 'candy')));

      final words = await wordsIn(vocabId);
      expect(words['candy'], isNotNull);
      expect(words['sweets'], isNull);

      // The whole point: the word changed, the location did not.
      expect(
        await positions(db),
        before,
        reason: 'renaming a word moved something',
      );
    });

    test('and is not offered again once it has been renamed', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      expect(
        (await topUpVocabulary(db, vocabularyId: vocabId)).renamed,
        isEmpty,
      );
    });

    test('leaves a message somebody had edited alone', () async {
      // The label is ours to correct. A sentence a caregiver wrote into the
      // button is theirs.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      await (db.update(db.buttons)
            ..where((b) => b.label.equals('candy') & b.isSystem.equals(false)))
          .write(
            const ButtonsCompanion(
              label: Value('sweets'),
              message: Value('I would like some sweets'),
            ),
          );

      await topUpVocabulary(db, vocabularyId: vocabId);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.label.equals('candy'))).getSingle();
      expect(button.message, 'I would like some sweets');
    });
  });

  group('together and separate', () {
    test('are on the measurement board, with the other opposites', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['together']!.single, startsWith('measurement'));
      expect(words['separate']!.single, startsWith('measurement'));
    });

    test('on the same row as the other distance pair', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final boards = await (db.select(
        db.boards,
      )..where((b) => b.vocabularyId.equals(vocabId))).get();
      final board = boards.firstWhere((b) => b.name == 'measurement');

      final rows = await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(board.id))).get();
      final rowOf = {
        for (final r in rows)
          r.readTable(db.buttons).label: r.readTable(db.cells).row,
      };

      expect(rowOf['together'], rowOf['far']);
      expect(rowOf['separate'], rowOf['far']);
    });
  });

  group('ok and bad', () {
    test('are on the board', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['ok'], isNotNull);
      expect(words['bad'], isNotNull);
    });

    test('sit in "good"\'s own column where the grid has room', () async {
      final roomy = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(roomy.close);
      final vocabId = await seedCoreBoardSet(roomy, rows: 10, cols: 14);

      final boards = await (roomy.select(
        roomy.boards,
      )..where((b) => b.vocabularyId.equals(vocabId))).get();
      final home = boards.firstWhere((b) => b.kind == BoardKind.root);

      final rows = await (roomy.select(roomy.buttons).join([
        innerJoin(roomy.cells, roomy.cells.id.equalsExp(roomy.buttons.cellId)),
      ])..where(roomy.cells.boardId.equals(home.id))).get();
      final at = {
        for (final r in rows)
          r.readTable(roomy.buttons).label: (
            row: r.readTable(roomy.cells).row,
            col: r.readTable(roomy.cells).col,
          ),
      };

      expect(at['ok']!.col, at['good']!.col);
      expect(at['bad']!.col, at['good']!.col);
      expect(at['ok']!.row, at['good']!.row + 1);
      expect(at['bad']!.row, at['good']!.row + 2);
    });

    test('and cost the tight grid nothing at all', () async {
      // The reason they are paged. At their own rank the describing band asks
      // for a second column at 7x12, and the column comes off `places`: this
      // is the list of words that left page one when that was tried.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      for (final word in [
        'under',
        'left',
        'right',
        'off',
        'forward',
        'backward',
        'good',
        'not',
        'yes',
        'no',
        "don't",
        'maybe',
      ]) {
        expect(
          words[word],
          contains('home'),
          reason: '"$word" was pushed off page one',
        );
      }
    });
  });

  group('the play board', () {
    test('has win and lose side by side', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final at = await placesOn(vocabId, 'play');

      expect(at['win']!.row, at['lose']!.row);
      expect(at['lose']!.col, at['win']!.col + 1);
    });

    test('has break beside build, and nowhere else', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final at = await placesOn(vocabId, 'play');
      final words = await wordsIn(vocabId);

      expect(at['break']!.row, at['build']!.row);
      expect(at['break']!.col, at['build']!.col + 1);

      // One word, one location: it left `doing` rather than being copied.
      expect(words['break'], hasLength(1));
      expect(words['break']!.single, startsWith('play'));
    });

    test('says movie and TV, not film and cartoon', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['movie'], isNotNull);
      expect(words['TV'], isNotNull);
      expect(words['film'], isNull);
      expect(words['cartoon'], isNull);
    });

    test('carries the new play words', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      for (final word in [
        'video game',
        'playground',
        'picture',
        'camera',
        'activity',
        'active',
        'sports',
        'soccer',
        'basketball',
      ]) {
        expect(
          words[word]?.any((b) => b.startsWith('play')),
          isTrue,
          reason: '"$word" is not on the play board',
        );
      }
    });

    test('and adding them moved nothing that was already there', () async {
      // `video game` reads best beside `game` and is appended instead,
      // because slotting it in pushed `puzzle` and `blocks` a column along.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final at = await placesOn(vocabId, 'play');

      expect(at['puzzle']!.col, at['game']!.col + 1);
      expect(at['blocks']!.col, at['game']!.col + 2);
      expect(at['video game']!.col, at['game']!.col + 3);
    });

    test('and "outside" is on places alone now', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['outside'], hasLength(1));
      expect(words['outside']!.single, startsWith('places'));
      expect(words['inside']!.single, startsWith('places'));
    });

    test('and "park" was not duplicated onto it', () async {
      // It has a level-1 location on `places`, one movement away. A second
      // copy is a second thing to learn about one word.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['park'], hasLength(1));
      expect(words['park']!.single, startsWith('places'));
    });
  });

  group('the colors board', () {
    test('exists, and was appended to the list', () async {
      // Appended, never inserted: the wheel is a window onto this list in
      // order, so a name anywhere but the end changes what a learned key
      // opens. It is not last any more — `nature` came after it — and that is
      // the point.
      expect(categoryNames, contains('colors'));
      expect(
        categoryNames.indexOf('colors'),
        greaterThan(categoryNames.indexOf('measurement')),
      );
    });

    test('carries the colors and its own name', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      for (final word in [
        'color',
        'red',
        'blue',
        'yellow',
        'green',
        'orange',
        'purple',
        'pink',
        'brown',
        'black',
        'white',
        'gray',
      ]) {
        expect(
          words[word]?.any((b) => b.startsWith('colors')),
          isTrue,
          reason: '"$word" is not on the colors board',
        );
      }
    });

    test(
      'and carries "rainbow", which is a thing rather than a color',
      () async {
        final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
        final at = await placesOn(vocabId, 'colors');

        expect(at['rainbow'], isNotNull);
        // On the noun row with "color", not among the hues: it names something
        // you point at rather than describing something else.
        expect(at['rainbow']!.row, at['color']!.row);
        expect(at['rainbow']!.row, isNot(at['red']!.row));
      },
    );

    test('and spells them the American way', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['grey'], isNull, reason: 'that is the British spelling');
      expect(words['colour'], isNull, reason: 'that is the British spelling');
    });
  });

  group('shopping', () {
    test('the place is "store" and the verb is "shop"', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['store']!.single, startsWith('places'));
      expect(words['shop']!.single, startsWith('doing'));
      // One label for two parts of speech makes the picture wrong for one of
      // them, which is what the rename is for.
      expect(words['shop'], hasLength(1));
    });

    test('and "buy" and "sell" are on the same row as it', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final at = await placesOn(vocabId, 'doing');

      expect(at['buy']!.row, at['shop']!.row);
      expect(at['sell']!.row, at['shop']!.row);
    });
  });

  group('the time board', () {
    test('reaches past a week, and down to a second', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final at = await placesOn(vocabId, 'time');

      for (final word in ['month', 'year', 'second', 'calendar']) {
        expect(at[word], isNotNull, reason: '"$word" is missing');
      }
      // On the row that already measures how long, appended so nothing on it
      // moved.
      expect(at['month']!.row, at['week']!.row);
      expect(at['week']!.col, lessThan(at['month']!.col));
    });
  });

  group('the nature board', () {
    test('exists, and carries what is outdoors', () async {
      expect(categoryNames.last, 'nature');

      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      for (final word in [
        'nature',
        'tree',
        'flower',
        'plant',
        'grass',
        'rock',
        'ocean',
        'moon',
        'star',
      ]) {
        expect(
          words[word]?.any((b) => b.startsWith('nature')),
          isTrue,
          reason: '"$word" is not on the nature board',
        );
      }
    });

    test('and leaves the weather and the animals to their own boards', () async {
      // A word on two boards is two things to learn about one word.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      for (final word in ['sun', 'rain', 'cloud', 'sky', 'wind']) {
        expect(
          words[word]!.any((b) => b.startsWith('nature')),
          isFalse,
          reason: '"$word" is on nature as well as weather',
        );
      }
      for (final word in ['bug', 'bird', 'fish']) {
        expect(
          words[word]!.any((b) => b.startsWith('nature')),
          isFalse,
          reason: '"$word" is on nature as well as animals',
        );
      }
      // And the one that collided: it is the thing a child digs in, on `play`.
      expect(words['sand']!.single, startsWith('play'));
    });
  });

  group('one word, one home', () {
    test('each of the six sits on the board it is wanted from', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      // The board somebody is standing on when they need the word.
      const homes = {
        'like': 'home',
        'doctor': 'health',
        'nurse': 'health',
        'bike': 'play',
        'thirsty': 'food',
        'itchy': 'health',
      };

      for (final entry in homes.entries) {
        expect(
          words[entry.key],
          hasLength(1),
          reason: '"${entry.key}" is still on more than one board',
        );
        expect(
          words[entry.key]!.single,
          startsWith(entry.value),
          reason: '"${entry.key}" is not on ${entry.value}',
        );
      }
    });

    test('and "chicken" keeps both, because it is two things', () async {
      // The bird in a field and the dinner on a plate. A child asking for one
      // is not asking for the other.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['chicken'], hasLength(2));
      expect(words['chicken'], containsAll(['food', 'animals']));
    });
  });

  group('being comfortable', () {
    test('is sayable, and so is not being', () async {
      // Without "uncomfortable" a chair, a seam or a position gets reported as
      // "hurt", which is a different thing and gets a person examined for a
      // problem they do not have.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final at = await placesOn(vocabId, 'feelings');

      expect(at['comfortable'], isNotNull);
      expect(at['uncomfortable'], isNotNull);
      expect(at['comfortable']!.row, at['uncomfortable']!.row);
    });
  });

  group('"on"', () {
    test('is one button, not two', () async {
      // Position and the opposite of "off" are the same three letters, said
      // the same way. A second button would be indistinguishable from the
      // first on the board and in the ear, and the movement to it would be a
      // coin toss between two locations that do the same thing.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final rows =
          await (db.select(db.buttons).join([
                  innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
                ])
                ..where(db.buttons.vocabularyId.equals(vocabId))
                ..where(db.buttons.label.equals('on'))
                ..where(db.buttons.isSystem.equals(false)))
              .get();

      expect(rows, hasLength(1));
    });

    test('and sits in the same band as "off"', () async {
      // Which is what makes the pair usable without a second button: they are
      // neighbors, so "on" and "off" are one region of the board.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final words = await wordsIn(vocabId);

      expect(words['on'], contains('home'));
      expect(words['off'], contains('home'));
    });
  });
}
