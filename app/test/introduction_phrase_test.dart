import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/grid/region_labels.dart';

/// §4.51. The sentence for somebody who does not know what they are looking at.
///
/// A stranger reads a pause as absence and starts talking to whoever is
/// standing next to the user. This is the one press that answers them, and it
/// belongs on the root board because the situation it is for arrives without
/// warning and from anywhere.
///
/// What makes it affordable is where it ranks, not how short it is. The root
/// board is exactly full at the shipped iPad grid, so a new band costs a line
/// wherever it goes; ranking it last means the line it costs is its own.
void main() {
  const introduction = 'I use this to talk';

  /// Everything the root board declares apart from the new band, which is what
  /// shipped before it existed.
  final without = [
    for (final band in homeBands)
      if (band.name != 'introduction') band,
  ];

  Set<String> pageOne({required int rows, required int cols}) {
    final layout = layOutBands(bands: homeBands, rows: rows, cols: cols);
    return {for (final p in layout.placed) p.value.label};
  }

  Set<String> pagedOff({required int rows, required int cols}) {
    final layout = layOutBands(bands: homeBands, rows: rows, cols: cols);
    return {for (final o in layout.overflow) o.item.value.label};
  }

  /// Where each word sits, keyed by label.
  Map<String, ({int row, int col})> coordinates(
    List<Band<SeedWord>> bands, {
    required int rows,
    required int cols,
  }) {
    final layout = layOutBands(bands: bands, rows: rows, cols: cols);
    return {
      for (final p in layout.placed) p.value.label: (row: p.row, col: p.col),
    };
  }

  group('the phrase itself', () {
    test('is on the root board', () {
      final labels = {
        for (final band in homeBands)
          for (final item in band.items) item.value.label,
      };
      expect(labels, contains(introduction));
    });

    test('is a whole utterance, so nothing may inflect it', () {
      // Coded as a noun it would take the endings, and the board would offer
      // "+'s" after it and say "I use this to talk's".
      final item = homeBands
          .expand((b) => b.items)
          .firstWhere((i) => i.value.label == introduction);

      expect(item.value.pos, PartOfSpeech.social);
      expect(item.value.morphemeKind, isNull);
      expect(item.value.action, ButtonAction.speak);
    });

    test('and says exactly what it reads', () {
      // Label and spoken text are the same string here. A phrase whose button
      // reads one thing and speaks another is a phrase a caregiver cannot
      // check by looking at the board.
      final item = homeBands
          .expand((b) => b.items)
          .firstWhere((i) => i.value.label == introduction);

      expect(item.value.message, introduction);
    });

    test('is level 2, because level 1 is the Universal Core 36 exactly', () {
      // A beginner is arguably the person most likely to be talked over. The
      // answer to that is to raise the level, not to widen quietly what the
      // evidence-based floor contains.
      final item = homeBands
          .expand((b) => b.items)
          .firstWhere((i) => i.value.label == introduction);

      expect(item.level, 2);
    });
  });

  group('what it costs the board', () {
    test('nothing at the shipped iPad grid: it pages instead', () {
      // "Second page material", which is what was asked for and also what the
      // board can afford.
      expect(pageOne(rows: 7, cols: 12), isNot(contains(introduction)));
      expect(pagedOff(rows: 7, cols: 12), contains(introduction));
    });

    test('and not one shipped word moves to make room for it', () {
      // The whole claim. Every location the board had before this band existed
      // is the same location afterwards, at every grid the app offers.
      for (final grid in const [
        (rows: 7, cols: 12),
        (rows: 6, cols: 12),
        (rows: 8, cols: 10),
        (rows: 5, cols: 14),
        (rows: 4, cols: 16),
      ]) {
        final before = coordinates(without, rows: grid.rows, cols: grid.cols);
        final after = coordinates(homeBands, rows: grid.rows, cols: grid.cols);

        for (final entry in before.entries) {
          expect(
            after[entry.key],
            entry.value,
            reason:
                '"${entry.key}" moved at ${grid.rows}x${grid.cols} to make '
                'room for the introduction phrase',
          );
        }
      }
    });

    test('and no shipped word is pushed off page one either', () {
      // Moving nothing is not enough on its own: a word shed to page two has
      // not moved, it has gone, and that is the more expensive loss.
      for (final grid in const [
        (rows: 7, cols: 12),
        (rows: 6, cols: 12),
        (rows: 8, cols: 10),
        (rows: 5, cols: 14),
        (rows: 4, cols: 16),
      ]) {
        final before = coordinates(without, rows: grid.rows, cols: grid.cols);
        final after = coordinates(homeBands, rows: grid.rows, cols: grid.cols);

        expect(
          after.keys.toSet(),
          containsAll(before.keys),
          reason: 'a shipped word left page one at ${grid.rows}x${grid.cols}',
        );
      }
    });

    test('but a grid whose last row ends short draws it there', () {
      // Not a rule that it may never be drawn. Where the board already ends
      // with an empty cell, spending that cell on this costs nobody anything,
      // and a press saved is a press saved.
      expect(pageOne(rows: 6, cols: 12), contains(introduction));
      expect(pagedOff(rows: 6, cols: 12), isNot(contains(introduction)));
    });

    test('and the tail it takes is never a reserve held further up', () {
      // The distinction the whole `tailOnly` band turns on. A reserved line is
      // a location a caregiver has been promised for a word that does not
      // exist yet; the tail of a written line is nobody's. Measured by taking
      // the phrase out and checking the empty cells are the same either way.
      for (final grid in const [
        (rows: 7, cols: 12),
        (rows: 6, cols: 12),
        (rows: 8, cols: 10),
        (rows: 5, cols: 14),
      ]) {
        final before = layOutBands(
          bands: without,
          rows: grid.rows,
          cols: grid.cols,
        );
        final after = layOutBands(
          bands: homeBands,
          rows: grid.rows,
          cols: grid.cols,
        );

        expect(
          after.bandLines,
          before.bandLines,
          reason:
              'a band gained or lost lines at ${grid.rows}x${grid.cols} '
              'because of a band that is supposed to claim none',
        );
      }
    });
  });

  group('on the board the iPad actually builds', () {
    // The engine tests above measure one page in isolation. This is the whole
    // group, through the path the seed uses.
    List<BandLayout<SeedWord>> home() =>
        pageBands(name: 'home', bands: rootBandsFor(7), rows: 7, cols: 12);

    test('it is on page two, one press from the root board', () {
      final pages = home();
      expect(pages.length, greaterThan(1), reason: 'the premise');

      final page = pages.indexWhere(
        (p) => p.placed.any((w) => w.value.label == introduction),
      );
      expect(page, 1);
    });

    test('and page one keeps every region exactly where it was', () {
      // The regions, not just the words: a band that gained or lost a column
      // has moved the boundary a caregiver reads the board by, even if every
      // word inside it happens to have landed in the same cell.
      final withPhrase = home();
      final withoutPhrase = pageBands(
        name: 'home',
        bands: [
          for (final b in rootBandsFor(7))
            if (b.name != 'introduction') b,
        ],
        rows: 7,
        cols: 12,
      );

      expect(withPhrase.first.bandLines, withoutPhrase.first.bandLines);
      expect(
        {
          for (final w in withPhrase.first.placed)
            w.value.label: (w.row, w.col),
        },
        {
          for (final w in withoutPhrase.first.placed)
            w.value.label: (w.row, w.col),
        },
      );
    });
  });

  group('what a caregiver reads over the row', () {
    test('a plain name rather than the band key', () {
      expect(regionLabel('introduction'), 'how I talk');
    });

    test('and it is offered when they name a row themselves', () {
      expect(namesToOffer, contains('how I talk'));
    });
  });
}
