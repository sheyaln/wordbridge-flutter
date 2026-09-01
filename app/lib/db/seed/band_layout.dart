/// Turning an ordered vocabulary into coordinates on a grid of any size.
///
/// The grid is something a caregiver chooses, so the vocabulary is declared as
/// a rule rather than as coordinates: bands of related words, in Fitzgerald
/// order, each claiming a contiguous range of columns wide enough to hold it.
/// One declaration serves every grid size.
///
/// The rule has to be deterministic. Two runs at the same size must produce
/// identical coordinates, or a rebuild would silently move words — the exact
/// failure this project exists to prevent. Everything here is a pure function
/// of (rows, cols, bands); nothing reads a clock, a device, or a database.
library;

/// Which way a board's bands run.
///
/// Columns on the root board, because column position there encodes Fitzgerald
/// sentence order — who, does, what, where — and reading left to right builds a
/// sentence.
///
/// Rows on a category board, where there is no sentence order to encode. Words
/// are grouped by class instead, and arranging by word class measurably speeds
/// message building (Thistle & Wilkinson 2017) and cuts fixations on
/// irrelevant symbols (Wilkinson, Gilmore & Qian 2022). A row also survives
/// row-column scanning: the first switch press picks a row, so a row that is
/// one word class narrows the choice, while a column-grouped row narrows
/// nothing.
enum BandAxis { columns, rows }

/// Which direction a band's own words run inside the lines it claims.
///
/// A line is a column on [BandAxis.columns] and a row on [BandAxis.rows]. The
/// band's region is the same either way; only the order within it differs.
enum BandFill {
  /// Along one line before starting the next. Consecutive words share a line,
  /// which is what a paradigm wants — the root board's first pronoun column is
  /// the subject set, and filling the other way would interleave it with the
  /// column beside it.
  alongLine,

  /// Across the band's lines before moving along them. Consecutive words end
  /// up side by side, which is what a run of alternatives wants: each is one
  /// cell from the last, so the pair is learned as a pair.
  ///
  /// Only for a band that starts its own line. A band filled this way ends in
  /// a ragged edge rather than one open tail, so there is nothing for a
  /// following [Band.startsLine] band to fill.
  acrossBand,
}

/// One word waiting for a location.
class BandItem<T> {
  const BandItem(
    this.value, {
    this.level = 1,
    this.essential = false,
    this.pageRankOverride,
  });

  final T value;

  /// Vocabulary level. Decides what is **drawn**, and nothing else: a word
  /// above the profile's level holds its location without being rendered, and
  /// raising the level reveals it exactly where it has always been.
  final int level;

  /// Set only where [pageRank] must not follow [level].
  final int? pageRankOverride;

  /// What gives way first when the chosen grid cannot hold everything.
  ///
  /// Separate from [level] because the two questions are separate. "Show this
  /// to a beginner" and "this is what a narrow grid can afford to put on a
  /// second page" agree most of the time, which is why this follows level by
  /// default — but where they disagree, tying them together forces a word to
  /// be hidden from someone who could use it in order to keep it off a page,
  /// or onto page one at the cost of something that earns the room.
  ///
  /// The default leaves gaps on purpose: level *n* ranks at *10n*, so a word
  /// can be placed between two levels without renumbering anything.
  int get pageRank => pageRankOverride ?? level * 10;

  /// Never moved to an overflow board, whatever the grid size.
  ///
  /// For the handful of words where an extra tap is not an acceptable cost:
  /// refusal, and anything else a user might need to say urgently. A grid too
  /// small to hold these is refused outright rather than quietly shipped
  /// without them.
  final bool essential;
}

/// A run of related words that occupies a contiguous range of columns.
class Band<T> {
  const Band({
    required this.name,
    required this.items,
    this.minLines = 0,
    this.maxLines,
    this.reserveLines = 0,
    this.reserveRank = 100,
    this.shedRank = 100,
    this.startsLine = true,
    this.tailOnly = false,
    this.fill = BandFill.alongLine,
  });

  final String name;

  /// In the order they should be read, which [fill] turns into a direction.
  final List<BandItem<T>> items;

  /// Which way [items] run inside the band's region.
  final BandFill fill;

