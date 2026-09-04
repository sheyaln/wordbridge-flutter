import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/grid_migration.dart';
import 'package:wordbridge/features/editor/pinning.dart';

/// Rebuilding a board set at a different grid.
///
/// The most destructive operation in the app, so the tests are about the two
/// properties that make it survivable: it is measured honestly before it runs,
/// and the previous board set comes back intact if it was a mistake.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
  });

  tearDown(() async => db.close());

  Future<Map<String, ({int row, int col})>> homePositions(String vocab) async {
    final query =
        db.select(db.buttons).join([
          innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
        ])..where(
          db.buttons.vocabularyId.equals(vocab) &
              db.boards.kind.equalsValue(BoardKind.root),
        );

    return {
      for (final r in await query.get())
        r.readTable(db.buttons).label: (
          row: r.readTable(db.cells).row,
          col: r.readTable(db.cells).col,
        ),
    };
  }

  /// Where every word sits, board by board. Board name rather than id, because
  /// a rebuild is a different set of boards carrying the same names.
  Future<Map<String, Map<String, ({int row, int col})>>> positionsByBoard(
    String vocab,
  ) async {
    final query =
        db.select(db.buttons).join([
          innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
        ])..where(
          db.buttons.vocabularyId.equals(vocab) &
              db.buttons.isSystem.equals(false),
        );

    final out = <String, Map<String, ({int row, int col})>>{};
    for (final r in await query.get()) {
      (out[r.readTable(db.boards).name] ??= {})[r.readTable(db.buttons).label] =
          (row: r.readTable(db.cells).row, col: r.readTable(db.cells).col);
    }
    return out;
  }

  /// Vocabulary only. The keys along the system row are not words, and which
  /// of them is showing depends on where the category wheel is turned to.
  Future<Set<String>> labelsIn(String vocab) async {
    final rows =
        await (db.select(db.buttons)..where(
              (b) => b.vocabularyId.equals(vocab) & b.isSystem.equals(false),
            ))
            .get();
    return {for (final b in rows) b.label};
  }

  /// Records taps at whichever location holds a word on the root board.
  Future<void> tap(String label, int times) async {
    final home = await (db.select(
      db.boards,
    )..where((b) => b.kind.equalsValue(BoardKind.root))).getSingle();

    final rows =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.cells.boardId.equals(home.id) & db.buttons.label.equals(label),
            ))
            .get();
    final button = rows.single.readTable(db.buttons);

    for (var i = 0; i < times; i++) {
      await db
          .into(db.usageEvents)
          .insert(
            UsageEventsCompanion.insert(
              deviceId: 'd',
              profileId: 'default',
              vocabularyId: vocabId,
              boardId: 'b',
              cellId: button.cellId!,
              action: ButtonAction.speak,
              source: UsageSource.touch,
              occurredAt: nowMs(),
            ),
          );
    }
  }

  group('measuring the cost before anything happens', () {
    test('a preview changes nothing', () async {
      final before = await homePositions(vocabId);

      await GridMigration.preview(db, vocabularyId: vocabId, rows: 5, cols: 9);

      expect(await homePositions(vocabId), before);
      expect(await db.select(db.vocabularies).get(), hasLength(1));
    });

    test('the same grid moves nothing', () async {
      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 7,
        cols: 12,
      );

      expect(impact.isNoOp, isTrue);
      expect(impact.moving, 0);
      expect(impact.staying, greaterThan(0));
    });

    test('a smaller grid moves most of the board', () async {
      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      expect(impact.moving, greaterThan(0));
      expect(impact.leaving, greaterThan(0));
    });

    test('the warning counts the taps at the locations that change', () async {
      // "turn" is a level-2 verb; a 5x9 grid has no room for it on the root
      // board, so it is certain to move.
      await tap('turn', 341);

      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      expect(impact.totalTaps, greaterThanOrEqualTo(341));
      expect(impact.mostPracticed.first.label, 'turn');
      expect(impact.mostPracticed.first.taps, 341);
      expect(impact.warningFor('Maya'), contains('Maya'));
      expect(impact.warningFor('Maya'), contains('${impact.totalTaps}'));
    });

    test('the warning says how far back its count reaches', () async {
      await tap('turn', 341);

      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      expect(
        impact.warningFor('Maya'),
        contains('since this board set was built'),
        reason:
            'a rebuild counts every tap ever recorded and a single word\'s '
            'move counts a recent window, so the same cell reads differently '
            'on the two screens unless each says which it is',
      );
    });

    test('it says so when it cannot tell you the cost', () async {
      // Usage tracking is off by default. A confident "0 taps" would read as
      // "this is free", which is the opposite of what is known.
      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
        trackingEnabled: false,
      );

      expect(impact.warningFor('Maya'), contains('not being recorded'));
      expect(impact.warningFor(null), contains('This user'));
    });

    test('a grid too small for the fixed keys is refused', () async {
      await expectLater(
        GridMigration.preview(db, vocabularyId: vocabId, rows: 4, cols: 5),
        throwsArgumentError,
      );
    });

    test('the count is what the rebuild then actually does', () async {
      // The number a caregiver decides on is the whole point of the preview.
      // If it works out where a word will land by any rule other than the one
      // that builds the board, it is a number about a board nobody gets.
      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      final before = await positionsByBoard(vocabId);
      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );
      final after = await positionsByBoard(rebuilt);

      var stayed = 0;
      var moved = 0;
      for (final board in before.entries) {
        for (final word in board.value.entries) {
          if (after[board.key]?[word.key] == word.value) {
            stayed++;
          } else {
            moved++;
          }
        }
      }

      expect(stayed, impact.staying);
      expect(moved, impact.moving);
    });
  });

  group('rebuilding', () {
    test('the board comes out at the new grid', () async {
      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(rebuilt))).getSingle();

      expect(vocab.gridRows, 5);
      expect(vocab.gridCols, 9);
    });

    test('the profile is pointed at the rebuilt board', () async {
      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals('default'))).getSingle();

      expect(profile.activeVocabularyId, rebuilt);
    });

    test('the previous board set survives untouched', () async {
      // What makes this reversible, and what stops a mistaken rebuild from
      // costing somebody a year of practice.
      final before = await homePositions(vocabId);
      await tap('turn', 12);

      await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      expect(await homePositions(vocabId), before);

      final events = await db.select(db.usageEvents).get();
      expect(events, hasLength(12));
    });

    test('reverting puts the original board back', () async {
      final before = await homePositions(vocabId);

      await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );
      await GridMigration.revert(
        db,
        profileId: 'default',
        toVocabularyId: vocabId,
      );

      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals('default'))).getSingle();

      expect(profile.activeVocabularyId, vocabId);
      expect(await homePositions(vocabId), before);
    });

    test('no word is lost in the rebuild', () async {
      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      final before = await labelsIn(vocabId);
      final after = await labelsIn(rebuilt);

      expect(
        before.difference(after),
        isEmpty,
        reason: 'the rebuild dropped vocabulary',
      );
    });

    test('the rebuild is recorded with the number that was shown', () async {
      await tap('turn', 25);

      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      final events = await (db.select(
        db.editEvents,
      )..where((e) => e.kind.equalsValue(EditKind.gridResize))).get();

      expect(events, hasLength(1));
      expect(events.single.vocabularyId, rebuilt);
      expect(events.single.motorImpactTaps, greaterThanOrEqualTo(25));
      expect(events.single.beforeJson, contains('"rows":7'));
      expect(events.single.afterJson, contains('"rows":5'));
    });
  });

  group('a caregiver’s own work is carried across', () {
    Future<void> addOwnWord(String label) async {
      final home = await (db.select(
        db.boards,
      )..where((b) => b.kind.equalsValue(BoardKind.root))).getSingle();

      final free =
          await (db.select(db.cells)..where(
                (c) =>
                    c.boardId.equals(home.id) &
                    c.state.equalsValue(CellState.emptyReserved),
              ))
              .get();

      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: free.first.id,
        label: label,
        message: label,
        partOfSpeech: PartOfSpeech.noun,
      );
    }

    test('a word they added survives the rebuild', () async {
      // The words nobody can recreate from a default.
      await addOwnWord('Nana');

      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      expect(await labelsIn(rebuilt), contains('Nana'));
    });

    test('their added words are counted in the warning', () async {
      await addOwnWord('Nana');

      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      expect(impact.customWords, greaterThanOrEqualTo(1));
      expect(impact.warningFor('Maya'), contains('added by hand'));
    });

    test('a word they switched off stays switched off', () async {
      final button = await (db.select(
        db.buttons,
      )..where((b) => b.label.equals('turn'))).getSingle();
      await hideButton(db, button.id);

      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );

      final after =
          await (db.select(db.buttons)..where(
                (b) => b.vocabularyId.equals(rebuilt) & b.label.equals('turn'),
              ))
              .getSingle();

      expect(
        after.hidden,
        isTrue,
        reason: 'a rebuild must not undo a caregiver’s decision',
      );
    });
  });

  /// §4.16. A pin is a decision about how a word is reached rather than a
  /// location, so a rebuild has to carry it the way it carries a chosen
  /// picture. The rows themselves cannot be carried: they hold the old grid's
  /// coordinates, and a pinned column is a different height on a different
  /// grid.
  group('a pinned word', () {
    /// A grid with a spare row in the pinned column. The default 7x12 fills it
    /// exactly, so there is nothing to pin into.
    Future<String> tallSeed() => seedCoreBoardSet(db, rows: 8, cols: 12);

    Future<Button> wordIn(String vocab, String label) async {
      final rows =
          await (db.select(db.buttons)..where(
                (b) =>
                    b.vocabularyId.equals(vocab) &
                    b.label.equals(label) &
                    b.isSystem.equals(false) &
                    b.pinnedFromId.isNull() &
                    b.cellId.isNotNull(),
              ))
              .get();
      expect(rows, isNotEmpty, reason: 'no "$label" in this board set');
      return rows.first;
    }

    test('is pinned again on the rebuilt boards', () async {
      final tall = await tallSeed();
      await pinWord(db, await wordIn(tall, 'eat'));

      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: tall,
        rows: 10,
        cols: 12,
      );

      final eat = await wordIn(rebuilt, 'eat');
      expect(
        await pinnedRowOf(db, eat),
        isNotNull,
        reason: 'the rebuild dropped the pin',
      );
    });

    test('and comes out one word, not one per board', () async {
      // Carried as rows rather than as a pin, a caregiver's own pinned word
      // was placed into the first free location of every rebuilt board — a
      // dozen unrelated copies scattered through the reserve.
      final tall = await tallSeed();
      await pinWord(db, await wordIn(tall, 'eat'));

      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: tall,
        rows: 10,
        cols: 12,
      );

      final eat = await wordIn(rebuilt, 'eat');
      final boards =
          await (db.select(db.boards)..where(
                (b) => b.vocabularyId.equals(rebuilt) & b.deletedAt.isNull(),
              ))
              .get();

      final pins =
          await (db.select(db.buttons)..where(
                (b) =>
                    b.vocabularyId.equals(rebuilt) & b.pinnedFromId.isNotNull(),
              ))
              .get();

      expect(pins, hasLength(boards.length));
      expect(pins.every((p) => p.pinnedFromId == eat.id), isTrue);
    });

    test('and the rebuild is not measured as a dozen words moving', () async {
      // A pinned row is the same word at a second location, so counting each
      // one would tell a caregiver a rebuild moves twelve words when it moves
      // one.
      final tall = await tallSeed();
      final before = await GridMigration.preview(
        db,
        vocabularyId: tall,
        rows: 10,
        cols: 12,
      );

      await pinWord(db, await wordIn(tall, 'eat'));

      final after = await GridMigration.preview(
        db,
        vocabularyId: tall,
        rows: 10,
        cols: 12,
      );

      expect(after.moving + after.staying, before.moving + before.staying);
    });
  });

  test('one word to a location after a rebuild', () async {
    final rebuilt = await GridMigration.apply(
      db,
      profileId: 'default',
      vocabularyId: vocabId,
      rows: 9,
      cols: 6,
    );

    final query = db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.buttons.vocabularyId.equals(rebuilt));

    final seen = <String>{};
    for (final r in await query.get()) {
      expect(
        seen.add(r.readTable(db.cells).id),
        isTrue,
        reason: '${r.readTable(db.buttons).label} shares a location',
      );
    }
  });
}
