import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/talk/word_path.dart';

/// Words Haley asked for, and what adding them cost.
///
/// Each goes into a band that already exists and already means what the word
/// means, so none of them should open a row or widen one. That is the claim,
/// and the only honest way to check it is to lay every grid out both ways and
/// compare where every word landed — the way §4.28 measured `maybe`.
void main() {
  /// Every word on a board set, keyed by board and label.
  Future<Map<String, Map<String, ({int row, int col})>>> layout({
    required int rows,
    required int cols,
    AgeBand ageBand = AgeBand.child,
    String? userName,
  }) async {
    final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    try {
      final vocabId = await seedCoreBoardSet(
        db,
        rows: rows,
        cols: cols,
        ageBand: ageBand,
        userName: userName,
      );

      final rows_ =
          await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
                innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
              ])..where(
                db.buttons.vocabularyId.equals(vocabId) &
                    db.buttons.isSystem.equals(false),
              ))
              .get();

      final out = <String, Map<String, ({int row, int col})>>{};
      for (final r in rows_) {
        final board = r.readTable(db.boards).name;
        final cell = r.readTable(db.cells);
        out.putIfAbsent(board, () => {})[r.readTable(db.buttons).label] = (
          row: cell.row,
          col: cell.col,
        );
      }
      return out;
    } finally {
      await db.close();
    }
  }

  /// The grids the app can actually build, plus the two shipped by hand.
  final grids = <(int, int)>[
    for (var rows = 4; rows <= 9; rows++)
      for (var cols = 6; cols <= 15; cols++)
        if (boardSetRefusal(rows: rows, cols: cols) == null) (rows, cols),
  ];

  test('the premise: there are grids to measure', () {
    expect(grids.length, greaterThan(20), reason: 'the sweep is not sweeping');
  });

  group('the words landed', () {
    test('sorry is with the other things people say', () async {
      final board = (await layout(rows: 7, cols: 12))['people']!;

      expect(board, contains('sorry'));
      expect(
        board['sorry']!.row,
        board['thank you']!.row,
        reason: 'sorry left the greeting row it was put in',
      );
    });

    test('butt is on the body board, not behind the adult page', () async {
      final child = (await layout(rows: 7, cols: 12))['health']!;
      expect(child, contains('butt'));
    });

    test('unlikely joins the words for not being sure', () async {
      final board = (await layout(rows: 7, cols: 12))['feelings']!;

      expect(board, contains('unlikely'));
      expect(board['unlikely']!.row, board['perhaps']!.row);
    });

    test('the possessives are on the people board, both forms', () async {
      final board = (await layout(rows: 7, cols: 12))['people']!;

      for (final word in ['your', 'our', 'their', 'yours', 'ours', 'theirs']) {
        expect(board, contains(word), reason: '"$word" was not placed');
      }
    });

    test('her is not on the people board twice', () async {
      // It is an object pronoun and a possessive and spelled the same. Two
      // keys reading "her" is a person unable to tell them apart.
      final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

      final labels =
          await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
                innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
              ])..where(
                db.buttons.vocabularyId.equals(vocabId) &
                    db.buttons.label.equals('her') &
                    db.boards.name.equals('people'),
              ))
              .get();

      expect(labels, hasLength(1));
    });
  });

  group('the time board', () {
    test('was appended, so nothing else moved', () {
      // It was the last key when it landed and is not any more — `objects`
      // shipped after it. What made it safe is the thing that still has to
      // hold: every category that existed before it sits exactly where it did,
      // so every key already learned opens what it always opened.
      expect(categoryNames.take(categoryNames.indexOf('time')), [
        'people',
        'food',
        'play',
        'feelings',
        'places',
        'health',
        'doing',
        'numbers',
      ]);
    });

    test('answers when, at level 1', () async {
      final board = (await layout(rows: 7, cols: 12))['time']!;

      for (final word in ['now', 'later', 'soon', 'today']) {
        expect(board, contains(word), reason: '"$word" was not placed');
      }
    });

    test('carries the days of the week', () async {
      final board = (await layout(rows: 7, cols: 12))['time']!;

      for (final day in [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        expect(board, contains(day));
      }
    });

    test('leaves before and after where they already were', () async {
      // They mean sequence on `numbers`. One word with two homes and neither
      // obvious is worse than one movement further away.
      final all = await layout(rows: 7, cols: 12);

      expect(all['numbers'], contains('before'));
      expect(all['time'] ?? const {}, isNot(contains('before')));
      expect(all['time'] ?? const {}, isNot(contains('after')));
    });

    test('is reachable, though no key points at it', () async {
      // As the ninth category it sits past the last slot, so nothing in the
      // database navigates to it — its slot is re-pointed when the wheel
      // turns. A board the finder cannot route to is one it will not offer,
      // so this is the check that the wheel counts as a way there.
      final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

      final found = await findWords(
        db,
        vocabularyId: vocabId,
        query: 'tomorrow',
      );

      expect(found, isNotEmpty, reason: 'no route to a word on the time board');
      expect(
        found.first.steps.any((s) => s.action == ButtonAction.cycleCategories),
        isTrue,
        reason: 'the route does not turn the wheel it has to turn',
      );
    });

    test('builds at every grid the app offers', () async {
      // A category that refuses a grid is a category that has taken a device
      // away from somebody.
      for (final (rows, cols) in grids) {
        final all = await layout(rows: rows, cols: cols);
        expect(
          all.keys.where((b) => b.startsWith('time')),
          isNotEmpty,
          reason: 'no time board at ${rows}x$cols',
        );
      }
    });
  });

  /// The family somebody chose, beside the family they were born to.
  ///
  /// A board that can say "mom" and "brother" and not "wife" has decided which
  /// of somebody's relationships count.
  group('partners', () {
    test('are on the people board, on the row the family is on', () async {
      final people = (await layout(rows: 7, cols: 12))['people']!;

      for (final word in ['husband', 'wife', 'boyfriend']) {
        expect(people, contains(word), reason: 'no word for a partner');
        expect(
          people[word]!.row,
          people['mom']!.row,
          reason: '"$word" is not on the row somebody looks for it on',
        );
      }
    });

    test('and every word already there kept its location', () async {
      // The whole argument for appending into the row's own free cells rather
      // than giving them a band. A seventh band on this board takes a seventh
      // row it does not have at 7x12, and the nine possessives pay for it.
      final people = (await layout(rows: 7, cols: 12))['people']!;

      const wasAt = {
        'mom': (row: 1, col: 0),
        'family': (row: 1, col: 7),
        'friend': (row: 2, col: 0),
        'boy': (row: 3, col: 0),
        'him': (row: 4, col: 0),
        'your': (row: 5, col: 0),
        'theirs': (row: 5, col: 8),
      };

      for (final entry in wasAt.entries) {
        expect(
          people[entry.key],
          entry.value,
          reason: '"${entry.key}" moved to make room for a partner',
        );
      }
    });

    test('and the possessives are still on page one', () async {
      // What a band of their own would have cost, asserted rather than
      // remembered: nine words a press further away to buy four.
      final boards = await layout(rows: 7, cols: 12);

      expect(boards['people']!.keys, containsAll(['your', 'mine', 'theirs']));
      expect(
        boards['people 2']?.keys ?? const <String>[],
        isNot(contains('your')),
      );
    });

    test('all four fit on a grid with room for them', () async {
      final people = (await layout(rows: 10, cols: 14))['people']!;

      expect(
        people.keys,
        containsAll(['husband', 'wife', 'boyfriend', 'girlfriend']),
      );
      for (final word in ['husband', 'wife', 'boyfriend', 'girlfriend']) {
        expect(people[word]!.row, people['mom']!.row);
      }
    });
  });

  group('the user’s own name', () {
    test('lands on the root board, in the pronoun column', () async {
      // Back on the root, beside `me` (§4.83). It went to `people` for a
      // while, and the argument for that still holds — a proper noun in the
      // middle of a closed set of pronouns draws in their color and fills the
      // reserve that band holds for personal vocabulary. It is outweighed by
      // where the word is used: this is how a person says who is talking, and
      // they say it from whatever board they are standing on.
      final home = (await layout(rows: 7, cols: 12, userName: 'Maya'))['home']!;

      expect(home, contains('Maya'));
      expect(
        home['Maya']!.col,
        home['me']!.col,
        reason: 'the name is not in the column the pronouns are in',
      );
      expect(
        home['Maya']!.row,
        greaterThan(home['me']!.row),
        reason: 'the name should sit below "me", not above it',
      );
    });

    test('and takes the one location the root board reserves for a name', () async {
      // Said out loud because it is the whole cost of putting it here: the
      // tail of the pronoun column is the only spare name location a shipped
      // root board has, and the person's own name now fills it. A family's
      // other names go in the `names` band on `people`, which is held open for
      // exactly that.
      final withName = (await layout(
        rows: 7,
        cols: 12,
        userName: 'Maya',
      ))['home']!;
      final without = (await layout(rows: 7, cols: 12))['home']!;

      expect(withName.length, without.length + 1);
    });

    test('is absent when nobody has a name set', () async {
      final home = (await layout(rows: 7, cols: 12))['home']!;
      expect(home.keys, isNot(contains('Maya')));

      final people = (await layout(rows: 7, cols: 12))['people']!;
      expect(people.keys, isNot(contains('Maya')));
    });

    test('displaces nothing, at any grid', () async {
      // The whole reason it is placed afterwards into a location the layout
      // already left free, rather than seeded as a band item.
      for (final (rows, cols) in grids) {
        final without = await layout(rows: rows, cols: cols);
        final with_ = await layout(rows: rows, cols: cols, userName: 'Maya');

        for (final board in without.entries) {
          for (final word in board.value.entries) {
            expect(
              with_[board.key]?[word.key],
              word.value,
              reason:
                  '"${word.key}" moved on ${board.key} at ${rows}x$cols when '
                  'the name was added',
            );
          }
        }
      }
    });

    test('never takes a location a word was going to have', () async {
      // It fills a reserved cell or it is not placed. Either is fine; taking
      // one from the vocabulary is not.
      for (final (rows, cols) in grids) {
        final without = await layout(rows: rows, cols: cols);
        final with_ = await layout(rows: rows, cols: cols, userName: 'Maya');

        final before = {for (final b in without.entries) b.key: b.value.length};
        final after = {for (final b in with_.entries) b.key: b.value.length};

        for (final board in before.keys) {
          expect(
            after[board],
            anyOf(before[board], before[board]! + 1),
            reason: 'word count changed by more than the name on $board',
          );
        }
      }
    });
  });
}