  /// Lines held open whether or not there are words to fill them, and the last
  /// thing to give way when the grid runs short.
  ///
  /// A line is a column on [BandAxis.columns] and a row on [BandAxis.rows].
  ///
  /// This is how personal vocabulary gets a permanent home from day one rather
  /// than being appended wherever there happens to be room later. It outranks
  /// shipped words deliberately: a word pushed onto the next page is still
  /// reachable, while a reserve given away is gone.
  ///
  /// Worth knowing that a reserved row costs a whole row of cells while a
  /// reserved column costs a whole column — at 7x12 that is 11 against 6 — so
  /// a guaranteed reserve is nearly twice as expensive on the row axis.
  final int minLines;

  /// The widest this band may ever be, however much room the grid has.
  ///
  /// For a band whose arrangement, not just its order, carries meaning. The
  /// verbs are read as rows of three — go beside stop, get beside take, open
  /// beside close — and [BandFill.acrossBand] produces those rows only while
  /// the band is exactly three lines wide. A fourth line is not extra room for
  /// the same band; it is a different band with the same words in it.
  ///
  /// Words past the cap page like any others, which is the cheaper loss: a word
  /// on the next page is one press away, while a pair pulled apart is two
  /// locations to learn where there was one.
  final int? maxLines;

  /// Extra empty lines this band would like if the grid turns out to have room
  /// to spare. Unlike [minLines], never at the expense of a word.
  final int reserveLines;

  /// Order in which spare lines are handed out. Lower goes first.
  final int reserveRank;

  /// Order in which a band gives way when the grid is too small. Lower holds
  /// on longest.
  final int shedRank;

  /// Whether this band starts a fresh line, or fills the empty tail the band
  /// before it left.
  ///
  /// False for the bands an age preset appends. They land in cells that would
  /// otherwise stay empty, so they cost no shipped word its location — which
  /// is the whole reason extras are appended rather than inserted.
  final bool startsLine;

  /// Claims no line at all: fills whatever tail is left over and pages the
  /// rest.
  ///
  /// [startsLine] alone is not enough for that. A band that fills a tail is
  /// still counted at a line's worth when the grid is measured, so appending
  /// even one word costs a line somewhere — and what it costs is whatever the
  /// grid had spare, which is a reserve some band was holding open. A reserve
  /// is exactly what must not be spent on a shipped word (§4.51).
  ///
  /// So this is the band for vocabulary that is genuinely worth having and
  /// genuinely not worth a column: it is free where the last line ends short,
  /// and it pages where the line ends flush. Nothing else on the board can
  /// move because of it, at any grid size, which is the whole reason it exists.
  ///
  /// Only the tail of the last written line, never a line held open further up.
  /// A band paging its words is a movement; a band spending somebody's reserve
  /// is a location that never comes back.
  ///
  /// Governs the first page only. [layOutOnto] places one like any other band,
  /// because a later page holds words that have already paid to be there and
  /// has no reserve to defend — and a band that could claim nothing anywhere
  /// would page for ever.
  final bool tailOnly;
}

/// A word that did not fit, still labeled with where it came from.
///
/// The band name travels with it so a band split across two pages keeps its
/// identity — a hidden band must not become half visible just because it
/// overflowed.
typedef BandOverflow<T> = ({String band, BandItem<T> item});

typedef BandPlacement<T> = ({
  int row,
  int col,
  String band,
  T value,
  int level,
});

class BandLayout<T> {
  const BandLayout({
    required this.placed,
    required this.overflow,
    required this.bandOrder,
    required this.bandLines,
    required this.axis,
    required this.contentRows,
    required this.contentCols,
  });

  final List<BandPlacement<T>> placed;

  /// Words the chosen grid had no room for, still carrying their levels so the
  /// next page can order them the same way. They are not discarded — the
  /// caller puts them on an overflow board, because a word that exists in the
  /// vocabulary and cannot be said is a worse outcome than an extra tap.
  final List<BandOverflow<T>> overflow;

  /// Band names in the order they were declared.
  final List<String> bandOrder;

  /// The lines each band owns, including the ones it holds open and never
  /// filled. A word a caregiver later adds to a reserved line belongs to the
  /// band that reserved it, which is how a rebuild at another grid size knows
  /// where to keep it.
  final Map<String, ({int first, int last})> bandLines;

  final BandAxis axis;

