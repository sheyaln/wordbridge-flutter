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
  final swearing = ageBand.canSwear;
  final swearingVisible = profanity ?? ageBand.swearsByDefault;
  SystemRowPlan.validate(rows: rows, cols: cols);

  final home = layOutBands(rows: rows, cols: cols, bands: homeBands);

  // A short grid cannot show all five questions in the pinned column. The ones
  // that do not fit move to the overflow board rather than being dropped: an
  // extra tap to ask "why" is a cost, losing the word is a different thing
  // entirely.
  final questionRows = rows - 1;
  final questions = pinnedQuestions.take(questionRows).toList();

  final extraWords = <BandItem<SeedWord>>[
    for (final o in home.overflow) o.item,
    ...pinnedQuestions.skip(questionRows),
  ];

  final plan = SystemRowPlan.forGrid(
    rows: rows,
    cols: cols,
    categories: categoryNames.length,
    needsOverflow: extraWords.isNotEmpty,
  );

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
          systemCellMap: Value(_systemCellMap(plan)),
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

  final homeId = await materialiseBoard(
    db,
    vocabularyId: vocabId,
    name: 'home',
    kind: BoardKind.root,
  );

  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId))).write(
    VocabulariesCompanion(rootBoardId: Value(homeId)),
  );

  await _placeAll(db, vocabId, homeId, home.placed);

  // Category boards must exist before the buttons that navigate to them, and
  // a page must exist before the key that pages to it.
  final categoryPages = <String, List<String>>{};
  for (final category in categoryNames) {
    categoryPages[category] = await _buildPagedBoards(
      db,
      vocabId: vocabId,
      name: category,
      bands: [
        ...categoryBands[category]!,
        ...ageBand.extrasFor(category),
        if (swearing && category == 'feelings') swearingBand,
      ],
      rows: rows,
      cols: cols,
      hiddenBands: swearingVisible ? const {} : {swearingBand.name},
    );
  }

  final shown = plan.categoryCols.length;
  final spilled = categoryNames.sublist(shown);

  final pageGroups = [...categoryPages.values];

  if (plan.overflowCol != null) {
    pageGroups.add(
      await _buildPagedBoards(
        db,
        vocabId: vocabId,
        name: 'more words',
        rows: rows,
        cols: cols,
        links: {for (final c in spilled) c: categoryPages[c]!.first},
        bands: [
          Band(
            name: 'categories',
            items: [
              for (final c in spilled)
                BandItem((
                  label: c,
                  message: '',
                  action: ButtonAction.navigate,
                  morphemeKind: null,
                  pos: null,
                )),
            ],
          ),
          Band(name: 'words', items: extraWords),
        ],
      ),
    );
  }

  final reachable = <String, String>{
    for (var i = 0; i < shown; i++)
      categoryNames[i]: categoryPages[categoryNames[i]]!.first,
  };

  // Every board carries the same frame, so reaching home or asking "where" is
  // one unchanging movement no matter where the user is.
  for (final boardId in [homeId, for (final g in pageGroups) ...g]) {
    final pages = pageGroups.firstWhere(
      (g) => g.contains(boardId),
      orElse: () => const [],
    );
    final index = pages.indexOf(boardId);

    await _addFixedKeys(
      db,
      vocabId: vocabId,
      boardId: boardId,
      rows: rows,
      cols: cols,
      plan: plan,
      questions: questions,
      categories: reachable,
      overflowBoardId: plan.overflowCol == null ? null : pageGroups.last.first,
      pageBack: index > 0 ? pages[index - 1] : null,
      pageForward: index >= 0 && index < pages.length - 1
          ? pages[index + 1]
          : null,
    );
  }

  return vocabId;
}

