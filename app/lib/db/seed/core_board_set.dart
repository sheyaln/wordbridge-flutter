import 'dart:convert';

import 'package:drift/drift.dart';

import '../board_builder.dart';
import '../database.dart';
import '../ids.dart';
import '../tables.dart';
import 'age_presets.dart';
import 'band_layout.dart';
import 'core_vocabulary.dart';
import '../../features/grid/region_labels.dart';
import '../../features/symbols/symbol_pack.dart';

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

/// What the key that turns the category wheel reads.
///
/// Shared, because the seed writes it, a top-up writes it again for a board
/// that gains a wheel, and the trail names a turn of the wheel with it. Three
/// copies of one string drift, and the drift reads as the board renaming a key
/// nobody touched.
const cycleCategoriesLabel = 'more categories';

/// What the key that turns to the next page reads.
///
/// Shared for the same reason: the seed writes it, and the trail names a page
/// step with it.
const moreWordsLabel = 'more words';

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
  String? userName,
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
  final questions = pinnedQuestions.take(rows - 1).toList();

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

  // The row, but not yet the pointer at this vocabulary. Attaching happens at
  // the very end — see the note there.
  if (attachToProfile) {
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: profileId,
            vocabLevel: Value(ageBand.startingLevel),
            createdAt: ts,
            updatedAt: ts,
          ),
          mode: InsertMode.insertOrIgnore,
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
    bands: rootBandsFor(rows),
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

  await placeUserName(
    db,
    vocabularyId: vocabId,
    boardId: homePages.first,
    name: userName,
  );

  // Last, and that is the whole point of where it sits.
  //
  // A profile's `active_vocabulary_id` is watched: the session follows it and
  // swaps the board the moment it changes. Pointing at this vocabulary before
  // the boards existed published a board set that was still being written —
  // `root_board_id` was null for the whole of the build, so the screen that
  // arrived had no board to draw and sat on a spinner that nothing would ever
  // clear. Rebuilding from the shipped vocabulary hung exactly there.
  //
  // Attaching here means a watcher sees the vocabulary only once it is whole.
  if (attachToProfile) {
    await (db.update(db.profiles)..where((p) => p.id.equals(profileId))).write(
      ProfilesCompanion(
        activeVocabularyId: Value(vocabId),
        updatedAt: Value(ts),
      ),
    );
  }

  return vocabId;
}

/// Puts the person's own name beside the pronouns, if there is room for it.
///
/// The single most personal word on any board, and the one a shipped
/// vocabulary can never guess. It goes in the pronoun band because that is
/// what it is — the word for the person saying it — and beside `I` and `you`
/// rather than on a page of its own.
///
/// **Placed afterwards rather than seeded as a band item, on purpose.** The
/// bands are what setup measures a grid against (`boardSetRefusal`), and a name
/// that varied the answer would let setup offer a grid the seed then refused —
/// the §4.6b bug, arrived at from a new direction. So this takes a location the
/// layout already left free and never asks for one.
///
/// **No free location means no cell**, rather than a location invented
/// somewhere else. A name that lands beside the pronouns on one device and on
/// page two of another is one word with a different motor path per device,
/// which is the thing this board does not do.
Future<String?> placeUserName(
  WordbridgeDatabase db, {
  required String vocabularyId,
  required String boardId,
  String? name,
}) async {
  final label = name?.trim();
  if (label == null || label.isEmpty) return null;

  final board = await (db.select(
    db.boards,
  )..where((b) => b.id.equals(boardId))).getSingleOrNull();
  if (board == null) return null;

  final regions = BoardRegions.decode(board.bandMap);
  final pronouns = regions?.bands
      .where((b) => b.name == 'pronouns')
      .firstOrNull;
  if (regions == null || pronouns == null) return null;

  final free = await _freeCellInLines(
    db,
    boardId: boardId,
    axis: regions.axis,
    first: pronouns.first,
    last: pronouns.last,
  );
  if (free == null) return null;

  return placeButton(
    db,
    vocabularyId: vocabularyId,
    cellId: free.id,
    label: label,
    message: label,
    partOfSpeech: PartOfSpeech.pronoun,
  );
}