  /// Which band owns a location, or null for one no band claimed.
  String? bandAt({required int row, required int col}) {
    final line = axis == BandAxis.columns ? col : row;
    for (final entry in bandLines.entries) {
      if (line >= entry.value.first && line <= entry.value.last) {
        return entry.key;
      }
    }
    return null;
  }

  final int contentRows;
  final int contentCols;

  /// Which bands overflowed, in declaration order, so the next page lays them
  /// out the same way this one would have.
  List<String> get overflowBands {
    final spilled = {for (final o in overflow) o.band};
    return [
      for (final name in bandOrder)
        if (spilled.contains(name)) name,
    ];
  }
}

/// Places [bands] one after another across a grid, each in a contiguous run of
/// lines and each filled in the direction its [Band.fill] asks for.
///
/// [systemRows] rows are held at the bottom and [pinnedCols] columns at the
/// right; neither is available to a band, because both carry keys that must be
/// at identical coordinates on every board.
BandLayout<T> layOutBands<T>({
  required int rows,
  required int cols,
  required List<Band<T>> bands,
  BandAxis axis = BandAxis.columns,
  int systemRows = 1,
  int pinnedCols = 1,
}) {
  final contentRows = rows - systemRows;
  final contentCols = cols - pinnedCols;

  if (contentRows < 1 || contentCols < 1) {
    throw ArgumentError(
      'A ${rows}x$cols grid leaves no room for vocabulary once the system row '
      'and pinned column are reserved.',
    );
  }

  // Bands are keyed by name throughout, so two bands sharing one would merge
  // and a whole band's words would vanish without a word of complaint. The
  // names a caller passes include the ones an age preset appends, which is
  // where a collision is easiest to introduce.
  assert(
    {for (final b in bands) b.name}.length == bands.length,
    'two bands share a name: ${bands.map((b) => b.name).toList()}',
  );

  assert(
    bands.every((b) => b.startsLine || b.fill == BandFill.alongLine),
    'a band filled across its lines needs a region of its own to wrap inside',
  );

  assert(
    bands.every(
      (b) =>
          !b.tailOnly ||
          (!b.startsLine && b.minLines == 0 && b.reserveLines == 0),
    ),
    'a band that only fills a tail claims no line, so it can neither start one '
    'nor hold one open',
  );

  // A line is what a band claims: a column on one axis, a row on the other.
  // Its length is whatever the grid measures in the other direction.
  final lineLength = axis == BandAxis.columns ? contentRows : contentCols;
  final lineCount = axis == BandAxis.columns ? contentCols : contentRows;

  final kept = {
    for (final b in bands) b.name: [...b.items],
  };
  final held = {for (final b in bands) b.name: b.minLines};
  final overflow = <BandOverflow<T>>[];

  assert(
    bands.every((b) => b.maxLines == null || b.minLines <= b.maxLines!),
    'a band cannot be guaranteed more lines than it is allowed',
  );

  // A capped band gives up its surplus before the grid is measured at all. The
  // cap is not about room — the words past it would break the arrangement even
  // on a board with columns to spare.
  for (final band in bands) {
    final cap = band.maxLines;
    if (cap == null) continue;
    final drop = kept[band.name]!.length - cap * lineLength;
    if (drop > 0) _shedFrom(band, kept[band.name]!, overflow, drop);
  }

  int linesOf(Band<T> b) {
    if (b.tailOnly) return 0;
    final needed = (kept[b.name]!.length / lineLength).ceil();
    return needed > held[b.name]! ? needed : held[b.name]!;
  }

  int totalWidth() => bands.fold(0, (sum, b) => sum + linesOf(b));

  // A line at a time, and all of it from one band. A band owns whole lines, so
  // a word taken from a band with room to spare costs that word its place and
  // buys the grid nothing.
  //
  // Empty lines go first: words that exist beat space held for words that do
  // not. A line held open is worth something only while there is room for it,
  // and a reserve kept at the price of "because" is a reserve bought with the
  // words it was meant to sit beside.
  while (totalWidth() > lineCount) {
    if (_giveUpReserve(bands, kept, held, lineLength)) continue;
    if (_shedALine(bands, kept, held, overflow, lineLength)) continue;

    throw StateError(
      'A ${rows}x$cols grid cannot hold the words that must always be '
      'reachable. Offer a smaller icon size or a different orientation '
      'rather than shipping a board without them.',
    );
  }

  var surplus = lineCount - totalWidth();
  final extra = <String, int>{for (final b in bands) b.name: 0};

  final byReserve = [...bands]
    ..sort((a, b) => a.reserveRank.compareTo(b.reserveRank));
  for (final b in byReserve) {
    if (surplus <= 0) break;
    final take = b.reserveLines < surplus ? b.reserveLines : surplus;
    extra[b.name] = take;
    surplus -= take;
  }

  final placed = <BandPlacement<T>>[];
  final bandLines = <String, ({int first, int last})>{};

  // Two cursors. The first is the next free line; the second is the next free
  // cell, which a band that does not start its own line begins from instead.
  var line = 0;
  var cell = 0;

  for (final band in bands) {
    final items = kept[band.name]!;

    if (band.tailOnly) {
      // Only what is left of the line last written into. Measured from the
      // cell cursor rather than from the line cursor, because the line cursor
      // has already stepped past any line a band is holding open, and those
      // cells belong to whoever reserved them.
      final used = cell % lineLength;
      final room = used == 0 ? 0 : lineLength - used;

      // Least important first, and what survives keeps its declared order —
      // the same rule every other band is shed by, so a band that half fits is
      // not a different band from one that fits whole.
      final drop = items.length - room;
      if (drop > 0) _shedFrom(band, items, overflow, drop);

      for (var i = 0; i < items.length; i++) {
        placed.add(_placement(cell + i, lineLength, axis, band.name, items[i]));
      }

      cell += items.length;
      continue;
    }

    final start = band.startsLine ? line * lineLength : cell;

    // Words wrap across the lines the band needs, never the ones it merely
    // holds open, so a reserve stays a contiguous block of empty cells.
    final wrap = linesOf(band);
    final across = band.fill == BandFill.acrossBand;

    for (var i = 0; i < items.length; i++) {
      final at = across
          ? (line + i % wrap) * lineLength + i ~/ wrap
          : start + i;
      placed.add(_placement(at, lineLength, axis, band.name, items[i]));
    }

    if (band.startsLine) {
      final width = wrap + extra[band.name]!;
      if (width > 0) {
        bandLines[band.name] = (first: line, last: line + width - 1);
      }
      line += width;
      if (across) {
        // A cross-filled block leaves a ragged edge rather than one open run,
        // so a band that fills a tail starts past it instead.
        cell = line * lineLength;
      } else if (items.isNotEmpty && start + items.length > cell) {
        cell = start + items.length;
      }
    } else if (items.isNotEmpty) {
      cell = start + items.length;
      // Filling past the last claimed line pushes the line cursor on, so the
      // band after this one does not land on top of these words.
      final reached = (cell + lineLength - 1) ~/ lineLength;
      if (reached > line) line = reached;
    }
  }

  assert(line <= lineCount, 'bands ran past the grid: $line > $lineCount');

  return BandLayout(
    placed: placed,
    overflow: overflow,
    bandOrder: [for (final b in bands) b.name],
    bandLines: bandLines,
    axis: axis,
    contentRows: contentRows,
    contentCols: contentCols,
  );
}

