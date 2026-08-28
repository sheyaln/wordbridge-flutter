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

/// One word waiting for a location.
class BandItem<T> {
  const BandItem(this.value, {this.level = 1, this.essential = false});

  final T value;

  /// Vocabulary level. When the chosen grid cannot hold everything, the
  /// highest levels lose their place first, so a small board still keeps the
  /// core words a user needs on day one.
  final int level;

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
    this.reserveLines = 0,
    this.reserveRank = 100,
    this.shedRank = 100,
    this.startsLine = true,
  });

  final String name;

  /// In the order they should be read. Placement fills a column top to bottom
  /// before starting the next one, so this order is what a user's eye follows.
  final List<BandItem<T>> items;

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
}

/// A word that did not fit, still labelled with where it came from.
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

/// Places [bands] left to right across a grid, filling each column top to
/// bottom.
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

  // A line is what a band claims: a column on one axis, a row on the other.
  // Its length is whatever the grid measures in the other direction.
  final lineLength = axis == BandAxis.columns ? contentRows : contentCols;
  final lineCount = axis == BandAxis.columns ? contentCols : contentRows;

  final kept = {
    for (final b in bands) b.name: [...b.items],
  };
  final held = {for (final b in bands) b.name: b.minLines};
  final overflow = <BandOverflow<T>>[];

  int linesOf(Band<T> b) {
    final needed = (kept[b.name]!.length / lineLength).ceil();
    return needed > held[b.name]! ? needed : held[b.name]!;
  }

  int totalWidth() => bands.fold(0, (sum, b) => sum + linesOf(b));

  // Shed one word at a time rather than a whole column, so what survives is
  // chosen by importance instead of by which band happened to be widest.
  while (totalWidth() > lineCount) {
    if (_shedLeastImportant(bands, kept, overflow)) continue;
    if (_giveUpReserve(bands, held)) continue;

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
    final start = band.startsLine ? line * lineLength : cell;

    for (var i = 0; i < items.length; i++) {
      final at = start + i;
      placed.add((
        row: axis == BandAxis.columns ? at % lineLength : at ~/ lineLength,
        col: axis == BandAxis.columns ? at ~/ lineLength : at % lineLength,
        band: band.name,
        value: items[i].value,
        level: items[i].level,
      ));
    }

    if (band.startsLine) {
      final width = linesOf(band) + extra[band.name]!;
      if (width > 0) {
        bandLines[band.name] = (first: line, last: line + width - 1);
      }
      line += width;
      if (items.isNotEmpty && start + items.length > cell) {
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

/// Moves the single least important remaining word to the overflow list.
///
/// Importance is level first, then how readily the band gives way, then
/// position within the band. Level dominating is what keeps "not" and "want"
/// on a small board while "turn" and "different" move to the overflow page.
///
/// Returns false when nothing is left to shed.
bool _shedLeastImportant<T>(
  List<Band<T>> bands,
  Map<String, List<BandItem<T>>> kept,
  List<BandOverflow<T>> overflow,
) {
  Band<T>? worstBand;
  var worstIndex = -1;
  var worstKey = <int>[];

  for (final band in bands) {
    final items = kept[band.name]!;
    for (var i = 0; i < items.length; i++) {
      if (items[i].essential) continue;

      final key = [items[i].level, band.shedRank, i];
      if (worstIndex < 0 || _greater(key, worstKey)) {
        worstBand = band;
        worstIndex = i;
        worstKey = key;
      }
    }
  }

  if (worstBand == null) return false;

  overflow.add((
    band: worstBand.name,
    item: kept[worstBand.name]!.removeAt(worstIndex),
  ));
  return true;
}

/// Takes one column back from the largest remaining reserve.
///
/// Only reached once every non-essential word has already moved to the
/// overflow list, because a word on the next page is still sayable and a
/// reserve given away is not recoverable.
bool _giveUpReserve<T>(List<Band<T>> bands, Map<String, int> held) {
  String? widest;
  for (final b in bands) {
    if (held[b.name]! < 1) continue;
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
