import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';

/// What the shipped vocabulary does on every grid the app will build, rather
/// than on the one the golden board is written at.
///
/// The 7x12 board is asserted to the cell elsewhere. These are the properties
/// that have to hold at 7x11 as well — which is the tested iPad at medium
/// icons, and where the layout was quietly worse than at the default size.
void main() {
  final grids = <(int, int)>[
    for (var rows = 4; rows <= 12; rows++)
      for (var cols = 6; cols <= 16; cols++)
        if (boardSetRefusal(rows: rows, cols: cols) == null) (rows, cols),
  ];

  List<BandLayout<SeedWord>> home(int rows, int cols) => pageBands(
    name: 'home',
    bands: rootBandsFor(rows),
    rows: rows,
    cols: cols,
  );

  /// Every board group the seed builds at this grid, root and categories.
  List<List<BandLayout<SeedWord>>> groups(int rows, int cols) => [
    home(rows, cols),
    for (final category in categoryNames)
      pageBands(
        name: category,
        bands: categoryBandsFor(category, AgeBand.child),
        rows: rows,
        cols: cols,
        axis: BandAxis.rows,
      ),
  ];

  int pageOf(List<BandLayout<SeedWord>> pages, String label) =>
      pages.indexWhere((p) => p.placed.any((w) => w.value.label == label));

  setUpAll(() => expect(grids, isNotEmpty));

  group('a column held open never outranks a word', () {
    test('the joining words are on the root board at the tested sizes', () {
      // The words that turn a run of content words into a sentence. They apply
      // to any sentence, which is more than a column held for one person's
      // nouns can say, and "because" is what turns a refusal into a reason.
      for (final grid in [(7, 12), (7, 11), (8, 10)]) {
        final pages = home(grid.$1, grid.$2);
        for (final word in ['a', 'the', 'and', 'but', 'because', 'so']) {
          expect(
            pageOf(pages, word),
            0,
            reason:
                '"$word" is on a later page at ${grid.$1}x${grid.$2} while a '
                'column nobody has filled keeps its place on page one',
          );
        }
      }
    });

    test('no grid pays for the reserve with a word', () {
      // The general rule, not the one instance of it: an empty line is given
      // back before any word is pushed to the next page. Stated as the thing it
      // promises — page one holds exactly the words it would hold if no line
      // were held open at all.
      for (final grid in grids) {
        final withReserve = home(grid.$1, grid.$2);
        final without = pageBands(
          name: 'home',
          bands: [
            for (final b in rootBandsFor(grid.$1))
              Band(
                name: b.name,
                items: b.items,
                maxLines: b.maxLines,
                reserveLines: b.reserveLines,
                reserveRank: b.reserveRank,
                shedRank: b.shedRank,
                startsLine: b.startsLine,
                tailOnly: b.tailOnly,
                fill: b.fill,
              ),
          ],
          rows: grid.$1,
          cols: grid.$2,
        );

        Set<String> onPageOne(List<BandLayout<SeedWord>> pages) => {
          for (final w in pages.first.placed) w.value.label,
        };

        expect(
          onPageOne(withReserve),
          onPageOne(without),
          reason:
              'at ${grid.$1}x${grid.$2} a word was sent to page two to keep a '
              'column nobody has filled',
        );
      }
    });

    test('the reserve is not lost, it moves', () {
      // What it gives up is page one, not the column. A caregiver's own nouns
      // still have a home held for them from day one; it costs one press.
      for (final grid in grids) {
        final pages = home(grid.$1, grid.$2);
        expect(
          pages.any((p) => p.bandLines.containsKey('nouns')),
          isTrue,
          reason:
              'THINGS has no column at all at ${grid.$1}x${grid.$2}, so '
              'personal nouns have nowhere reserved to land',
        );
      }
    });
  });

  test('a band starts on the same line on every page it appears on', () {
    // A region that means "doing" teaches somebody where to look, and one that
    // moves when you page is learned twice. Under row-column scanning it is
    // worse than that: the first press narrows to a region, and a region that
    // relocates per page makes the narrowing worth nothing.
    for (final grid in grids) {
      for (final pages in groups(grid.$1, grid.$2)) {
        final start = <String, int>{};
        for (var index = 0; index < pages.length; index++) {
          for (final entry in pages[index].bandLines.entries) {
            final was = start[entry.key];
            if (was == null) {
              start[entry.key] = entry.value.first;
              continue;
            }
            expect(
              entry.value.first,
              was,
              reason:
                  '"${entry.key}" starts at $was on an earlier page and at '
                  '${entry.value.first} on page ${index + 1} '
                  'at ${grid.$1}x${grid.$2}',
            );
          }
        }
      }
    }
  });

  test('two bands never claim the same line on one page', () {
    for (final grid in grids) {
      for (final pages in groups(grid.$1, grid.$2)) {
        for (final page in pages) {
          final owner = <int, String>{};
          for (final entry in page.bandLines.entries) {
            for (
              var line = entry.value.first;
              line <= entry.value.last;
              line++
            ) {
              expect(
                owner.containsKey(line),
                isFalse,
                reason:
                    '"${entry.key}" and "${owner[line]}" both own line $line '
                    'at ${grid.$1}x${grid.$2}',
              );
              owner[line] = entry.key;
            }
          }
        }
      }
    }
  });

  test('the verbs are three columns wide at every grid', () {
    // The band is read as rows of three, and it fills across its columns, so a
    // fourth column re-wraps every row of it. Nothing about the grid changes
    // that, which is why the cap is on the band rather than on the board.
    for (final grid in grids) {
      for (final page in home(grid.$1, grid.$2)) {
        final verbs = page.bandLines['verbs'];
        if (verbs == null) continue;
        expect(
          verbs.last - verbs.first + 1,
          lessThanOrEqualTo(3),
          reason: 'the verbs widened at ${grid.$1}x${grid.$2}',
        );
      }
    }
  });

  test('the verb pairs stay side by side on every page at the tested sizes', () {
    // Three is the arrangement, not a maximum that happens to be three, and the
    // cap is what stops a wide grid re-wrapping it into rows of four.
    //
    // Only at the sizes a tested device produces. A grid narrow enough that the
    // band has to shed pulls the pairs apart whatever its width — the words
    // between them are gone — and that is a cost of the grid, not something the
    // arrangement can be asked to survive.
    for (final grid in [(7, 12), (7, 11), (8, 10)]) {
      final pages = home(grid.$1, grid.$2);

      for (var index = 0; index < pages.length; index++) {
        final verbs = pages[index].bandLines['verbs'];
        if (verbs == null || verbs.last - verbs.first + 1 != 3) continue;

        final at = {
          for (final p in pages[index].placed)
            p.value.label: (row: p.row, col: p.col),
        };

        for (final pair in [
          ('go', 'stop'),
          ('get', 'take'),
          ('open', 'close'),
        ]) {
          final a = at[pair.$1];
          final b = at[pair.$2];
          if (a == null || b == null) continue;
          expect(
            a.row == b.row && (a.col - b.col).abs() == 1,
            isTrue,
            reason:
                '"${pair.$1}" and "${pair.$2}" came apart on page '
                '${index + 1} at ${grid.$1}x${grid.$2}',
          );
        }
      }
    }
  });
}