/// Moves exactly enough words off one band for it to need one line fewer.
///
/// A band claims whole lines, so a word taken from a band that is not about to
/// cross a line boundary buys nothing: the grid is no narrower and the word is
/// on page two. Shedding the globally least important word repeatedly does
/// exactly that — it empties the bands with the most slack first, because
/// their words are the ones ranked lowest, and takes fifteen words off a full
/// board to free one column.
///
/// So the choice is made a line at a time. Every band is asked what it would
/// cost to give up a line; the band whose most important sacrifice is the
/// least important overall gives it up, and only that band loses anything.
///
/// Importance is [BandItem.pageRank] first, then how readily the band gives
/// way, then position within the band.
///
/// Returns false when no band can give up a line.
bool _shedALine<T>(
  List<Band<T>> bands,
  Map<String, List<BandItem<T>>> kept,
  Map<String, int> held,
  List<BandOverflow<T>> overflow,
  int lineLength,
) {
  Band<T>? chosen;
  List<int>? chosenIndices;
  List<int>? chosenKey;

  for (final band in bands) {
    // Claims no line, so it has none to give up and taking its words would
    // narrow nothing. Its overflow is decided at placement, against the tail
    // that is actually left.
    if (band.tailOnly) continue;

    final items = kept[band.name]!;
    final lines = (items.length / lineLength).ceil();

    // Already down to the lines it is guaranteed, so it has none to give.
    if (lines <= held[band.name]!) continue;

    final drop = items.length - (lines - 1) * lineLength;
    if (drop <= 0) continue;

    final candidates = _disposable(band, items);
    if (candidates.length < drop) continue;

    final taken = candidates.take(drop).toList();
    final indices = [for (final k in taken) k[2]]
      ..sort((a, b) => b.compareTo(a));

    // What this line costs is set by the most important word in it: a band
    // does not get to hide a core word behind five it was happy to lose.
    final key = taken.reduce((a, b) => _greater(a, b) ? b : a);

    if (chosenKey == null || _greater(key, chosenKey)) {
      chosen = band;
      chosenIndices = indices;
      chosenKey = key;
    }
  }

  if (chosen == null) return false;

  // Descending, so each removal leaves the indices below it valid.
  for (final i in chosenIndices!) {
    overflow.add((band: chosen.name, item: kept[chosen.name]!.removeAt(i)));
  }
  return true;
}

