import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/remap.dart';
import 'package:wordbridge/features/usage/logger.dart';

void main() {
  late WordbridgeDatabase db;
  late RemapService remap;
  late UsageLogger logger;
  late String vocabId;
  late String boardId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    remap = RemapService(db);
    logger = UsageLogger(db, deviceId: 'test')..enabled = true;

    vocabId = newId();
    final ts = nowMs();
    await db
        .into(db.vocabularies)
        .insert(
          VocabulariesCompanion.insert(
            id: vocabId,
            name: 'test',
            gridRows: 7,
            gridCols: 12,
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    boardId = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: 'home',
      kind: BoardKind.root,
    );
  });

  tearDown(() async => db.close());

  Future<String> placeAt(int row, int col, String label) async {
    final cell = await cellAt(db, boardId: boardId, row: row, col: col);
    return placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: label,
    );
  }

  Future<void> recordTaps(String buttonId, int count) async {
    final button = await (db.select(
      db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingle();
    for (var i = 0; i < count; i++) {
      logger.log(
        profileId: 'p1',
        vocabularyId: vocabId,
        boardId: boardId,
        cellId: button.cellId!,
        buttonId: buttonId,
        label: button.label,
        action: ButtonAction.speak,
        source: UsageSource.touch,
      );
    }
    await logger.flush();
  }

  group('impact reflects practice at the location', () {
    test('an unused word carries no warning', () async {
      final id = await placeAt(0, 0, 'eat');
      expect(await remap.warningFor(id), isNull);
    });

    test('a lightly used word warns without alarm', () async {
      final id = await placeAt(0, 0, 'eat');
      await recordTaps(id, 3);

      final warning = await remap.warningFor(id, userName: 'Maya');
      expect(warning, contains('3 times'));
      expect(warning, contains('low risk'));
    });

    test(
      'a learned position states the cost in the user\'s own numbers',
      () async {
        final id = await placeAt(2, 3, 'eat');
        await recordTaps(id, 341);

        final warning = await remap.warningFor(id, userName: 'Maya');
        expect(warning, contains('Maya'));
        expect(warning, contains('341'));
        expect(warning, contains('"eat"'));
        expect(warning, contains('relearn'));
        expect(
          warning,
          contains('in the last ${RemapService.practiceWindow.days} days'),
          reason:
              'a rebuild counts the same cell over its whole history, so a '
              'count shown without its span reads as whichever the caregiver '
              'assumes',
        );
      },
    );

    test('partner modelling does not count as the user\'s practice', () async {
      final id = await placeAt(0, 0, 'eat');
      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();

      for (var i = 0; i < 50; i++) {
        logger.log(
          profileId: 'p1',
          vocabularyId: vocabId,
          boardId: boardId,
          cellId: button.cellId!,
          buttonId: id,
          label: 'eat',
          action: ButtonAction.speak,
          // A communication partner demonstrating the word teaches the user,
          // but it is not evidence the user knows where it is.
          source: UsageSource.partnerModel,
        );
      }
      await logger.flush();

      expect(await remap.warningFor(id), isNull);
    });

    test('a word taken from the suggestions is not practice either', () async {
      final id = await placeAt(0, 0, 'eat');
      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();

      for (var i = 0; i < 50; i++) {
        logger.log(
          profileId: 'p1',
          vocabularyId: vocabId,
          boardId: boardId,
          cellId: button.cellId!,
          buttonId: id,
          label: 'eat',
          action: ButtonAction.speak,
          // The word does live here, so this is the right location to record
          // against. But the user pressed the prediction strip, not this
          // spot, so it is no evidence they know where the spot is.
          source: UsageSource.prediction,
        );
      }
      await logger.flush();

      expect(
        await remap.warningFor(id),
        isNull,
        reason:
            'a warning inflated by suggestions would talk a caregiver out '
            'of a move that costs nothing',
      );
    });
  });

  group('moving a word', () {
    test('relocates it and frees the old location', () async {
      final id = await placeAt(1, 1, 'eat');
      final target = await cellAt(db, boardId: boardId, row: 5, col: 5);

      await remap.moveButton(buttonId: id, toCellId: target.id);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(button.cellId, target.id);

      final old = await cellAt(db, boardId: boardId, row: 1, col: 1);
      expect(old.state, CellState.emptyReserved);

      final moved = await cellAt(db, boardId: boardId, row: 5, col: 5);
      expect(moved.state, CellState.occupied);
    });

    test('refuses to overwrite an occupied location', () async {
      final a = await placeAt(0, 0, 'eat');
      await placeAt(0, 1, 'drink');
      final occupied = await cellAt(db, boardId: boardId, row: 0, col: 1);

      expect(
        () => remap.moveButton(buttonId: a, toCellId: occupied.id),
        throwsStateError,
      );
    });

    test('records the cost it incurred', () async {
      final id = await placeAt(2, 2, 'eat');
      await recordTaps(id, 87);
      final target = await cellAt(db, boardId: boardId, row: 4, col: 4);

      await remap.moveButton(buttonId: id, toCellId: target.id);

      final event = await db.select(db.editEvents).getSingle();
      expect(event.kind, EditKind.remap);
      expect(
        event.motorImpactTaps,
        87,
        reason:
            'the audit trail must say what the move cost, not just that '
            'it happened',
      );
    });
  });

  group('undo', () {
    test('puts a moved word back exactly where it was', () async {
      final id = await placeAt(3, 3, 'eat');
      final target = await cellAt(db, boardId: boardId, row: 6, col: 6);

      await remap.moveButton(buttonId: id, toCellId: target.id);
      expect(await remap.undoLast(vocabId), isTrue);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      final original = await cellAt(db, boardId: boardId, row: 3, col: 3);
      expect(button.cellId, original.id);
      expect(original.state, CellState.occupied);
    });
  });

  group('hiding', () {
    test('does not release the location', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await remap.setHidden(buttonId: id, hidden: true);

      final cell = await cellAt(db, boardId: boardId, row: 1, col: 2);
      expect(
        cell.state,
        CellState.occupied,
        reason:
            'a freed location would be taken by the next word added, '
            'displacing this one when it is revealed',
      );

      expect(
        () => placeButton(
          db,
          vocabularyId: vocabId,
          cellId: cell.id,
          label: 'something else',
          message: 'something else',
        ),
        throwsStateError,
      );
    });
  });

  group('hiding a key every board carries', () {
    Future<String> placeSystemHome() async {
      final cell = await cellAt(db, boardId: boardId, row: 6, col: 0);
      return placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'home',
        message: '',
        action: ButtonAction.home,
        isSystem: true,
      );
    }

    test('is refused', () async {
      final id = await placeSystemHome();

      expect(
        () => remap.setHidden(buttonId: id, hidden: true),
        throwsStateError,
        reason: 'a hidden home key is a board an AAC user cannot leave',
      );

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(button.hidden, isFalse);
    });

    test('unhiding one is not refused', () async {
      // Only the direction that takes a key away is blocked. Refusing to
      // restore one would leave a board built before this rule with no way
      // back.
      final id = await placeSystemHome();
      await (db.update(db.buttons)..where((b) => b.id.equals(id))).write(
        const ButtonsCompanion(hidden: Value(true)),
      );

      await remap.setHidden(buttonId: id, hidden: false);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(button.hidden, isFalse);
    });
  });

  group('deleting', () {
    test('releases the location, which is what hiding does not', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await remap.deleteButton(buttonId: id);

      final cell = await cellAt(db, boardId: boardId, row: 1, col: 2);
      expect(
        cell.state,
        CellState.emptyReserved,
        reason: 'a delete that held the location would just be a hide',
      );

      // The whole cost of the operation, stated as a test: whatever is put
      // here next is reached by the movement the deleted word had.
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'something else',
        message: 'something else',
      );
    });

    test('keeps the row so the history still resolves', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await recordTaps(id, 5);
      await remap.deleteButton(buttonId: id);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingleOrNull();

      expect(button, isNotNull, reason: 'a hard delete strands usage rows');
      expect(button!.deletedAt, isNotNull);
      expect(button.cellId, isNull);
    });

    test('refuses a key every board carries', () async {
      final cell = await cellAt(db, boardId: boardId, row: 6, col: 0);
      final id = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'home',
        message: '',
        action: ButtonAction.home,
        isSystem: true,
      );

      expect(() => remap.deleteButton(buttonId: id), throwsStateError);
      expect(
        (await cellAt(db, boardId: boardId, row: 6, col: 0)).state,
        CellState.occupied,
        reason: 'the refusal still let go of the location',
      );
    });

    test('records what the location had taken', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await recordTaps(id, 7);
      await remap.deleteButton(buttonId: id);

      final event = await (db.select(
        db.editEvents,
      )..where((e) => e.buttonId.equals(id))).getSingle();

      expect(event.kind, EditKind.delete);
      expect(event.motorImpactTaps, 7);
    });

    test('undo puts the word back where it was', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await remap.deleteButton(buttonId: id);

      expect(await remap.restoreButton(id), isTrue);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      final cell = await cellAt(db, boardId: boardId, row: 1, col: 2);

      expect(button.deletedAt, isNull);
      expect(button.cellId, cell.id);
      expect(cell.state, CellState.occupied);
    });

    test('undo refuses once something else holds the location', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await remap.deleteButton(buttonId: id);
      await placeAt(1, 2, 'swing');

      expect(
        await remap.restoreButton(id),
        isFalse,
        reason:
            'putting it somewhere else would be a move nobody asked for, and '
            'overwriting would cost the new word its location',
      );

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(button.deletedAt, isNotNull);
    });
  });
}