/// The first reserved location inside a run of lines, reading the way the band
/// was filled.
///
/// Ordered by line and then by position within it, so the name lands at the top
/// of the first column with room rather than wherever the query happened to
/// return — a location chosen by row order is one a person can find again.
Future<Cell?> _freeCellInLines(
  WordbridgeDatabase db, {
  required String boardId,
  required BandAxis axis,
  required int first,
  required int last,
}) async {
  final cells =
      await (db.select(db.cells)..where(
            (c) =>
                c.boardId.equals(boardId) &
                c.state.equalsValue(CellState.emptyReserved),
          ))
          .get();

  int line(Cell c) => axis == BandAxis.columns ? c.col : c.row;
  int within(Cell c) => axis == BandAxis.columns ? c.row : c.col;

  final inBand =
      [
        for (final c in cells)
          if (line(c) >= first && line(c) <= last) c,
      ]..sort((a, b) {
        final byLine = line(a).compareTo(line(b));
        return byLine != 0 ? byLine : within(a).compareTo(within(b));
      });

  return inBand.firstOrNull;
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

/// What the root board holds on a grid this tall.
///
/// One answer, shared by the seed and by the fit check setup runs before
/// offering a grid. Two derivations of the same thing drift, and this drift
/// would show up as a grid a caregiver was offered and the seed then refused.
List<Band<SeedWord>> rootBandsFor(int rows) {
  final spilled = pinnedQuestions.skip(rows - 1).toList();

  return [
    ...homeBands,
    // Filling the tail the band before it left rather than claiming a line of
    // its own. One or two spilled items would otherwise cost a whole column at
    // 7x12 and push every band to their right along with it — a price paid by
    // the entire board so that one word need not move.
    if (spilled.isNotEmpty)
      Band(name: 'questions', items: spilled, shedRank: 3, startsLine: false),
  ];
}

/// Why this grid cannot carry the shipped vocabulary, or null if it can.
///
/// [SystemRowPlan.validate] answers a narrower question — whether the frame
/// every board carries fits — and a grid can pass that and still be one the
/// layout engine refuses, because a band's essential words have nowhere to go.
/// Setup has to ask the question the seed will ask rather than a proxy for it:
/// they agree at every size the app can produce but one, and on that one a
/// caregiver is offered a grid and profile creation then throws.
///
/// Answered by laying the boards out, because that is the only thing that
/// knows. Memoized because the setup page asks it for every icon size on every
/// rebuild, and the layout is a pure function of the grid.
String? boardSetRefusal({required int rows, required int cols}) {
  final key = (rows, cols);
  if (_refusals.containsKey(key)) return _refusals[key];

  String? refusal;
  try {
    SystemRowPlan.validate(rows: rows, cols: cols);
    pageBands(name: 'home', bands: rootBandsFor(rows), rows: rows, cols: cols);

    // Every preset, because the answer has to hold for whichever birthday the
    // caregiver enters after choosing the grid.
    for (final band in AgeBand.values) {
      for (final category in categoryNames) {
        pageBands(
          name: category,
          bands: categoryBandsFor(category, band),
          rows: rows,
          cols: cols,
          axis: BandAxis.rows,
        );
      }
    }
  } on ArgumentError catch (error) {
    refusal = '${error.message}';
  } on StateError catch (error) {
    refusal = error.message;
  }

  return _refusals[key] = refusal;
}

final _refusals = <(int, int), String?>{};

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
  final anchors = <String, ({int first, int last})>{};
  var remaining = bands;

  while (true) {
    final page = pages.isEmpty
        ? layOutBands(rows: rows, cols: cols, bands: remaining, axis: axis)
        : layOutOnto(
            rows: rows,
            cols: cols,
            bands: remaining,
            anchors: anchors,
            axis: axis,
          );
    pages.add(page);

    // The lines a band is given the first time it appears, and what it owns
    // from then on — not the extent it ended up with, which is narrower on a
    // page it had little to put on and wider on one where it borrowed a free
    // line. The two never disagree about what fits, because a page is built
    // from the last one's overflow and a band's needs only shrink; the
    // distinction is which of them the rule is.
    for (final entry in page.bandLines.entries) {
      anchors.putIfAbsent(entry.key, () => entry.value);
    }

    if (page.overflow.isEmpty) {
      return _withReserves(pages, bands, anchors, rows, cols, axis);
    }

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
    // Shedding takes words in whatever order the grid runs out of room, which
    // is not the order they read. Page two is rebuilt in declaration order so
    // that a band reads the same way on both pages — a run of alternatives
    // whose pairs came apart between pages would be a second thing to learn
    // about one group of words.
    final fills = {for (final b in remaining) b.name: b.fill};
    final caps = {for (final b in remaining) b.name: b.maxLines};
    final declared = {
      for (final b in remaining)
        b.name: {for (var i = 0; i < b.items.length; i++) b.items[i]: i},
    };

    remaining = [
      for (final band in page.overflowBands)
        Band(
          name: band,
          fill: fills[band]!,
          maxLines: caps[band],
          items:
              [
                for (final o in page.overflow)
                  if (o.band == band) o.item,
              ]..sort(
                (a, b) => (declared[band]![a] ?? 0).compareTo(
                  declared[band]![b] ?? 0,
                ),
              ),
        ),
    ];
  }
}