/// Lays a later page of a group onto the lines its bands already own.
///
/// Page one decides where a region is and every page after it agrees. A region
/// that moved when the user paged would be a second thing to learn about one
/// group of words, and under row-column scanning it would make the first press
/// — the one that narrows to a region — worth nothing.
///
/// [anchors] is what the pages before this one assigned. A band shed entirely
/// off page one owns no lines there, so it is given lines on the first page it
/// appears on, out of the ones whose owner has nothing to put here; the caller
/// keeps that assignment and hands it back for every page after.
///
/// A band that has run out of its own lines grows into adjacent ones nothing
/// else needs on this page before it pages anything. A page is a movement every
/// time the word is said; an unclaimed column beside a band is not. What that
/// costs is that a band's *extent* can differ page to page — its start, which
/// is what a person reaches for, does not.
BandLayout<T> layOutOnto<T>({
  required int rows,
  required int cols,
  required List<Band<T>> bands,
  required Map<String, ({int first, int last})> anchors,
  BandAxis axis = BandAxis.columns,
  int systemRows = 1,
  int pinnedCols = 1,
}) {
  final contentRows = rows - systemRows;
  final contentCols = cols - pinnedCols;
  final lineLength = axis == BandAxis.columns ? contentRows : contentCols;
  final lineCount = axis == BandAxis.columns ? contentCols : contentRows;

  final kept = {
    for (final b in bands) b.name: [...b.items],
  };
  final overflow = <BandOverflow<T>>[];

  for (final band in bands) {
    final cap = band.maxLines;
    if (cap == null) continue;
    final drop = kept[band.name]!.length - cap * lineLength;
    if (drop > 0) _shedFrom(band, kept[band.name]!, overflow, drop);
  }

  // A band absent from this page is absent from every page after it — a page
  // is built from the overflow of the one before it, and overflow only shrinks.
  // So
  // its lines are free here for good, and handing them to a band that has none
  // cannot collide with an owner returning later.
  final free = List<bool>.filled(lineCount, true);
  final lines = <String, ({int first, int last})>{};

  // A band takes its own lines from the start of its run, and only as many as
  // its words here need. The rest of the run is nobody's on this page: holding
  // it would be holding empty space at the price of a band that has none, which
  // is the ordering page one already refuses.
  for (final band in bands) {
    final anchor = anchors[band.name];
    if (anchor == null) continue;

    final need = (kept[band.name]!.length / lineLength).ceil();
    final width = anchor.last - anchor.first + 1;
    final take = need < width ? need : width;
    lines[band.name] = (first: anchor.first, last: anchor.first + take - 1);
    for (var l = anchor.first; l < anchor.first + take; l++) {
      free[l] = false;
    }
  }

  // Bands with no lines yet are given some, as near as the free space allows to
  // where declaration order puts them. On the root board that order is the
  // Fitzgerald sentence order, so a band dropped in at the far end would read
  // as a different sentence.
  for (final band in bands) {
    if (lines.containsKey(band.name)) continue;

    var after = 0;
    for (final other in bands) {
      if (other.name == band.name) break;
      final anchor = anchors[other.name];
      if (anchor != null && anchor.last + 1 > after) after = anchor.last + 1;
    }

    final need = (kept[band.name]!.length / lineLength).ceil();
    final run = _freeRun(free, need, after);
    if (run == null) continue;

    lines[band.name] = run;
    for (var l = run.first; l <= run.last; l++) {
      free[l] = false;
    }
  }

  // Only now, once every band has somewhere to be, does a band that wants more
  // room take what is going spare.
  for (final band in bands) {
    final own = lines[band.name];
    if (own == null) continue;

    // No cap to check here: a capped band has already given up everything past
    // it, so what is left never asks for more lines than it may have.
    var last = own.last;
    final need = (kept[band.name]!.length / lineLength).ceil();
    while (last - own.first + 1 < need &&
        last + 1 < lineCount &&
        free[last + 1]) {
      last += 1;
      free[last] = false;
    }
    lines[band.name] = (first: own.first, last: last);
  }

  final placed = <BandPlacement<T>>[];

  for (final band in bands) {
    final own = lines[band.name];
    final items = kept[band.name]!;

    if (own == null) {
      for (final item in items) {
        overflow.add((band: band.name, item: item));
      }
      continue;
    }

    final width = own.last - own.first + 1;
    final drop = items.length - width * lineLength;
    if (drop > 0) _shedFrom(band, items, overflow, drop);

    final across = band.fill == BandFill.acrossBand;
    for (var i = 0; i < items.length; i++) {
      final at = across
          ? (own.first + i % width) * lineLength + i ~/ width
          : own.first * lineLength + i;
      placed.add(_placement(at, lineLength, axis, band.name, items[i]));
    }
  }

  // Left to right, which is not declaration order once a band has been given
  // lines somewhere else. The map is what names the regions on the board, and
  // a caregiver reading it should read it the way the board is drawn.
  final ordered = lines.entries.toList()
    ..sort((a, b) => a.value.first.compareTo(b.value.first));

  return BandLayout(
    placed: placed,
    overflow: overflow,
    bandOrder: [for (final b in bands) b.name],
    bandLines: {for (final e in ordered) e.key: e.value},
    axis: axis,
    contentRows: contentRows,
    contentCols: contentCols,
  );
}

