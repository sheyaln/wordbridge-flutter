import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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

  Future<Button> buttonById(String id) =>
      (db.select(db.buttons)..where((b) => b.id.equals(id))).getSingle();

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
    Future<int> editCount() async =>
        (await db.select(db.editEvents).get()).length;

    Future<String> makeSymbol(String label) async {
      final id = newId();
      await db
          .into(db.symbols)
          .insert(
            SymbolsCompanion.insert(
              id: id,
              source: SymbolSource.bundled,
              label: label,
              license: 'CC0',
              attribution: 'test',
              createdAt: nowMs(),
            ),
          );
      return id;
    }

    Future<void> showPicture(String buttonId, String symbolId) async {
      await (db.update(db.buttons)..where((b) => b.id.equals(buttonId))).write(
        ButtonsCompanion(symbolId: Value(symbolId), updatedAt: Value(nowMs())),
      );
    }

    /// An audit row, written the way the feature that performs the edit writes
    /// one. Kinds nothing in this file performs are reached this way.
    Future<String> recordEdit({
      required EditKind kind,
      String? buttonId,
      Map<String, Object?>? before,
    }) async {
      final id = newId();
      await db
          .into(db.editEvents)
          .insert(
            EditEventsCompanion.insert(
              id: id,
              vocabularyId: vocabId,
              buttonId: Value(buttonId),
              kind: kind,
              beforeJson: Value(before == null ? null : jsonEncode(before)),
              changedAt: nowMs(),
            ),
          );
      return id;
    }

    /// Records a word being added, the way the board editor records it.
    Future<String> addWord(int row, int col, String label) async {
      final cell = await cellAt(db, boardId: boardId, row: row, col: col);
      final id = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: label,
        message: label,
      );
      // Through the one writer the board editor uses, so a record that stopped
      // naming the word would fail here rather than in front of a caregiver.
      await remap.recordCreate(
        vocabularyId: vocabId,
        buttonId: id,
        cellId: cell.id,
      );
      return id;
    }

    test('takes a word back off, and gives its location up', () async {
      // The reverse of adding is removing, not hiding. The location was free
      // before the word arrived, and the next word added there has to find it
      // free again rather than held by something nobody meant to keep.
      final id = await addWord(2, 4, 'trampoline');

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(button.deletedAt, isNotNull);
      expect(button.cellId, isNull);

      final cell = await cellAt(db, boardId: boardId, row: 2, col: 4);
      expect(cell.state, CellState.emptyReserved);
    });

    test('refuses to take back a word that has since moved', () async {
      // The recorded location is not where the word lives any more, and
      // freeing that cell would release one somebody else is being taught to
      // reach for.
      final id = await addWord(2, 4, 'trampoline');
      final away = await cellAt(db, boardId: boardId, row: 5, col: 5);
      await remap.moveButton(buttonId: id, toCellId: away.id);

      // The move first, which is the most recent edit.
      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      // Then the add, whose word is back where it started.
      expect(await remap.undoLast(vocabId), UndoOutcome.undone);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(button.deletedAt, isNotNull);
    });

    test('says whether it ran out of history or hit a full location', () async {
      // Two ways of doing nothing, and they are different things to be told.
      // "Nothing to undo" sent to somebody whose location is taken makes them
      // look for a history that is still there.
      expect(await remap.undoLast(vocabId), UndoOutcome.nothing);

      final id = await placeAt(1, 1, 'eat');
      await remap.deleteButton(buttonId: id);
      await placeAt(1, 1, 'swing');

      expect(await remap.undoLast(vocabId), UndoOutcome.blocked);
    });

    test('puts a moved word back exactly where it was', () async {
      final id = await placeAt(3, 3, 'eat');
      final target = await cellAt(db, boardId: boardId, row: 6, col: 6);

      await remap.moveButton(buttonId: id, toCellId: target.id);
      expect(await remap.undoLast(vocabId), UndoOutcome.undone);

      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      final original = await cellAt(db, boardId: boardId, row: 3, col: 3);
      expect(button.cellId, original.id);
      expect(original.state, CellState.occupied);
    });

    test('two moves come back one at a time, newest first', () async {
      final id = await placeAt(3, 3, 'eat');
      final second = await cellAt(db, boardId: boardId, row: 4, col: 4);
      final third = await cellAt(db, boardId: boardId, row: 5, col: 5);

      await remap.moveButton(buttonId: id, toCellId: second.id);
      await remap.moveButton(buttonId: id, toCellId: third.id);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      expect(
        (await buttonById(id)).cellId,
        second.id,
        reason:
            'stepping back two edits at once is a location the caregiver '
            'never chose',
      );

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      final first = await cellAt(db, boardId: boardId, row: 3, col: 3);
      expect((await buttonById(id)).cellId, first.id);
      expect(first.state, CellState.occupied);
      expect(
        (await cellAt(db, boardId: boardId, row: 4, col: 4)).state,
        CellState.emptyReserved,
      );
      expect(
        (await cellAt(db, boardId: boardId, row: 5, col: 5)).state,
        CellState.emptyReserved,
      );
    });

    test('an edit already taken back is not taken back again', () async {
      final id = await placeAt(3, 3, 'eat');
      final target = await cellAt(db, boardId: boardId, row: 6, col: 6);
      await remap.moveButton(buttonId: id, toCellId: target.id);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      expect(await remap.undoLast(vocabId), isNot(UndoOutcome.undone));

      final home = await cellAt(db, boardId: boardId, row: 3, col: 3);
      expect(
        (await buttonById(id)).cellId,
        home.id,
        reason:
            'a second press must not send the word back out to where the '
            'first press brought it from',
      );
      expect(
        (await cellAt(db, boardId: boardId, row: 6, col: 6)).state,
        CellState.emptyReserved,
      );
    });

    test('a move made after a hide is still reachable', () async {
      final id = await placeAt(1, 1, 'trampoline');
      await remap.setHidden(buttonId: id, hidden: true);
      final target = await cellAt(db, boardId: boardId, row: 2, col: 2);
      await remap.moveButton(buttonId: id, toCellId: target.id);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      final home = await cellAt(db, boardId: boardId, row: 1, col: 1);
      expect((await buttonById(id)).cellId, home.id);
      expect((await buttonById(id)).hidden, isTrue);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      expect((await buttonById(id)).hidden, isFalse);
      expect((await buttonById(id)).cellId, home.id);
    });

    test('hiding comes back without the location ever moving', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await remap.setHidden(buttonId: id, hidden: true);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);

      final cell = await cellAt(db, boardId: boardId, row: 1, col: 2);
      final button = await buttonById(id);
      expect(button.hidden, isFalse);
      expect(button.cellId, cell.id);
      expect(
        cell.state,
        CellState.occupied,
        reason:
            'hiding never released the location, so revealing has nothing '
            'to reclaim and nothing to take from anybody',
      );
    });

    test('unhiding comes back too', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await remap.setHidden(buttonId: id, hidden: true);
      await remap.setHidden(buttonId: id, hidden: false);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      expect((await buttonById(id)).hidden, isTrue);
      expect(
        (await cellAt(db, boardId: boardId, row: 1, col: 2)).state,
        CellState.occupied,
      );
    });

    test('re-hiding a key every board carries is refused', () async {
      final cell = await cellAt(db, boardId: boardId, row: 6, col: 0);
      final id = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'home',
        message: '',
        action: ButtonAction.home,
        isSystem: true,
        hidden: true,
      );
      await remap.setHidden(buttonId: id, hidden: false);

      expect(
        await remap.undoLast(vocabId),
        UndoOutcome.blocked,
        reason:
            'the undo button is not a way round the rule that keeps a way '
            'off the board',
      );
      expect((await buttonById(id)).hidden, isFalse);
    });

    test('a deleted word comes back through the same walk', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await remap.deleteButton(buttonId: id);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);

      final cell = await cellAt(db, boardId: boardId, row: 1, col: 2);
      final button = await buttonById(id);
      expect(button.deletedAt, isNull);
      expect(button.cellId, cell.id);
      expect(
        cell.state,
        CellState.occupied,
        reason:
            'deleting gave the location up, so undoing it has to take '
            'the same one back',
      );
    });

    test('a delete taken back by name is not taken back twice', () async {
      final id = await placeAt(1, 2, 'trampoline');
      final target = await cellAt(db, boardId: boardId, row: 5, col: 5);
      await remap.moveButton(buttonId: id, toCellId: target.id);
      await remap.deleteButton(buttonId: id);

      expect(await remap.restoreButton(id), isTrue);

      final deletes = await (db.select(
        db.editEvents,
      )..where((e) => e.kind.equalsValue(EditKind.delete))).get();
      expect(
        deletes,
        hasLength(1),
        reason:
            'the trail says what a board has been through, and the word '
            'having been taken off it is part of that',
      );

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);

      final button = await buttonById(id);
      expect(button.deletedAt, isNull);
      expect(
        button.cellId,
        (await cellAt(db, boardId: boardId, row: 1, col: 2)).id,
        reason:
            'the toast already put the word back, so the walk owes the '
            'caregiver the move before it',
      );
    });

    test('a removed board is not put back one word at a time', () async {
      final id = await placeAt(1, 2, 'trampoline');
      await recordEdit(
        kind: EditKind.delete,
        before: {'boardId': boardId, 'name': 'breakfast'},
      );

      expect(
        await remap.undoLast(vocabId),
        UndoOutcome.blocked,
        reason:
            'a board coming back is not one word going back to one cell, '
            'and restoring one of them would look like the board returned',
      );
      expect((await buttonById(id)).deletedAt, isNull);
    });

    test('a picture change comes back', () async {
      final id = await placeAt(2, 2, 'eat');
      final apple = await makeSymbol('apple');
      final pear = await makeSymbol('pear');

      await showPicture(id, apple);
      await showPicture(id, pear);
      await recordEdit(
        kind: EditKind.resymbol,
        buttonId: id,
        before: {'symbolId': apple},
      );

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      expect((await buttonById(id)).symbolId, apple);
    });

    test('a picture on a key comes back off every copy of it', () async {
      final other = await materialiseBoard(
        db,
        vocabularyId: vocabId,
        name: 'food',
        kind: BoardKind.category,
      );
      final pinned = await cellAt(db, boardId: boardId, row: 0, col: 11);
      final twin = await cellAt(db, boardId: other, row: 0, col: 11);

      final here = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: pinned.id,
        label: 'what',
        message: 'what',
      );
      final there = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: twin.id,
        label: 'what',
        message: 'what',
      );

      final drawn = await makeSymbol('question mark');
      final photo = await makeSymbol('a photo of nobody');
      await showPicture(here, drawn);
      await showPicture(there, drawn);
      await showPicture(here, photo);
      await showPicture(there, photo);
      await recordEdit(
        kind: EditKind.resymbol,
        buttonId: here,
        before: {'symbolId': drawn},
      );

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      expect((await buttonById(here)).symbolId, drawn);
      expect(
        (await buttonById(there)).symbolId,
        drawn,
        reason:
            'one movement that looks like two different keys depending on '
            'the board is the confusion the fixed frame prevents',
      );
    });

    test('a picture change with nothing recorded to go back to is '
        'refused', () async {
      final id = await placeAt(2, 2, 'eat');
      final photo = await makeSymbol('a photo of nobody');
      await showPicture(id, photo);
      await recordEdit(kind: EditKind.resymbol, buttonId: id);

      expect(
        await remap.undoLast(vocabId),
        UndoOutcome.blocked,
        reason:
            'guessing would put a picture nobody chose on a key an AAC user '
            'finds by its picture',
      );
      expect((await buttonById(id)).symbolId, photo);
    });

    test('a rebuild is not stepped back one edit at a time', () async {
      final id = await placeAt(1, 1, 'eat');
      final target = await cellAt(db, boardId: boardId, row: 2, col: 2);
      await remap.moveButton(buttonId: id, toCellId: target.id);
      await recordEdit(kind: EditKind.gridResize);

      expect(
        await remap.undoLast(vocabId),
        UndoOutcome.blocked,
        reason:
            'a resize moved every location at once; stepping past it would '
            'take back a move the caregiver was not asking about',
      );
      expect((await buttonById(id)).cellId, target.id);
    });

    test('a word lifted from the tray goes back to the tray', () async {
      final id = newId();
      final ts = nowMs();
      await db
          .into(db.buttons)
          .insert(
            ButtonsCompanion.insert(
              id: id,
              vocabularyId: vocabId,
              label: 'trampoline',
              message: 'trampoline',
              action: ButtonAction.speak,
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      final target = await cellAt(db, boardId: boardId, row: 4, col: 4);
      await remap.moveButton(buttonId: id, toCellId: target.id);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);
      expect((await buttonById(id)).cellId, isNull);
      expect(
        (await cellAt(db, boardId: boardId, row: 4, col: 4)).state,
        CellState.emptyReserved,
        reason: 'the word left, so the location it was dropped on is free',
      );
    });

    test('an undo the board has outgrown changes nothing at all', () async {
      final id = await placeAt(3, 3, 'eat');
      final target = await cellAt(db, boardId: boardId, row: 6, col: 6);
      await remap.moveButton(buttonId: id, toCellId: target.id);
      final newcomer = await placeAt(3, 3, 'drink');

      final trail = await editCount();
      expect(await remap.undoLast(vocabId), isNot(UndoOutcome.undone));

      expect((await buttonById(id)).cellId, target.id);
      expect(
        (await buttonById(newcomer)).cellId,
        (await cellAt(db, boardId: boardId, row: 3, col: 3)).id,
        reason:
            'overwriting would cost "drink" the location it is already '
            'being reached for',
      );
      expect(
        (await cellAt(db, boardId: boardId, row: 3, col: 3)).state,
        CellState.occupied,
      );
      expect(
        (await cellAt(db, boardId: boardId, row: 6, col: 6)).state,
        CellState.occupied,
      );
      expect(
        await editCount(),
        trail,
        reason:
            'a refusal that wrote a row would spend the edit it could not '
            'take back',
      );
    });

    test('the trail keeps the edit and the second thought', () async {
      final id = await placeAt(1, 1, 'eat');
      await recordTaps(id, 12);
      final target = await cellAt(db, boardId: boardId, row: 2, col: 2);
      await remap.moveButton(buttonId: id, toCellId: target.id);

      expect(await remap.undoLast(vocabId), UndoOutcome.undone);

      final events = await db.select(db.editEvents).get();
      expect(events, hasLength(2), reason: 'the move was removed from history');

      final undo = events.singleWhere(
        (e) => (e.afterJson ?? '').contains('undoOf'),
      );
      final move = events.singleWhere((e) => e.id != undo.id);
      expect(jsonDecode(undo.afterJson!)['undoOf'], move.id);
      expect(
        move.motorImpactTaps,
        12,
        reason:
            'what the move cost is the answer to what changed on Tuesday, '
            'and undoing it does not unspend the practice',
      );
    });

    test(
      'the trail is what remembers, so a restart does not reset it',
      () async {
        // Two live instances is what a restart looks like from here, so the
        // warning about them is noise rather than a finding.
        final warn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(
          () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = warn,
        );

        final dir = await Directory.systemTemp.createTemp('wordbridge-undo');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/wordbridge.sqlite');

        var disk = WordbridgeDatabase.forTesting(NativeDatabase(file));
        final vocab = newId();
        final ts = nowMs();
        await disk
            .into(disk.vocabularies)
            .insert(
              VocabulariesCompanion.insert(
                id: vocab,
                name: 'test',
                gridRows: 7,
                gridCols: 12,
                createdAt: ts,
                updatedAt: ts,
              ),
            );
        final board = await materialiseBoard(
          disk,
          vocabularyId: vocab,
          name: 'home',
          kind: BoardKind.root,
        );
        final home = await cellAt(disk, boardId: board, row: 1, col: 1);
        final away = await cellAt(disk, boardId: board, row: 5, col: 5);
        final id = await placeButton(
          disk,
          vocabularyId: vocab,
          cellId: home.id,
          label: 'eat',
          message: 'eat',
        );

        await RemapService(disk).moveButton(buttonId: id, toCellId: away.id);
        expect(await RemapService(disk).undoLast(vocab), UndoOutcome.undone);
        await disk.close();

        disk = WordbridgeDatabase.forTesting(NativeDatabase(file));
        addTearDown(() => disk.close());

        expect(
          await RemapService(disk).undoLast(vocab),
          UndoOutcome.nothing,
          reason:
              'a stack held in memory is empty on reopening, so the move '
              'would be offered back a second time',
        );
        final button = await (disk.select(
          disk.buttons,
        )..where((b) => b.id.equals(id))).getSingle();
        expect(button.cellId, home.id);
      },
    );
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
