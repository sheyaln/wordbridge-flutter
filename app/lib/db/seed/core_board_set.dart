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

  // Column 1 was held for names, and still mostly is. "we" and "they" take
  // its top two locations because they are core vocabulary and column 0 is
  // full — adding them here is additive, where reshuffling column 0 to make
  // room would have moved six words that already have positions.
  (row: 0, col: 1, label: 'we', pos: PartOfSpeech.pronoun, level: 1),
  (row: 1, col: 1, label: 'they', pos: PartOfSpeech.pronoun, level: 1),

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
  // Modals. "will" is how the board says anything about the future at all,
  // which the vocabulary had no way to express.
  (row: 2, col: 5, label: 'will', pos: PartOfSpeech.verb, level: 1),

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

/// Word endings, sitting immediately right of the verbs.
///
/// Five locations buy every inflected form of every verb on the board. The
/// alternative — a cell each for want, wants, wanted, wanting — would consume
/// the grid several times over and still miss combinations nobody predicted.
///
/// Placed at column 6 because verbs occupy 3 to 5: the movement reads left to
/// right, verb then ending, matching the order the words come out in.
const _morphemeColumn = 6;

const _morphemes =
    <({int row, String label, MorphemeKind? kind, String tense})>[
      (row: 0, label: '+s', kind: MorphemeKind.pluralS, tense: ''),
      (row: 1, label: '+ed', kind: MorphemeKind.pastEd, tense: ''),
      (row: 2, label: '+ing', kind: MorphemeKind.ing, tense: ''),
      (row: 3, label: "+'s", kind: MorphemeKind.possessive, tense: ''),
      // The copula agrees with whatever subject is already in the bar, so one
      // location covers am / is / are and another covers was / were.
      (row: 4, label: 'am/is/are', kind: null, tense: 'present'),
      (row: 5, label: 'was/were', kind: null, tense: 'past'),
    ];

/// Articles, one column further right.
///
/// "a" is inserted and repaired to "an" once the following word is known —
/// the choice has to be made before the noun exists, and asking a user to
/// know how their next word starts is not a reasonable thing to ask.
const _articleColumn = 7;