/// The first run of [need] free lines at or after [from], or the longest free
/// run anywhere if nothing that wide is left.
({int first, int last})? _freeRun(List<bool> free, int need, int from) {
  ({int first, int last})? longest;

  for (var start = 0; start < free.length; start++) {
    if (!free[start]) continue;
    var end = start;
    while (end + 1 < free.length && free[end + 1]) {
      end += 1;
    }

    if (start >= from && end - start + 1 >= need) {
      return (first: start, last: start + need - 1);
    }
    if (longest == null || end - start > longest.last - longest.first) {
      longest = (first: start, last: end);
    }
    start = end;
  }

  if (longest == null) return null;
  final width = longest.last - longest.first + 1;
  return width > need
      ? (first: longest.first, last: longest.first + need - 1)
      : longest;
}

BandPlacement<T> _placement<T>(
  int at,
  int lineLength,
  BandAxis axis,
  String band,
  BandItem<T> item,
) => (
  row: axis == BandAxis.columns ? at % lineLength : at ~/ lineLength,
  col: axis == BandAxis.columns ? at ~/ lineLength : at % lineLength,
  band: band,
  value: item.value,
  level: item.level,
);

/// A band's words ordered most disposable first, as `[pageRank, shedRank,
/// index]` keys.
///
/// The least important words in the band, not the last ones in it. A band holds
/// its words in the order they read, so its final line is as likely to be core
/// vocabulary as anything else — shedding by position would lose "good" while
/// keeping a word nobody has needed yet. What survives re-packs in declared
/// order either way.
List<List<int>> _disposable<T>(Band<T> band, List<BandItem<T>> items) => [
  for (var i = 0; i < items.length; i++)
    if (!items[i].essential) [items[i].pageRank, band.shedRank, i],
]..sort((a, b) => _greater(a, b) ? -1 : 1);

/// Moves [drop] words off one band, least important first.
void _shedFrom<T>(
  Band<T> band,
  List<BandItem<T>> items,
  List<BandOverflow<T>> overflow,
  int drop,
) {
  final candidates = _disposable(band, items);
  if (candidates.length < drop) {
    throw StateError(
      'The "${band.name}" band holds $drop words more than it may show, and '
      'too many of them must always be reachable to give any up.',
    );
  }

  // Descending, so each removal leaves the indices below it valid.
  final indices = [for (final k in candidates.take(drop)) k[2]]
    ..sort((a, b) => b.compareTo(a));
  for (final i in indices) {
    overflow.add((band: band.name, item: items.removeAt(i)));
  }
}

