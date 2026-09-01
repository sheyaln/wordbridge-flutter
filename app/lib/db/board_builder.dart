import 'package:drift/drift.dart';

import 'database.dart';
import 'ids.dart';
import 'tables.dart';

/// Creates a board and materializes every one of its grid locations.
///
/// All `rows * cols` cells are inserted up front, in one transaction, so a
/// location exists before anything occupies it. This is what makes positions
/// stable: words attach to locations that were already there rather than
/// locations being derived from the current list of words.
///
/// Geometry comes from the vocabulary, never from the caller, because every
/// board in a vocabulary must share dimensions for motor plans to hold.
Future<String> materializeBoard(
  WordbridgeDatabase db, {
  required String vocabularyId,
  required String name,
  required BoardKind kind,
}) async {
  return db.transaction(() async {
    final vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();

    final boardId = newId();
    final ts = nowMs();

    await db
        .into(db.boards)
        .insert(
          BoardsCompanion.insert(
            id: boardId,
            vocabularyId: vocabularyId,
            name: name,
            kind: kind,
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    await db.batch((batch) {
      for (var row = 0; row < vocab.gridRows; row++) {
        for (var col = 0; col < vocab.gridCols; col++) {
          batch.insert(
            db.cells,
            CellsCompanion.insert(
              id: newId(),
              boardId: boardId,
              row: row,
              col: col,
              createdAt: ts,
            ),
          );
        }
      }
    });

    return boardId;
  });
}

/// Attaches a word to an existing location.
///
/// Fails if the location is already occupied — placing a word is additive by
/// construction, and overwriting would be a displacing change wearing the
/// costume of an additive one. Moving a word is a separate, deliberate
/// operation that goes through the remap path.
Future<String> placeButton(
  WordbridgeDatabase db, {
  required String vocabularyId,
  required String cellId,
  required String label,
  required String message,
  ButtonAction action = ButtonAction.speak,
  String? targetBoardId,
  String? symbolId,
  MorphemeKind? morphemeKind,
  PartOfSpeech? partOfSpeech,
  int vocabLevel = 1,
  bool hidden = false,
  bool isSystem = false,
}) async {
  return db.transaction(() async {
    final cell = await (db.select(
      db.cells,
    )..where((c) => c.id.equals(cellId))).getSingle();

    if (cell.state == CellState.occupied) {
      throw StateError(
        'Cell ${cell.row},${cell.col} is already occupied. Placing over an '
        'existing word would displace it; use a remap instead.',
      );
    }

    final buttonId = newId();
    final ts = nowMs();

    await db
        .into(db.buttons)
        .insert(
          ButtonsCompanion.insert(
            id: buttonId,
            cellId: Value(cellId),
            vocabularyId: vocabularyId,
            label: label,
            message: message,
            action: action,
            targetBoardId: Value(targetBoardId),
            symbolId: Value(symbolId),
            morphemeKind: Value(morphemeKind),
            partOfSpeech: Value(partOfSpeech),
            vocabLevel: Value(vocabLevel),
            hidden: Value(hidden),
            isSystem: Value(isSystem),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    await (db.update(db.cells)..where((c) => c.id.equals(cellId))).write(
      const CellsCompanion(state: Value(CellState.occupied)),
    );

    return buttonId;
  });
}

/// Looks up a location by its coordinates on a board.
Future<Cell> cellAt(
  WordbridgeDatabase db, {
  required String boardId,
  required int row,
  required int col,
}) {
  return (db.select(db.cells)..where(
        (c) =>
            c.boardId.equals(boardId) & c.row.equals(row) & c.col.equals(col),
      ))
      .getSingle();
}

/// Hides a word without releasing its location.
///
/// The cell stays [CellState.occupied] so nothing else can take it. This is
/// the entire mechanism behind vocabulary levels: unhiding six months later
/// puts the word back exactly where it always was.
Future<void> hideButton(WordbridgeDatabase db, String buttonId) async {
  await (db.update(db.buttons)..where((b) => b.id.equals(buttonId))).write(
    ButtonsCompanion(hidden: const Value(true), updatedAt: Value(nowMs())),
  );
}

Future<void> unhideButton(WordbridgeDatabase db, String buttonId) async {
  await (db.update(db.buttons)..where((b) => b.id.equals(buttonId))).write(
    ButtonsCompanion(hidden: const Value(false), updatedAt: Value(nowMs())),
  );
}
