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
  'questions': 'asking',
  'names': 'people you know',
};

/// What to write over a band.
String regionLabel(String band) => _spokenAs[band] ?? band;

/// What to write over the two frames every board carries.
const pinnedColumnLabel = 'asking';
const systemRowLabel = 'getting around';
