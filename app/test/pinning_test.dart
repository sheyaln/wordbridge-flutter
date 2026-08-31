import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/pinning.dart';

/// §4.16. One word reachable from every board, at the same coordinates.
///
/// The decision under test is that **a pin is a copy, not a move**. The word
/// keeps the location it already has and gains a second, shorter route to
/// itself — which is what makes unpinning safe, because nothing was displaced
/// to make room and nothing has to be put back.
void main() {
  late WordbridgeDatabase db;

  tearDown(() async => db.close());

  /// A grid with a spare row in the pinned column.
  ///
  /// At 7 rows the column is exactly full — six questions in `rows - 1` — so
  /// the case worth testing needs one more row than the shipped iPad grid.
  Future<Vocabulary> seed({int rows = 8, int cols = 12}) async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    final id = await seedCoreBoardSet(db, rows: rows, cols: cols);
    return (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(id))).getSingle();
  }

  Future<Button> word(Vocabulary vocabulary, String label) async {
    final rows =
        await (db.select(db.buttons)
              ..where((b) => b.vocabularyId.equals(vocabulary.id))
              ..where((b) => b.label.equals(label))
              ..where((b) => b.isSystem.equals(false)))
            .get();
    if (rows.isEmpty) throw StateError('no "$label" on this board set');
    return rows.first;
  }

  Future<List<Board>> boardsOf(Vocabulary vocabulary) =>
      (db.select(db.boards)
            ..where((b) => b.vocabularyId.equals(vocabulary.id))
            ..where((b) => b.deletedAt.isNull()))
          .get();

  Future<List<Button>> inPinnedColumn(Vocabulary vocabulary, String label) =>
      (db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.buttons.vocabularyId.equals(vocabulary.id) &
                db.buttons.deletedAt.isNull() &
                db.buttons.label.equals(label) &
                db.cells.col.equals(pinnedColumn(vocabulary)),
          ))
          .get()
          .then((rows) => [for (final r in rows) r.readTable(db.buttons)]);

  group('where a pin can go', () {
    test('the last column, where the questions already are', () async {
      final vocabulary = await seed();
      expect(pinnedColumn(vocabulary), vocabulary.gridCols - 1);
    });

    test('a row every board has free, and only such a row', () async {
      final vocabulary = await seed();
      final free = await freePinnedRows(db, vocabulary);
      expect(free, isNotEmpty, reason: 'the premise: 8 rows leaves one spare');

      // One board putting something there takes the row off the table for all
      // of them: a pin is one location on every board or it is not a pin.
      final boards = await boardsOf(vocabulary);
      final cell =
          await (db.select(db.cells)
                ..where((c) => c.boardId.equals(boards.first.id))
                ..where((c) => c.row.equals(free.first))
                ..where((c) => c.col.equals(pinnedColumn(vocabulary))))
              .getSingle();
      await (db.update(db.cells)..where((c) => c.id.equals(cell.id))).write(
        const CellsCompanion(state: Value(CellState.occupied)),
      );

      expect(await freePinnedRows(db, vocabulary), isNot(contains(free.first)));
    });

    test(
      'and at seven rows there is none, because the column is full',
      () async {
        // The shipped iPad grid. Six questions in `rows - 1` fills it exactly,
        // and §4.43 closed the system row's gap — which was §4.16's other
        // candidate — to words.
        final vocabulary = await seed(rows: 7);
        expect(await freePinnedRows(db, vocabulary), isEmpty);
      },
    );
  });

  group('what is refused, and why it says so', () {
    test('a key every board already carries', () async {
      final vocabulary = await seed();
      final home =
          await (db.select(db.buttons)
                ..where((b) => b.vocabularyId.equals(vocabulary.id))
                ..where((b) => b.isSystem.equals(true)))
              .get();

      final refusal = await refusalToPin(db, home.first);
      expect(refusal, contains('already on every board'));
    });

    test('a word that is already in the pinned column', () async {
      final vocabulary = await seed();
      final question = (await inPinnedColumn(vocabulary, 'what')).first;

      expect(
        await refusalToPin(db, question),
        contains('already in the pinned column'),
      );
    });

    test('a full column, naming why hiding does not free one', () async {
      final vocabulary = await seed(rows: 7);
      final refusal = await refusalToPin(db, await word(vocabulary, 'eat'));

      expect(refusal, contains('full'));
      // Hiding never releases a location (§2), and that rule is not something
      // to break for a pin.
      expect(refusal, contains('hiding'));
    });

    test('a board set with no frame recorded', () async {
      final vocabulary = await seed();
      await (db.update(db.vocabularies)
            ..where((v) => v.id.equals(vocabulary.id)))
          .write(const VocabulariesCompanion(systemCellMap: Value('{}')));
      final reread = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabulary.id))).getSingle();

      expect(
        await refusalToPin(db, await word(reread, 'eat')),
        contains('was not built with a pinned column'),
      );
    });

    test('and an ordinary word on a grid with room is not refused', () async {
      final vocabulary = await seed();
      expect(await refusalToPin(db, await word(vocabulary, 'eat')), isNull);
    });
  });

  group('what pinning does', () {
    test('puts the word at one location on every board', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      final boards = await boardsOf(vocabulary);

      await pinWord(db, eat);

      final copies = await inPinnedColumn(vocabulary, 'eat');
      expect(copies, hasLength(boards.length));

      final cells = await (db.select(
        db.cells,
      )..where((c) => c.id.isIn([for (final b in copies) b.cellId!]))).get();
      expect(
        cells.map((c) => c.row).toSet(),
        hasLength(1),
        reason: 'the same movement has to reach it from every board',
      );
    });

    test('and leaves the word where it was', () async {
      // A pin is a copy. Trading a learned position for a shorter route is
      // the thing this is not.
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');

      await pinWord(db, eat);

      final after = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(eat.id))).getSingle();
      expect(after.cellId, eat.cellId);
      expect(after.deletedAt, isNull);
    });

    test('and moves nothing else', () async {
      final vocabulary = await seed();
      final before = await db.select(db.buttons).get();

      await pinWord(db, await word(vocabulary, 'eat'));

      final after = await db.select(db.buttons).get();
      for (final was in before) {
        final now = after.firstWhere((b) => b.id == was.id);
        expect(now.cellId, was.cellId, reason: '"${was.label}" moved');
      }
    });

    test('taking a row that was free, and only that row', () async {
      final vocabulary = await seed();
      final free = await freePinnedRows(db, vocabulary);

      await pinWord(db, await word(vocabulary, 'eat'));

      expect(await freePinnedRows(db, vocabulary), free.skip(1).toList());
    });

    test('so a second pin is refused once the column fills', () async {
      final vocabulary = await seed();
      await pinWord(db, await word(vocabulary, 'eat'));

      final refusal = await refusalToPin(db, await word(vocabulary, 'drink'));
      expect(refusal, contains('full'));
    });

    test('and the same word cannot be pinned twice', () async {
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      expect(await pinnedRowOf(db, eat), isNotNull);
      expect(await refusalToPin(db, eat), contains('already pinned'));
    });

    test('a refusal is enforced here too, not only by the screen', () async {
      // A rule enforced only by the screen that shows it is a rule with a way
      // round it. The message is asserted, not just the throw: without the
      // guard this still throws, on an empty list, which would be the right
      // outcome for the wrong reason.
      final vocabulary = await seed(rows: 7);
      final eat = await word(vocabulary, 'eat');

      await expectLater(
        pinWord(db, eat),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'the refusal a caregiver would have read',
            contains('full'),
          ),
        ),
      );
    });

    test('and it refuses a key every board already carries', () async {
      // This grid has room, so nothing else would stop it: without the guard
      // the frame's own keys get copied into the pinned column.
      final vocabulary = await seed();
      final home =
          await (db.select(db.buttons)
                ..where((b) => b.vocabularyId.equals(vocabulary.id))
                ..where((b) => b.isSystem.equals(true)))
              .get();

      await expectLater(
        pinWord(db, home.first),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'the refusal',
            contains('already on every board'),
          ),
        ),
      );
      expect(await freePinnedRows(db, vocabulary), isNotEmpty);
    });
  });

  group('what unpinning does', () {
    test('gives every location back, still reserved', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      final free = await freePinnedRows(db, vocabulary);

      await pinWord(db, eat);
      await unpinWord(db, vocabulary: vocabulary, row: free.first);

      expect(await freePinnedRows(db, vocabulary), free);
      expect(await inPinnedColumn(vocabulary, 'eat'), isEmpty);
    });

    test('and cannot strand the word, because it never moved', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      final free = await freePinnedRows(db, vocabulary);

      await pinWord(db, eat);
      await unpinWord(db, vocabulary: vocabulary, row: free.first);

      final after = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(eat.id))).getSingle();
      expect(after.cellId, eat.cellId);
      expect(after.deletedAt, isNull);
    });

    test('and a row with nothing on it is left alone', () async {
      final vocabulary = await seed();
      final free = await freePinnedRows(db, vocabulary);
      final before = await db.select(db.cells).get();

      await unpinWord(db, vocabulary: vocabulary, row: free.first);

      expect(await db.select(db.cells).get(), before);
    });

    test(
      'but a question word in that column is a pin like any other',
      () async {
        // The questions are not a different kind of thing — §4.16's whole
        // observation is that they are ordinary vocabulary that happens to be
        // pinned. So this reaches them, and the only protection against doing
        // it by accident is that nothing offers a bare row number: the editor
        // asks `pinnedRowOf` for the word in front of it.
        final vocabulary = await seed();
        final what = (await inPinnedColumn(vocabulary, 'what')).first;
        final row = await pinnedRowOf(db, what);
        expect(row, isNotNull, reason: 'the premise');

        await unpinWord(db, vocabulary: vocabulary, row: row!);

        expect(await inPinnedColumn(vocabulary, 'what'), isEmpty);
        expect(await freePinnedRows(db, vocabulary), contains(row));
      },
    );
  });

  group('a word that lives in the pinned column and nowhere else', () {
    test('is not a pin of anything', () async {
      final vocabulary = await seed();
      final what = (await inPinnedColumn(vocabulary, 'what')).first;

      // Unpinning it would be a deletion wearing the word "unpin": it has no
      // home to fall back to, so "the word keeps the location it has always
      // had" would be false of it.
      expect(await livesInPinnedColumn(db, what), isTrue);
    });

    test('and an ordinary word is not one of them', () async {
      final vocabulary = await seed();
      expect(
        await livesInPinnedColumn(db, await word(vocabulary, 'eat')),
        isFalse,
      );
    });

    test(
      'but a pinned copy is, which is why the copy is not re-pinnable',
      () async {
        final vocabulary = await seed();
        await pinWord(db, await word(vocabulary, 'eat'));

        final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
        expect(await livesInPinnedColumn(db, copy), isTrue);
        expect(await refusalToPin(db, copy), isNotNull);
      },
    );
  });

  group('what a caregiver is told it costs', () {
    test('locations, one per board, not one', () {
      final said = pinCost(label: 'eat', boards: 11);
      expect(said, contains('11 locations'));
      expect(said, contains('11 boards'));
      expect(said, contains('keeps the location it has now'));
    });

    test('and it reads correctly for a board set of one', () {
      final said = pinCost(label: 'eat', boards: 1);
      expect(said, contains('1 location'));
      expect(said, isNot(contains('1 locations')));
    });
  });
}
