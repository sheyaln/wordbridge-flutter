/// Bringing shipped words to a board that was built before they existed.
///
/// The vocabulary grows between releases. A board built last month should be
/// able to receive this month's words without being rebuilt, because rebuilding
/// is what moves things.
///
/// Additive by construction. A word only ever lands at the location the layout
/// rule already assigns it on that grid, and only if that location is still
/// free. Nothing is moved, nothing is overwritten, and a caregiver's own word
/// sitting where a shipped one would go keeps the spot — their choice is worth
/// more than ours.
library;

import 'package:drift/drift.dart';

import '../board_builder.dart';
import '../database.dart';
import '../tables.dart';
import 'age_presets.dart';
import 'band_layout.dart';
import 'core_vocabulary.dart';

/// What a top-up would do, or did.
class VocabularyTopUp {
  const VocabularyTopUp({required this.added, required this.blocked});

  /// Words placed, or that would be placed.
  final List<({String label, String board, int row, int col})> added;

  /// Words whose location is already taken by something else. Reported rather
  /// than forced, so a caregiver can see what the board gave up and decide.
  final List<({String label, String board, String occupant})> blocked;

  bool get isEmpty => added.isEmpty && blocked.isEmpty;
  int get count => added.length;
}

/// Works out what is missing, and optionally places it.
///
/// Pass `dryRun: true` to show a caregiver what would happen before it does.
Future<VocabularyTopUp> topUpVocabulary(
  WordbridgeDatabase db, {
  required String vocabularyId,
  AgeBand ageBand = AgeBand.child,
  bool profanity = false,
  bool dryRun = false,
}) async {
  final vocab = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingle();

  final boards = await (db.select(
    db.boards,
  )..where((b) => b.vocabularyId.equals(vocabularyId))).get();

  final added = <({String label, String board, int row, int col})>[];
  final blocked = <({String label, String board, String occupant})>[];

  Future<void> consider(
    Board board,
    String label,
    SeedWord word,
    int level,
    int row,
    int col,
  ) async {
    final existing = await _labelsOn(db, board.id);
    if (existing.containsKey(label)) return;

    final cell = await cellAt(db, boardId: board.id, row: row, col: col);
    if (cell.state == CellState.occupied) {
      final occupant = await (db.select(
        db.buttons,
      )..where((b) => b.cellId.equals(cell.id))).getSingleOrNull();
      blocked.add((
        label: label,
        board: board.name,
        occupant: occupant?.label ?? 'something else',
      ));
      return;
    }

    added.add((label: label, board: board.name, row: row, col: col));
    if (dryRun) return;

    await placeButton(
      db,
      vocabularyId: vocabularyId,
      cellId: cell.id,
      label: word.label,
      message: word.message,
      action: word.action,
      morphemeKind: word.morphemeKind,
      partOfSpeech: word.pos,
      vocabLevel: level,
    );
  }

  // The root board, laid out by the same rule that built it. A word's location
  // is wherever that rule puts it on this grid, which is where it would have
  // been had it shipped in the first place.
  final root = boards.where((b) => b.kind == BoardKind.root).firstOrNull;
  if (root != null) {
    final layout = layOutBands(
      rows: vocab.gridRows,
      cols: vocab.gridCols,
      bands: homeBands,
    );
    for (final p in layout.placed) {
      await consider(root, p.value.label, p.value, p.level, p.row, p.col);
    }
  }

  // The pinned column belongs to every board, so a new question mark has to
  // reach all of them or it is in a different place depending on where you are.
  final questionCol = vocab.gridCols - 1;
  final questionRows = vocab.gridRows - 1;
  for (final board in boards) {
    for (var i = 0; i < pinnedQuestions.length && i < questionRows; i++) {
      final item = pinnedQuestions[i];
      await consider(
        board,
        item.value.label,
        item.value,
        item.level,
        i,
        questionCol,
      );
    }
  }

  for (final category in categoryNames) {
    final board = boards.where((b) => b.name == category).firstOrNull;
    if (board == null) continue;

    final layout = layOutBands(
      rows: vocab.gridRows,
      cols: vocab.gridCols,
      axis: BandAxis.rows,
      bands: [
        ...categoryBands[category]!,
        ...ageBand.extrasFor(category),
        if (ageBand.canSwear && category == 'feelings') swearingBand,
      ],
    );

    for (final p in layout.placed) {
      await consider(board, p.value.label, p.value, p.level, p.row, p.col);
    }
  }

  return VocabularyTopUp(added: added, blocked: blocked);
}

Future<Map<String, String>> _labelsOn(
  WordbridgeDatabase db,
  String boardId,
) async {
  // System keys only, excluded. "home", "back" and "play" are all both a key
  // and a word, so counting the keys would make those three words look
  // already-present on every board that carries them.
  final query =
      db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(
        db.cells.boardId.equals(boardId) & db.buttons.isSystem.equals(false),
      );

  return {
    for (final r in await query.get())
      r.readTable(db.buttons).label: r.readTable(db.buttons).id,
  };
}
