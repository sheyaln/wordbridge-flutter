/// Moving a whole row of words to another page of the same category (§4.42).
///
/// Every category board ships a `saying` row of phrases on page one. A
/// caregiver who reaches for those constantly wants them there; one who never
/// does wants the row back for vocabulary. Which page a row sits on is the
/// choice that was asked for, and it only exists once there is a second page.
///
/// **This is a displacing edit and is never anything else.** A row moving
/// pages takes every word on it to a new location, which is the thing this app
/// exists to stop happening by accident. So it is offered with what it costs
/// stated first, in the same terms as the remap warning, and it is refused
/// rather than forced wherever it cannot be done cleanly.
///
/// **The row keeps its line.** It moves to the *same* line on the other page,
/// so the words stay at the height they were and only the page changes — the
/// smallest movement that does what was asked. That also makes it exactly
/// reversible: the line it leaves goes back to reserved, so moving it back
/// puts every word where it was.
library;

import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/seed/core_board_set.dart';
import '../../db/tables.dart';
import '../usage/usage_queries.dart';
import 'remap.dart';

/// What moving a row would cost, in the units a caregiver counts in.
typedef RowMoveCost = ({int words, int taps, int windowDays});

/// Every page of the group this board belongs to, first page first.
///
/// Walked through the paging keys rather than read off the board names, for
/// §4.42's reason: a board a caregiver renamed still pages the way it always
/// did, and a name is the one thing about a board they are free to change.
Future<List<Board>> pagesOfGroup(WordbridgeDatabase db, Board board) async {
  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(board.vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return [board];

  final frame = SystemFrame.parse(vocabulary.systemCellMap);
  if (frame == null) return [board];

  Future<Board?> step(Board from, int col) async {
    final rows =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.cells.boardId.equals(from.id) &
                  db.cells.row.equals(frame.row) &
                  db.cells.col.equals(col) &
                  db.buttons.deletedAt.isNull() &
                  db.buttons.isSystem.equals(true),
            ))
            .get();
    if (rows.isEmpty) return null;

    final target = rows.first.readTable(db.buttons).targetBoardId;
    if (target == null) return null;

    return (db.select(db.boards)
          ..where((b) => b.id.equals(target))
          ..where((b) => b.deletedAt.isNull()))
        .getSingleOrNull();
  }

  // Back to the front of the group first, then forward through it. Guarded
  // against a cycle: a board set edited by hand can point a paging key at a
  // board that points back, and an editor that hangs is worse than one that
  // shows a short list.
  var first = board;
  final seen = <String>{board.id};
  while (true) {
    final back = await step(first, frame.pageBackCol);
    if (back == null || !seen.add(back.id)) break;
    first = back;
  }

  final pages = <Board>[first];
  final walked = <String>{first.id};
  var current = first;
  while (true) {
    final next = await step(current, frame.pageForwardCol);
    if (next == null || !walked.add(next.id)) break;
    pages.add(next);
    current = next;
  }

  return pages;
}

/// The words on one line of a board, left to right.
///
/// **The pinned question column is not one of them.** It carries `what`,
/// `where` and the rest at identical coordinates on every board and every page
/// (§4.16), and they are ordinary vocabulary rather than system keys — so
/// nothing here may match on `isSystem` alone. A row move that took them with
/// it would move a question off the frame it is the frame *of*.
Future<List<Button>> wordsOnLine(
  WordbridgeDatabase db,
  String boardId,
  int line, {
  required int pinnedCol,
}) async {
  final rows =
      await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])
            ..where(
              db.cells.boardId.equals(boardId) &
                  db.cells.row.equals(line) &
                  db.cells.col.isNotValue(pinnedCol) &
                  db.buttons.deletedAt.isNull() &
                  db.buttons.isSystem.equals(false),
            )
            ..orderBy([OrderingTerm.asc(db.cells.col)]))
          .get();

  return [for (final r in rows) r.readTable(db.buttons)];
}

/// The column the frame pins the questions into, on every board.
int pinnedColumnOf(Vocabulary vocabulary) => vocabulary.gridCols - 1;