/// Gives a reserve that lost page one a home on a later one.
///
/// A band held open for words nobody has added yet yields to words that exist —
/// that is what makes "because" survive a narrow grid. What it yields is page
/// one, not the reserve: a caregiver's own nouns still have a column of their
/// own, one page press away, rather than being appended wherever there happens
/// to be room years later.
///
/// It has no words, so nothing carries it forward on its own: paging moves
/// items, and a band with none is not moved.
List<BandLayout<SeedWord>> _withReserves(
  List<BandLayout<SeedWord>> pages,
  List<Band<SeedWord>> bands,
  Map<String, ({int first, int last})> anchors,
  int rows,
  int cols,
  BandAxis axis,
) {
  final denied = [
    for (final band in bands)
      if (band.minLines > 0 && !anchors.containsKey(band.name)) band,
  ];
  if (denied.isEmpty) return pages;

  final lineCount = axis == BandAxis.columns ? cols - 1 : rows - 1;
  final out = [...pages];

  for (final band in denied) {
    // Where declaration order puts it, so a reserve on the root board keeps its
    // place in the Fitzgerald sentence order rather than landing in the first
    // gap on the left.
    var after = 0;
    for (final other in bands) {
      if (other.name == band.name) break;
      final anchor = anchors[other.name];
      if (anchor != null && anchor.last + 1 > after) after = anchor.last + 1;
    }

    final free = List<bool>.filled(lineCount, true);
    var at = -1;

    // From page two on, because page one is the one it gave up.
    for (var page = 1; page < out.length; page++) {
      free.fillRange(0, lineCount, true);
      for (final entry in out[page].bandLines.values) {
        for (var l = entry.first; l <= entry.last; l++) {
          free[l] = false;
        }
      }
      if (_runOf(free, band.minLines, after) != null) {
        at = page;
        break;
      }
    }

    // Every page full, so the reserve gets one of its own. Guaranteed means
    // guaranteed: a column a caregiver was promised and cannot find is worse
    // than the page press it costs to reach.
    if (at < 0) {
      free.fillRange(0, lineCount, true);
      at = out.length;
      out.add(
        BandLayout(
          placed: const [],
          overflow: const [],
          bandOrder: const [],
          bandLines: const {},
          axis: axis,
          contentRows: rows - 1,
          contentCols: cols - 1,
        ),
      );
    }

    final run = _runOf(free, band.minLines, after)!;
    final page = out[at];
    final ordered = [...page.bandLines.entries, MapEntry(band.name, run)]
      ..sort((a, b) => a.value.first.compareTo(b.value.first));

    out[at] = BandLayout(
      placed: page.placed,
      overflow: page.overflow,
      bandOrder: page.bandOrder,
      bandLines: {for (final e in ordered) e.key: e.value},
      axis: page.axis,
      contentRows: page.contentRows,
      contentCols: page.contentCols,
    );
    anchors[band.name] = run;
  }

  return out;
}