const _articles = <({int row, String label, String word})>[
  (row: 0, label: 'a', word: 'a'),
  (row: 1, label: 'the', word: 'the'),
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

/// Fringe vocabulary, written as the grid it becomes.
///
/// Each inner list is a row; `null` is a location deliberately left open.
/// Laying it out literally rather than filling from a flat word list is the
/// point: a word's position is written down, so adding one later cannot
/// quietly shift the rest. Only rows 0-3 are used, leaving rows 4 and 5 free
/// for the vocabulary a particular person turns out to need.
///
/// Columns stop at 10. Column 11 is the pinned question column.
typedef _CategoryGrid = ({
  List<List<String?>> rows,
  Set<String> verbs,
  Set<String> adjectives,
});

// The grid below is laid out to be read as a grid. dart format would set one
// word per line, which hides the very thing that makes it reviewable: whether
// a board is balanced, and where the deliberate gaps are.
// dart format off
const _categoryVocabulary = <String, _CategoryGrid>{
  // Generic relations only. The blank columns are where a family's actual
  // names belong — the most-requested personal vocabulary in every account of
  // AAC use, and the thing a shipped board can never guess.
  'people': (
    rows: [
      ['mum',     'dad',      null,     null, null, 'friend',    'teacher'],
      ['baby',    'brother',  'sister', null, null, 'doctor',    'nurse'],
      ['grandma', 'grandpa',  null,     null, null, 'everybody', 'nobody'],
      ['name',    'who'],
    ],
    verbs: {},
    adjectives: {},
  ),
  'food': (
    rows: [
      ['eat',       'drink',   null,      'water',  'milk',    'juice',    null, 'hungry', 'thirsty'],
      ['apple',     'banana',  'bread',   'cheese', 'egg',     'rice',     null, 'hot',    'cold'],
      ['pizza',     'pasta',   'chicken', 'soup',   'cake',    'biscuit',  null, 'yummy',  'yucky'],
      ['breakfast', 'lunch',   'dinner',  'snack'],
    ],
    verbs: {'eat', 'drink'},
    adjectives: {'hungry', 'thirsty', 'hot', 'cold', 'yummy', 'yucky'},
  ),
  'play': (
    rows: [
      ['play',    'read',      'draw',       'sing',    'dance',  'run'],
      ['ball',    'book',      'toy',        'game',    'puzzle', 'blocks'],
      ['music',   'video',     'tablet',     'bubbles', 'swing',  'slide'],
      ['outside', 'my turn',   'your turn',  'again'],
    ],
    verbs: {'play', 'read', 'draw', 'sing', 'dance', 'run'},
    adjectives: {},
  ),
  // Deliberately includes the difficult ones. A board that can only say
  // "happy" and "sad" cannot report pain, fear, or being overwhelmed, which
  // are the feelings that most need saying.
  'feelings': (
    rows: [
      ['happy',    'sad',        'angry',    'scared',          'tired', 'excited'],
      ['hurt',     'sick',       'worried',  'lonely',          'bored', 'silly'],
      ['love',     'like',       'hate',     'miss'],
      ['too loud', 'too bright', 'too much', 'leave me alone'],
    ],
    verbs: {'love', 'like', 'hate', 'miss'},
    adjectives: {
      'happy', 'sad', 'angry', 'scared', 'tired', 'excited',
      'hurt', 'sick', 'worried', 'lonely', 'bored', 'silly',
    },
  ),
  'places': (
    rows: [
      ['home',     'school',  'shop',    'park',   'car',     'bus'],
      ['bathroom', 'bedroom', 'kitchen', 'garden', 'outside', 'inside'],
      ['hospital', 'work',    'holiday', 'away'],
    ],
    verbs: {},
    adjectives: {},
  ),
  'body': (
    rows: [
      ['head',     'face',     'eyes',    'ears', 'nose',  'mouth'],
      ['hand',     'arm',      'leg',     'foot', 'tummy', 'back'],
      ['hair',     'teeth',    'throat',  'skin'],
      ['it hurts', 'medicine', 'plaster'],
    ],
    verbs: {},
    adjectives: {},
  ),
};
// dart format on

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

  await db
      .into(db.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: 'default',
          displayName: 'default',
          activeVocabularyId: Value(vocabId),
          createdAt: ts,
          updatedAt: ts,
        ),
        mode: InsertMode.insertOrIgnore,
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

  for (final m in _morphemes) {
    final cell = await cellAt(
      db,
      boardId: homeId,
      row: m.row,
      col: _morphemeColumn,
    );
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: m.label,
      // A copula carries its tense here; a suffix carries it in morphemeKind.
      message: m.tense,
      action: ButtonAction.morpheme,
      morphemeKind: m.kind,
      partOfSpeech: PartOfSpeech.other,
      vocabLevel: 2,
    );
  }

  for (final a in _articles) {
    final cell = await cellAt(
      db,
      boardId: homeId,
      row: a.row,
      col: _articleColumn,
    );
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: a.label,
      message: 'article',
      action: ButtonAction.morpheme,
      partOfSpeech: PartOfSpeech.determiner,
      vocabLevel: 2,
    );
  }

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

  for (final entry in boardIds.entries) {
    await _fillCategory(db, vocabId, entry.value, entry.key);
  }

  await _addPinnedCells(db, vocabId, homeId, boardIds);
  for (final id in boardIds.values) {
    await _addPinnedCells(db, vocabId, id, boardIds);
  }

  return vocabId;
}

/// Places a category's vocabulary at the coordinates its grid declares.
Future<void> _fillCategory(
  WordbridgeDatabase db,
  String vocabId,
  String boardId,
  String category,
) async {
  final grid = _categoryVocabulary[category];
  if (grid == null) return;

  for (var row = 0; row < grid.rows.length; row++) {
    final labels = grid.rows[row];
    for (var col = 0; col < labels.length; col++) {
      final label = labels[col];
      if (label == null) continue;

      final cell = await cellAt(db, boardId: boardId, row: row, col: col);
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: label,
        message: label,
        partOfSpeech: grid.verbs.contains(label)
            ? PartOfSpeech.verb
            : grid.adjectives.contains(label)
            ? PartOfSpeech.adjective
            : PartOfSpeech.noun,
        // Fringe vocabulary sits at level 2 so an emergent user starts on core
        // words alone, and the categories fill in without anything moving.
        vocabLevel: 2,
      );
    }
  }
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

  // No undo or clear here. Both duplicate controls that belong on the
  // utterance bar, and every duplicate costs a permanent location on every
  // board — plus a second place a user can accidentally delete their sentence
  // from. Those two slots stay reserved.
}