/// Why this row cannot move to that page, in the sentence a caregiver reads.
///
/// A refusal that names its reason rather than a control that is missing —
/// the rule §4.15 set and §4.43 and §4.16 both follow.
Future<String?> refusalToMoveRow(
  WordbridgeDatabase db, {
  required Board from,
  required int line,
  required Board to,
}) async {
  if (from.id == to.id) return 'That row is already on this page.';

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(from.vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return 'This board set could not be read.';

  final frame = SystemFrame.parse(vocabulary.systemCellMap);
  if (frame != null && line == frame.row) {
    return 'That is the row every board navigates from. It is the same row on '
        'every page, so there is nowhere for it to go.';
  }

  final pinnedCol = pinnedColumnOf(vocabulary);
  final words = await wordsOnLine(db, from.id, line, pinnedCol: pinnedCol);
  if (words.isEmpty) return 'There are no words on that row to move.';

  // The pinned column is occupied on every row of every page, by the question
  // that belongs there. Counting it would make every row look spoken for.
  final occupied =
      await (db.select(db.cells)
            ..where((c) => c.boardId.equals(to.id))
            ..where((c) => c.row.equals(line))
            ..where((c) => c.col.isNotValue(pinnedCol))
            ..where((c) => c.state.equalsValue(CellState.occupied)))
          .get();

  if (occupied.isNotEmpty) {
    final count = occupied.length;
    return 'Row ${line + 1} of "${to.name}" already holds '
        '${count == 1 ? '1 word' : '$count words'}. A row only moves onto a '
        'row that is empty, so nothing already placed is displaced to make '
        'room for it.';
  }

  return null;
}

/// How many words move, and how often those locations have been reached for.
///
/// Taps across the whole row rather than per word, because what is being
/// decided is the row: a caregiver moving five words is told what the five
/// cost together.
Future<RowMoveCost> rowMoveCost(
  WordbridgeDatabase db, {
  required Board from,
  required int line,
  UsageWindow window = const UsageWindow.rollingDays(90),
}) async {
  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(from.vocabularyId))).getSingle();

  final words = await wordsOnLine(
    db,
    from.id,
    line,
    pinnedCol: pinnedColumnOf(vocabulary),
  );
  final usage = UsageQueries(db);

  var taps = 0;
  for (final word in words) {
    final cellId = word.cellId;
    if (cellId == null) continue;
    taps += (await usage.historyForCell(cellId, window: window)).taps;
  }

  return (words: words.length, taps: taps, windowDays: window.days);
}

/// What moving the row costs, said before it happens.
///
/// The same voice as the remap warning: name the thing being given up, in the
/// user's own terms, and let the caregiver decide.
String rowMoveWarning({
  required RowMoveCost cost,
  required String toBoardName,
  String? userName,
}) {
  final who = userName ?? 'This user';
  final words = cost.words == 1 ? '1 word' : '${cost.words} words';

  final practice = cost.taps == 0
      ? 'Nothing on this row has been reached for in the last '
            '${cost.windowDays} days, as far as anything recorded says.'
      : '$who has reached for these locations ${cost.taps} times in the last '
            '${cost.windowDays} days. If those positions have been learned, '
            'moving them may take weeks to relearn.';

  return '$words move to "$toBoardName", onto the same row one page across. '
      'Nothing else on either page moves.\n\n'
      '$practice\n\n'
      'The row they leave goes back to being empty and reserved, so moving '
      'them back puts every one of them exactly where it is now.';
}

/// Moves every word on a line to the same line on another page.
///
/// Throws where [refusalToMoveRow] would have refused. The screen asks first;
/// this asks again, because a rule enforced only by the screen that shows it
/// is a rule with a way round it.
///
/// One word at a time through [RemapService.moveButton], so every move is
/// recorded in the trail the way a single move is and undo can walk back
/// through them — a row move is a lot of edits, not a new kind of edit.
Future<void> moveRow(
  WordbridgeDatabase db, {
  required Board from,
  required int line,
  required Board to,
  String? profileId,
}) async {
  final refusal = await refusalToMoveRow(db, from: from, line: line, to: to);
  if (refusal != null) throw StateError(refusal);

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(from.vocabularyId))).getSingle();

  final words = await wordsOnLine(
    db,
    from.id,
    line,
    pinnedCol: pinnedColumnOf(vocabulary),
  );
  final remap = RemapService(db);

  for (final word in words) {
    final cell = await (db.select(
      db.cells,
    )..where((c) => c.id.equals(word.cellId!))).getSingle();

    final target =
        await (db.select(db.cells)
              ..where((c) => c.boardId.equals(to.id))
              ..where((c) => c.row.equals(line))
              ..where((c) => c.col.equals(cell.col)))
            .getSingle();

    await remap.moveButton(
      buttonId: word.id,
      toCellId: target.id,
      profileId: profileId,
    );
  }
}
