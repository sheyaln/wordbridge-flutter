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
/// way. A new board is the safest addition there is: it materializes beside the
/// others and costs one system-row column that was empty, so every key already
/// on the row keeps opening what it always opened.
library;

import 'package:drift/drift.dart';

import '../board_builder.dart';
import '../database.dart';
import '../ids.dart';
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
    this.renamed = const [],
    this.addedQuickSettings = false,
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

  /// Words whose label was corrected in place (§4.82), old name first.
  ///
  /// Separate from [added] because nothing arrived: these are buttons that
  /// were already on the board, at the same locations, now saying the right
  /// word. Counting them as additions would tell a caregiver a word appeared
  /// somewhere when what happened is that a word they already had got its
  /// spelling fixed.
  final List<({String from, String to})> renamed;

  /// Whether the quick settings key was put on the row (§4.81).
  ///
  /// Reported on its own rather than counted among [added], because it is not
  /// a word: it costs a column that was empty on every board, and a caregiver
  /// reading "1 word added" and finding a menu key would be reading a wrong
  /// answer to the question they asked.
  final bool addedQuickSettings;

  bool get isEmpty =>
      added.isEmpty &&
      blocked.isEmpty &&
      refusedBoards.isEmpty &&
      renamed.isEmpty &&
      !addedQuickSettings;
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
  var vocab = await (db.select(
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

  // Before anything is counted as missing. A category that was renamed is
  // still here under its old name, and everything below matches by name.
  final renamed = await _applyRenames(
    db,
    vocab: vocab,
    boards: boards,
    dryRun: dryRun,
  );
  vocab = renamed.vocab;
  boards = renamed.boards;

  // Before anything is counted as missing, for the same reason the category
  // renames run first: a word that was renamed is still on the board under its
  // old label, and everything below matches by label. Without this, "candy"
  // reads as absent, gets aimed at the cell "sweets" is sitting in, and is
  // reported as blocked by itself.
  final renamedWordList = await _renameWords(
    db,
    vocab: vocab,
    boards: boards,
    dryRun: dryRun,
  );

  // The boards somebody navigates to, which is every board except the quick
  // settings menu (§4.81).
  //
  // **Everything below that writes "to every board" means this list.** The menu
  // is drawn *over* a board rather than being one: it has no system row and no
  // pinned question column, because the board underneath it already has both.
  // Treating it as an ordinary board put a question column down the side of the
  // menu, and the menu draws what is on its board — so "what", "where" and
  // "who" turned up as menu rows.
  List<Board> navigable() => [
    for (final b in boards)
      if (b.kind != BoardKind.system) b,
  ];

  final added = <({String label, String board, int row, int col})>[];
  final blocked = <({String label, String board, String occupant})>[];

  // Strong language arrives whether or not it is switched on. Hiding holds the
  // location, so switching it on a year from now reveals it where it has always
  // been instead of pushing other words aside.
  final hiddenBands = (profanity ?? ageBand.swearsByDefault)
      ? const <String>{}
      : {swearingBand.name};

  // Read once per board and kept up to date as words land, because the check
  // below runs for every shipped word against every page of a board.
  final labelsSeen = <String, Map<String, String>>{};
  Future<Map<String, String>> labelsOn(String boardId) async =>
      labelsSeen[boardId] ??= await _labelsOn(db, boardId);

  Future<void> consider(
    Board board,
    String label,
    SeedWord word,
    int level,
    int row,
    int col, {
    bool hidden = false,
  }) async {
    // Every page of the board, not just this one. A word the grid pushed onto
    // page two is on the board; looking at page one alone places a second copy
    // and gives one word two locations, which is the one thing a layout built
    // on fixed positions cannot survive.
    for (final page in _pageGroup(boards, board)) {
      if ((await labelsOn(page.id)).containsKey(label)) return;
    }

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

    (await labelsOn(board.id))[label] = label;

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
  for (final board in navigable()) {
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

  final quickSettings = await _addQuickSettingsKey(
    db,
    vocab: vocab,
    boards: boards,
    dryRun: dryRun,
  );

  return VocabularyTopUp(
    added: added,
    blocked: blocked,
    addedBoards: newBoards.addedBoards,
    refusedBoards: newBoards.refusedBoards,
    renamed: renamedWordList,
    addedQuickSettings: quickSettings,
  );
}

/// Corrects the label on a word that shipped under the wrong one (§4.82).
///
/// **Nothing moves and nothing is created.** The button keeps its cell, its
/// id, its picture, its part of speech and its place in every motor plan that
/// reaches it; the word written on it changes. A person who had learned where
/// "sweets" was finds "candy" in exactly that location, said with exactly that
/// movement.
///
/// System keys are left alone. A category key is renamed by [_applyRenames],
/// which knows to match the board it opens as well as the label — renaming by
/// label alone here would take the word `home` off a board that carries it as
/// vocabulary.
Future<List<({String from, String to})>> _renameWords(
  WordbridgeDatabase db, {
  required Vocabulary vocab,
  required List<Board> boards,
  required bool dryRun,
}) async {
  final done = <({String from, String to})>[];

  for (final entry in renamedWords) {
    // `onBoard` is what keeps a rename off a word that merely shares a
    // spelling: "shop" the place becomes "store", and "shop" the verb on
    // `doing` is a different word and is left alone.
    final onlyHere = entry.onBoard;
    final pages = onlyHere == null
        ? null
        : {
            for (final b in boards)
              if (b.name == onlyHere || b.name.startsWith('$onlyHere ')) b.id,
          };

    final matches =
        await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])
              ..where(db.buttons.vocabularyId.equals(vocab.id))
              ..where(db.buttons.label.equals(entry.from))
              ..where(db.buttons.isSystem.equals(false)))
            .get();

    final wanted = [
      for (final r in matches)
        if (pages == null || pages.contains(r.readTable(db.cells).boardId)) r,
    ];
    if (wanted.isEmpty) continue;

    done.add((from: entry.from, to: entry.to));
    if (dryRun) continue;

    for (final row in wanted) {
      final button = row.readTable(db.buttons);
      await (db.update(db.buttons)..where((b) => b.id.equals(button.id))).write(
        ButtonsCompanion(
          label: Value(entry.to),
          // Only where the two were the same word. A button somebody edited to
          // say something longer — "I would like some sweets" — is that
          // person's sentence, and rewriting it would be editing what they
          // wrote rather than correcting what shipped.
          message: button.message == entry.from
              ? Value(entry.to)
              : const Value.absent(),
          updatedAt: Value(nowMs()),
        ),
      );
    }
  }

  return done;
}