/// The first run of [need] free lines at or after [from], or the first one
/// anywhere when there is none that late. Null when the page has no room.
({int first, int last})? _runOf(List<bool> free, int need, int from) {
  ({int first, int last})? earlier;

  for (var start = 0; start < free.length; start++) {
    if (!free[start]) continue;
    var end = start;
    while (end + 1 < free.length && free[end + 1]) {
      end += 1;
    }
    if (end - start + 1 >= need) {
      final run = (first: start, last: start + need - 1);
      if (start >= from) return run;
      earlier ??= run;
    }
    start = end;
  }

  return earlier;
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
    final boardId = await materializeBoard(
      db,
      vocabularyId: vocabId,
      name: pageName(name, index),
      kind: rootKind && index == 0 ? BoardKind.root : BoardKind.category,
    );
    boardIds.add(boardId);

    // Which lines each band took, recorded rather than left to be worked out
    // again. The layout is decided once; a second answer computed later could
    // disagree with the board somebody is looking at.
    await (db.update(db.boards)..where((b) => b.id.equals(boardId))).write(
      BoardsCompanion(
        bandMap: Value(BoardRegions.encode(axis, pages[index].bandLines)),
      ),
    );

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
      symbolId: await wordSymbol(db, p.value.label),
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
      symbolId: await frameKeySymbol(db, label),
    );
  }

  // Questions first: they are ordinary vocabulary that happens to be pinned,
  // not controls, so they keep their part-of-speech color and stay editable
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
    await key(
      frame.cycleCol!,
      cycleCategoriesLabel,
      ButtonAction.cycleCategories,
    );
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
      moreWordsLabel,
      ButtonAction.navigate,
      target: pageForward,
    );
  }
}

/// The emoji each fixed key draws, and the symbol row that carries it (§4.69).
///
/// These keys had no picture at all. The talk grid resolves a bare word
/// through [boardSymbolPackIds], which is the curated pack alone, and that pack
/// has no entry for `home`, `back`, `more categories` or a paging key — so they
/// rendered as their words while every ordinary word beside them had a drawing.
///
/// **A chosen symbol rather than a wider fallback.** A button carrying a
/// `symbolId` resolves through `resolveChosen`, which never consults the pack
/// list, so these get exactly the picture named here. Adding the emoji pack to
/// the board's fallback instead would let *every* bare word take an emoji
/// picked by keyword match, unwatched, on a board somebody is talking on.
///
/// A glyph, not an image: the codepoint travels with the board and the platform
/// draws it in its own font. Nothing is ever rasterized — those fonts are
/// proprietary, and no cache, capture or file of one may exist here.
const frameKeyEmoji = {
  'home': (systemEmojiPackId, '1f3e0', 'house'),
  'back': (systemEmojiPackId, '1f519', 'back arrow'),
  // Handpicked from the downloading pack rather than the emoji font. It is the
  // one of these with no emoji worth the name — a cycling arrow says "again",
  // not "more of these" — so it is fetched like any other picture, and until
  // it lands the key shows its words, as any unfetched picture does.
  cycleCategoriesLabel: ('globalsymbols', '53182', 'categories'),
  // Not a key. Here because this is where the fallback's codepoint and name
  // are read from, and a second table would be a second place to get it wrong.
  '': (systemEmojiPackId, '1f504', 'counterclockwise arrows button'),
  moreWordsLabel: (systemEmojiPackId, '27a1-fe0f', 'right arrow'),
  'back a page': (systemEmojiPackId, '2b05-fe0f', 'left arrow'),
};

