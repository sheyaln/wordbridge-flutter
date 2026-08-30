import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/frame_keys.dart';

/// A key every board carries is one key, not one key per board.
///
/// Reported: changing the picture on `more words` or `more categories` on one
/// board left every other board showing the old one. They are stored a row per
/// board — a location is a row, and each board needs its own — but to the
/// person using them there is one key, in one place, doing one thing, wherever
/// they are. A picture that changes from board to board makes one movement look
/// like several different keys, which is what the fixed frame exists to prevent.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

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
  });

  tearDown(() async => db.close());

  Future<List<Button>> named(String label) =>
      (db.select(db.buttons)..where(
            (b) => b.vocabularyId.equals(vocabId) & b.label.equals(label),
          ))
          .get();

  Future<Button> onBoard(String label, String boardName) async {
    final board = await (db.select(
      db.boards,
    )..where((b) => b.name.equals(boardName))).getSingle();

    final rows =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.buttons.label.equals(label) &
                  db.cells.boardId.equals(board.id),
            ))
            .get();

    return rows.single.readTable(db.buttons);
  }

  group('a key every board carries', () {
    test('finds its copies on the other boards', () async {
      final key = await onBoard(moreWordsLabel, 'home');
      final siblings = await frameSiblings(db, key);

      // Every board that has a page to go to carries one.
      expect(siblings, isNotEmpty);
      expect(
        {for (final b in siblings) b.id}..add(key.id),
        {for (final b in await named(moreWordsLabel)) b.id},
        reason:
            'a copy of the key was left out, so it would keep the old '
            'picture',
      );
    });

    test('the cycle key too', () async {
      final key = await onBoard(cycleCategoriesLabel, 'home');
      expect(await frameSiblings(db, key), isNotEmpty);
    });

    test('and home, which is on every board there is', () async {
      final key = await onBoard('home', 'food');
      final siblings = await frameSiblings(db, key);

      final boards = await db.select(db.boards).get();
      expect(
        siblings.length,
        boards.length - 1,
        reason: 'home is on every board, so every other one is a copy',
      );
    });

    test('a pinned question, which is a word rather than a key', () async {
      // Ordinary vocabulary that happens to be pinned. It keeps its
      // part-of-speech colour and stays editable — and it is still the same
      // word at the same location on every board.
      final key = await onBoard('what', 'home');
      expect(await frameSiblings(db, key), isNotEmpty);
    });
  });

  group('an ordinary word', () {
    test('is a copy of nothing', () async {
      final key = await onBoard('want', 'home');
      expect(
        await frameSiblings(db, key),
        isEmpty,
        reason:
            'a word in the content area is one word in one place, and giving '
            'it a picture must not reach across boards',
      );
    });

    test('put on a paging location is still its own word', () async {
      // The last page has no forward key, so its location is free for a
      // caregiver to use. What they put there is not a copy of `more words`.
      final pages = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home 2'))).getSingle();

      final frame = SystemFrame.parse(
        (await (db.select(
          db.vocabularies,
        )..where((v) => v.id.equals(vocabId))).getSingle()).systemCellMap,
      )!;

      final cell = await cellAt(
        db,
        boardId: pages.id,
        row: frame.row,
        col: frame.pageForwardCol,
      );
      final id = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'biscuit',
        message: 'biscuit',
      );

      final placed = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();

      expect(
        await frameSiblings(db, placed),
        isEmpty,
        reason: 'an ordinary word took the picture meant for the paging key',
      );
    });
  });

  group('choosing a picture for one', () {
    test('puts it on every board at once', () async {
      // The reported bug, stated as the fix. Written through the one writer
      // rather than the picker, because the picker is a sheet and the defect
      // was in what it wrote, not in how it looked.
      final key = await onBoard(moreWordsLabel, 'home');
      await setButtonSymbol(db, key, 'chosen-picture');

      final copies = await named(moreWordsLabel);
      expect(copies.length, greaterThan(1));
      expect(
        copies.map((b) => b.symbolId).toSet(),
        {'chosen-picture'},
        reason:
            'one movement, one key — a picture that stops at the board the '
            'caregiver had open makes it look like several',
      );
    });

    test('leaves an ordinary word to itself', () async {
      final want = await onBoard('want', 'home');
      await setButtonSymbol(db, want, 'chosen-picture');

      final touched =
          await (db.select(db.buttons)..where(
                (b) =>
                    b.vocabularyId.equals(vocabId) &
                    b.symbolId.equals('chosen-picture'),
              ))
              .get();

      expect(touched.map((b) => b.id), [want.id]);
    });

    test('records one edit, against the button the caregiver opened', () async {
      final key = await onBoard(moreWordsLabel, 'home');
      await setButtonSymbol(db, key, 'chosen-picture');

      final events = await db.select(db.editEvents).get();
      expect(events, hasLength(1));
      expect(events.single.kind, EditKind.resymbol);
      expect(events.single.buttonId, key.id);
    });

    test(
      'records what the picture replaced, so it can be taken back',
      () async {
        // An edit recorded without what it replaced is one nothing can reverse:
        // the trail says a picture changed and cannot say to what from.
        final key = await onBoard(moreWordsLabel, 'home');
        final was = key.symbolId;

        await setButtonSymbol(db, key, 'chosen-picture');

        final event = await db.select(db.editEvents).getSingle();
        expect(jsonDecode(event.beforeJson!), {'symbolId': was});
        expect(jsonDecode(event.afterJson!), {'symbolId': 'chosen-picture'});
      },
    );
  });

  test(
    'a category key is a copy too, where it draws its own picture',
    () async {
      // On a grid wide enough that every category has a permanent slot, the key
      // draws the picture on the button. On a narrower one the wheel turns and
      // the slot takes its picture from whichever category it is showing, so a
      // chosen one is ignored — this is the case where it is not.
      final wide = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(wide.close);
      final id = await seedCoreBoardSet(wide, rows: 7, cols: 14);

      final frame = SystemFrame.parse(
        (await (wide.select(
          wide.vocabularies,
        )..where((v) => v.id.equals(id))).getSingle()).systemCellMap,
      )!;
      expect(
        frame.showsEveryCategory,
        isTrue,
        reason: 'the premise: this grid does not turn the wheel',
      );

      final home = await (wide.select(
        wide.boards,
      )..where((b) => b.name.equals('home'))).getSingle();
      final cell = await cellAt(
        wide,
        boardId: home.id,
        row: frame.row,
        col: frame.categoryCols.first,
      );
      final key = await (wide.select(
        wide.buttons,
      )..where((b) => b.cellId.equals(cell.id))).getSingle();

      expect(await frameSiblings(wide, key), isNotEmpty);
    },
  );

  test('a board set with no frame recorded has no copies', () async {
    // An imported board set, or one built before the frame was written down.
    // Nothing on it is known to be a key every board carries, so nothing on it
    // may be edited on another board's behalf.
    await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId)))
        .write(const VocabulariesCompanion(systemCellMap: Value('')));

    final key = await onBoard('home', 'food');
    expect(await frameSiblings(db, key), isEmpty);
  });
}
