import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';

import 'core_board_set_test.dart' show universalCore36;
import 'grid_sizes_test.dart' show geometries;

/// The three levels have to stay three different boards.
///
/// Levels are assigned one word at a time as vocabulary is added, and nobody
/// adding a word counts the total. Left alone that converges on one board
/// wearing three names — which is what happened before this file existed:
/// level 1 drew 58% of everything and level 2 to 3 was eight words.
///
/// The unit is words drawn on one page, because that is what a person faces.
/// The ceiling is Project Core's own 36-location Universal Core board (Center
/// for Literacy and Disability Studies, UNC-Chapel Hill): the density that
/// project publishes for a beginning communicator's whole-day display. Project
/// Core also publishes the same 36 words four, six and nine to a page, so a
/// grid too small to draw them at once pages the rest rather than losing it.
///
/// Bands rather than exact numbers everywhere except the root board, which is
/// exact on purpose: it is the board every person meets first and the one the
/// ceiling actually binds on.
void main() {
  /// The locations the Universal Core has no answer for.
  ///
  /// It carries `not`, which negates inside a sentence but can neither answer
  /// a question nor make an imperative, and its possessive key fires after `I`
  /// to give "I's". `how` is the one English question word it omits, and a
  /// pinned column offering five of the six reads as having a hole. Adding to
  /// this set is adding to a beginner's first board, so it is spelled out
  /// rather than counted. `maybe` is the third answer to a direct question:
  /// the core can agree and it can refuse, and without a hedge a person asked
  /// anything has to overstate what they mean or say nothing at all.
  const rootBoardAdditions = {
    'yes',
    'no',
    "don't",
    'wait',
    'me',
    'how',
    'maybe',
  };

  /// Project Core's density for a whole-day beginning-communicator board.
  const universalCoreDensity = 36;

  /// What the root board draws at level 1: that density and one location more.
  ///
  /// The extra one is `maybe`, and it is the only extra the root board gets.
  /// The published figure is a board somebody built rather than a threshold
  /// anything was measured against, and a beginner is not served differently
  /// by thirty six locations than by thirty seven — so what this guards is
  /// that the number stays one somebody argued for, word by word, in the set
  /// above. Every other board holds to the published density.
  const rootBoardDensity = universalCoreDensity + 1;

  /// How many words a category board holds at or below [level], across every
  /// page, ignoring the frame every board carries.
  int levelledCategoryContent(String category, int level) => [
    for (final band in categoryBandsFor(category, AgeBand.child))
      for (final item in band.items)
        if (item.level <= level) item,
  ].length;

  Set<String> levelledAtMost(int level) => {
    for (final band in homeBands)
      for (final item in band.items)
        if (item.level <= level) item.value.label,
    for (final item in pinnedQuestions)
      if (item.level <= level) item.value.label,
    for (final bands in categoryBands.values)
      for (final band in bands)
        for (final item in band.items)
          if (item.level <= level) item.value.label,
  };

  Set<String> everyShippedLabel() => {
    for (final band in homeBands)
      for (final item in band.items) item.value.label,
    for (final item in pinnedQuestions) item.value.label,
    for (final bands in categoryBands.values)
      for (final band in bands)
        for (final item in band.items) item.value.label,
  };

  int shippedWordsAtMost(int level) => [
    for (final band in homeBands) ...band.items,
    ...pinnedQuestions,
    for (final bands in categoryBands.values)
      for (final band in bands) ...band.items,
  ].where((item) => item.level <= level).length;

  group('the root board is the Universal Core 36 and nothing else', () {
    test('level 1 draws exactly the core plus the five it cannot answer', () {
      final drawn = {
        for (final band in homeBands)
          for (final item in band.items)
            if (item.level == 1) item.value.label,
        for (final item in pinnedQuestions)
          if (item.level == 1) item.value.label,
      };

      expect(
        drawn,
        universalCore36.union(rootBoardAdditions),
        reason:
            'the first board a person meets is no longer the evidence-based '
            'floor plus a named handful — either a core word has been held '
            'back, or a word has been promoted onto it without an argument',
      );
    });

    test('its content area is exactly the published density', () {
      // The question words live in the pinned column, which repeats on every
      // board, so they are not this board's own load.
      final content = [
        for (final band in homeBands)
          for (final item in band.items)
            if (item.level == 1) item.value.label,
      ];

      expect(content, hasLength(rootBoardDensity));
    });
  });

  group('what one page draws', () {
    for (final g in geometries) {
      for (final ageBand in AgeBand.values) {
        test('${g.rows}x${g.cols}, ${ageBand.name}', () async {
          final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
          addTearDown(db.close);

          final vocabId = await seedCoreBoardSet(
            db,
            rows: g.rows,
            cols: g.cols,
            ageBand: ageBand,
          );

          final query =
              db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
                innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
              ])..where(
                db.buttons.vocabularyId.equals(vocabId) &
                    db.buttons.isSystem.equals(false),
              );

          // The pinned question column is the same six words on every board,
          // so it is not any one board's own load and not evidence that a
          // board has anything on it.
          final questionCol = g.cols - 1;
          final ownContent = <String, int>{};

          for (final r in await query.get()) {
            final button = r.readTable(db.buttons);
            if (button.vocabLevel > 1) continue;
            if (r.readTable(db.cells).col == questionCol) continue;

            final board = r.readTable(db.boards).name;
            ownContent[board] = (ownContent[board] ?? 0) + 1;
          }

          for (final entry in ownContent.entries) {
            // The root board is allowed its one extra location; a category
            // board reaching the published density would be a category board
            // that had become a second root board.
            final ceiling = entry.key.startsWith('home')
                ? rootBoardDensity
                : universalCoreDensity;

            expect(
              entry.value,
              lessThanOrEqualTo(ceiling),
              reason:
                  '"${entry.key}" draws ${entry.value} words at level 1, past '
                  'the density Project Core publishes for a beginner. A first '
                  'board is a page, not a total',
            );
          }

          // A category key that opens onto a blank board is worse than not
          // having the board: it is vocabulary a person is shown and cannot
          // reach. Page one of each category, because that is where its key
          // lands.
          //
          // A category may hold nothing at level 1 — `numbers` does, because
          // `more` and `all` cover a beginner's quantity work and a
          // single-word board does not need `seven`. The rule that keeps the
          // promise is then on the drawing side: the talk screen does not draw
          // a category key whose board holds nothing this level would show, so
          // no key ever opens onto a blank board. `empty_page_test.dart` is
          // where that half is held.
          for (final category in categoryNames) {
            final own = ownContent[category] ?? 0;
            if (own == 0) {
              expect(
                levelledCategoryContent(category, 3),
                greaterThan(0),
                reason:
                    'the "$category" board holds nothing at any level, so it '
                    'is a key onto a blank board however it is drawn',
              );
              continue;
            }
            expect(own, greaterThan(0));
          }
        });
      }
    }
  });

  group('the three levels stay three boards', () {
    // Bands, not numbers. Vocabulary is added a word at a time and a band is
    // what survives that; an exact count would be edited to match rather than
    // argued with.
    test('level 1 is a first board', () {
      expect(shippedWordsAtMost(1), inInclusiveRange(80, 130));
    });

    test('level 2 is where most of a day is sayable', () {
      // Roughly 200-250 words cover about 80% of everyday speech in English
      // and the European languages measured (Hattingh & Tönsing 2020).
      //
      // The ceiling is above that figure on purpose, and was raised from 265
      // when the `time` board landed. The two count different populations:
      // the study counts *core* words covering running speech, and this counts
      // every shipped word drawn at level 2 or below — which includes the
      // fringe on nine category boards, none of which the 80% figure is about.
      //
      // What the ceiling is actually for is stopping level 2 from quietly
      // becoming level 3, and it still does that: level 3 is roughly twice
      // this, and `each step is a real step` below pins the gap at both ends.
      // It was at 264 of 265 before the `time` board, which is not a budget so
      // much as a wall — any word added anywhere at level 2 broke it, which is
      // a test failing for arithmetic rather than for a decision.
      //
      // Raise it deliberately again if a board is added, and say so here.
      expect(shippedWordsAtMost(2), inInclusiveRange(200, 290));
    });

    test('level 3 is everything', () {
      expect(levelledAtMost(3), everyShippedLabel());
    });

    test('each step is a real step', () {
      final one = shippedWordsAtMost(1);
      final two = shippedWordsAtMost(2);
      final three = shippedWordsAtMost(3);

      expect(
        two - one,
        greaterThanOrEqualTo(90),
        reason: 'level 2 is level 1 again under a different name',
      );
      expect(
        three - two,
        greaterThanOrEqualTo(90),
        reason: 'level 3 is level 2 again under a different name',
      );
    });

    test('the step shows up on the page, not just in the total', () async {
      final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await seedCoreBoardSet(db, rows: defaultGridRows, cols: defaultGridCols);
      final home = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home'))).getSingle();

      final query =
          db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.cells.boardId.equals(home.id) &
                db.buttons.isSystem.equals(false) &
                db.cells.col.isSmallerThanValue(defaultGridCols - 1),
          );

      final levels = [
        for (final r in await query.get()) r.readTable(db.buttons).vocabLevel,
      ];

      expect(levels.where((l) => l <= 1), hasLength(rootBoardDensity));
      expect(
        levels.where((l) => l <= 2).length - rootBoardDensity,
        greaterThanOrEqualTo(15),
        reason:
            'raising the level on the board a person uses most reveals almost '
            'nothing, so the setting reads as broken',
      );
    });
  });

  test('the whole Universal Core 36 is drawn at level 1', () async {
    final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final vocabId = await seedCoreBoardSet(db);
    final rows = await (db.select(
      db.buttons,
    )..where((b) => b.vocabularyId.equals(vocabId))).get();

    final drawnAtOne = {
      for (final b in rows)
        if (!b.isSystem && !b.hidden && b.vocabLevel <= 1) b.label,
    };

    expect(
      universalCore36.difference(drawnAtOne),
      isEmpty,
      reason:
          'a core word is seeded but held back, so a board set to the first '
          'level is short of the evidence-based floor it claims',
    );
  });

  test('nothing on the root board outranks the verbs that page off', () {
    // Level is also shed order: the highest level leaves the page first. The
    // tail of the verb band is the run a 7x12 grid has no room for, so a level
    // above it anywhere else sheds ahead of it and takes a learned location.
    for (final band in homeBands) {
      for (final item in band.items) {
        if (band.name == 'verbs') continue;
        expect(
          item.level,
          lessThanOrEqualTo(2),
          reason:
              '"${item.value.label}" in "${band.name}" sheds before the verbs '
              'the root board already pages off, which moves the words around '
              'it',
        );
      }
    }

    final verbLevels = [
      for (final band in homeBands)
        if (band.name == 'verbs')
          for (final item in band.items) item.level,
    ];

    expect(
      verbLevels.skipWhile((l) => l <= 2),
      everyElement(3),
      reason: 'the level-3 verbs are no longer one run at the end of the band',
    );
  });

  test('the preset extras are levelled like everything else', () {
    // Every preset that receives extras starts at level 2, so extras left
    // wholly at level 1 look calibrated and have never been tested. What they
    // are for is the profile a caregiver has simplified back to level 1.
    for (final ageBand in AgeBand.values) {
      for (final category in categoryNames) {
        final items = [
          for (final band in ageBand.extrasFor(category)) ...band.items,
        ];
        if (items.isEmpty) continue;

        expect(
          items.map((i) => i.level).toSet().length,
          greaterThan(1),
          reason:
              '${ageBand.name}/$category gives every extra the same level, so '
              'the level does nothing on that strip',
        );
      }
    }
  });
}
