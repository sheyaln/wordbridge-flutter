import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';

/// What a grid gives up first, held apart from what it draws.
///
/// `level` decides who sees a word. `pageRank` decides what a grid too small
/// to hold everything moves to a second page. Tying them together meant a word
/// could only be kept off page one by being hidden from somebody who could use
/// it, and could only be shown to that person by taking a page-one location
/// from something that earned it.
///
/// The grids here are the ones the geometry actually derives, not round
/// numbers: a grid is small because the buttons are large, and the buttons are
/// large for the people least able to afford an extra movement.
void main() {
  /// The labels page one draws at this geometry.
  Set<String> pageOne({required int rows, required int cols}) {
    final layout = layOutBands(bands: homeBands, rows: rows, cols: cols);
    return {for (final p in layout.placed) p.value.label};
  }

  /// The keys that turn a run of content words into a sentence.
  const grammarKeys = {
    '+s',
    '+ed',
    '+ing',
    "+'s",
    'am/is/are',
    'was/were',
    'a',
    'the',
  };

  const endings = {'+s', '+ed', '+ing', "+'s"};

  group('the grammar engine holds page one ahead of ordinary vocabulary', () {
    test('the endings survive at 8x10, where no key used to', () {
      // Not the articles: the root board is full enough that one more verb in
      // the band costs their column here. The endings are the ones that earn
      // the room — a suffix key multiplies every verb on the board, while an
      // article is one word and a sentence without it is still understood.
      expect(pageOne(rows: 8, cols: 10), containsAll(endings));
      expect(
        pageOne(rows: 8, cols: 10),
        containsAll({'am/is/are', 'was/were'}),
      );
    });

    test('the endings survive at 6x12', () {
      // Not the whole set: the past copula and the articles still page off
      // here, because a rank that outran the level-1 core would take a word
      // somebody can see to make room for one they cannot.
      expect(pageOne(rows: 6, cols: 12), containsAll(endings));
    });

    test('and at 5x14', () {
      expect(pageOne(rows: 5, cols: 14), containsAll(endings));
    });

    test('the default grid keeps every key — it has room for all of them', () {
      expect(pageOne(rows: 7, cols: 12), containsAll(grammarKeys));
    });
  });

  group('the two ranks are genuinely separate', () {
    test('a word can be drawn early and paged off late', () {
      // The tail of the verb band. Drawn at level 2, and still the run a 7x12
      // grid pages off, so raising it revealed the words without moving one.
      final tail = {'know', 'think', 'say', 'tell', 'see', 'come', 'give'};

      final verbBand = homeBands.firstWhere((b) => b.name == 'verbs');
      for (final item in verbBand.items.where(
        (i) => tail.contains(i.value.label),
      )) {
        expect(item.level, 2, reason: '${item.value.label} is drawn at 2');
        expect(item.pageRank, 30, reason: '${item.value.label} pages off at 3');
      }

      expect(pageOne(rows: 7, cols: 12), isNot(containsAll(tail)));
    });

    test('and a word can be drawn late and paged off early', () {
      final endingsBand = homeBands.firstWhere((b) => b.name == 'endings');
      for (final item in endingsBand.items) {
        expect(item.level, 2);
        expect(item.pageRank, lessThan(20));
      }
    });

    test('rank follows level wherever nothing says otherwise', () {
      const item = BandItem('x', level: 2);
      expect(item.pageRank, 20);
    });

    test('the default leaves room to sit between two levels', () {
      const between = BandItem('x', level: 2, pageRankOverride: 15);
      expect(between.pageRank, greaterThan(const BandItem('x').pageRank));
      expect(
        between.pageRank,
        lessThan(const BandItem('x', level: 2).pageRank),
      );
    });
  });
}
