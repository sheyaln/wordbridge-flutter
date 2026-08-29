import 'dart:convert';

import 'package:drift/drift.dart';

import '../board_builder.dart';
import '../database.dart';
import '../ids.dart';
import '../tables.dart';
import 'age_presets.dart';
import 'band_layout.dart';
import 'core_vocabulary.dart';

/// Builds the shipped vocabulary at whatever grid size was chosen.
///
/// The words and their order live in core_vocabulary.dart; this file turns
/// them into rows, boards, cells and buttons. Nothing here decides where a
/// word goes — [layOutBands] does, from the same declaration every time, so
/// two runs at one grid size produce byte-identical coordinates.
///
/// Roughly half of every board ships deliberately empty. Those locations are
/// reserved, not missing: personal vocabulary grows into them without
/// displacing anything already learned.

/// The default, and what a 10-inch tablet in landscape comfortably holds.
const defaultGridRows = 7;
const defaultGridCols = 12;

/// Creates a vocabulary and returns its id.
Future<String> seedCoreBoardSet(
  WordbridgeDatabase db, {
  String name = 'wordbridge core',
  String locale = 'en-US',
  int rows = defaultGridRows,
  int cols = defaultGridCols,
  String profileId = 'default',
  bool attachToProfile = true,
  AgeBand ageBand = AgeBand.child,
  bool? profanity,
}) async {
  // Seeded whether or not it is switched on. Hiding holds the locations, so
  // switching strong language on a year from now reveals it where it has
  // always been instead of pushing other words aside.
  final swearingVisible = profanity ?? ageBand.swearsByDefault;

  SystemRowPlan.validate(rows: rows, cols: cols);

  final plan = SystemRowPlan.forGrid(
    rows: rows,
    cols: cols,
    categories: categoryNames.length,
  );

  // A short grid cannot show all the questions in the pinned column. The ones
  // that do not fit become ordinary words on the root board rather than being
  // dropped: an extra movement to ask "why" is a cost, losing the word is a
  // different thing entirely.
  final questionRows = rows - 1;
  final questions = pinnedQuestions.take(questionRows).toList();
  final spilledQuestions = pinnedQuestions.skip(questionRows).toList();

  final vocabId = newId();
  final ts = nowMs();

  await db
      .into(db.vocabularies)
      .insert(
        VocabulariesCompanion.insert(
          id: vocabId,
          name: name,
          locale: Value(locale),
          gridRows: rows,
          gridCols: cols,
          isTemplate: const Value(true),
          sourceLicense: const Value(
            'Word selection derived from Project Core Universal Core 36 '
            '(UNC CLDS). Layout independently designed.',
          ),
          createdAt: ts,
          updatedAt: ts,
        ),
      );

  if (attachToProfile) {
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: profileId,
            activeVocabularyId: Value(vocabId),
            vocabLevel: Value(ageBand.startingLevel),
            createdAt: ts,
            updatedAt: ts,
          ),
          mode: InsertMode.insertOrIgnore,
        );

    await (db.update(db.profiles)..where((p) => p.id.equals(profileId))).write(
      ProfilesCompanion(
        activeVocabularyId: Value(vocabId),
        updatedAt: Value(ts),
      ),
    );
  }

  // The root board pages like any other. Words the grid cannot hold go to a
  // second page reached by the same key, rather than to a board of leftovers
  // that would need a key of its own.
  final homePages = await _buildPagedBoards(
    db,
    vocabId: vocabId,
    name: 'home',
    rootKind: true,
    rows: rows,
    cols: cols,
    bands: [
      ...homeBands,
      // Filling the tail the band before it left rather than claiming a line
      // of its own. One or two spilled items would otherwise cost a whole
      // column at 7x12 and push every band to their right along with it — a
      // price paid by the entire board so that one word need not move.
      if (spilledQuestions.isNotEmpty)
        Band(
          name: 'questions',
          items: spilledQuestions,
          shedRank: 3,
          startsLine: false,
        ),
    ],
  );

  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId))).write(
    VocabulariesCompanion(rootBoardId: Value(homePages.first)),
  );

  // Category boards must exist before the keys that navigate to them, and a
  // page must exist before the key that pages to it.
  final categoryPages = <String, List<String>>{};
  for (final category in categoryNames) {
    categoryPages[category] = await _buildPagedBoards(
      db,
      vocabId: vocabId,
      name: category,
      axis: BandAxis.rows,
      bands: categoryBandsFor(category, ageBand),
      rows: rows,
      cols: cols,
      hiddenBands: swearingVisible ? const {} : {swearingBand.name},
    );
  }

  // Every category in a fixed order. The keys along the system row are a
  // window onto this list; the cycle key moves the window. Recording the order
  // here is what lets the talk screen do that without moving a button.
  final frame = SystemFrame.of(plan, [
    for (final c in categoryNames) (name: c, boardId: categoryPages[c]!.first),
  ]);

  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId))).write(
    VocabulariesCompanion(systemCellMap: Value(frame.toJson())),
  );

  final pageGroups = [homePages, ...categoryPages.values];

  // Every board carries the same frame, so reaching home or asking "where" is
  // one unchanging movement no matter where the user is.
  for (final group in pageGroups) {
    for (var index = 0; index < group.length; index++) {
      await addFixedKeys(
        db,
        vocabId: vocabId,
        boardId: group[index],
        rows: rows,
        cols: cols,
        frame: frame,
        questions: questions,
        pageBack: index > 0 ? group[index - 1] : null,
        pageForward: index < group.length - 1 ? group[index + 1] : null,
      );
    }
  }

  return vocabId;
}