/// Lays a board's vocabulary out across as many pages as the grid needs.
///
/// Paging rather than scrolling. A page is a grid, so a word on page two is
/// still at one unchanging sequence of movements; a scrolling surface would
/// put a word wherever the scroll happened to be, which is no position at all.
Future<List<String>> _buildPagedBoards(
  WordbridgeDatabase db, {
  required String vocabId,
  required String name,
  required List<Band<SeedWord>> bands,
  required int rows,
  required int cols,
  Map<String, String> links = const {},
  Set<String> hiddenBands = const {},
}) async {
  final boardIds = <String>[];
  var remaining = bands;

  while (true) {
    final page = layOutBands(rows: rows, cols: cols, bands: remaining);

    final boardId = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: boardIds.isEmpty ? name : '$name ${boardIds.length + 1}',
      kind: BoardKind.category,
    );
    boardIds.add(boardId);

    await _placeAll(
      db,
      vocabId,
      boardId,
      page.placed,
      links: links,
      hiddenBands: hiddenBands,
    );

    if (page.overflow.isEmpty) return boardIds;

    // A page that placed nothing would loop forever. The layout engine always
    // fits at least one column of words, so this guards a future change rather
    // than a case that happens today.
    if (page.placed.isEmpty) {
      throw StateError('"$name" cannot be paged onto a ${rows}x$cols grid.');
    }

    // Overflow keeps its band name so a hidden band stays hidden wherever it
    // lands. Splitting a band across pages must not reveal half of it.
    remaining = [
      for (final name in page.overflowBands)
        Band(
          name: name,
          items: [
            for (final o in page.overflow)
              if (o.band == name) o.item,
          ],
        ),
    ];
  }
}

Future<void> _placeAll(
  WordbridgeDatabase db,
  String vocabId,
  String boardId,
  List<BandPlacement<SeedWord>> placements, {
  Map<String, String> links = const {},
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
      targetBoardId: p.value.action == ButtonAction.navigate
          ? links[p.value.label]
          : null,
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
Future<void> _addFixedKeys(
  WordbridgeDatabase db, {
  required String vocabId,
  required String boardId,
  required int rows,
  required int cols,
  required SystemRowPlan plan,
  required List<BandItem<SeedWord>> questions,
  required Map<String, String> categories,
  String? overflowBoardId,
  String? pageBack,
  String? pageForward,
}) async {
  Future<void> key(
    int col,
    String label,
    ButtonAction action, {
    String? target,
  }) async {
    final cell = await cellAt(db, boardId: boardId, row: plan.row, col: col);
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
      partOfSpeech: item.value.pos,
      vocabLevel: item.level,
    );
  }

  await key(plan.homeCol, 'home', ButtonAction.home);
  await key(plan.backCol, 'back', ButtonAction.back);

  for (var i = 0; i < plan.categoryCols.length; i++) {
    final name = categoryNames[i];
    await key(
      plan.categoryCols[i],
      name,
      ButtonAction.navigate,
      target: categories[name],
    );
  }

  if (plan.overflowCol != null && overflowBoardId != null) {
    await key(
      plan.overflowCol!,
      'more words',
      ButtonAction.navigate,
      target: overflowBoardId,
    );
  }

  // Paging keys are drawn only where there is a page to go to, and reappear in
  // the same place when there is. No undo or clear here: both duplicate
  // controls that belong on the utterance bar, and every duplicate costs a
  // permanent location on every board — plus a second place a user can
  // accidentally delete their sentence from.
  if (pageBack != null) {
    await key(
      plan.pageBackCol,
      'back a page',
      ButtonAction.navigate,
      target: pageBack,
    );
  }
  if (pageForward != null) {
    await key(
      plan.pageForwardCol,
      'more',
      ButtonAction.navigate,
      target: pageForward,
    );
  }
}

/// Records where the fixed keys landed, so a later rebuild at the same size
/// can be checked against what the user actually learned.
String _systemCellMap(SystemRowPlan plan) => jsonEncode({
  'row': plan.row,
  'home': plan.homeCol,
  'back': plan.backCol,
  'categories': plan.categoryCols,
  if (plan.overflowCol != null) 'more words': plan.overflowCol,
  'back a page': plan.pageBackCol,
  'more': plan.pageForwardCol,
});
