/// Reaching one word from every board (§4.16).
///
/// The board is built so a word costs the same movements every time, and the
/// one thing that breaks that promise is depth: a word on a category board
/// costs the trip in and the trip back. The frame already answers this for the
/// question words — `what where who when why how` hold identical coordinates on
/// every board — and pinning hands that same class to a caregiver.
///
/// **A pin is a copy, not a move.** The word keeps the location it already has
/// and *gains* a second, shorter route to itself, so unpinning cannot strand
/// anything: it takes the pinned location back to reserved and never touches
/// the original. The alternative — moving the word into the pinned column —
/// would trade one learned motor path for another, which is the opposite of
/// what pinning is for. Two routes to one word is also already how this board
/// works: `where` is in the pinned column and reachable nowhere else.
///
/// **Only the pinned column, never the system row.** §4.16 originally offered
/// the gap at column 2 of the system row as the one spare location at 7×12.
/// §4.43 closed that row to words, and its reasoning is exactly why: the gap is
/// a deliberate blank whose whole job is that an imprecise reach for `back`
/// does not land on a category key, and a word there is spent guard. So at 7
/// rows the pinned column is full and there is nothing to pin into; at 8 rows
/// or more there is.
library;

import 'package:drift/drift.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/seed/core_board_set.dart';
import '../../db/tables.dart';

/// The column the frame pins into: the last one, where the questions live.
int pinnedColumn(Vocabulary vocabulary) => vocabulary.gridCols - 1;

/// The rows of the pinned column that are free on every board at once.
///
/// A pin is one location on every board or it is not a pin, so a row counts
/// only where every board has it reserved and empty. One board having put a
/// word there takes that row off the table for all of them.
Future<List<int>> freePinnedRows(
  WordbridgeDatabase db,
  Vocabulary vocabulary,
) async {
  final boards =
      await (db.select(db.boards)
            ..where((b) => b.vocabularyId.equals(vocabulary.id))
            ..where((b) => b.deletedAt.isNull()))
          .get();
  if (boards.isEmpty) return const [];

  final ids = [for (final b in boards) b.id];
  final col = pinnedColumn(vocabulary);

  final cells =
      await (db.select(db.cells)
            ..where((c) => c.boardId.isIn(ids))
            ..where((c) => c.col.equals(col)))
          .get();

  final free = <int, int>{};
  for (final cell in cells) {
    if (cell.state != CellState.emptyReserved) continue;
    free[cell.row] = (free[cell.row] ?? 0) + 1;
  }

  final rows = [
    for (final entry in free.entries)
      if (entry.value == boards.length) entry.key,
  ]..sort();
  return rows;
}