/// What belongs on a category board for one age preset.
///
/// Extras are appended, never inserted, so two profiles of different ages put
/// the same shipped word in the same place. One answer, shared by the seed, a
/// rebuild's preview and a top-up: three that computed it separately would
/// drift, and the drift would show up as words moving.
List<Band<SeedWord>> categoryBandsFor(String category, AgeBand ageBand) => [
  ...categoryBands[category]!,
  ...ageBand.extrasFor(category),
  if (ageBand.canSwear && category == 'feelings') swearingBand,
];

/// What page [index] of a board group is called.
///
/// Page one keeps the board's own name, so the name a category key navigates
/// to is the same string whether or not the grid needed a second page.
String pageName(String name, int index) =>
    index == 0 ? name : '$name ${index + 1}';

/// Lays a board's vocabulary out across as many pages as the grid needs.
///
/// Paging rather than scrolling. A page is a grid, so a word on page two is
/// still at one unchanging sequence of movements; a scrolling surface would
/// put a word wherever the scroll happened to be, which is no position at all.
///
/// Pure, and the single answer to "where would this word land": a preview that
/// paged differently from the seed would promise a location the board then
/// does not deliver.
List<BandLayout<SeedWord>> pageBands({
  required String name,
  required List<Band<SeedWord>> bands,
  required int rows,
  required int cols,
  BandAxis axis = BandAxis.columns,
}) {
  final pages = <BandLayout<SeedWord>>[];
  var remaining = bands;

  while (true) {
    final page = layOutBands(
      rows: rows,
      cols: cols,
      bands: remaining,
      axis: axis,
    );
    pages.add(page);

    if (page.overflow.isEmpty) return pages;

    // A page that placed nothing would loop forever. The layout engine always
    // fits at least one column of words, so this guards a future change rather
    // than a case that happens today.
    if (page.placed.isEmpty) {
      throw StateError('"$name" cannot be paged onto a ${rows}x$cols grid.');
    }

    // Overflow keeps its band name so a hidden band stays hidden wherever it
    // lands. Splitting a band across pages must not reveal half of it.
    //
    // It keeps the band's fill for the same reason: a band reads one way, and
    // a page where the same band ran the other way would be a second thing to
    // learn about words that are already one group.
    //
    // Shedding works from the end of a band backwards, so the overflow list
    // arrives reversed. Putting it back into declaration order is what makes
    // page two read the same way page one does.
    final fills = {for (final b in remaining) b.name: b.fill};
    remaining = [
      for (final band in page.overflowBands)
        Band(
          name: band,
          fill: fills[band]!,
          items: [
            for (final o in page.overflow.reversed)
              if (o.band == band) o.item,
          ],
        ),
    ];
  }
}

Future<List<String>> _buildPagedBoards(
  WordbridgeDatabase db, {
  required String vocabId,
  required String name,
  required List<Band<SeedWord>> bands,
  required int rows,
  required int cols,
  BandAxis axis = BandAxis.columns,
  bool rootKind = false,
  Set<String> hiddenBands = const {},
}) async {
  final pages = pageBands(
    name: name,
    bands: bands,
    rows: rows,
    cols: cols,
    axis: axis,
  );

  final boardIds = <String>[];
  for (var index = 0; index < pages.length; index++) {
    final boardId = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: pageName(name, index),
      kind: rootKind && index == 0 ? BoardKind.root : BoardKind.category,
    );
    boardIds.add(boardId);

    await _placeAll(
      db,
      vocabId,
      boardId,
      pages[index].placed,
      hiddenBands: hiddenBands,
    );
  }

  return boardIds;
}

