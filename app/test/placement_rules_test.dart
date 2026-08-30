import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/placement_rules.dart';
import 'package:wordbridge/features/editor/remap.dart';

/// The system row is not for words (§4.43).
///
/// It is the row that undoes things — home, back, the category keys, the key
/// that turns them — and the gap in it exists so a reach for one does not land
/// on the other. A word there speaks in a row that navigates, spends that gap,
/// and can block a category board that has not shipped yet.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;
  late Vocabulary vocab;
  late SystemFrame frame;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabId))).getSingle();
    frame = SystemFrame.parse(vocab.systemCellMap)!;
  });

  tearDown(() async => db.close());

  Future<Board> boardNamed(String name) =>
      (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

  Future<Cell> freeCellOnRow(String boardId, int row) async {
    final cells =
        await (db.select(db.cells)..where(
              (c) =>
                  c.boardId.equals(boardId) &
                  c.row.equals(row) &
                  c.state.equalsValue(CellState.emptyReserved),
            ))
            .get();
    return cells.first;
  }

  group('a location on the system row', () {
    test('is refused, with a reason a caregiver can act on', () async {
      final why = await refusalToPlaceAt(
        db,
        vocabularyId: vocabId,
        row: frame.row,
      );

      expect(why, isNotNull);
      expect(
        why,
        contains('back'),
        reason: 'the refusal does not say what the row is for',
      );
      expect(
        why,
        contains('free location'),
        reason: 'a refusal with nowhere to go instead is a dead end',
      );
    });

    test('is refused even where the row has a location going spare', () async {
      // The gap between the pair that undo and the keys that go somewhere new.
      // It is empty on purpose, which is exactly why it looks available.
      final home = await boardNamed('home');
      final spare = await freeCellOnRow(home.id, frame.row);

      expect(
        await refusalToPlaceAt(db, vocabularyId: vocabId, row: spare.row),
        isNotNull,
      );
    });
  });

  group('everywhere else', () {
    test('the content area takes a word', () async {
      for (var row = 0; row < frame.row; row++) {
        expect(
          await refusalToPlaceAt(db, vocabularyId: vocabId, row: row),
          isNull,
          reason: 'row $row was refused, and it is not the system row',
        );
      }
    });

    test('a board set with no frame recorded refuses nothing', () async {
      // An imported board set, or one built by hand. Nothing on it is known to
      // be a system row, and refusing on a guess would take locations away
      // from a board that never had one to protect.
      await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId)))
          .write(const VocabulariesCompanion(systemCellMap: Value('')));

      expect(
        await refusalToPlaceAt(db, vocabularyId: vocabId, row: frame.row),
        isNull,
      );
    });

    test('a vocabulary that is not there refuses nothing', () async {
      expect(
        await refusalToPlaceAt(db, vocabularyId: 'gone', row: frame.row),
        isNull,
      );
    });
  });

  group('moving a word onto it', () {
    test('is refused by the writer, not only by the screen', () async {
      // The editor asks before it offers the move. This is the guard for a
      // path that does not — one rule, asked in one place.
      final home = await boardNamed('home');
      final target = await freeCellOnRow(home.id, frame.row);

      final word =
          await (db.select(db.buttons)
                ..where((b) => b.vocabularyId.equals(vocabId))
                ..where((b) => b.isSystem.equals(false))
                ..limit(1))
              .getSingle();

      await expectLater(
        RemapService(db).moveButton(buttonId: word.id, toCellId: target.id),
        throwsA(isA<StateError>()),
      );

      final after = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(word.id))).getSingle();
      expect(
        after.cellId,
        word.cellId,
        reason: 'the word moved anyway, and the throw came too late',
      );
    });

    test('a frame key itself still moves where the frame puts it', () async {
      // The rule is about a caregiver's own words. The keys that belong on
      // that row are placed there by the seed and must stay placeable.
      final home = await boardNamed('home');
      final key =
          await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])..where(
                db.buttons.isSystem.equals(true) &
                    db.cells.boardId.equals(home.id) &
                    db.cells.row.equals(frame.row),
              ))
              .get();

      expect(key, isNotEmpty, reason: 'the premise: the row carries keys');

      final target = await freeCellOnRow(home.id, frame.row);
      await RemapService(db).moveButton(
        buttonId: key.first.readTable(db.buttons).id,
        toCellId: target.id,
      );

      final moved =
          await (db.select(db.buttons)
                ..where((b) => b.id.equals(key.first.readTable(db.buttons).id)))
              .getSingle();
      expect(moved.cellId, target.id);
    });
  });

  test('a word already on the row is left alone', () async {
    // Removing one would be a displacing edit nobody asked for, on the row
    // where a movement is most likely to have been learned.
    final home = await boardNamed('home');
    final cell = await freeCellOnRow(home.id, frame.row);

    final id = await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: 'Nana',
      message: 'Nana',
    );

    final still = await (db.select(
      db.buttons,
    )..where((b) => b.id.equals(id))).getSingle();
    expect(still.cellId, cell.id);
  });
}
