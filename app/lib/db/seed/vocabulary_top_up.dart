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
///
/// A whole category that shipped since the board set was built arrives the same
/// way. A new board is the safest addition there is: it materialises beside the
/// others and costs one system-row column that was empty, so every key already
/// on the row keeps opening what it always opened.
library;

import 'package:drift/drift.dart';

import '../board_builder.dart';
import '../database.dart';
import '../tables.dart';
import 'age_presets.dart';
import 'band_layout.dart';
import 'core_board_set.dart';
import 'core_vocabulary.dart';

/// What a top-up would do, or did.
class VocabularyTopUp {
  const VocabularyTopUp({
    required this.added,
    required this.blocked,
    this.addedBoards = const [],
    this.refusedBoards = const [],
  });

  /// Words placed, or that would be placed.
  final List<({String label, String board, int row, int col})> added;

  /// Words whose location is already taken by something else. Reported rather
  /// than forced, so a caregiver can see what the board gave up and decide.
  final List<({String label, String board, String occupant})> blocked;

  /// Category boards created. Their words are counted in [added] like any
  /// other, because that is what they are.
  final List<String> addedBoards;

  /// Categories that could not be added, because the system row has no free
  /// column to open one from. Taking a key that already opens something else
  /// would relocate what a learned movement does, which is the one thing a
  /// top-up may never do.
  final List<String> refusedBoards;

  bool get isEmpty => added.isEmpty && blocked.isEmpty && refusedBoards.isEmpty;
  int get count => added.length;
}

/// Works out what is missing, and optionally places it.
///
/// Pass `dryRun: true` to show a caregiver what would happen before it does.
Future<VocabularyTopUp> topUpVocabulary(
  WordbridgeDatabase db, {
  required String vocabularyId,
  AgeBand ageBand = AgeBand.child,
  bool? profanity,
  bool dryRun = false,
}) async {
  final vocab = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingle();

  // A removed board takes no new words and holds no name against a category
  // that wants it. Writing to one would put shipped vocabulary somewhere
  // nothing can reach.
  var boards =
      await (db.select(db.boards)
            ..where((b) => b.vocabularyId.equals(vocabularyId))
            ..where((b) => b.deletedAt.isNull()))
          .get();

  final added = <({String label, String board, int row, int col})>[];
  final blocked = <({String label, String board, String occupant})>[];

  // Strong language arrives whether or not it is switched on. Hiding holds the
  // location, so switching it on a year from now reveals it where it has always
  // been instead of pushing other words aside.
  final hiddenBands = (profanity ?? ageBand.swearsByDefault)
      ? const <String>{}
      : {swearingBand.name};

  Future<void> consider(
    Board board,
    String label,
    SeedWord word,
    int level,
    int row,
    int col, {
    bool hidden = false,
  }) async {
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
      hidden: hidden,
    );
  }

  final newBoards = await _addMissingCategories(
    db,
    vocab: vocab,
    boards: boards,
    ageBand: ageBand,
    hiddenBands: hiddenBands,
    dryRun: dryRun,
  );

  added.addAll(newBoards.added);
  if (!dryRun && newBoards.addedBoards.isNotEmpty) {
    boards =
        await (db.select(db.boards)
              ..where((b) => b.vocabularyId.equals(vocabularyId))
              ..where((b) => b.deletedAt.isNull()))
            .get();
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
      bands: categoryBandsFor(category, ageBand),
    );

    for (final p in layout.placed) {
      await consider(
        board,
        p.value.label,
        p.value,
        p.level,
        p.row,
        p.col,
        hidden: hiddenBands.contains(p.band),
      );
    }
  }

  return VocabularyTopUp(
    added: added,
    blocked: blocked,
    addedBoards: newBoards.addedBoards,
    refusedBoards: newBoards.refusedBoards,
  );
}

typedef _NewCategories = ({
  List<({String label, String board, int row, int col})> added,
  List<String> addedBoards,
  List<String> refusedBoards,
});

