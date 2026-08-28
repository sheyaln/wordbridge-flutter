import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/vocabulary_top_up.dart';
import 'package:wordbridge/db/tables.dart';

/// Bringing new shipped words to a board that already exists.
///
/// The whole point is that it is additive: a word lands where the layout rule
/// already puts it, or it does not land at all. A top-up that moved something
/// would be a rebuild wearing a disguise.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
  });

  tearDown(() async => db.close());

  Future<Board> boardNamed(String name) =>
      (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

  Future<Map<String, ({int row, int col})>> positionsOn(String boardId) async {
    final query = db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.cells.boardId.equals(boardId));

    return {
      for (final r in await query.get())
        r.readTable(db.buttons).label: (
          row: r.readTable(db.cells).row,
          col: r.readTable(db.cells).col,
        ),
    };
  }

  /// Removes a word, leaving its location free, to stand in for a board built
  /// before that word shipped.
  Future<({int row, int col})> removeWord(String label) async {
    final button = await (db.select(
      db.buttons,
    )..where((b) => b.label.equals(label))).getSingle();

    final cell = await (db.select(
      db.cells,
    )..where((c) => c.id.equals(button.cellId!))).getSingle();

    await (db.delete(db.buttons)..where((b) => b.id.equals(button.id))).go();
    await (db.update(db.cells)..where((c) => c.id.equals(cell.id))).write(
      const CellsCompanion(state: Value(CellState.emptyReserved)),
    );

    return (row: cell.row, col: cell.col);
  }

  test('a missing word returns to the location the rule gives it', () async {
    final home = await boardNamed('home');
    final was = await removeWord('yes');

    final result = await topUpVocabulary(db, vocabularyId: vocabId);

    expect(result.added.map((a) => a.label), contains('yes'));
    expect((await positionsOn(home.id))['yes'], was);
  });

  test('nothing already on the board moves', () async {
    // The one thing a top-up must never do.
    final home = await boardNamed('home');
    await removeWord('yes');

    final before = await positionsOn(home.id);
    await topUpVocabulary(db, vocabularyId: vocabId);
    final after = await positionsOn(home.id);

    for (final entry in before.entries) {
      expect(
        after[entry.key],
        entry.value,
        reason: '"${entry.key}" moved during a top-up',
      );
    }
  });

  test('a board with nothing missing is left alone', () async {
    final result = await topUpVocabulary(db, vocabularyId: vocabId);

    expect(result.added, isEmpty);
    expect(result.blocked, isEmpty);
    expect(result.isEmpty, isTrue);
  });

  test('a caregiver’s own word keeps the location', () async {
    // Their choice about their own child's board outranks ours about a
    // shipped default.
    final home = await boardNamed('home');
    final was = await removeWord('yes');

    final cell = await cellAt(db, boardId: home.id, row: was.row, col: was.col);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: 'Nana',
      message: 'Nana',
      partOfSpeech: PartOfSpeech.noun,
    );

    final result = await topUpVocabulary(db, vocabularyId: vocabId);

    expect(result.added.map((a) => a.label), isNot(contains('yes')));
    expect(
      result.blocked.map((b) => b.label),
      contains('yes'),
      reason: 'a caregiver has to be told what did not fit, not left guessing',
    );
    expect(result.blocked.single.occupant, 'Nana');
    expect((await positionsOn(home.id))['Nana'], was);
  });

  test('a dry run changes nothing', () async {
    await removeWord('yes');

    final preview = await topUpVocabulary(
      db,
      vocabularyId: vocabId,
      dryRun: true,
    );
    expect(preview.added.map((a) => a.label), contains('yes'));

    final home = await boardNamed('home');
    expect((await positionsOn(home.id))['yes'], isNull);

    // And the real run then does exactly what the preview said.
    final applied = await topUpVocabulary(db, vocabularyId: vocabId);
    expect(applied.added.length, preview.added.length);
  });

  test('the question mark reaches every board, not just the root', () async {
    // The pinned column is the same on every board or it is not pinned.
    for (final board in await db.select(db.boards).get()) {
      final button =
          await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])..where(
                db.cells.boardId.equals(board.id) &
                    db.buttons.label.equals('?'),
              ))
              .get();

      expect(button, hasLength(1), reason: '"${board.name}" cannot ask');
    }
  });

  test('a top-up run twice adds nothing the second time', () async {
    await removeWord('yes');
    await removeWord('no');

    final first = await topUpVocabulary(db, vocabularyId: vocabId);
    expect(first.added, hasLength(2));

    final second = await topUpVocabulary(db, vocabularyId: vocabId);
    expect(second.added, isEmpty);
  });

  test('every location stays occupied by exactly one word', () async {
    await removeWord('yes');
    await topUpVocabulary(db, vocabularyId: vocabId);

    final seen = <String>{};
    for (final r in await (db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])).get()) {
      final cell = r.readTable(db.cells);
      expect(seen.add(cell.id), isTrue);
    }
  });
}
