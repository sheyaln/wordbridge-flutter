import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/db/tables.dart';

/// Every grid a caregiver could plausibly land on.
///
/// Icon size and orientation are chosen at setup, so the shipped vocabulary
/// has to survive all of these — not just the one it was written for. A word
/// silently vanishing at some sizes and not others is the kind of thing that
/// only shows up on a device someone already depends on.
const geometries = [
  (rows: 7, cols: 12, name: 'tablet landscape, medium icons'),
  (rows: 5, cols: 9, name: 'tablet landscape, large icons'),
  (rows: 4, cols: 7, name: 'tablet landscape, largest icons'),
  (rows: 9, cols: 15, name: 'tablet landscape, small icons'),
  (rows: 12, cols: 8, name: 'tablet portrait, medium icons'),
  (rows: 9, cols: 6, name: 'tablet portrait, large icons'),
  (rows: 14, cols: 9, name: 'tablet portrait, small icons'),
];

Set<String> allVocabulary() => {
  for (final band in homeBands)
    for (final item in band.items) item.value.label,
  for (final bands in categoryBands.values)
    for (final band in bands)
      for (final item in band.items) item.value.label,
  for (final item in pinnedQuestions) item.value.label,
};

/// Words a board without them is not a communication device.
const mustBeOnHome = {'I', 'you', 'want', 'stop', 'help', 'not', 'more'};

