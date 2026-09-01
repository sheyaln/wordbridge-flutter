import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/seed/band_layout.dart';

Band<String> band(
  String name,
  List<String> words, {
  int level = 1,
  int reserveLines = 0,
  int minLines = 0,
  int reserveRank = 100,
  int shedRank = 100,
  BandFill fill = BandFill.alongLine,
}) => Band(
  name: name,
  items: [for (final w in words) BandItem(w, level: level)],
  reserveLines: reserveLines,
  minLines: minLines,
  reserveRank: reserveRank,
  shedRank: shedRank,
  fill: fill,
);

Band<String> leveled(
  String name,
  Map<String, int> words, {
  int shedRank = 100,
  Set<String> essential = const {},
}) => Band(
  name: name,
  items: [
    for (final e in words.entries)
      BandItem(e.key, level: e.value, essential: essential.contains(e.key)),
  ],
  shedRank: shedRank,
);

void main() {
  Map<String, ({int row, int col})> coords(BandLayout<String> layout) => {
    for (final p in layout.placed) p.value: (row: p.row, col: p.col),
  };

  List<String> shed(BandLayout<String> layout) => [
    for (final o in layout.overflow) o.item.value,
  ];

  group('filling', () {
    test('a band fills a column top to bottom before starting the next', () {
      // Reading order is down then across. It matches the way the columns are
      // arranged into a sentence left to right, and it means adding a word to
      // a band lengthens a column rather than reflowing every row.
      final layout = layOutBands(
        rows: 4,
        cols: 4,
        bands: [
          band('verbs', ['a', 'b', 'c', 'd', 'e']),
        ],
      );

      expect(coords(layout), {
        'a': (row: 0, col: 0),
        'b': (row: 1, col: 0),
        'c': (row: 2, col: 0),
        'd': (row: 0, col: 1),
        'e': (row: 1, col: 1),
      });
    });

    test('bands are placed left to right in declaration order', () {
      final layout = layOutBands(
        rows: 4,
        cols: 5,
        bands: [
          band('first', ['a', 'b', 'c']),
          band('second', ['d']),
          band('third', ['e']),
        ],
      );

      expect(coords(layout)['a']!.col, 0);
      expect(coords(layout)['d']!.col, 1);
      expect(coords(layout)['e']!.col, 2);
    });

    test('nothing is placed in the system row or the pinned column', () {
      final layout = layOutBands(
        rows: 7,
        cols: 12,
        bands: [
          band('big', [for (var i = 0; i < 66; i++) 'w$i']),
        ],
      );

      for (final p in layout.placed) {
        expect(p.row, lessThan(6), reason: 'the system row is not available');
        expect(
          p.col,
          lessThan(11),
          reason: 'the pinned column is not available',
        );
      }
    });

    test('no two words land on the same location', () {
      final layout = layOutBands(
        rows: 7,
        cols: 12,
        bands: [
          band('a', [for (var i = 0; i < 14; i++) 'a$i'], reserveLines: 2),
          band('b', [for (var i = 0; i < 9; i++) 'b$i']),
          band('c', [for (var i = 0; i < 20; i++) 'c$i']),
        ],
      );

      final seen = <String>{};
      for (final p in layout.placed) {
        expect(
          seen.add('${p.row}:${p.col}'),
          isTrue,
          reason: '${p.value} collided at ${p.row},${p.col}',
        );
      }
    });
  });

  group('filling across the band', () {
    test('consecutive items land side by side', () {
      // What a run of alternatives wants: each is one cell from the last, so
      // the pair is learned as a pair rather than as two locations.
      final layout = layOutBands(
        rows: 5,
        cols: 4,
        bands: [
          band('verbs', [
            'a',
            'b',
            'c',
            'd',
            'e',
            'f',
            'g',
          ], fill: BandFill.acrossBand),
        ],
      );

      expect(coords(layout), {
        'a': (row: 0, col: 0),
        'b': (row: 0, col: 1),
        'c': (row: 1, col: 0),
        'd': (row: 1, col: 1),
        'e': (row: 2, col: 0),
        'f': (row: 2, col: 1),
        'g': (row: 3, col: 0),
      });
    });

    test('the band keeps the same region either way', () {
      // Column position on the root board is sentence order. Only the order
      // inside the region may change; the region itself is fixed.
      List<Band<String>> makeBands(BandFill fill) => [
        band('pronouns', ['I', 'you', 'he', 'she']),
        band('verbs', [
          'want',
          'need',
          'go',
          'stop',
          'get',
          'take',
          'do',
        ], fill: fill),
        band('places', ['here', 'in']),
      ];

      Map<String, ({int first, int last})> regions(BandFill fill) =>
          layOutBands(rows: 4, cols: 8, bands: makeBands(fill)).bandLines;

      expect(regions(BandFill.acrossBand), regions(BandFill.alongLine));

      final across = layOutBands(
        rows: 4,
        cols: 8,
        bands: makeBands(BandFill.acrossBand),
      );
      final verbs = across.bandLines['verbs']!;
      for (final p in across.placed.where((p) => p.band == 'verbs')) {
        expect(p.col, inInclusiveRange(verbs.first, verbs.last));
      }
    });

    test('a reserved line stays empty', () {
      // A reserve is a block of cells held open. Words wrap across the lines
      // the band needs, never the ones it is only holding.
      final layout = layOutBands(
        rows: 4,
        cols: 6,
        bands: [
          band(
            'verbs',
            ['a', 'b', 'c', 'd', 'e', 'f'],
            reserveLines: 1,
            reserveRank: 0,
            fill: BandFill.acrossBand,
          ),
          band('rest', ['z']),
        ],
      );

      expect(layout.bandLines['verbs'], (first: 0, last: 2));
      for (final p in layout.placed) {
        expect(p.col, isNot(2), reason: 'the reserved line took a word');
      }
      expect(coords(layout)['z']!.col, 3);
    });

    test('the same grid always produces the same coordinates', () {
      List<Band<String>> makeBands() => [
        band('verbs', [
          'want',
          'need',
          'go',
          'stop',
          'get',
        ], fill: BandFill.acrossBand),
      ];

      final first = coords(layOutBands(rows: 5, cols: 5, bands: makeBands()));
      final second = coords(layOutBands(rows: 5, cols: 5, bands: makeBands()));

      expect(second, first);
    });

    test('a band that fills a tail cannot also fill across', () {
      // A cross-filled block ends in a ragged edge, not one open run, so
      // there is nothing coherent for it to append to.
      expect(
        () => layOutBands(
          rows: 5,
          cols: 5,
          bands: [
            band('shipped', ['a', 'b']),
            Band(
              name: 'extra',
              startsLine: false,
              fill: BandFill.acrossBand,
              items: [BandItem('x')],
            ),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('the band after a cross-filled one never lands on top of it', () {
      final layout = layOutBands(
        rows: 4,
        cols: 6,
        bands: [
          band('verbs', ['a', 'b', 'c', 'd', 'e'], fill: BandFill.acrossBand),
          Band(
            name: 'extra',
            startsLine: false,
            items: [BandItem('x'), BandItem('y')],
          ),
        ],
      );

      final seen = <String>{};
      for (final p in layout.placed) {
        expect(seen.add('${p.row}:${p.col}'), isTrue, reason: p.value);
      }
      expect(coords(layout)['x']!.col, greaterThan(1));
    });

    test('the row axis fills down the band instead of across it', () {
      // A line is a row here, so the same rule reads the other way round.
      final layout = layOutBands(
        rows: 5,
        cols: 4,
        axis: BandAxis.rows,
        bands: [
          band('verbs', ['a', 'b', 'c', 'd', 'e'], fill: BandFill.acrossBand),
        ],
      );

      expect(coords(layout), {
        'a': (row: 0, col: 0),
        'b': (row: 1, col: 0),
        'c': (row: 0, col: 1),
        'd': (row: 1, col: 1),
        'e': (row: 0, col: 2),
      });
    });
  });

  group('the row axis', () {
    test('a band fills a row left to right before starting the next', () {
      // Category boards group by word class along a row, so related words are
      // side by side. A row-column scan then narrows to a word class on the
      // first press instead of narrowing to nothing.
      final layout = layOutBands(
        rows: 4,
        cols: 4,
        axis: BandAxis.rows,
        bands: [
          band('verbs', ['a', 'b', 'c', 'd', 'e']),
        ],
      );

      expect(coords(layout), {
        'a': (row: 0, col: 0),
        'b': (row: 0, col: 1),
        'c': (row: 0, col: 2),
        'd': (row: 1, col: 0),
        'e': (row: 1, col: 1),
      });
    });

    test('bands stack top to bottom in declaration order', () {
      final layout = layOutBands(
        rows: 5,
        cols: 4,
        axis: BandAxis.rows,
        bands: [
          band('first', ['a', 'b', 'c']),
          band('second', ['d']),
          band('third', ['e']),
        ],
      );

      expect(coords(layout)['a']!.row, 0);
      expect(coords(layout)['d']!.row, 1);
      expect(coords(layout)['e']!.row, 2);
    });

    test('nothing is placed in the system row or the pinned column', () {
      final layout = layOutBands(
        rows: 7,
        cols: 12,
        axis: BandAxis.rows,
        bands: [
          band('big', [for (var i = 0; i < 66; i++) 'w$i']),
        ],
      );

      for (final p in layout.placed) {
        expect(p.row, lessThan(6));
        expect(p.col, lessThan(11));
      }
    });

    test(
      'a band that does not start a line fills the tail of the one before',
      () {
        // How an age preset adds words without costing a shipped word its
        // location: the extras land in cells the band above left empty.
        final layout = layOutBands(
          rows: 4,
          cols: 5,
          axis: BandAxis.rows,
          bands: [
            band('shipped', ['a', 'b']),
            Band(
              name: 'extra',
              startsLine: false,
              items: [BandItem('x'), BandItem('y')],
            ),
          ],
        );

        expect(coords(layout)['a'], (row: 0, col: 0));
        expect(coords(layout)['b'], (row: 0, col: 1));
        expect(coords(layout)['x'], (row: 0, col: 2));
        expect(coords(layout)['y'], (row: 0, col: 3));
      },
    );

    test('a filled tail still pushes the next band onto a fresh row', () {
      final layout = layOutBands(
        rows: 4,
        cols: 3,
        axis: BandAxis.rows,
        bands: [
          band('shipped', ['a', 'b']),
          Band(
            name: 'extra',
            startsLine: false,
            items: [BandItem('x'), BandItem('y')],
          ),
          band('after', ['z']),
        ],
      );

      final seen = <String>{};
      for (final p in layout.placed) {
        expect(seen.add('${p.row}:${p.col}'), isTrue, reason: p.value);
      }
      expect(coords(layout)['z']!.row, greaterThan(0));
    });
  });

  test('two bands sharing a name is caught, not silently merged', () {
    // Bands are keyed by name, so a collision would place one band's words
    // twice and never place the other's at all.
    expect(
      () => layOutBands(
        rows: 5,
        cols: 5,
        bands: [
          band('out', ['a']),
          band('out', ['b']),
        ],
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('the same grid always produces the same coordinates', () {
    // A rebuild that produced different coordinates would move every word on
    // the board, which is the failure the whole project is built to prevent.
    List<Band<String>> makeBands() => [
      band('pronouns', ['I', 'you', 'he'], reserveLines: 2, reserveRank: 0),
      band('verbs', ['want', 'go', 'stop', 'help', 'look']),
      band('places', ['here', 'in']),
    ];

    final first = coords(layOutBands(rows: 6, cols: 9, bands: makeBands()));
    final second = coords(layOutBands(rows: 6, cols: 9, bands: makeBands()));

    expect(second, first);
  });

  group('reserved columns', () {
    test('a band gets the spare columns it asked for', () {
      final layout = layOutBands(
        rows: 4,
        cols: 6,
        bands: [
          band('names', ['mum'], reserveLines: 2, reserveRank: 0),
          band('verbs', ['go']),
        ],
      );

      // names takes column 0 and holds 1 and 2, so verbs starts at 3.
      expect(coords(layout)['mum']!.col, 0);
      expect(coords(layout)['go']!.col, 3);
    });

    test('spare columns go by rank when there are not enough', () {
      final layout = layOutBands(
        rows: 4,
        cols: 5,
        bands: [
          band('low', ['a'], reserveLines: 2, reserveRank: 9),
          band('high', ['b'], reserveLines: 2, reserveRank: 1),
          band('rest', ['c']),
        ],
      );

      // Three bands need one column each out of four available, so exactly one
      // spare exists and the higher-ranked band takes it.
      expect(coords(layout)['a']!.col, 0);
      expect(coords(layout)['b']!.col, 1);
      expect(coords(layout)['c']!.col, 3);
    });

    test('a reserve is never taken from space a word needs', () {
      // Reserve comes out of what is spare, so asking for more room than the
      // grid has costs nothing — it cannot push a word off the board.
      final layout = layOutBands(
        rows: 4,
        cols: 4,
        bands: [
          band('names', ['mum'], reserveLines: 9, reserveRank: 0),
          band('verbs', ['go', 'stop']),
        ],
      );

      expect(shed(layout), isEmpty);
      expect(coords(layout).keys, containsAll(['mum', 'go', 'stop']));
    });
  });

  group('a grid too small to hold everything', () {
    test('sheds the highest level first', () {
      // Two columns of two rows hold four words; there are five. The one that
      // goes is the one furthest from day-one vocabulary.
      final layout = layOutBands(
        rows: 3,
        cols: 3,
        bands: [
          leveled('mixed', {'core': 1, 'later': 2, 'much later': 3}),
          leveled('other', {'core two': 1, 'later two': 2}),
        ],
      );

      expect(shed(layout), ['much later']);
    });

    test('sheds from the band that gives way first when levels tie', () {
      final layout = layOutBands(
        rows: 3,
        cols: 2,
        bands: [
          band('keep', ['a', 'b'], shedRank: 0),
          band('yield', ['c', 'd'], shedRank: 9),
        ],
      );

      expect(shed(layout), ['d', 'c']);
      expect(coords(layout).keys, containsAll(['a', 'b']));
    });

    test('a shed word is handed back, never dropped', () {
      // A word that exists in the vocabulary and cannot be said anywhere is a
      // worse outcome than an extra tap to reach it.
      final words = [for (var i = 0; i < 40; i++) 'w$i'];
      final layout = layOutBands(rows: 5, cols: 4, bands: [band('all', words)]);

      final accounted = [...layout.placed.map((p) => p.value), ...shed(layout)];
      expect(accounted..sort(), (words.toList()..sort()));
    });

    test('core words survive down to the smallest usable grid', () {
      // Eight words, six locations. The board keeps one of each kind, which is
      // the difference between a small board and a broken one.
      final layout = layOutBands(
        rows: 3,
        cols: 4,
        bands: [
          leveled('pronouns', {'I': 1, 'you': 1, 'we': 2}, shedRank: 0),
          leveled('verbs', {'want': 1, 'go': 1, 'turn': 2}, shedRank: 1),
          leveled(
            'negation',
            {'not': 1, 'good': 2},
            shedRank: 2,
            essential: {'not'},
          ),
        ],
      );

      expect(
        coords(layout).keys,
        containsAll(['I', 'you', 'want', 'go', 'not']),
      );

      // Two words, not three. Only the two bands that had a line to give up
      // lose anything; the negation band is never asked, so "good" keeps a
      // location that was never contested. Shedding by rank across every band
      // would have taken it to buy a column that was already free.
      expect(shed(layout)..sort(), ['turn', 'we']);
    });

    test('a band with room to spare is not asked to pay', () {
      // Two bands, one of them nearly empty. The grid is one line short, and
      // the line has to come from the band that is actually using them.
      final layout = layOutBands(
        rows: 4,
        cols: 4,
        bands: [
          leveled('sparse', {'I': 1, 'you': 2}, shedRank: 0),
          leveled('crowded', {
            'a': 1,
            'b': 1,
            'c': 2,
            'd': 2,
            'e': 2,
            'f': 2,
            'g': 2,
          }, shedRank: 1),
        ],
      );

      expect(coords(layout).keys, containsAll(['I', 'you']));
      expect(shed(layout), isNot(contains('you')));
    });

    test('an essential word is kept even when its band gives way first', () {
      // Refusal is the most urgent thing a user can need to say. Putting it a
      // navigation step away on a small board is a safety problem, not a
      // space-saving.
      final layout = layOutBands(
        rows: 3,
        cols: 2,
        bands: [
          band('bulk', ['a', 'b', 'c'], shedRank: 0),
          leveled('negation', {'not': 1}, shedRank: 9, essential: {'not'}),
        ],
      );

      expect(coords(layout).keys, contains('not'));
    });

    test('a grid too small to hold the essentials is refused', () {
      expect(
        () => layOutBands(
          rows: 2,
          cols: 2,
          bands: [
            leveled(
              'negation',
              {'not': 1, 'stop': 1},
              essential: {'not', 'stop'},
            ),
          ],
        ),
        throwsStateError,
      );
    });
  });

  group('a line held open against a word that exists', () {
    test('the held line goes first', () {
      // Four columns, and the two bands need three between them, but one of
      // them is holding a column open for words nobody has added yet. The held
      // column is what gives way — a word on the next page is a press away, and
      // a word nobody has written yet is not there to lose anything.
      final layout = layOutBands(
        rows: 3,
        cols: 5,
        bands: [
          band('verbs', ['go', 'stop', 'get', 'take']),
          band('things', const [], minLines: 1),
          band('joining', ['and', 'but', 'because', 'so']),
        ],
      );

      expect(
        shed(layout),
        isEmpty,
        reason: 'a word was pushed off to keep an empty column',
      );
      expect(layout.bandLines.containsKey('things'), isFalse);
    });

    test('a line the band\'s own words need is not a held line', () {
      // Only the empty ones are on offer. A band asked to give back a line its
      // own words are sitting on frees nothing and loses its floor, and then
      // the shedding that follows takes the words it was guaranteed to keep.
      final layout = layOutBands(
        rows: 3,
        cols: 4,
        bands: [
          band('names', ['mum', 'dad', 'nan', 'pop'], minLines: 2),
          band('things', const [], minLines: 1),
          band('verbs', ['a', 'b', 'c', 'd', 'e', 'f']),
        ],
      );

      expect(
        coords(layout).keys,
        containsAll(['mum', 'dad', 'nan', 'pop']),
        reason: 'a guaranteed band was stripped of its floor and then shed',
      );
      expect(layout.bandLines['names'], (first: 0, last: 1));
      expect(layout.bandLines.containsKey('things'), isFalse);
    });
  });

  group('a band that may not grow', () {
    test('is capped even where the grid has room to spare', () {
      // The cap is not about room. This band is read as rows of two — go beside
      // stop, get beside take — and a third column re-wraps every one of them,
      // so the words past the cap page rather than rearrange the rest.
      final layout = layOutBands(
        rows: 3,
        cols: 9,
        bands: [
          Band(
            name: 'verbs',
            maxLines: 2,
            fill: BandFill.acrossBand,
            items: [
              for (final w in ['go', 'stop', 'get', 'take', 'open', 'close'])
                BandItem(w),
            ],
          ),
        ],
      );

      expect(shed(layout), ['close', 'open']);
      expect(coords(layout)['go']!.col, 0);
      expect(coords(layout)['stop']!.col, 1);
      expect(coords(layout)['get']!.col, 0);
      expect(coords(layout)['take']!.col, 1);
    });

    test('sheds its least important words, not its last ones', () {
      final layout = layOutBands(
        rows: 4,
        cols: 6,
        bands: [
          Band(
            name: 'verbs',
            maxLines: 1,
            items: [
              BandItem('go'),
              BandItem('later', level: 3),
              BandItem('stop'),
              BandItem('wait'),
            ],
          ),
        ],
      );

      expect(shed(layout), ['later']);
    });
  });

  group('a later page of the same group', () {
    test('puts a band back on the lines it owns', () {
      // The whole argument of the board, one level down: a region that means
      // "doing" teaches somebody where to look, and a region that moves when
      // you page is learned twice. It matters more under row-column scanning,
      // where the first press narrows to a region.
      final layout = layOutOnto(
        rows: 3,
        cols: 6,
        bands: [
          band('verbs', ['open', 'close']),
        ],
        anchors: {
          'pronouns': (first: 0, last: 1),
          'verbs': (first: 2, last: 4),
        },
      );

      expect(coords(layout)['open']!.col, 2);
      expect(coords(layout)['close']!.col, 2);
    });

    test('a band shed off page one is given lines where it belongs', () {
      // 1,414 band-and-grid combinations have an overflowing band with no
      // page-one lines at all, because shedding takes whole lines and a band
      // that gives up all of them gets no entry. "Keep your lines" has to say
      // something for those, and what it says is where they start.
      //
      // The pronouns are not on this page, so their columns are free — and
      // taking them would put the joining words to the left of the verbs, which
      // on the root board is a different sentence.
      final layout = layOutOnto(
        rows: 3,
        cols: 6,
        bands: [
          band('verbs', ['open']),
          band('joining', ['and', 'but']),
        ],
        anchors: {
          'pronouns': (first: 0, last: 1),
          'verbs': (first: 2, last: 2),
        },
      );

      expect(
        layout.bandLines['joining']!.first,
        3,
        reason:
            'a band with no lines of its own landed out of declaration order, '
            'which on the root board is the sentence order',
      );
    });

    test('takes only the lines its words here need', () {
      // A band holding lines it has nothing to put in would be holding empty
      // space at the price of a band that has none — the same ordering page one
      // refuses. The verbs own three columns and have one word to put here, so
      // two of them are the joining words' only way onto this page.
      final layout = layOutOnto(
        rows: 3,
        cols: 4,
        bands: [
          band('verbs', ['open']),
          band('joining', ['and', 'but']),
        ],
        anchors: {'verbs': (first: 0, last: 2)},
      );

      expect(
        shed(layout),
        isEmpty,
        reason: 'the verbs held two empty columns and two words paged for them',
      );
      expect(layout.bandLines['verbs'], (first: 0, last: 0));
    });

    test('grows into free lines rather than costing a page', () {
      // A page is a movement every time the word is said; an unclaimed column
      // beside a band is not. Where nothing else needs the line, the band takes
      // it and keeps its start.
      final layout = layOutOnto(
        rows: 3,
        cols: 6,
        bands: [
          band('verbs', ['open', 'close', 'get', 'take']),
        ],
        anchors: {'verbs': (first: 1, last: 1)},
      );

      expect(shed(layout), isEmpty);
      expect(layout.bandLines['verbs'], (first: 1, last: 2));
    });

    test('a capped band is still capped here', () {
      final layout = layOutOnto(
        rows: 4,
        cols: 6,
        bands: [
          Band(
            name: 'verbs',
            maxLines: 1,
            items: [
              for (final w in ['open', 'close', 'get', 'take']) BandItem(w),
            ],
          ),
        ],
        anchors: {'verbs': (first: 1, last: 1)},
      );

      expect(shed(layout), ['take']);
      expect(layout.bandLines['verbs'], (first: 1, last: 1));
    });

    test('will not grow over a line another band needs here', () {
      final layout = layOutOnto(
        rows: 4,
        cols: 5,
        bands: [
          band('verbs', ['open', 'close', 'get', 'take']),
          band('joining', ['and']),
        ],
        anchors: {'verbs': (first: 0, last: 0), 'joining': (first: 1, last: 1)},
      );

      expect(shed(layout), ['take']);
      expect(coords(layout)['and']!.col, 1);
    });

    test('names its regions left to right', () {
      // The map is what labels the regions on the board, and a caregiver
      // reading it should read it the way the board is drawn — not in the order
      // the bands happened to be declared.
      final layout = layOutOnto(
        rows: 3,
        cols: 6,
        bands: [
          band('verbs', ['open']),
          band('joining', ['and']),
        ],
        anchors: {'verbs': (first: 3, last: 3), 'joining': (first: 0, last: 0)},
      );

      expect(layout.bandLines.keys.toList(), ['joining', 'verbs']);
    });
  });

  test('a grid with no room for vocabulary is refused, not fudged', () {
    expect(
      () => layOutBands(
        rows: 1,
        cols: 4,
        bands: [
          band('a', ['x']),
        ],
      ),
      throwsArgumentError,
    );
  });

  group('the keys on every board', () {
    test('home, back and paging sit at the edges', () {
      final plan = SystemRowPlan.forGrid(rows: 7, cols: 12, categories: 6);

      expect(plan.row, 6);
      expect(plan.homeCol, 0);
      expect(plan.backCol, 1);
      expect(plan.pageBackCol, 10);
      expect(plan.pageForwardCol, 11);
    });

    test('a gap separates navigation from the category keys', () {
      // Home and back undo what just happened; a category key goes somewhere
      // new. Shoulder to shoulder, an imprecise reach for one lands on the
      // other.
      final plan = SystemRowPlan.forGrid(rows: 7, cols: 12, categories: 6);
      expect(plan.categoryCols.first, 3);
      expect(plan.categoryCols, [3, 4, 5, 6, 7, 8]);
      expect(
        plan.cycleCol,
        isNull,
        reason: 'nothing to cycle when every category has its own key',
      );
    });

    test('categories that do not fit are cycled through, not buried', () {
      // A board of categories would put every one of them two movements away.
      // Cycling keeps them at one movement plus however many turns.
      final plan = SystemRowPlan.forGrid(rows: 8, cols: 7, categories: 6);

      expect(plan.categoryCols, hasLength(1));
      expect(plan.cycleCol, isNotNull);
      expect(plan.cycleCol, greaterThan(plan.categoryCols.last));
      expect(plan.cycleCol, lessThan(plan.pageBackCol));
    });

    test('an extra category takes a new key without moving the others', () {
      // Adding a category board is additive or it is not shippable: every key
      // already on the system row has been learned.
      for (final g in [
        (rows: 7, cols: 12),
        (rows: 9, cols: 15),
        (rows: 8, cols: 7),
        (rows: 12, cols: 8),
      ]) {
        final before = SystemRowPlan.forGrid(
          rows: g.rows,
          cols: g.cols,
          categories: 6,
        );
        final after = SystemRowPlan.forGrid(
          rows: g.rows,
          cols: g.cols,
          categories: 7,
        );

        expect(
          after.categoryCols.take(before.categoryCols.length),
          before.categoryCols,
          reason: 'a category key moved at ${g.rows}x${g.cols}',
        );
        if (before.cycleCol != null) {
          expect(after.cycleCol, before.cycleCol);
        }
      }
    });

    test('a grid too small for the fixed keys is refused', () {
      expect(
        () => SystemRowPlan.forGrid(rows: 7, cols: 5, categories: 6),
        throwsArgumentError,
      );
      expect(
        () => SystemRowPlan.forGrid(rows: 3, cols: 12, categories: 6),
        throwsArgumentError,
      );
    });
  });

  group('a band that claims no line', () {
    Band<String> tail(String name, List<String> words) => Band(
      name: name,
      startsLine: false,
      tailOnly: true,
      items: [for (final w in words) BandItem(w)],
    );

    List<String> placedIn(BandLayout<String> layout, String name) => [
      for (final p in layout.placed)
        if (p.band == name) p.value,
    ];

    test('takes the tail of the last written line', () {
      // Four words in a line of six leaves two cells nobody claimed.
      final layout = layOutBands(
        rows: 7,
        cols: 3,
        bands: [
          band('words', ['a', 'b', 'c', 'd']),
          tail('extra', ['x']),
        ],
        pinnedCols: 0,
      );

      expect(placedIn(layout, 'extra'), ['x']);
      expect(layout.overflow, isEmpty);
    });

    test('and pages where the line ends flush', () {
      final layout = layOutBands(
        rows: 7,
        cols: 3,
        bands: [
          band('words', ['a', 'b', 'c', 'd', 'e', 'f']),
          tail('extra', ['x']),
        ],
        pinnedCols: 0,
      );

      expect(placedIn(layout, 'extra'), isEmpty);
      expect(layout.overflow.map((o) => o.item.value), ['x']);
    });

    test('never a line another band is holding open', () {
      // The distinction the whole thing turns on, and the one the shipped
      // vocabulary cannot exercise because nothing after its reserves asks for
      // one. A reserve is a location promised to a word that does not exist
      // yet; measuring the tail from the line cursor would hand it to a word
      // that does, and the promise would be broken by an unrelated edit.
      final layout = layOutBands(
        rows: 7,
        cols: 4,
        bands: [
          band('words', ['a', 'b', 'c', 'd'], reserveLines: 1, reserveRank: 0),
          tail('extra', ['x', 'y', 'z']),
        ],
        pinnedCols: 0,
      );

      expect(layout.bandLines['words'], (
        first: 0,
        last: 1,
      ), reason: 'the reserve was not granted, so the premise is gone');

      // Two cells of the written line, and no more — the six of the reserved
      // line beside it stay empty.
      expect(placedIn(layout, 'extra'), ['x', 'y']);
      expect(layout.overflow.map((o) => o.item.value), ['z']);
    });

    test('and claims none of the grid when it is measured', () {
      // Without this the band costs a line even when it fills a tail, and what
      // that line costs is whichever reserve the grid had spare.
      final bands = [
        band('words', ['a', 'b', 'c', 'd'], reserveLines: 1, reserveRank: 0),
      ];

      final before = layOutBands(rows: 7, cols: 4, bands: bands, pinnedCols: 0);
      final after = layOutBands(
        rows: 7,
        cols: 4,
        bands: [
          ...bands,
          tail('extra', ['x']),
        ],
        pinnedCols: 0,
      );

      expect(after.bandLines, before.bandLines);
    });

    test('sheds its least important words first, like every other band', () {
      final layout = layOutBands(
        rows: 7,
        cols: 3,
        bands: [
          band('words', ['a', 'b', 'c', 'd']),
          Band(
            name: 'extra',
            startsLine: false,
            tailOnly: true,
            items: [
              BandItem('keep', level: 1),
              BandItem('drop', level: 3),
              BandItem('also', level: 1),
            ],
          ),
        ],
        pinnedCols: 0,
      );

      // Two cells of tail for three words: the level-3 one is the one that
      // pays, and what survives is still in the order it was declared.
      expect(placedIn(layout, 'extra'), ['keep', 'also']);
      expect(layout.overflow.map((o) => o.item.value), ['drop']);
    });
  });
}