/// Gives a board set a category board that shipped after it was built.
///
/// Everything here is an addition. The board materialises at the grid the
/// vocabulary already declares — every board in a set shares one geometry or
/// the motor plan does not hold — and its words page exactly as they would on
/// a new profile of the same size. The only thing written to a board that
/// already exists is one key, on a column of the system row that was empty.
Future<_NewCategories> _addMissingCategories(
  WordbridgeDatabase db, {
  required Vocabulary vocab,
  required List<Board> boards,
  required AgeBand ageBand,
  required Set<String> hiddenBands,
  required bool dryRun,
}) async {
  final added = <({String label, String board, int row, int col})>[];
  final addedBoards = <String>[];
  final refused = <String>[];

  var present = {for (final b in boards) b.name};
  var carrying = boards;
  var frame = SystemFrame.parse(vocab.systemCellMap);

  for (final category in categoryNames) {
    if (present.contains(category)) continue;

    // A board no key opens is worse than not having the board: it is
    // vocabulary the user is told about and cannot reach.
    final room = frame == null ? null : _roomForCategory(frame);
    if (frame == null || room == null) {
      refused.add(category);
      continue;
    }

    // Either a slot for the category itself, or the cycle key that reaches it.
    // Both are new keys on a column that carried nothing.
    final key = room.categoryCols.length > frame.categoryCols.length
        ? (col: room.categoryCols.last, cycles: false)
        : room.cycleCol != frame.cycleCol
        ? (col: room.cycleCol!, cycles: true)
        : null;

    if (key != null &&
        !await _isFreeOnEvery(db, carrying, frame.row, key.col)) {
      refused.add(category);
      continue;
    }

    final pages = pageBands(
      name: category,
      bands: categoryBandsFor(category, ageBand),
      rows: vocab.gridRows,
      cols: vocab.gridCols,
      axis: BandAxis.rows,
    );

    for (var page = 0; page < pages.length; page++) {
      for (final p in pages[page].placed) {
        added.add((
          label: p.value.label,
          board: pageName(category, page),
          row: p.row,
          col: p.col,
        ));
      }
    }
    addedBoards.add(category);
    present = {
      ...present,
      for (var p = 0; p < pages.length; p++) pageName(category, p),
    };

    if (dryRun) {
      frame = frame.copyWith(
        categoryCols: room.categoryCols,
        cycleCol: room.cycleCol,
        categories: [...frame.categories, (name: category, boardId: '')],
      );
      continue;
    }

    final pageIds = <String>[];
    for (var page = 0; page < pages.length; page++) {
      final boardId = await materialiseBoard(
        db,
        vocabularyId: vocab.id,
        name: pageName(category, page),
        kind: BoardKind.category,
      );
      pageIds.add(boardId);

      for (final p in pages[page].placed) {
        final cell = await cellAt(db, boardId: boardId, row: p.row, col: p.col);
        await placeButton(
          db,
          vocabularyId: vocab.id,
          cellId: cell.id,
          label: p.value.label,
          message: p.value.message,
          action: p.value.action,
          morphemeKind: p.value.morphemeKind,
          partOfSpeech: p.value.pos,
          vocabLevel: p.level,
          hidden: hiddenBands.contains(p.band),
        );
      }
    }

    // Appended, never inserted. The slots are a window onto this list, so a
    // name put anywhere but the end would change which board every key after
    // it opens without a single button moving.
    frame = frame.copyWith(
      categoryCols: room.categoryCols,
      cycleCol: room.cycleCol,
      categories: [
        ...frame.categories,
        (name: category, boardId: pageIds.first),
      ],
    );

    for (var page = 0; page < pageIds.length; page++) {
      await addFixedKeys(
        db,
        vocabId: vocab.id,
        boardId: pageIds[page],
        rows: vocab.gridRows,
        cols: vocab.gridCols,
        frame: frame,
        questions: pinnedQuestions.take(vocab.gridRows - 1).toList(),
        pageBack: page > 0 ? pageIds[page - 1] : null,
        pageForward: page < pageIds.length - 1 ? pageIds[page + 1] : null,
      );
    }

    if (key != null) {
      for (final board in carrying) {
        final cell = await cellAt(
          db,
          boardId: board.id,
          row: frame.row,
          col: key.col,
        );
        await placeButton(
          db,
          vocabularyId: vocab.id,
          cellId: cell.id,
          label: key.cycles ? 'more categories' : category,
          message: '',
          action: key.cycles
              ? ButtonAction.cycleCategories
              : ButtonAction.navigate,
          targetBoardId: key.cycles ? null : pageIds.first,
          isSystem: true,
        );
      }
    }

    carrying =
        await (db.select(db.boards)
              ..where((b) => b.vocabularyId.equals(vocab.id))
              ..where((b) => b.deletedAt.isNull()))
            .get();
  }

  if (!dryRun && frame != null && addedBoards.isNotEmpty) {
    await (db.update(db.vocabularies)..where((v) => v.id.equals(vocab.id)))
        .write(VocabulariesCompanion(systemCellMap: Value(frame.toJson())));
  }

  return (added: added, addedBoards: addedBoards, refusedBoards: refused);
}

/// Room along a system row that is already learned, for one more category.
///
/// While every category has a slot of its own, the next column along is still
/// empty and becomes one. Once the wheel turns, a category costs nothing at
/// all: it is one more turn of a key that already exists. Between those two
/// sits a row whose slots are full and which has never cycled — the cycle key
/// then takes the gap column, the only one left, because a cycle key beside
/// "back" is a smaller cost than a category nobody can open.
///
/// Widening the window is only safe while every category is showing. The slots
/// are a window onto the ordered list, so widening one that already turns
/// renumbers what every later turn shows.
///
/// Null when no column is free, which is the point at which a board set stops
/// being able to gain categories.
({List<int> categoryCols, int? cycleCol})? _roomForCategory(SystemFrame frame) {
  if (!frame.showsEveryCategory) {
    return (categoryCols: frame.categoryCols, cycleCol: frame.cycleCol);
  }

  final next = frame.categoryCols.last + 1;
  if (next < frame.pageBackCol) {
    return (categoryCols: [...frame.categoryCols, next], cycleCol: null);
  }

  final gap = frame.backCol + 1;
  if (gap >= frame.categoryCols.first) return null;
  return (categoryCols: frame.categoryCols, cycleCol: gap);
}

/// Whether one location is empty on every board in the set.
///
/// A key that lands on some boards and not others is not a fixed key, so a
/// single occupied cell is enough to refuse the whole addition.
Future<bool> _isFreeOnEvery(
  WordbridgeDatabase db,
  List<Board> boards,
  int row,
  int col,
) async {
  for (final board in boards) {
    final cell = await cellAt(db, boardId: board.id, row: row, col: col);
    if (cell.state == CellState.occupied) return false;
  }
  return true;
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