void main() {
  for (final g in geometries) {
    group('${g.rows}x${g.cols} — ${g.name}', () {
      late WordbridgeDatabase db;
      late String vocabId;

      setUp(() async {
        db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        vocabId = await seedCoreBoardSet(db, rows: g.rows, cols: g.cols);
      });

      tearDown(() async => db.close());

      Future<List<TypedResult>> placed() {
        final query = db.select(db.buttons).join([
          innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
        ])..where(db.buttons.vocabularyId.equals(vocabId));
        return query.get();
      }

      test('no word is lost', () async {
        // A word that exists in the vocabulary and cannot be said anywhere is
        // the worst outcome available here. Shedding moves words to another
        // page; it must never drop them.
        final labels = {
          for (final r in await placed()) r.readTable(db.buttons).label,
        };

        expect(
          allVocabulary().difference(labels),
          isEmpty,
          reason: 'vocabulary disappeared at ${g.rows}x${g.cols}',
        );
      });

      test('nothing is placed outside the grid', () async {
        for (final r in await placed()) {
          final cell = r.readTable(db.cells);
          expect(cell.row, inInclusiveRange(0, g.rows - 1));
          expect(cell.col, inInclusiveRange(0, g.cols - 1));
        }
      });

      test('one word to a location', () async {
        final seen = <String>{};
        for (final r in await placed()) {
          final cell = r.readTable(db.cells);
          expect(
            seen.add('${cell.boardId}:${cell.row}:${cell.col}'),
            isTrue,
            reason:
                '"${r.readTable(db.buttons).label}" shares a location on '
                '"${r.readTable(db.boards).name}"',
          );
        }
      });

      test('the urgent words stay on the root board', () async {
        final root = await (db.select(
          db.boards,
        )..where((b) => b.kind.equalsValue(BoardKind.root))).getSingle();

        final onHome = {
          for (final r in await placed())
            if (r.readTable(db.cells).boardId == root.id)
              r.readTable(db.buttons).label,
        };

        expect(
          mustBeOnHome.difference(onHome),
          isEmpty,
          reason:
              'a word a user may need urgently moved behind a navigation '
              'step at ${g.rows}x${g.cols}',
        );
      });

      test('home and back are in the same place on every board', () async {
        final byBoard = <String, Map<String, int>>{};

        for (final r in await placed()) {
          final button = r.readTable(db.buttons);
          if (button.label != 'home' && button.label != 'back') continue;
          final cell = r.readTable(db.cells);
          (byBoard[cell.boardId] ??= {})[button.label] = cell.col;
        }

        expect(byBoard, isNotEmpty);
        final reference = byBoard.values.first;
        for (final entry in byBoard.entries) {
          expect(entry.value, reference);
        }
      });

      test('every board carries what fits of the question column', () async {
        final boards = await db.select(db.boards).get();
        final questionCol = g.cols - 1;

        for (final board in boards) {
          final query =
              db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])..where(
                db.cells.boardId.equals(board.id) &
                    db.cells.col.equals(questionCol) &
                    db.cells.row.isSmallerThanValue(g.rows - 1),
              );

          final labels = {
            for (final r in await query.get()) r.readTable(db.buttons).label,
          };

          expect(
            labels,
            containsAll(['what', 'where']),
            reason: '"${board.name}" cannot ask a question',
          );
        }
      });

      test('every navigation key leads somewhere real', () async {
        final boardIds = (await db.select(db.boards).get())
            .map((b) => b.id)
            .toSet();

        for (final r in await placed()) {
          final button = r.readTable(db.buttons);
          if (button.action != ButtonAction.navigate) continue;

          expect(
            boardIds,
            contains(button.targetBoardId),
            reason: '"${button.label}" goes nowhere',
          );
        }
      });

      test('every category is reachable', () async {
        // Directly from a system-row key, or by turning the wheel those keys
        // sit on when the grid is too narrow to show them all at once. The
        // wheel is recorded on the vocabulary, because the keys themselves
        // only ever hold whichever category is showing.
        final vocab = await (db.select(
          db.vocabularies,
        )..where((v) => v.id.equals(vocabId))).getSingle();

        final map = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
        final wheel = {
          for (final entry
              in (map['categories'] as List).cast<Map<String, dynamic>>())
            entry['name'] as String,
        };

        expect(wheel, containsAll(categoryNames));

        // And every one of them names a board that exists.
        final boardIds = (await db.select(db.boards).get())
            .map((b) => b.id)
            .toSet();
        for (final entry
            in (map['categories'] as List).cast<Map<String, dynamic>>()) {
          expect(boardIds, contains(entry['boardId']));
        }
      });

      test('the wheel turns through every category without a gap', () async {
        final vocab = await (db.select(
          db.vocabularies,
        )..where((v) => v.id.equals(vocabId))).getSingle();

        final map = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
        final slots = (map['categoryCols'] as List).length;
        final total = (map['categories'] as List).length;

        // A cycle key exists exactly when there is something to cycle to.
        expect(map.containsKey('cycleCol'), total > slots);
        expect(slots, greaterThan(0));
      });

      test('there is room left to grow', () async {
        final root = await (db.select(
          db.boards,
        )..where((b) => b.kind.equalsValue(BoardKind.root))).getSingle();

        final reserved =
            await (db.select(db.cells)..where(
                  (c) =>
                      c.boardId.equals(root.id) &
                      c.state.equalsValue(CellState.emptyReserved),
                ))
                .get();

        expect(
          reserved,
          isNotEmpty,
          reason:
              'the root board is packed full at ${g.rows}x${g.cols}, so '
              'personal vocabulary has nowhere to go',
        );
      });
    });
  }

  test('a grid too small for the fixed keys is refused, not fudged', () async {
    // Better to tell a caregiver the icon size does not fit this device than
    // to hand them a board that quietly lost half its vocabulary.
    final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(
      () => seedCoreBoardSet(db, rows: 4, cols: 5),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('the same size twice gives the same board', () async {
    final first = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    final second = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(first.close);
    addTearDown(second.close);

    Future<Map<String, String>> layoutOf(WordbridgeDatabase db) async {
      await seedCoreBoardSet(db, rows: 9, cols: 6);

      final query = db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
        innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
      ]);

      return {
        for (final r in await query.get())
          '${r.readTable(db.boards).name}:'
              '${r.readTable(db.cells).row},${r.readTable(db.cells).col}': r
              .readTable(db.buttons)
              .label,
      };
    }

    expect(await layoutOf(second), await layoutOf(first));
  });
}
