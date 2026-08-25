import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';

/// Project Core's Universal Core 36 (UNC Center for Literacy and Disability
/// Studies). The shipped vocabulary must contain all of them.
const universalCore36 = {
  'all',
  'can',
  'different',
  'do',
  'finished',
  'get',
  'go',
  'good',
  'he',
  'help',
  'here',
  'I',
  'in',
  'it',
  'like',
  'look',
  'make',
  'more',
  'not',
  'on',
  'open',
  'put',
  'same',
  'she',
  'some',
  'stop',
  'that',
  'turn',
  'up',
  'want',
  'what',
  'when',
  'where',
  'who',
  'why',
  'you',
};

void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
  });

  tearDown(() async => db.close());

  Future<List<Button>> buttons() => (db.select(
    db.buttons,
  )..where((b) => b.vocabularyId.equals(vocabId))).get();

  test('ships the complete Universal Core 36', () async {
    final labels = (await buttons())
        .where((b) => !b.isSystem)
        .map((b) => b.label)
        .toSet();

    expect(
      universalCore36.difference(labels),
      isEmpty,
      reason: 'a core word is missing from the shipped vocabulary',
    );
  });

  test('leaves room to grow', () async {
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final reserved =
        await (db.select(db.cells)..where(
              (c) =>
                  c.boardId.equals(home.id) &
                  c.state.equalsValue(CellState.emptyReserved),
            ))
            .get();

    // Roughly half the home board ships deliberately empty. If a future edit
    // packs it full, personal vocabulary has nowhere to land that does not
    // displace something already learned.
    expect(reserved.length, greaterThan(20));
  });

  test('reserves the column beside the pronouns for names', () async {
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final col1 = await (db.select(
      db.cells,
    )..where((c) => c.boardId.equals(home.id) & c.col.equals(1))).get();

    final vocabRows = col1.where((c) => c.row < 6);
    expect(
      vocabRows.every((c) => c.state == CellState.emptyReserved),
      isTrue,
      reason: 'family names need a permanent home next to the pronouns',
    );
  });

  group('system row is identical on every board', () {
    test('every board carries the same system positions', () async {
      final boards = await db.select(db.boards).get();
      expect(boards.length, greaterThan(1));

      final signatures = <String, Map<String, int>>{};

      for (final board in boards) {
        final query =
            db.select(db.cells).join([
              innerJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
            ])..where(
              db.cells.boardId.equals(board.id) &
                  db.buttons.isSystem.equals(true),
            );

        final rows = await query.get();
        signatures[board.name] = {
          for (final r in rows)
            r.readTable(db.buttons).label: r.readTable(db.cells).col,
        };
      }

      final reference = signatures.values.first;
      for (final entry in signatures.entries) {
        expect(
          entry.value,
          reference,
          reason:
              'system buttons moved on "${entry.key}" — home and back '
              'must be the same movement from every board',
        );
      }
    });

    test('home and back sit at fixed columns', () async {
      final query =
          db.select(db.cells).join([
            innerJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
          ])..where(
            db.buttons.isSystem.equals(true) &
                db.buttons.label.isIn(['home', 'back']),
          );

      for (final r in await query.get()) {
        final label = r.readTable(db.buttons).label;
        final cell = r.readTable(db.cells);
        expect(cell.row, 6);
        expect(cell.col, label == 'home' ? 0 : 1);
      }
    });
  });

  test('every category button leads somewhere real', () async {
    final navButtons = (await buttons())
        .where((b) => b.action == ButtonAction.navigate)
        .toList();

    expect(navButtons, isNotEmpty);

    final boardIds = (await db.select(db.boards).get())
        .map((b) => b.id)
        .toSet();
    for (final b in navButtons) {
      expect(b.targetBoardId, isNotNull, reason: '"${b.label}" goes nowhere');
      expect(boardIds, contains(b.targetBoardId));
    }
  });

  test('refusal is reachable without navigating', () async {
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final query = db.select(db.buttons).join(
      [innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId))],
    )..where(db.buttons.label.equals('not') & db.cells.boardId.equals(home.id));

    final rows = await query.get();
    expect(
      rows,
      hasLength(1),
      reason: 'refusal must be on the root board, not buried in a folder',
    );
    expect(rows.single.readTable(db.buttons).vocabLevel, 1);
  });
}
