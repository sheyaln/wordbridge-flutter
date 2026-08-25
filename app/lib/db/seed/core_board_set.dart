import 'package:drift/drift.dart';

import '../board_builder.dart';
import '../database.dart';
import '../ids.dart';
import '../tables.dart';

/// The shipped starter vocabulary.
///
/// Independently designed. Word selection comes from Project Core's Universal
/// Core 36 (Center for Literacy and Disability Studies, UNC-Chapel Hill);
/// placement follows the Fitzgerald Key's left-to-right sentence ordering,
/// published in 1926 and long out of copyright. No commercial vocabulary
/// layout was consulted or reproduced. See docs/starter-vocabulary.md for the
/// full derivation.
///
/// Roughly half the grid ships deliberately empty. Those locations are
/// reserved, not missing: personal vocabulary grows into them without
/// displacing anything already learned.

const _gridRows = 7;
const _gridCols = 12;

/// Row 6 is the system row on every board, so its positions are identical
/// wherever the user happens to be.
const _systemRow = 6;

typedef _Word = ({int row, int col, String label, PartOfSpeech pos, int level});

/// Column bands, following Fitzgerald ordering: who → does → what/where → why.
///
/// Column 1 is intentionally blank. It sits immediately beside the pronouns
/// and is where family names belong — the single most-requested personal
/// vocabulary, given a permanent home from day one rather than appended
/// wherever there happens to be room.
const _homeWords = <_Word>[
  // Column 0 — pronouns
  (row: 0, col: 0, label: 'I', pos: PartOfSpeech.pronoun, level: 1),
  (row: 1, col: 0, label: 'you', pos: PartOfSpeech.pronoun, level: 1),
  (row: 2, col: 0, label: 'he', pos: PartOfSpeech.pronoun, level: 1),
  (row: 3, col: 0, label: 'she', pos: PartOfSpeech.pronoun, level: 1),
  (row: 4, col: 0, label: 'it', pos: PartOfSpeech.pronoun, level: 1),
  (row: 5, col: 0, label: 'that', pos: PartOfSpeech.pronoun, level: 1),

  // Column 2 — determiners and quantifiers
  (row: 0, col: 2, label: 'all', pos: PartOfSpeech.determiner, level: 1),
  (row: 1, col: 2, label: 'some', pos: PartOfSpeech.determiner, level: 1),
  (row: 2, col: 2, label: 'same', pos: PartOfSpeech.determiner, level: 2),
  (row: 3, col: 2, label: 'different', pos: PartOfSpeech.determiner, level: 2),
  (row: 4, col: 2, label: 'more', pos: PartOfSpeech.determiner, level: 1),

  // Columns 3-5 — verbs, the largest band because they carry the most traffic
  (row: 0, col: 3, label: 'want', pos: PartOfSpeech.verb, level: 1),
  (row: 1, col: 3, label: 'go', pos: PartOfSpeech.verb, level: 1),
  (row: 2, col: 3, label: 'get', pos: PartOfSpeech.verb, level: 1),
  (row: 3, col: 3, label: 'do', pos: PartOfSpeech.verb, level: 1),
  (row: 4, col: 3, label: 'make', pos: PartOfSpeech.verb, level: 2),
  (row: 5, col: 3, label: 'put', pos: PartOfSpeech.verb, level: 2),

  (row: 0, col: 4, label: 'like', pos: PartOfSpeech.verb, level: 1),
  (row: 1, col: 4, label: 'help', pos: PartOfSpeech.verb, level: 1),
  (row: 2, col: 4, label: 'look', pos: PartOfSpeech.verb, level: 1),
  (row: 3, col: 4, label: 'open', pos: PartOfSpeech.verb, level: 2),
  (row: 4, col: 4, label: 'turn', pos: PartOfSpeech.verb, level: 2),
  (row: 5, col: 4, label: 'stop', pos: PartOfSpeech.verb, level: 1),

  (row: 0, col: 5, label: 'can', pos: PartOfSpeech.verb, level: 2),
  (row: 1, col: 5, label: 'finished', pos: PartOfSpeech.verb, level: 1),

  // Column 9 — prepositions and place
  (row: 0, col: 9, label: 'here', pos: PartOfSpeech.preposition, level: 1),
  (row: 1, col: 9, label: 'in', pos: PartOfSpeech.preposition, level: 2),
  (row: 2, col: 9, label: 'on', pos: PartOfSpeech.preposition, level: 2),
  (row: 3, col: 9, label: 'up', pos: PartOfSpeech.preposition, level: 2),

  // Column 10 — descriptors and negation.
  // "not" gets a high-contrast location of its own: refusal is the most
  // urgent thing a user can need, and burying it is a safety problem.
  (row: 0, col: 10, label: 'good', pos: PartOfSpeech.adjective, level: 1),
  (row: 1, col: 10, label: 'not', pos: PartOfSpeech.negation, level: 1),
];