/// Puts the quick settings key on a board set built before it existed (§4.81).
///
/// **Purely additive, or it does not happen.** The key goes in column 2, which
/// every board in a set laid out by [SystemRowPlan] leaves empty — it was the
/// gap between the undo keys and the category keys. If anything at all is
/// sitting there on any board, this returns without writing: a key that
/// appears on some boards and not others is not a fixed key, and one that
/// displaced something would change what a learned movement does.
///
/// Nothing moves either way. This fills a reserved location or it fills none.
Future<bool> _addQuickSettingsKey(
  WordbridgeDatabase db, {
  required Vocabulary vocab,
  required List<Board> boards,
  required bool dryRun,
}) async {
  final frame = SystemFrame.parse(vocab.systemCellMap);
  if (frame == null || frame.configCol != null) return false;

  // Column 2 is the gap, and only where the categories start after it. A grid
  // narrow enough to have given the gap up has a category key there, and that
  // key is not available.
  const col = 2;
  if (frame.categoryCols.isEmpty || frame.categoryCols.first <= col) {
    return false;
  }

  // Not until the wheel turns. Until then this column is the cycle key's last
  // resort, and a category that cannot be opened is worse than a menu that is
  // not on the row — see `SystemRowPlan.forGrid`. A board set that starts
  // cycling later gets the key on the top-up after that.
  if (frame.cycleCol == null) return false;
  if (frame.homeCol == col || frame.backCol == col) return false;
  final carrying = [
    for (final b in boards)
      if (b.kind != BoardKind.system) b,
  ];
  if (!await _isFreeOnEvery(db, carrying, frame.row, col)) return false;

  if (dryRun) return true;

  for (final board in carrying) {
    final cell = await cellAt(db, boardId: board.id, row: frame.row, col: col);
    await placeButton(
      db,
      vocabularyId: vocab.id,
      cellId: cell.id,
      label: quickSettingsLabel,
      message: '',
      action: ButtonAction.quickSettings,
      isSystem: true,
      symbolId: await frameKeySymbol(db, quickSettingsLabel),
    );
  }

  // The menu the key opens, which is a board of its own. Skipped if one is
  // somehow already there, so a half-finished top-up that is run again does
  // not leave a board set with two menus and no way to tell which one opens.
  final existing =
      await (db.select(db.boards)
            ..where((b) => b.vocabularyId.equals(vocab.id))
            ..where((b) => b.name.equals(quickSettingsBoardName)))
          .getSingleOrNull();
  if (existing == null) {
    await seedQuickSettingsMenu(
      db,
      vocabId: vocab.id,
      rows: vocab.gridRows,
      cols: vocab.gridCols,
      frame: frame.copyWith(configCol: col),
    );
  }

  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocab.id))).write(
    VocabulariesCompanion(
      systemCellMap: Value(frame.copyWith(configCol: col).toJson()),
    ),
  );

  return true;
}

