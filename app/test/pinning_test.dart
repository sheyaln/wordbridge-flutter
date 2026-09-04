import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/frame_keys.dart';
import 'package:wordbridge/features/editor/pinning.dart';
import 'package:wordbridge/features/editor/remap.dart';

/// §4.16. One word reachable from every board, at the same coordinates.
///
/// Two decisions under test, and they pull in opposite directions on purpose.
///
/// **A pin is a copy, not a move.** The word keeps the location it already has
/// and gains a second, shorter route to itself — which is what makes unpinning
/// safe, because nothing was displaced to make room and nothing has to be put
/// back.
///
/// **What it copies is the location, never the word.** The two rows are one
/// word: an edit to either reaches both, hiding it takes it off both, and
/// removing it removes both. Without that, a caregiver who fixed the picture
/// on the pinned copy left the original showing the old one, and the board
/// carried two things that looked like one and had stopped agreeing — to
/// somebody with no way to report it.
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

    // `buttons.symbol_id` is a foreign key, so the picture has to exist before
    // anything can point at it.
    await db
        .into(db.symbols)
        .insert(
          SymbolsCompanion.insert(
            id: 'chosen-picture',
            source: SymbolSource.custom,
            label: 'chosen',
            license: '',
            attribution: '',
            createdAt: nowMs(),
          ),
        );

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

  /// §4.66. The pinned column holds two different kinds of thing and the
  /// editor could not tell them apart, so it offered the pinned copy of a word
  /// the chance to be pinned.
  group('telling a pinned copy from a word that lives there', () {
    test('a copy knows it is one', () async {
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
      expect(await livesInPinnedColumn(db, copy), isTrue, reason: 'premise');
      expect(await isPinnedCopy(db, copy), isTrue);
    });

    test(
      'a question word does not, because it has no home elsewhere',
      () async {
        // Unpinning this would be a deletion wearing the word unpin, which is
        // the whole reason the two cases have to be separable.
        final vocabulary = await seed();
        final what = (await inPinnedColumn(vocabulary, 'what')).first;

        expect(await livesInPinnedColumn(db, what), isTrue, reason: 'premise');
        expect(await isPinnedCopy(db, what), isFalse);
      },
    );

    test('and the original of a pinned word is not a copy either', () async {
      // It lives on a category board. The copy is the thing in the column.
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      expect(await isPinnedCopy(db, eat), isFalse);
    });

    test('a word that was never pinned is not a copy', () async {
      final vocabulary = await seed(rows: 10);
      expect(await isPinnedCopy(db, await word(vocabulary, 'eat')), isFalse);
    });

    test('a system key is never a copy', () async {
      final vocabulary = await seed();
      final home =
          await (db.select(db.buttons)
                ..where((b) => b.vocabularyId.equals(vocabulary.id))
                ..where((b) => b.isSystem.equals(true)))
              .get();

      expect(await isPinnedCopy(db, home.first), isFalse);
    });
  });

  group('unpinning from the copy', () {
    test('the copy knows which row it is on', () async {
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
      expect(await rowInPinnedColumn(db, copy), await pinnedRowOf(db, eat));
    });

    test('and a word outside the column is on no row of it', () async {
      final vocabulary = await seed(rows: 10);
      expect(
        await rowInPinnedColumn(db, await word(vocabulary, 'eat')),
        isNull,
      );
    });

    test('so unpinning works from either end', () async {
      // The copy is where somebody looks to get rid of it. Before §4.66 the
      // only way was to find the original on whatever board it lives on.
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
      final row = await rowInPinnedColumn(db, copy);
      expect(row, isNotNull, reason: 'premise');

      await unpinWord(db, vocabulary: vocabulary, row: row!);

      expect(await inPinnedColumn(vocabulary, 'eat'), isEmpty);
      // And the word itself is untouched, which is what makes it safe.
      final still = await word(vocabulary, 'eat');
      expect(still.cellId, eat.cellId);
    });
  });

  /// A location on this board that nothing holds, outside the frame.
  ///
  /// The system row and the pinned column are both spoken for, and a word
  /// moved onto either is refused (§4.43) or is a pin rather than a move.
  Future<Cell> spareCellOn(Vocabulary vocabulary, String boardId) async {
    final cell =
        await (db.select(db.cells)
              ..where((c) => c.boardId.equals(boardId))
              ..where((c) => c.state.equalsValue(CellState.emptyReserved))
              ..where((c) => c.col.isNotValue(pinnedColumn(vocabulary)))
              ..where((c) => c.row.isSmallerThanValue(vocabulary.gridRows - 1))
              ..orderBy([
                (c) => OrderingTerm.asc(c.row),
                (c) => OrderingTerm.asc(c.col),
              ])
              ..limit(1))
            .getSingleOrNull();
    expect(cell, isNotNull, reason: 'the premise: this grid has reserve');
    return cell!;
  }

  Future<Button> reread(String id) =>
      (db.select(db.buttons)..where((b) => b.id.equals(id))).getSingle();

  /// §4.66 again, and the rule it did not go far enough for: a pin and the
  /// word it was pinned from are one word, so an edit to either is an edit to
  /// the word.
  group('a pin and the word it was pinned from are one word', () {
    test('the pin records which word it is a pin of', () async {
      // The link, not the label. A label is not an identity: two words can be
      // spelled the same on purpose, and the moment a label match would come
      // apart is the moment somebody renames one of them.
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copies = await inPinnedColumn(vocabulary, 'eat');
      expect(copies, isNotEmpty, reason: 'the premise');
      expect(copies.every((c) => c.pinnedFromId == eat.id), isTrue);
    });

    test('and the word is the same set asked from either end', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copies = await inPinnedColumn(vocabulary, 'eat');
      final whole = {eat.id, for (final c in copies) c.id};

      expect({for (final b in await wordFamily(db, eat)) b.id}, whole);
      expect({for (final b in await wordFamily(db, copies.first)) b.id}, whole);
    });

    test('a picture chosen on the original reaches every pin', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      await setButtonSymbol(db, eat, 'chosen-picture');

      final copies = await inPinnedColumn(vocabulary, 'eat');
      expect(copies, isNotEmpty, reason: 'the premise');
      for (final copy in copies) {
        expect(copy.symbolId, 'chosen-picture');
      }
    });

    test('and one chosen on a pin reaches the original', () async {
      // The pinned column is where a caregiver is looking when they notice the
      // picture is wrong, because it is the one they see from every board.
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
      await setButtonSymbol(db, copy, 'chosen-picture');

      expect((await reread(eat.id)).symbolId, 'chosen-picture');
      for (final other in await inPinnedColumn(vocabulary, 'eat')) {
        expect(other.symbolId, 'chosen-picture');
      }
    });

    test('hiding it takes it off every route to it', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      final free = await freePinnedRows(db, vocabulary);
      await pinWord(db, eat);

      await RemapService(db).setHidden(buttonId: eat.id, hidden: true);

      expect((await reread(eat.id)).hidden, isTrue);
      for (final copy in await inPinnedColumn(vocabulary, 'eat')) {
        expect(copy.hidden, isTrue);
      }
      // Hiding never releases a location (§2), and a pinned one is no
      // different — the row stays spoken for.
      expect(await freePinnedRows(db, vocabulary), isNot(contains(free.first)));
    });

    test('and showing it again from the pin brings all of it back', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final remap = RemapService(db);
      await remap.setHidden(buttonId: eat.id, hidden: true);

      final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
      await remap.setHidden(buttonId: copy.id, hidden: false);

      expect((await reread(eat.id)).hidden, isFalse);
      for (final other in await inPinnedColumn(vocabulary, 'eat')) {
        expect(other.hidden, isFalse);
      }
    });

    test('a word pinned while hidden does not come back on', () async {
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      await RemapService(db).setHidden(buttonId: eat.id, hidden: true);

      await pinWord(db, await reread(eat.id));

      for (final copy in await inPinnedColumn(vocabulary, 'eat')) {
        expect(copy.hidden, isTrue, reason: 'the pin put a hidden word back');
      }
    });

    test('but no edit to it moves any of it', () async {
      // Content is the word's; a location is the row's. This is the whole of
      // the distinction, and the thing a write-through could quietly destroy.
      final vocabulary = await seed();
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final before = {
        for (final b in await wordFamily(db, eat)) b.id: b.cellId,
      };

      await setButtonSymbol(db, eat, 'chosen-picture');
      await RemapService(db).setHidden(buttonId: eat.id, hidden: true);

      expect({
        for (final b in await wordFamily(db, eat)) b.id: b.cellId,
      }, before);
    });

    test('and moving one location leaves the others where they are', () async {
      // Two locations, deliberately. A pin is a second route to the word, so
      // moving the word's own location shortens nothing about the pin.
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copies = await inPinnedColumn(vocabulary, 'eat');
      final home = await (db.select(
        db.cells,
      )..where((c) => c.id.equals(eat.cellId!))).getSingle();
      final target = await spareCellOn(vocabulary, home.boardId);

      await RemapService(db).moveButton(buttonId: eat.id, toCellId: target.id);

      expect((await reread(eat.id)).cellId, target.id);
      for (final copy in copies) {
        expect((await reread(copy.id)).cellId, copy.cellId);
      }
    });

    test('and two words spelled the same are still two words', () async {
      // What the label match got wrong. A caregiver may deliberately place a
      // second "eat" — a phrase board, a second sense — and an edit to the
      // pinned one has no business reaching it.
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final boards = await boardsOf(vocabulary);
      final spare = await spareCellOn(vocabulary, boards.first.id);
      final twin = await placeButton(
        db,
        vocabularyId: vocabulary.id,
        cellId: spare.id,
        label: 'eat',
        message: 'eat',
      );

      await setButtonSymbol(db, eat, 'chosen-picture');

      expect((await reread(twin)).symbolId, isNull);
    });

    test('a pin whose original went with a board is not a copy', () async {
      // Removing a board marks every word on it deleted. The pin is then the
      // only route left to that word, and offering to unpin it would be the
      // §4.66 failure wearing a different hat: a deletion wearing the word
      // unpin.
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      await (db.update(db.buttons)..where((b) => b.id.equals(eat.id))).write(
        const ButtonsCompanion(cellId: Value(null), deletedAt: Value(1)),
      );

      final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
      expect(await isPinnedCopy(db, copy), isFalse);
    });
  });

  /// Removing a word that has more than one location.
  ///
  /// A pin is a second route to the word rather than a second word, so a route
  /// left behind after the word is gone leads somewhere it no longer is — from
  /// every board at once, since that is what the pinned column is.
  group('removing a pinned word', () {
    test('takes every location it holds', () async {
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      final free = await freePinnedRows(db, vocabulary);
      await pinWord(db, eat);

      await RemapService(db).deleteButton(buttonId: eat.id);

      expect(await inPinnedColumn(vocabulary, 'eat'), isEmpty);
      expect(
        await freePinnedRows(db, vocabulary),
        free,
        reason: 'the pinned locations did not go back to reserved',
      );

      final gone = await reread(eat.id);
      expect(gone.deletedAt, isNotNull);
      expect(gone.cellId, isNull);
    });

    test('and does so from the pinned column too', () async {
      // Removing the word is removing the word, whichever route it was reached
      // by. Taking the pin back and keeping the word is unpinning, which the
      // editor offers directly above this.
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final copy = (await inPinnedColumn(vocabulary, 'eat')).first;
      await RemapService(db).deleteButton(buttonId: copy.id);

      expect((await reread(eat.id)).deletedAt, isNotNull);
      expect(await inPinnedColumn(vocabulary, 'eat'), isEmpty);
    });

    test('and undo puts every one of them back', () async {
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      final free = await freePinnedRows(db, vocabulary);
      await pinWord(db, eat);

      final boards = await boardsOf(vocabulary);
      final remap = RemapService(db);
      await remap.deleteButton(buttonId: eat.id);

      expect(await remap.restoreButton(eat.id), isTrue);

      expect((await reread(eat.id)).cellId, eat.cellId);
      expect(await inPinnedColumn(vocabulary, 'eat'), hasLength(boards.length));
      expect(await freePinnedRows(db, vocabulary), free.skip(1).toList());
    });

    test('and puts none back if one of the locations is taken', () async {
      // A half-applied undo is the worst outcome available: a word restored on
      // some boards and missing on others, on a board somebody navigates by
      // muscle memory.
      final vocabulary = await seed(rows: 10);
      final eat = await word(vocabulary, 'eat');
      await pinWord(db, eat);

      final freed = (await inPinnedColumn(vocabulary, 'eat')).first.cellId!;
      final remap = RemapService(db);
      await remap.deleteButton(buttonId: eat.id);

      await placeButton(
        db,
        vocabularyId: vocabulary.id,
        cellId: freed,
        label: 'drum',
        message: 'drum',
      );

      expect(await remap.restoreButton(eat.id), isFalse);
      expect((await reread(eat.id)).deletedAt, isNotNull);
      expect((await reread(eat.id)).cellId, isNull);
    });
  });
}
