import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';

/// A word's motor path: the board it lives on and the location within it.
/// Two paths compare equal only if the finger movement is identical.
typedef MotorPath = ({String board, int row, int col});

/// Snapshots every word's location across an entire vocabulary.
///
/// Hidden words are included deliberately — a word that is masked today must
/// reappear at the same location when it is revealed months later, so its
/// position is part of the contract even while invisible.
Future<Map<String, MotorPath>> motorPaths(
  WordbridgeDatabase db,
  String vocabularyId,
) async {
  final query = db.select(db.buttons).join([
    innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
  ])
    ..where(db.buttons.vocabularyId.equals(vocabularyId));

  final rows = await query.get();
  return {
    for (final r in rows)
      r.readTable(db.buttons).label: (
        board: r.readTable(db.boards).name,
        row: r.readTable(db.cells).row,
        col: r.readTable(db.cells).col,
      ),
  };
}

void main() {
  late WordbridgeDatabase db;
  late String vocabId;
  late String homeBoardId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());

    vocabId = newId();
    final ts = nowMs();
    await db.into(db.vocabularies).insert(
          VocabulariesCompanion.insert(
            id: vocabId,
            name: 'test',
            gridRows: 7,
            gridCols: 12,
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    homeBoardId = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: 'home',
      kind: BoardKind.root,
    );
  });

  tearDown(() async => db.close());

  group('cell materialisation', () {
    test('creates every grid location up front', () async {
      final count = await db.cells.count().getSingle();
      expect(count, 7 * 12);
    });

    test('locations start reserved, not absent', () async {
      final reserved = await (db.select(db.cells)
            ..where((c) => c.state.equalsValue(CellState.emptyReserved)))
          .get();
      expect(reserved.length, 84);
    });

    test('a location cannot be duplicated', () async {
      final existing = await cellAt(db, boardId: homeBoardId, row: 0, col: 0);
      expect(
        () => db.into(db.cells).insert(
              CellsCompanion.insert(
                id: newId(),
                boardId: homeBoardId,
                row: existing.row,
                col: existing.col,
                createdAt: nowMs(),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('placement', () {
    test('occupying a location marks it occupied', () async {
      final cell = await cellAt(db, boardId: homeBoardId, row: 2, col: 3);
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'eat',
        message: 'eat',
      );

      final after = await cellAt(db, boardId: homeBoardId, row: 2, col: 3);
      expect(after.state, CellState.occupied);
    });

    test('refuses to overwrite an occupied location', () async {
      final cell = await cellAt(db, boardId: homeBoardId, row: 2, col: 3);
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'eat',
        message: 'eat',
      );

      expect(
        () => placeButton(
          db,
          vocabularyId: vocabId,
          cellId: cell.id,
          label: 'drink',
          message: 'drink',
        ),
        throwsStateError,
      );
    });
  });

  group('hiding never frees a location', () {
    test('a hidden word keeps its cell occupied', () async {
      final cell = await cellAt(db, boardId: homeBoardId, row: 1, col: 1);
      final id = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'later',
        message: 'later',
        hidden: true,
      );

      await hideButton(db, id);

      final after = await cellAt(db, boardId: homeBoardId, row: 1, col: 1);
      expect(
        after.state,
        CellState.occupied,
        reason: 'a freed cell would be taken by the next word added, '
            'displacing this one when it is revealed',
      );
    });

    test('unhiding restores the original location', () async {
      final cell = await cellAt(db, boardId: homeBoardId, row: 4, col: 5);
      final id = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'trampoline',
        message: 'trampoline',
        vocabLevel: 3,
        hidden: true,
      );

      final before = await motorPaths(db, vocabId);
      await unhideButton(db, id);
      final after = await motorPaths(db, vocabId);

      expect(after['trampoline'], before['trampoline']);
      expect(after['trampoline'], (board: 'home', row: 4, col: 5));
    });
  });

  group('THE INVARIANT: motor plans grow but never change', () {
    test('full vocabulary growth displaces nothing', () async {
      // A level-1 starter set scattered across the grid.
      const starter = {
        'I': (0, 0),
        'you': (0, 1),
        'want': (1, 0),
        'go': (1, 1),
        'stop': (2, 0),
        'more': (2, 1),
        'help': (3, 0),
        'like': (3, 1),
      };

      for (final entry in starter.entries) {
        final cell = await cellAt(
          db,
          boardId: homeBoardId,
          row: entry.value.$1,
          col: entry.value.$2,
        );
        await placeButton(
          db,
          vocabularyId: vocabId,
          cellId: cell.id,
          label: entry.key,
          message: entry.key,
        );
      }

      final before = await motorPaths(db, vocabId);
      expect(before.length, starter.length);

      // Now grow the vocabulary every way the app allows.

      // 1. Fill reserved locations on the existing board.
      final free = await (db.select(db.cells)
            ..where((c) =>
                c.boardId.equals(homeBoardId) &
                c.state.equalsValue(CellState.emptyReserved)))
          .get();
      for (var i = 0; i < 40; i++) {
        await placeButton(
          db,
          vocabularyId: vocabId,
          cellId: free[i].id,
          label: 'fill_$i',
          message: 'fill_$i',
          vocabLevel: 2,
        );
      }

      // 2. Add category boards and populate them.
      for (final name in ['food', 'actions', 'describe']) {
        final boardId = await materialiseBoard(
          db,
          vocabularyId: vocabId,
          name: name,
          kind: BoardKind.category,
        );
        for (var i = 0; i < 30; i++) {
          final cell = await cellAt(
            db,
            boardId: boardId,
            row: i ~/ 12,
            col: i % 12,
          );
          await placeButton(
            db,
            vocabularyId: vocabId,
            cellId: cell.id,
            label: '${name}_$i',
            message: '${name}_$i',
            vocabLevel: 3,
          );
        }
      }

      // 3. Hide and reveal a starter word — the level progression.
      final likeButton = await (db.select(db.buttons)
            ..where((b) => b.label.equals('like')))
          .getSingle();
      await hideButton(db, likeButton.id);
      await unhideButton(db, likeButton.id);

      // 4. Relabel a word in place. Content changed, location did not.
      final goButton =
          await (db.select(db.buttons)..where((b) => b.label.equals('go')))
              .getSingle();
      await (db.update(db.buttons)..where((b) => b.id.equals(goButton.id)))
          .write(ButtonsCompanion(
        message: const Value('go now'),
        updatedAt: Value(nowMs()),
      ));

      final after = await motorPaths(db, vocabId);

      // The vocabulary grew from 8 words to 138.
      expect(after.length, 8 + 40 + 90);

      // Not one of the original words moved.
      for (final label in starter.keys) {
        expect(
          after[label],
          before[label],
          reason: '"$label" moved from ${before[label]} to ${after[label]}. '
              'A learned motor pattern was silently destroyed.',
        );
      }
    });
  });
}
