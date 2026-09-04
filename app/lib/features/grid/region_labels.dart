import 'dart:convert';

import '../../db/seed/band_layout.dart';

/// What a run of locations on a board is for, and what to call it.
///
/// The board's argument is that a column means something — the root board
/// encodes Fitzgerald sentence order, so reading left to right builds a
/// sentence, and a category board groups by word class. None of that is
/// visible to somebody looking at the grid for the first time, and the people
/// looking at it for the first time are the ones who have to teach it.
class BoardRegions {
  const BoardRegions({required this.axis, required this.bands});

  /// Whether a band owns columns or rows.
  final BandAxis axis;

  /// Each band's first and last line, in the order they were laid out.
  final List<({String name, int first, int last})> bands;

  bool get isEmpty => bands.isEmpty;

  static String encode(
    BandAxis axis,
    Map<String, ({int first, int last})> bandLines,
  ) => jsonEncode({
    'axis': axis.name,
    'bands': [
      for (final e in bandLines.entries)
        {'name': e.key, 'first': e.value.first, 'last': e.value.last},
    ],
  });

  /// Null for a board with nothing recorded — one built before the map was
  /// stored, or one a caregiver made by hand, which has no bands to name.
  static BoardRegions? decode(String? json) {
    if (json == null || json.isEmpty) return null;

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final axis = BandAxis.values.firstWhere(
        (a) => a.name == map['axis'],
        orElse: () => BandAxis.columns,
      );

      return BoardRegions(
        axis: axis,
        bands: [
          for (final b in (map['bands'] as List).cast<Map<String, dynamic>>())
            (
              name: b['name'] as String,
              first: b['first'] as int,
              last: b['last'] as int,
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Band names written for somebody who has not read the code.
///
/// Only the ones that need it. Most bands are already named after what they
/// hold — `family`, `eating`, `moving`, `feeling` — and inventing a second
/// name for those would be two things to keep in step for no gain.
const _spokenAs = <String, String>{
  'pronouns': 'who',
  'determiners': 'which one',
  'verbs': 'doing',
  'endings': 'word endings',
  'articles': 'joining words',
  'nouns': 'things',
  'places': 'where',
  'describing': 'yes, no and how it is',
  'introduction': 'how I talk',
  'questions': 'asking',
  'names': 'people you know',
  // Category-board clusters whose one-word name is either jargon or ambiguous.
  // "staples" reads as stationery, "out" as a direction, and "people" is the
  // name of the board it sits on.
  'staples': 'everyday food',
  'out': 'places you go',
  'people': 'words for people',
  'referring': 'who you mean',
};

/// What to write over a band.
String regionLabel(String band) => _spokenAs[band] ?? band;

/// The names offered when a caregiver is asked what a row is for (§4.26).
///
/// Every name the shipped layout uses, so the words on the strip stay the same
/// words whether the row came with the board or somebody added it. Sorted, so
/// a list this long can be read.
List<String> get namesToOffer => ({
  ..._spokenAs.values,
  'drinks',
  'meals',
  'fruit',
  'snacks',
  'body',
  'clothes',
  'feelings',
  'family',
  'school',
  'toys',
  'animals',
  'colors',
  'numbers',
  'time',
  'weather',
  'pets',
}.toList()..sort());

/// One label on the strip: what it says, and which lines it sits over.
typedef RegionLabel = ({String name, int first, int last});

/// Names a caregiver chose, keyed by line index (§4.26).
///
/// Per line rather than per band, because a board somebody made by hand has no
/// bands at all and naming a row is exactly what it needs. Kept in its own
/// column so that what the layout decided and what a person chose can never be
/// confused for one another.
class RegionNames {
  const RegionNames(this.byLine);

  final Map<int, String> byLine;

  static const empty = RegionNames(<int, String>{});

  bool get isEmpty => byLine.isEmpty;

  String? forLine(int line) => byLine[line];

  /// Drops a name, which is how a caregiver falls back to what the layout
  /// called the row.
  RegionNames without(int line) => RegionNames({...byLine}..remove(line));

  RegionNames with_(int line, String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty
        ? without(line)
        : RegionNames({...byLine, line: trimmed});
  }

  static String encode(RegionNames names) =>
      jsonEncode({for (final e in names.byLine.entries) '${e.key}': e.value});

  /// Null or unreadable decodes to nothing named, never to a throw: a board
  /// with a damaged names column still has to draw.
  static RegionNames decode(String? json) {
    if (json == null || json.isEmpty) return empty;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final byLine = <int, String>{};
      for (final entry in map.entries) {
        final line = int.tryParse(entry.key);
        final name = entry.value;
        if (line != null && name is String && name.trim().isNotEmpty) {
          byLine[line] = name;
        }
      }
      return RegionNames(byLine);
    } catch (_) {
      return empty;
    }
  }
}

/// Every line's label as the editor shows it, with an empty slot where there
/// is none.
///
/// A row with no name has to have somewhere to tap or it can never gain one,
/// which is the whole difference between the editor's strip and the talk
/// screen's. The blanks are never drawn in front of the user.
List<RegionLabel> editableRegionLabels({
  required BoardRegions? regions,
  required RegionNames names,
  required int lines,
}) {
  final drawn = regionLabels(regions: regions, names: names);
  final covered = <int>{
    for (final label in drawn)
      for (var line = label.first; line <= label.last; line++) line,
  };

  return [
    ...drawn,
    for (var line = 0; line < lines; line++)
      if (!covered.contains(line)) (name: '', first: line, last: line),
  ]..sort((a, b) => a.first.compareTo(b.first));
}

/// Every label the strip should draw: the layout's, with a caregiver's over
/// the top of them.
///
/// An override on a band's first line renames that band and keeps its extent —
/// the name is what changes, not what it covers. An override on a line no band
/// owns stands on its own, which is the only kind a hand-made board has.
List<RegionLabel> regionLabels({
  required BoardRegions? regions,
  required RegionNames names,
}) {
  final bands = regions?.bands ?? const <RegionLabel>[];
  final covered = <int>{
    for (final band in bands)
      for (var line = band.first; line <= band.last; line++) line,
  };

  return [
    for (final band in bands)
      (
        name: names.forLine(band.first) ?? regionLabel(band.name),
        first: band.first,
        last: band.last,
      ),
    for (final entry in names.byLine.entries)
      if (!covered.contains(entry.key))
        (name: entry.value, first: entry.key, last: entry.key),
  ]..sort((a, b) => a.first.compareTo(b.first));
}

/// What to write over the two frames every board carries.
const pinnedColumnLabel = 'asking';
const systemRowLabel = 'getting around';