Future<void> _placeAll(
  WordbridgeDatabase db,
  String vocabId,
  String boardId,
  List<BandPlacement<SeedWord>> placements, {
  Set<String> hiddenBands = const {},
}) async {
  for (final p in placements) {
    final cell = await cellAt(db, boardId: boardId, row: p.row, col: p.col);
    await placeButton(
      db,
      vocabularyId: vocabId,
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

/// Places everything that appears at identical coordinates on every board.
///
/// The bottom row (home, back, categories, paging) and the rightmost column
/// (questions). Reaching them is one fixed movement rather than a path that
/// depends on which board happens to be open.
Future<void> addFixedKeys(
  WordbridgeDatabase db, {
  required String vocabId,
  required String boardId,
  required int rows,
  required int cols,
  required SystemFrame frame,
  required List<BandItem<SeedWord>> questions,
  String? pageBack,
  String? pageForward,
}) async {
  Future<void> key(
    int col,
    String label,
    ButtonAction action, {
    String? target,
  }) async {
    final cell = await cellAt(db, boardId: boardId, row: frame.row, col: col);
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
  // not controls, so they keep their part-of-speech colour and stay editable
  // like any other word.
  final questionCol = cols - 1;
  for (var i = 0; i < questions.length; i++) {
    final item = questions[i];
    final cell = await cellAt(db, boardId: boardId, row: i, col: questionCol);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: item.value.label,
      message: item.value.message,
      action: item.value.action,
      partOfSpeech: item.value.pos,
      vocabLevel: item.level,
    );
  }

  await key(frame.homeCol, 'home', ButtonAction.home);
  await key(frame.backCol, 'back', ButtonAction.back);

  // The keys as they stand on the first turn of the wheel. When there are more
  // categories than slots, the talk screen draws a different one of them in
  // each slot as the wheel turns; the location never changes, only what it
  // opens.
  for (var i = 0; i < frame.categoryCols.length; i++) {
    await key(
      frame.categoryCols[i],
      frame.categories[i].name,
      ButtonAction.navigate,
      target: frame.categories[i].boardId,
    );
  }

  if (frame.cycleCol != null) {
    await key(frame.cycleCol!, 'more categories', ButtonAction.cycleCategories);
  }

  // Paging keys are drawn only where there is a page to go to, and reappear in
  // the same place when there is. No undo or clear here: both duplicate
  // controls that belong on the utterance bar, and every duplicate costs a
  // permanent location on every board — plus a second place a user can
  // accidentally delete their sentence from.
  if (pageBack != null) {
    await key(
      frame.pageBackCol,
      'back a page',
      ButtonAction.navigate,
      target: pageBack,
    );
  }
  if (pageForward != null) {
    await key(
      frame.pageForwardCol,
      'more words',
      ButtonAction.navigate,
      target: pageForward,
    );
  }
}

/// Where the fixed keys landed, and which category each one opens.
///
/// Recorded on the vocabulary, and from then on the authority — not what
/// [SystemRowPlan] would compute today. A board set gains a category by
/// appending to this recording, so a key that has been learned keeps opening
/// what it always opened.
class SystemFrame {
  const SystemFrame({
    required this.row,
    required this.homeCol,
    required this.backCol,
    required this.categoryCols,
    required this.cycleCol,
    required this.pageBackCol,
    required this.pageForwardCol,
    required this.categories,
  });

  SystemFrame.of(SystemRowPlan plan, this.categories)
    : row = plan.row,
      homeCol = plan.homeCol,
      backCol = plan.backCol,
      categoryCols = plan.categoryCols,
      cycleCol = plan.cycleCol,
      pageBackCol = plan.pageBackCol,
      pageForwardCol = plan.pageForwardCol;

  /// Reads a recording back, or null for one that does not describe a wheel —
  /// an imported board set, or a vocabulary built before the wheel existed.
  /// Nothing may be appended to a frame that cannot be read: a category board
  /// no key opens is worse than not having the board.
  static SystemFrame? parse(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final cols = (map['categoryCols'] as List?)?.cast<int>();
      final categories = (map['categories'] as List?)
          ?.cast<Map<String, dynamic>>();
      if (cols == null || cols.isEmpty || categories == null) return null;

      return SystemFrame(
        row: map['row'] as int,
        homeCol: map['home'] as int,
        backCol: map['back'] as int,
        categoryCols: cols,
        cycleCol: map['cycleCol'] as int?,
        pageBackCol: map['backAPage'] as int,
        pageForwardCol: map['moreWords'] as int,
        categories: [
          for (final c in categories)
            (name: c['name'] as String, boardId: c['boardId'] as String),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  final int row;
  final int homeCol;
  final int backCol;

  /// One per category showing at a time, left to right.
  final List<int> categoryCols;

  /// Where the key that turns the wheel goes, or null while every category has
  /// a slot of its own.
  final int? cycleCol;

  final int pageBackCol;
  final int pageForwardCol;

  /// Every category, in the order its key was learned. The slots are a window
  /// onto this list and [cycleCol] moves the window.
  final List<({String name, String boardId})> categories;

  /// Whether the slots show every category at once, so the wheel never turns.
  bool get showsEveryCategory =>
      cycleCol == null && categories.length <= categoryCols.length;

  SystemFrame copyWith({
    List<int>? categoryCols,
    int? cycleCol,
    List<({String name, String boardId})>? categories,
  }) => SystemFrame(
    row: row,
    homeCol: homeCol,
    backCol: backCol,
    categoryCols: categoryCols ?? this.categoryCols,
    cycleCol: cycleCol ?? this.cycleCol,
    pageBackCol: pageBackCol,
    pageForwardCol: pageForwardCol,
    categories: categories ?? this.categories,
  );

  String toJson() => jsonEncode({
    'row': row,
    'home': homeCol,
    'back': backCol,
    'categoryCols': categoryCols,
    if (cycleCol != null) 'cycleCol': cycleCol,
    'backAPage': pageBackCol,
    'moreWords': pageForwardCol,
    // The full ordered list, so the talk screen can turn the wheel without a
    // button ever changing its location.
    'categories': [
      for (final c in categories) {'name': c.name, 'boardId': c.boardId},
    ],
  });
}