/// Takes one line back from the largest reserve still holding an empty one.
///
/// Tried before any word is shed. A reserve is space held for words nobody has
/// added yet, and the words already in the vocabulary are not what it should be
/// paid for. What it costs the reserve is a page press, not the line: the
/// caller hands a denied reserve to the first page with room for it.
///
/// Only lines a band is holding beyond what its words need count. Decrementing
/// past that frees nothing, because the band's own words still ask for the
/// line — it would spin without narrowing the board.
bool _giveUpReserve<T>(
  List<Band<T>> bands,
  Map<String, List<BandItem<T>>> kept,
  Map<String, int> held,
  int lineLength,
) {
  String? widest;
  for (final b in bands) {
    final needed = (kept[b.name]!.length / lineLength).ceil();
    if (held[b.name]! <= needed) continue;
    if (widest == null || held[b.name]! > held[widest]!) widest = b.name;
  }

  if (widest == null) return false;

  held[widest] = held[widest]! - 1;
  return true;
}

bool _greater(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Where the keys that appear on every board go, for a grid of any size.
///
/// The bottom row and the rightmost column are the two fixed frames of the
/// whole system: reaching home, or asking "where", is one unchanging movement
/// no matter which board is open.
class SystemRowPlan {
  const SystemRowPlan._({
    required this.row,
    required this.homeCol,
    required this.backCol,
    required this.categoryCols,
    required this.cycleCol,
    required this.pageBackCol,
    required this.pageForwardCol,
  });

  /// The smallest grid this can be laid out on: home, back, the separating
  /// gap, one category slot, and the two paging keys.
  static const minCols = 6;
  static const minRows = 4;

  /// Refuses a grid that cannot carry the keys every board needs.
  ///
  /// Called before anything is laid out so a caregiver gets the actionable
  /// message — this icon size does not fit this device — rather than a
  /// complaint about vocabulary that is really a complaint about the grid.
  static void validate({required int rows, required int cols}) {
    if (cols < minCols || rows < minRows) {
      throw ArgumentError(
        'A ${rows}x$cols grid is too small for the keys every board needs. '
        'Minimum is ${minRows}x$minCols.',
      );
    }
  }

  factory SystemRowPlan.forGrid({
    required int rows,
    required int cols,
    required int categories,
  }) {
    validate(rows: rows, cols: cols);

    // Column 2 is normally left empty. Home and back undo what the user just
    // did; the category keys go somewhere new. Shoulder to shoulder, an
    // imprecise reach for one lands on the other.
    //
    // A grid narrow enough that the gap would leave room for the cycle key and
    // no category at all gives the gap up. Its buttons are large — that is why
    // there are so few — so the mis-reach it guards against is the less likely
    // problem, and a system row with no category key on it is the worse one.
    final lastCategory = cols - 3;
    var firstCategory = 3;
    if (lastCategory - firstCategory + 1 < 2 && categories > 1) {
      firstCategory = 2;
    }
    final slots = lastCategory - firstCategory + 1;

    // Categories that do not fit are reached by cycling these same keys rather
    // than by opening a board of categories. A board would put every category
    // two movements away instead of one; cycling keeps them all at one
    // movement plus however many presses of the cycle key.
    final cycles = categories > slots;
    final shown = cycles ? slots - 1 : categories;

    return SystemRowPlan._(
      row: rows - 1,
      homeCol: 0,
      backCol: 1,
      categoryCols: [for (var i = 0; i < shown; i++) firstCategory + i],
      cycleCol: cycles ? firstCategory + shown : null,
      pageBackCol: cols - 2,
      pageForwardCol: cols - 1,
    );
  }

  final int row;
  final int homeCol;
  final int backCol;

  /// One per category shown at a time, left to right. When there are more
  /// categories than slots, these keys are a window onto the full list and
  /// [cycleCol] moves the window.
  final List<int> categoryCols;

  /// Where the key that moves the window goes, or null when every category
  /// already has a permanent slot.
  final int? cycleCol;

  final int pageBackCol;
  final int pageForwardCol;
}
