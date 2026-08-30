/// The keys every board carries, treated as one key rather than as one per
/// board.
///
/// Home, back, `more words`, `more categories`, the category slots and the
/// pinned questions exist as a separate row per board, because a location is a
/// row and each board needs its own. That is a storage fact, not a fact about
/// the board: to the person using it there is one `more words` key, at one
/// place, doing one thing, wherever they happen to be.
///
/// So an edit to how one of them looks is an edit to the key. A picture chosen
/// on the food board and not on the home board makes the same movement look
/// like two different keys, which is the confusion the fixed frame exists to
/// prevent.
library;

import 'package:drift/drift.dart';

import '../../db/ids.dart';
import '../../db/database.dart';
import '../../db/tables.dart';
import '../../db/seed/core_board_set.dart';

/// Puts a picture on a key, and on every copy of it.
///
/// The one place a chosen symbol is written, so it cannot be written to a
/// single board by a path that forgot. What a caregiver edited is what the
/// audit trail records — the propagation is part of that one edit, not a
/// separate edit to each board.
Future<void> setButtonSymbol(
  WordbridgeDatabase db,
  Button button,
  String symbolId,
) async {
  final siblings = await frameSiblings(db, button);
  final ids = [button.id, for (final b in siblings) b.id];

  await (db.update(db.buttons)..where((b) => b.id.isIn(ids))).write(
    ButtonsCompanion(symbolId: Value(symbolId), updatedAt: Value(nowMs())),
  );

  await db
      .into(db.editEvents)
      .insert(
        EditEventsCompanion.insert(
          id: newId(),
          vocabularyId: button.vocabularyId,
          cellId: Value(button.cellId),
          buttonId: Value(button.id),
          kind: EditKind.resymbol,
          changedAt: nowMs(),
        ),
      );
}

/// Every other copy of the same frame key, or empty for an ordinary word.
///
/// Matched on the location, because that is what makes them the same key, and
/// then on whether it is one of the keys every board carries — a caregiver may
/// have put an ordinary word on a paging location that this board has no page
/// for, and that word is not a copy of anything.
///
/// The action is not compared, and does not need to be: a column of the frame
/// carries the same key on every board it appears on, so matching the location
/// has already matched the action.
Future<List<Button>> frameSiblings(WordbridgeDatabase db, Button button) async {
  final cellId = button.cellId;
  if (cellId == null) return const [];

  final cell = await (db.select(
    db.cells,
  )..where((c) => c.id.equals(cellId))).getSingleOrNull();
  if (cell == null) return const [];

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(button.vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return const [];

  if (!_isFrame(vocabulary, cell.row, cell.col)) return const [];

  final rows =
      await (db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.buttons.vocabularyId.equals(button.vocabularyId) &
                db.buttons.id.isNotValue(button.id) &
                db.buttons.deletedAt.isNull() &
                db.buttons.isSystem.equals(button.isSystem) &
                db.cells.row.equals(cell.row) &
                db.cells.col.equals(cell.col),
          ))
          .get();

  return [for (final row in rows) row.readTable(db.buttons)];
}

/// Whether a location is one the frame owns on every board.
///
/// Read from what the vocabulary recorded rather than recomputed, for the same
/// reason [SystemFrame] is the authority everywhere else: a board set that
/// gained a category has a frame that [SystemRowPlan] would no longer produce.
///
/// A vocabulary with nothing recorded — an imported board set — has no frame,
/// so nothing on it is a copy of anything.
bool _isFrame(Vocabulary vocabulary, int row, int col) {
  // The pinned column carries the questions, at identical coordinates on every
  // board. They are ordinary vocabulary that happens to be pinned, which is why
  // they are not matched on `isSystem`.
  if (col == vocabulary.gridCols - 1) return true;

  final frame = SystemFrame.parse(vocabulary.systemCellMap);
  if (frame == null || row != frame.row) return false;

  return col == frame.homeCol ||
      col == frame.backCol ||
      col == frame.pageBackCol ||
      col == frame.pageForwardCol ||
      col == frame.cycleCol ||
      frame.categoryCols.contains(col);
}