/// Why this word cannot be pinned, in the sentence a caregiver reads, or null
/// where it can.
///
/// A refusal that names its reason rather than a control that is missing —
/// §4.15's argument, and the one §4.43 makes again. A caregiver who cannot see
/// why has nothing to do next.
Future<String?> refusalToPin(WordbridgeDatabase db, Button button) async {
  if (button.isSystem) {
    return '"${button.label}" is one of the keys every board carries, so it '
        'is already on every board.';
  }

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(button.vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return 'This board set could not be read.';

  if (SystemFrame.parse(vocabulary.systemCellMap) == null) {
    return 'This board set was not built with a pinned column, so there is '
        'nowhere on it that every board shares.';
  }

  final cellId = button.cellId;
  if (cellId != null) {
    final cell = await (db.select(
      db.cells,
    )..where((c) => c.id.equals(cellId))).getSingleOrNull();
    if (cell != null && cell.col == pinnedColumn(vocabulary)) {
      return '"${button.label}" is already in the pinned column, so it is '
          'already reachable from every board.';
    }
  }

  if (await pinnedRowOf(db, button) != null) {
    return '"${button.label}" is already pinned.';
  }

  if ((await freePinnedRows(db, vocabulary)).isEmpty) {
    return 'The pinned column is full. Every location in it is spoken for, '
        'and hiding one of the question words does not free it. A location a '
        'word holds stays that word\'s.';
  }

  return null;
}

/// Whether this button itself is one of the pinned column's own.
///
/// A question word lives *only* there, so it is not a pin of anything and has
/// no home to fall back to. Taking it away would be a deletion wearing the
/// word "unpin", and the sentence that makes unpinning safe — "the word keeps
/// the location it has always had" — would be false of it.
Future<bool> livesInPinnedColumn(WordbridgeDatabase db, Button button) async {
  final cellId = button.cellId;
  if (cellId == null) return false;

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(button.vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return false;

  final cell = await (db.select(
    db.cells,
  )..where((c) => c.id.equals(cellId))).getSingleOrNull();
  return cell != null && cell.col == pinnedColumn(vocabulary);
}

/// Where this word's pinned copy sits, or null if it has none.
///
/// Matched on the label in the pinned column, which is what makes them the
/// same word — the copies are separate rows because a location is a row, the
/// same storage fact the frame keys live with.
Future<int?> pinnedRowOf(WordbridgeDatabase db, Button button) async {
  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(button.vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return null;

  final col = pinnedColumn(vocabulary);
  final rows =
      await (db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.buttons.vocabularyId.equals(vocabulary.id) &
                db.buttons.deletedAt.isNull() &
                db.buttons.label.equals(button.label) &
                db.buttons.isSystem.equals(false) &
                db.cells.col.equals(col),
          ))
          .get();

  if (rows.isEmpty) return null;
  return rows.first.readTable(db.cells).row;
}

/// What pinning costs, said in the units it is paid in.
///
/// Cells, not words. One pin is one location on every board at once, and a
/// caregiver told "one location is available" has been told the wrong number.
String pinCost({required String label, required int boards}) =>
    'A pinned word takes the same location on every board, so "$label" costs '
    '${boards == 1 ? '1 location' : '$boards locations'}, one on each of the '
    '${boards == 1 ? 'board' : '$boards boards'} in this set. Nothing already '
    'placed moves, and "$label" keeps the location it has now as well.';

/// Copies a word into the pinned column on every board.
///
/// Additive by construction: every location it fills was reserved and empty on
/// every board, so nothing anybody has learned moves.
///
/// Throws where [refusalToPin] would have refused. The screen asks first; this
/// asks again, because a rule enforced only by the screen that shows it is a
/// rule with a way round it.
Future<void> pinWord(WordbridgeDatabase db, Button button) async {
  final refusal = await refusalToPin(db, button);
  if (refusal != null) throw StateError(refusal);

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(button.vocabularyId))).getSingle();

  final row = (await freePinnedRows(db, vocabulary)).first;
  final col = pinnedColumn(vocabulary);

  final boards =
      await (db.select(db.boards)
            ..where((b) => b.vocabularyId.equals(vocabulary.id))
            ..where((b) => b.deletedAt.isNull()))
          .get();

  await db.transaction(() async {
    for (final board in boards) {
      final cell =
          await (db.select(db.cells)
                ..where((c) => c.boardId.equals(board.id))
                ..where((c) => c.row.equals(row))
                ..where((c) => c.col.equals(col)))
              .getSingle();

      await placeButton(
        db,
        vocabularyId: vocabulary.id,
        cellId: cell.id,
        label: button.label,
        message: button.message,
        symbolId: button.symbolId,
        partOfSpeech: button.partOfSpeech,
        vocabLevel: button.vocabLevel,
      );
    }

    await db
        .into(db.editEvents)
        .insert(
          EditEventsCompanion.insert(
            id: newId(),
            vocabularyId: vocabulary.id,
            buttonId: Value(button.id),
            kind: EditKind.create,
            afterJson: Value('{"pinnedRow":$row,"label":"${button.label}"}'),
            changedAt: nowMs(),
          ),
        );
  });
}

/// Takes a pinned word off every board, and leaves the original alone.
///
/// The locations go back to reserved, which is what they were before the pin.
/// Nothing that was there before the pin is touched, because a pin never
/// displaced anything to get there.
Future<void> unpinWord(
  WordbridgeDatabase db, {
  required Vocabulary vocabulary,
  required int row,
}) async {
  final col = pinnedColumn(vocabulary);

  final found =
      await (db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.buttons.vocabularyId.equals(vocabulary.id) &
                db.buttons.deletedAt.isNull() &
                db.buttons.isSystem.equals(false) &
                db.cells.row.equals(row) &
                db.cells.col.equals(col),
          ))
          .get();
  if (found.isEmpty) return;

  final ts = nowMs();
  final buttonIds = [for (final r in found) r.readTable(db.buttons).id];
  final cellIds = [for (final r in found) r.readTable(db.cells).id];

  await db.transaction(() async {
    await (db.update(db.buttons)..where((b) => b.id.isIn(buttonIds))).write(
      ButtonsCompanion(
        cellId: const Value(null),
        deletedAt: Value(ts),
        updatedAt: Value(ts),
      ),
    );
    await (db.update(db.cells)..where((c) => c.id.isIn(cellIds))).write(
      const CellsCompanion(state: Value(CellState.emptyReserved)),
    );
  });
}