/// The rightmost column, repeated on every board.
///
/// Questions are not a category — they apply to whatever the user is already
/// looking at. Pinning them means "where" is one movement from anywhere
/// rather than a trip back to the root board and out again, which is the
/// difference between asking a question and giving up on asking it.
///
/// Same reasoning as the system row, one axis over.
const _pinnedColumn = 11;

const _pinnedWords = <_Word>[
  (
    row: 0,
    col: _pinnedColumn,
    label: 'what',
    pos: PartOfSpeech.question,
    level: 1,
  ),
  (
    row: 1,
    col: _pinnedColumn,
    label: 'where',
    pos: PartOfSpeech.question,
    level: 1,
  ),
  (
    row: 2,
    col: _pinnedColumn,
    label: 'who',
    pos: PartOfSpeech.question,
    level: 2,
  ),
  (
    row: 3,
    col: _pinnedColumn,
    label: 'when',
    pos: PartOfSpeech.question,
    level: 2,
  ),
  (
    row: 4,
    col: _pinnedColumn,
    label: 'why',
    pos: PartOfSpeech.question,
    level: 2,
  ),
];

/// Category boards reachable in one tap from the system row.
const _categories = <({int col, String name, String label})>[
  (col: 3, name: 'people', label: 'people'),
  (col: 4, name: 'food', label: 'food'),
  (col: 5, name: 'play', label: 'play'),
  (col: 6, name: 'feelings', label: 'feelings'),
  (col: 7, name: 'places', label: 'places'),
  (col: 8, name: 'body', label: 'body'),
];

/// Creates the shipped vocabulary and returns its id.
Future<String> seedCoreBoardSet(
  WordbridgeDatabase db, {
  String name = 'wordbridge core',
  String locale = 'en-US',
}) async {
  final vocabId = newId();
  final ts = nowMs();

  await db
      .into(db.vocabularies)
      .insert(
        VocabulariesCompanion.insert(
          id: vocabId,
          name: name,
          locale: Value(locale),
          gridRows: _gridRows,
          gridCols: _gridCols,
          isTemplate: const Value(true),
          sourceLicense: const Value(
            'Word selection derived from Project Core Universal Core 36 '
            '(UNC CLDS). Layout independently designed.',
          ),
          createdAt: ts,
          updatedAt: ts,
        ),
      );

  final homeId = await materialiseBoard(
    db,
    vocabularyId: vocabId,
    name: 'home',
    kind: BoardKind.root,
  );

  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId))).write(
    VocabulariesCompanion(rootBoardId: Value(homeId)),
  );

  for (final w in _homeWords) {
    final cell = await cellAt(db, boardId: homeId, row: w.row, col: w.col);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: w.label,
      message: w.label,
      partOfSpeech: w.pos,
      vocabLevel: w.level,
    );
  }

  // Category boards must exist before the buttons that navigate to them.
  final boardIds = <String, String>{};
  for (final c in _categories) {
    boardIds[c.name] = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: c.name,
      kind: BoardKind.category,
    );
  }

  await _addPinnedCells(db, vocabId, homeId, boardIds);
  for (final id in boardIds.values) {
    await _addPinnedCells(db, vocabId, id, boardIds);
  }

  return vocabId;
}

/// Places everything that appears on every board.
///
/// The bottom row (home, back, categories, editing) and the rightmost column
/// (questions) are at identical coordinates wherever the user is, so reaching
/// them is one fixed movement rather than a path that depends on which board
/// happens to be open.
Future<void> _addPinnedCells(
  WordbridgeDatabase db,
  String vocabId,
  String boardId,
  Map<String, String> categoryBoards,
) async {
  Future<void> place(
    int col,
    String label,
    ButtonAction action, {
    String? target,
  }) async {
    final cell = await cellAt(db, boardId: boardId, row: _systemRow, col: col);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: '',
      action: action,
      targetBoardId: target,
      isSystem: true,
    );
  }

  // Questions first: they are ordinary vocabulary that happens to be pinned,
  // not controls, so they keep their part-of-speech colour and are editable
  // like any other word.
  for (final w in _pinnedWords) {
    final cell = await cellAt(db, boardId: boardId, row: w.row, col: w.col);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: w.label,
      message: w.label,
      partOfSpeech: w.pos,
      vocabLevel: w.level,
    );
  }

  await place(0, 'home', ButtonAction.home);
  await place(1, 'back', ButtonAction.back);

  for (final c in _categories) {
    await place(
      c.col,
      c.label,
      ButtonAction.navigate,
      target: categoryBoards[c.name],
    );
  }

  await place(10, 'undo', ButtonAction.backspace);
  await place(11, 'clear', ButtonAction.clear);
}