/// Ordinary words whose picture is chosen rather than matched by keyword.
///
/// The curated pack matches on the word, and for most words that is the right
/// answer. A handful are better served by something the pack has no entry for
/// — `go` wants the green circle everybody already reads as *go*, not a
/// drawing of somebody walking.
///
/// Same mechanism as the fixed keys: a chosen `symbolId` resolves through
/// `resolveChosen`, which never consults the pack list, so this is a decision
/// rather than a match that might drift when the pack changes.
/// Ordinary words whose picture is chosen rather than matched by keyword.
///
/// The curated pack matches on the word, and for most words that is the right
/// answer. A handful are better served by something the pack has no entry for
/// — `go` wants the green circle everybody already reads as *go*, not a
/// drawing of somebody walking.
///
/// Same mechanism as the fixed keys: a chosen `symbolId` resolves through
/// `resolveChosen`, which never consults the pack list, so this is a decision
/// rather than a match that might drift when the pack changes.
const wordEmoji = {'go': ('1f7e2', 'green circle')};

/// The symbol id for a word that was given one, or null for a word that takes
/// whatever the pack has for it.
Future<String?> wordSymbol(WordbridgeDatabase db, String label) async {
  final chosen = wordEmoji[label.toLowerCase().trim()];
  if (chosen == null) return null;

  final (codepoints, name) = chosen;
  final id = 'word-$codepoints';

  await db
      .into(db.symbols)
      .insert(
        SymbolsCompanion.insert(
          id: id,
          packId: const Value(systemEmojiPackId),
          source: SymbolSource.bundled,
          externalId: Value(codepoints),
          label: name,
          license: 'Unicode-3.0',
          attribution: 'Emoji drawn by this device in its own font',
          createdAt: nowMs(),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  return id;
}

/// The symbol id for a fixed key, made on first use, or null for a key that
/// has no emoji of its own — a category key, which is a word and takes the
/// picture its word already has.
Future<String?> frameKeySymbol(WordbridgeDatabase db, String label) async {
  final chosen = frameKeyEmoji[label];
  if (chosen == null) return null;

  final (packId, externalId, name) = chosen;
  // One row per emoji for the whole database, at a derived id: every board
  // carries its own copy of each fixed key, and a row per copy would be one
  // per board per key for nothing.
  final id = 'frame-$externalId';

  await db
      .into(db.symbols)
      .insert(
        SymbolsCompanion.insert(
          id: id,
          packId: Value(packId),
          source: packId == systemEmojiPackId
              ? SymbolSource.bundled
              : SymbolSource.downloaded,
          externalId: Value(externalId),
          label: name,
          license: packId == systemEmojiPackId ? 'Unicode-3.0' : 'CC-BY-SA-4.0',
          attribution: packId == systemEmojiPackId
              ? 'Emoji drawn by this device in its own font'
              : 'Global Symbols',
          createdAt: nowMs(),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  // The second picture, seeded whether or not it is ever drawn. A fallback
  // that is only written when the first one fails would need somebody to fail
  // first, on a device that has no network — which is exactly the device that
  // cannot then write it.
  final second = symbolFallbacks[id];
  if (second != null) {
    final emoji = frameKeyEmoji.values.firstWhere(
      (v) => 'frame-${v.$2}' == second,
    );
    await db
        .into(db.symbols)
        .insert(
          SymbolsCompanion.insert(
            id: second,
            packId: const Value(systemEmojiPackId),
            source: SymbolSource.bundled,
            externalId: Value(emoji.$2),
            label: emoji.$3,
            license: 'Unicode-3.0',
            attribution: 'Emoji drawn by this device in its own font',
            createdAt: nowMs(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  return id;
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