/// Brings a board set's category names forward, so a rename is not read as a
/// board that went missing (§4.42).
///
/// Two places carry the name and both have to move together: the board row a
/// person navigates to, and the recorded frame the wheel is a window onto. A
/// board renamed without its frame entry is a board the wheel stops offering;
/// a frame entry renamed without its board is a key that opens nothing.
///
/// The pages come too. A board that overflowed is `body 2`, `body 3`, and
/// `pageName` will look for `health 2` the moment anything asks.
///
/// The key that opens it is relabelled too. The talk screen already draws that
/// key from the frame rather than from the button underneath — the slot shows a
/// different category on each turn of the wheel — so this changes nothing on
/// screen. It is for everywhere that does read the button: an exported board
/// file, and the editor a caregiver opens to look at what is on the row.
///
/// **Nothing moves.** A row's name is not a location: the board keeps its id,
/// every button on it keeps its cell, and the frame keeps the name at the index
/// it always sat at — so every key already learned opens what it always
/// opened, which is what makes this safe to do without asking.
///
/// Under [dryRun] the rename is applied in memory and never written, so the
/// preview a caregiver reads counts the same words the real run would place.
Future<({Vocabulary vocab, List<Board> boards})> _applyRenames(
  WordbridgeDatabase db, {
  required Vocabulary vocab,
  required List<Board> boards,
  required bool dryRun,
}) async {
  /// The name this board should carry now, or null if it already does.
  String? renameOf(String name) {
    for (final entry in renamedCategories.entries) {
      if (name == entry.key) return entry.value;
      if (name.startsWith('${entry.key} ')) {
        return '${entry.value}${name.substring(entry.key.length)}';
      }
    }
    return null;
  }

  final wanted = <String, String>{};
  for (final b in boards) {
    final to = renameOf(b.name);
    if (to != null) wanted[b.id] = to;
  }
  if (wanted.isEmpty) return (vocab: vocab, boards: boards);

  final frame = SystemFrame.parse(vocab.systemCellMap);
  final settled = frame?.copyWith(
    categories: [
      for (final c in frame.categories)
        (name: renamedCategories[c.name] ?? c.name, boardId: c.boardId),
    ],
  );

  if (!dryRun) {
    for (final entry in wanted.entries) {
      await (db.update(db.boards)..where((b) => b.id.equals(entry.key))).write(
        BoardsCompanion(name: Value(entry.value), updatedAt: Value(nowMs())),
      );

      // Only a key that says the old name and opens this board. A word that
      // happens to be spelled the same — `body` is on the board it names — is
      // vocabulary, not a label for a category, and renaming it would take a
      // word off somebody's board.
      final was = boards.firstWhere((b) => b.id == entry.key).name;
      await (db.update(db.buttons)..where(
            (b) =>
                b.targetBoardId.equals(entry.key) &
                b.label.equals(was) &
                b.isSystem.equals(true),
          ))
          .write(
            ButtonsCompanion(
              label: Value(entry.value),
              updatedAt: Value(nowMs()),
            ),
          );
    }
    if (settled != null) {
      await (db.update(
        db.vocabularies,
      )..where((v) => v.id.equals(vocab.id))).write(
        VocabulariesCompanion(
          systemCellMap: Value(settled.toJson()),
          updatedAt: Value(nowMs()),
        ),
      );
    }
  }

  return (
    vocab: settled == null
        ? vocab
        : vocab.copyWith(systemCellMap: settled.toJson()),
    boards: [
      for (final b in boards)
        if (wanted[b.id] case final to?) b.copyWith(name: to) else b,
    ],
  );
}

typedef _NewCategories = ({
  List<({String label, String board, int row, int col})> added,
  List<String> addedBoards,
  List<String> refusedBoards,
});

/// Gives a board set a category board that shipped after it was built.
///
/// Everything here is an addition. The board materializes at the grid the
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

    // **Refused, never resolved by moving something.** The gap is the cycle
    // key's last resort and it is also where the quick settings key sits
    // (§4.81), so a board set that has stopped cycling and still carries that
    // key has nowhere to put a cycle key.
    //
    // Evicting the quick settings key to make room was tried and is wrong:
    // every top-up is an addition, and `fingerprint` proves it by asserting
    // that nothing on any board has changed. A key vanishing from a row
    // somebody has learned is precisely the displacement that guarantee
    // exists to forbid — it does not stop being one because what it makes
    // room for is valuable.
    //
    // So the category is refused and said out loud, which is the honest
    // outcome and the one a caregiver can act on.
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
      final boardId = await materializeBoard(
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
          label: key.cycles ? cycleCategoriesLabel : category,
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

/// The pages of one board, which are one board as far as a word is concerned.
///
/// Pages are named "home", "home 2", "home 3" — the same board, continued — so
/// the group is everything sharing that stem.
List<Board> _pageGroup(List<Board> boards, Board board) {
  final base = _pageStem(board.name);
  return [
    for (final b in boards)
      if (_pageStem(b.name) == base) b,
  ];
}

String _pageStem(String name) {
  final at = name.lastIndexOf(' ');
  if (at < 0) return name;
  return int.tryParse(name.substring(at + 1)) == null
      ? name
      : name.substring(0, at);
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
