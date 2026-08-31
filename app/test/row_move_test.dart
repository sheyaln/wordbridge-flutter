import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/row_move.dart';

/// §4.42. Which page a row of words sits on, chosen by a caregiver.
///
/// Every category board ships a row of phrases on page one. Somebody who
/// reaches for them constantly wants them there; somebody who never does wants
/// the row back for vocabulary. The choice only exists once there is a second
/// page, which is what the request said.
///
/// It is a displacing edit and is treated as one: every word on the row moves.
void main() {
  late WordbridgeDatabase db;
  late Vocabulary vocabulary;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    // 7x12 is the shipped iPad grid, where `food` really does page.
    final id = await seedCoreBoardSet(db, rows: 7, cols: 12);
    vocabulary = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(id))).getSingle();
  });

  tearDown(() async => db.close());

  Future<Board> boardNamed(String name) =>
      (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

  int pinnedCol() => pinnedColumnOf(vocabulary);

  Future<List<Button>> row(Board board, int line) =>
      wordsOnLine(db, board.id, line, pinnedCol: pinnedCol());

  /// A line of the board that holds words and is not the system row.
  Future<int> fullLine(Board board) async {
    for (var line = 0; line < 6; line++) {
      if ((await row(board, line)).isNotEmpty) return line;
    }
    throw StateError('no row on "${board.name}" holds anything');
  }

  /// A line that holds words on [board] and nothing on [and], so a move
  /// between them is allowed.
  ///
  /// The pinned column is skipped on both counts: it carries a question at
  /// every row of every page, and counting it would make every row look
  /// spoken for.
  Future<int> movableLine(Board board, Board and) async {
    for (var line = 0; line < 6; line++) {
      if ((await row(board, line)).isEmpty) continue;
      if ((await row(and, line)).isEmpty) return line;
    }
    throw StateError('no row of "${board.name}" can move to "${and.name}"');
  }

  Future<int> freeLineOn(Board board) async {
    for (var line = 0; line < 6; line++) {
      if ((await row(board, line)).isEmpty) return line;
    }
    throw StateError('every row of "${board.name}" is spoken for');
  }

  group('finding the pages a row could go to', () {
    test('follows the paging keys, not the board names', () async {
      // A caregiver may rename a board; they may not rewire it. Reading the
      // group off the names would lose it the moment somebody did.
      final food = await boardNamed('food');
      final pages = await pagesOfGroup(db, food);

      expect(pages.length, greaterThan(1));
      expect(pages.first.id, food.id, reason: 'page one is not first');

      await (db.update(db.boards)..where((b) => b.id.equals(food.id))).write(
        const BoardsCompanion(name: Value('mealtimes')),
      );
      final renamed = await (db.select(
        db.boards,
      )..where((b) => b.id.equals(food.id))).getSingle();

      expect(
        (await pagesOfGroup(db, renamed)).map((p) => p.id),
        pages.map((p) => p.id),
      );
    });

    test('and finds the same group from any page in it', () async {
      final food = await boardNamed('food');
      final pages = await pagesOfGroup(db, food);
      expect(pages.length, greaterThan(1), reason: 'the premise');

      expect(
        (await pagesOfGroup(db, pages.last)).map((p) => p.id),
        pages.map((p) => p.id),
        reason: 'walking back from the last page found a different group',
      );
    });

    test('a board with no second page is a group of one', () async {
      final numbers = await boardNamed('numbers');
      final pages = await pagesOfGroup(db, numbers);

      // Nothing to move to, which is the state the whole control is absent in.
      expect(pages.map((p) => p.id), [numbers.id]);
    });
  });

  group('what is refused, and why it says so', () {
    test('the row every board navigates from', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];

      expect(
        await refusalToMoveRow(db, from: food, line: 6, to: second),
        contains('navigates from'),
      );
    });

    test('a row with nothing on it', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final empty = await freeLineOn(second);

      expect(
        await refusalToMoveRow(db, from: second, line: empty, to: food),
        contains('no words on that row'),
      );
    });

    test('a destination row that already holds something', () async {
      // A row only moves onto a row that is empty. Nothing already placed is
      // displaced to make room for one that has just arrived.
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final taken = await fullLine(second);

      final refusal = await refusalToMoveRow(
        db,
        from: food,
        line: taken,
        to: second,
      );
      expect(refusal, contains('already holds'));
    });

    test('and the page it is already on', () async {
      final food = await boardNamed('food');
      expect(
        await refusalToMoveRow(db, from: food, line: 0, to: food),
        contains('already on this page'),
      );
    });

    test('but a full row onto a free one is allowed', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final free = await movableLine(food, second);

      expect(
        await refusalToMoveRow(db, from: food, line: free, to: second),
        isNull,
        reason: 'row $free of food holds words and is free on page two',
      );
    });
  });

  group('what moving does', () {
    test('takes every word to the same row one page across', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final line = await movableLine(food, second);

      final before = await row(food, line);
      expect(before, isNotEmpty, reason: 'the premise');

      await moveRow(db, from: food, line: line, to: second);

      final moved = await row(second, line);
      expect(
        moved.map((b) => b.label),
        before.map((b) => b.label),
        reason: 'the row arrived in a different order, or short',
      );
      expect(await row(food, line), isEmpty);
    });

    test('and keeps each word in its own column', () async {
      // The row keeps its line *and* its shape: only the page changes.
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final line = await movableLine(food, second);

      final columns = <String, int>{};
      for (final word in await row(food, line)) {
        final cell = await (db.select(
          db.cells,
        )..where((c) => c.id.equals(word.cellId!))).getSingle();
        columns[word.label] = cell.col;
      }

      await moveRow(db, from: food, line: line, to: second);

      for (final word in await row(second, line)) {
        final cell = await (db.select(
          db.cells,
        )..where((c) => c.id.equals(word.cellId!))).getSingle();
        expect(cell.col, columns[word.label], reason: word.label);
      }
    });

    test('leaving the row it came from reserved, not occupied', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final line = await movableLine(food, second);

      await moveRow(db, from: food, line: line, to: second);

      final vacated =
          await (db.select(db.cells)
                ..where((c) => c.boardId.equals(food.id))
                ..where((c) => c.row.equals(line)))
              .get();

      // Reserved rather than gone: the location is permanent, and it is what
      // makes moving the row back put every word where it was.
      for (final cell in vacated) {
        if (cell.col == 11) continue; // the pinned question column
        expect(cell.state, CellState.emptyReserved, reason: '${cell.col}');
      }
    });

    test('and moving it back puts every word exactly where it was', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final line = await movableLine(food, second);

      final before = {for (final w in await row(food, line)) w.label: w.cellId};

      await moveRow(db, from: food, line: line, to: second);
      await moveRow(db, from: second, line: line, to: food);

      final after = {for (final w in await row(food, line)) w.label: w.cellId};
      expect(after, before);
    });

    test('and nothing on either page moves with it', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final line = await movableLine(food, second);

      final moving = {for (final w in await row(food, line)) w.id};
      final before = {
        for (final b in await db.select(db.buttons).get())
          if (!moving.contains(b.id)) b.id: b.cellId,
      };

      await moveRow(db, from: food, line: line, to: second);

      for (final b in await db.select(db.buttons).get()) {
        if (moving.contains(b.id)) continue;
        expect(b.cellId, before[b.id], reason: '"${b.label}" moved');
      }
    });

    test(
      'and a row with nothing on it is refused rather than shrugged off',
      () async {
        // The one refusal `moveButton` cannot make on its own: an empty row is
        // zero words to move, so without the guard this succeeds silently and a
        // caregiver is told a row moved that never existed.
        final food = await boardNamed('food');
        final second = (await pagesOfGroup(db, food))[1];
        final empty = await freeLineOn(second);

        await expectLater(
          moveRow(db, from: second, line: empty, to: food),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'the refusal',
              contains('no words on that row'),
            ),
          ),
        );
      },
    );

    test('a refusal is enforced here too, not only by the screen', () async {
      final food = await boardNamed('food');
      final second = (await pagesOfGroup(db, food))[1];
      final taken = await fullLine(second);

      await expectLater(
        moveRow(db, from: food, line: taken, to: second),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'the refusal a caregiver would have read',
            contains('already holds'),
          ),
        ),
      );
    });
  });

  group('what a caregiver is told it costs', () {
    test('how many words, and how often they have been reached for', () async {
      final food = await boardNamed('food');
      final line = await fullLine(food);

      final cost = await rowMoveCost(db, from: food, line: line);
      expect(cost.words, greaterThan(0));
      expect(cost.taps, 0, reason: 'nothing has been recorded on this board');

      final said = rowMoveWarning(
        cost: cost,
        toBoardName: 'food 2',
        userName: 'Maya',
      );
      expect(said, contains('${cost.words} words'));
      expect(said, contains('food 2'));
      expect(said, contains('back'));
    });

    test('and it names the person where anything has been recorded', () {
      final said = rowMoveWarning(
        cost: (words: 5, taps: 341, windowDays: 90),
        toBoardName: 'food 2',
        userName: 'Maya',
      );

      expect(said, contains('Maya has reached for these locations 341 times'));
      expect(said, contains('may take weeks to relearn'));
    });

    test('and says so plainly when nothing has been', () {
      final said = rowMoveWarning(
        cost: (words: 5, taps: 0, windowDays: 90),
        toBoardName: 'food 2',
      );

      expect(said, contains('Nothing on this row has been reached for'));
      expect(said, isNot(contains('relearn')));
    });
  });
}
