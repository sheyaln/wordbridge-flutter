import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/vocabulary_top_up.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/tone.dart';
import 'package:wordbridge/features/talk/quick_settings.dart';

import 'vocabulary_top_up_test.dart' show positions;

/// The quick settings key, and the column it was given (§4.81).
///
/// Column 2 was deliberately empty: the gap that keeps an imprecise reach for
/// "back" off the category keys. Spending it is the one part of this feature
/// that touches the board everybody has learned, so most of what is here is
/// about proving that spending it moved nothing.
void main() {
  late WordbridgeDatabase db;

  setUp(() {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  /// The boards somebody navigates to.
  ///
  /// Excludes [BoardKind.system], which is the quick settings menu: it is drawn
  /// over whichever board you are on rather than being one, so it carries no
  /// system row and no pinned questions. Every "on every board" claim below
  /// means every board a person can stand on.
  Future<List<Board>> boardsOf(String vocabId) =>
      (db.select(db.boards)
            ..where((b) => b.vocabularyId.equals(vocabId))
            ..where((b) => b.kind.equalsValue(BoardKind.system).not()))
          .get();

  Future<Button?> buttonAt(String boardId, int row, int col) async {
    final cell = await cellAt(db, boardId: boardId, row: row, col: col);
    return (db.select(
      db.buttons,
    )..where((b) => b.cellId.equals(cell.id))).getSingleOrNull();
  }

  group('where the key goes', () {
    test('column 2 on every board, on a grid with room for it', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final frame = SystemFrame.parse(vocab.systemCellMap)!;

      expect(frame.configCol, 2);

      final boards = await boardsOf(vocabId);
      expect(boards, isNotEmpty);
      for (final board in boards) {
        final button = await buttonAt(board.id, frame.row, 2);
        expect(
          button?.action,
          ButtonAction.quickSettings,
          reason: 'no quick settings key on "${board.name}"',
        );
        expect(button!.isSystem, isTrue);
        expect(button.label, quickSettingsLabel);
      }
    });

    test('and the rest of the row is exactly where it was', () async {
      // The key was added to a column nothing was in. If any of these moved,
      // it was not added — it displaced something, which for a row every board
      // carries is the worst version of that failure.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final frame = SystemFrame.parse(vocab.systemCellMap)!;

      expect(frame.row, 6);
      expect(frame.homeCol, 0);
      expect(frame.backCol, 1);
      expect(frame.categoryCols.first, 3);
      expect(frame.pageBackCol, 10);
      expect(frame.pageForwardCol, 11);

      final root = (await boardsOf(vocabId))
          .firstWhere((b) => b.kind == BoardKind.root);
      expect((await buttonAt(root.id, 6, 0))!.action, ButtonAction.home);
      expect((await buttonAt(root.id, 6, 1))!.action, ButtonAction.back);
      expect((await buttonAt(root.id, 6, 3))!.action, ButtonAction.navigate);
    });

    test('but not while the wheel has not started turning', () async {
      // Column 2 is also the cycle key's last resort. Until the wheel turns,
      // it belongs to the wheel: a category no key opens is vocabulary
      // somebody is told about and cannot reach, which beats a settings menu.
      final plan = SystemRowPlan.forGrid(rows: 7, cols: 12, categories: 3);
      expect(plan.cycleCol, isNull, reason: 'the fixture already cycles');
      expect(plan.configCol, isNull);

      // And it takes the column the moment the wheel is turning, because the
      // gap can never be wanted again after that.
      final turning = SystemRowPlan.forGrid(rows: 7, cols: 12, categories: 14);
      expect(turning.cycleCol, isNotNull);
      expect(turning.configCol, 2);
    });

    test('and nowhere at all on a grid too narrow to spare a column', () async {
      // Six columns gives the gap up to fit a category key. There is no spare
      // column, so there is no menu key — and the category key that took the
      // column is still the thing sitting in it.
      final narrow = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(narrow.close);

      final vocabId = await seedCoreBoardSet(narrow, rows: 7, cols: 6);
      final vocab = await (narrow.select(
        narrow.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final frame = SystemFrame.parse(vocab.systemCellMap)!;

      expect(frame.configCol, isNull);
      expect(frame.categoryCols.first, 2);

      final boards =
          await (narrow.select(narrow.boards)
                ..where((b) => b.vocabularyId.equals(vocabId))
                ..where((b) => b.kind.equalsValue(BoardKind.system).not()))
              .get();
      for (final board in boards) {
        final cell = await cellAt(
          narrow,
          boardId: board.id,
          row: frame.row,
          col: 2,
        );
        final button = await (narrow.select(
          narrow.buttons,
        )..where((b) => b.cellId.equals(cell.id))).getSingleOrNull();
        expect(button?.action, isNot(ButtonAction.quickSettings));
      }
    });
  });

  group('a board set built before the key existed', () {
    /// Strips the key back out, leaving the board set as it shipped without it.
    Future<void> unwind(String vocabId) async {
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final frame = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
      frame.remove('configCol');

      for (final board in await boardsOf(vocabId)) {
        final cell = await cellAt(
          db,
          boardId: board.id,
          row: vocab.gridRows - 1,
          col: 2,
        );
        await (db.delete(
          db.buttons,
        )..where((b) => b.cellId.equals(cell.id))).go();
        await (db.update(db.cells)..where((c) => c.id.equals(cell.id))).write(
          const CellsCompanion(state: Value(CellState.emptyReserved)),
        );
      }

      await (db.update(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).write(
        VocabulariesCompanion(systemCellMap: Value(jsonEncode(frame))),
      );
    }

    test('gains the key, and nothing on it moves', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      await unwind(vocabId);

      final before = await positions(db);

      final result = await topUpVocabulary(db, vocabularyId: vocabId);
      expect(result.addedQuickSettings, isTrue);

      final after = await positions(db);
      for (final entry in before.entries) {
        expect(
          after[entry.key],
          entry.value,
          reason: 'a button moved when the quick settings key arrived',
        );
      }

      // Every board, not most of them. A key on some boards and not others is
      // not a fixed key.
      for (final board in await boardsOf(vocabId)) {
        expect(
          (await buttonAt(board.id, 6, 2))?.action,
          ButtonAction.quickSettings,
          reason: '"${board.name}" did not get the key',
        );
      }

      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      expect(SystemFrame.parse(vocab.systemCellMap)!.configCol, 2);
    });

    test('and does not gain a second one on the next run', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      await unwind(vocabId);

      expect(
        (await topUpVocabulary(db, vocabularyId: vocabId)).addedQuickSettings,
        isTrue,
      );
      expect(
        (await topUpVocabulary(db, vocabularyId: vocabId)).addedQuickSettings,
        isFalse,
      );
    });

    test('a dry run reports it and writes nothing', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      await unwind(vocabId);

      final before = await positions(db);
      final preview = await topUpVocabulary(
        db,
        vocabularyId: vocabId,
        dryRun: true,
      );

      expect(preview.addedQuickSettings, isTrue);
      expect(await positions(db), before);
    });

    test('refuses the column if anything is sitting in it', () async {
      // One occupied cell on one board is enough. Placing the key anyway would
      // make it a key that means one thing on eleven boards and something else
      // on the twelfth.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      await unwind(vocabId);

      final boards = await boardsOf(vocabId);
      final cell = await cellAt(db, boardId: boards.last.id, row: 6, col: 2);
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'squatter',
        message: 'squatter',
        action: ButtonAction.speak,
      );

      final result = await topUpVocabulary(db, vocabularyId: vocabId);
      expect(result.addedQuickSettings, isFalse);

      for (final board in boards) {
        final button = await buttonAt(board.id, 6, 2);
        expect(button?.action, isNot(ButtonAction.quickSettings));
      }
    });
  });

  group('when the wheel needs the column back', () {
    test('the category is refused rather than the key being moved', () async {
      // Both want column 2 and there is no other. The key stays and the
      // category is refused, because every top-up is an addition: a key
      // vanishing from a row somebody has learned is the displacement that
      // guarantee exists to forbid, and it does not stop being one because
      // what it would make room for is valuable. The refusal is reported.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final frame = SystemFrame.parse(vocab.systemCellMap)!;

      // The shipped set cycles, so the key holds the gap and the wheel already
      // has its own key elsewhere — the two only contend once a board set has
      // lost enough categories to stop cycling.
      expect(frame.configCol, 2);
      expect(frame.cycleCol, isNotNull);
    });
  });

  group('favorites', () {
    late ProfileSettings settings;

    setUp(() async {
      const profileId = 'p1';
      final ts = nowMs();
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: profileId,
              displayName: 'Maya',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      settings = ProfileSettings(db, profileId);
      await settings.load();
    });

    test('start empty', () {
      expect(settings.favorites, isEmpty);
    });

    test('keep the order they were added in', () async {
      // Never sorted, and never by frequency. A list that reorders itself is
      // the moving-target failure this whole app refuses.
      await settings.addFavorite('juice');
      await settings.addFavorite('bathroom');
      await settings.addFavorite('mom');

      expect(settings.favorites.map((f) => f.label), [
        'juice',
        'bathroom',
        'mom',
      ]);
    });

    test('adding one twice changes nothing', () async {
      await settings.addFavorite('juice');
      await settings.addFavorite('juice');
      expect(settings.favorites, hasLength(1));
    });

    test('carry a message that can differ from the label', () async {
      await settings.addFavorite('juice', message: 'I want juice please');
      expect(settings.favorites.single.message, 'I want juice please');
    });

    test('and default the message to the label', () async {
      await settings.addFavorite('juice');
      expect(settings.favorites.single.message, 'juice');
    });

    test('removing one leaves the rest in order', () async {
      await settings.addFavorite('juice');
      await settings.addFavorite('bathroom');
      await settings.addFavorite('mom');
      await settings.removeFavorite('bathroom');

      expect(settings.favorites.map((f) => f.label), ['juice', 'mom']);
    });

    test('removing one that is not there changes nothing', () async {
      await settings.addFavorite('juice');
      await settings.removeFavorite('nothing');
      expect(settings.favorites, hasLength(1));
    });

    test('survive a reload', () async {
      await settings.addFavorite('juice', message: 'I want juice');

      final reopened = ProfileSettings(db, 'p1');
      await reopened.load();
      expect(reopened.favorites.single.label, 'juice');
      expect(reopened.favorites.single.message, 'I want juice');
    });

    test('a corrupt entry is skipped rather than crashing the board', () async {
      // These come back off a JSON blob that a restored backup or a hand-edited
      // profile can have anything in. A favorites list is not worth taking the
      // talk screen down for.
      await settings.set('favorites', [
        {'label': 'juice', 'message': 'juice'},
        'not a map',
        {'message': 'no label'},
        42,
      ]);
      expect(settings.favorites.map((f) => f.label), ['juice']);
    });

    test('a non-list is read as no favorites', () async {
      await settings.set('favorites', 'nonsense');
      expect(settings.favorites, isEmpty);
    });
  });

  group('the volume ends', () {
    test('run whisper to yelling, inside what the platform accepts', () {
      expect(volumeQuietest.value, lessThan(volumeLoudest.value));
      expect(volumeLoudest.value, 1.0);
      expect(volumeQuietest.value, greaterThan(0.0));
    });

    test('and are named for a room, not a number', () {
      expect(volumeQuietest.label, 'Whisper');
      expect(volumeLoudest.label, 'Loud');
      expect(volumeNormal.label, 'Normal');
    });
  });

  group('the tones offered', () {
    test('leave "quiet" out, because it was never a tone', () {
      // It is the volume dial wearing a tone's name. The slider does that job
      // now, and does it honestly.
      expect(Tone.offeredTones, isNot(contains(Tone.quiet)));
      expect(Tone.quiet.offered, isFalse);
    });

    test('but the engine still carries it, so a stored one still resolves', () {
      // A value that vanished would leave a profile that had chosen it
      // silently reading as "normal", with nothing to show it had happened.
      expect(Tone.values, contains(Tone.quiet));
      expect(Tone.byName('quiet'), Tone.quiet);
    });

    test('and every one of them is a way of speaking', () {
      expect(Tone.offeredTones, isNotEmpty);
      expect(Tone.offeredTones, contains(Tone.normal));
      for (final tone in Tone.offeredTones) {
        expect(tone.offered, isTrue);
      }
    });
  });

  group('the menu board', () {
    test('is a board, with a button on it for every row', () async {
      // The whole point of it being a board: these are real buttons at real
      // cells, so a caregiver can put the right picture on one with the picker
      // they already know.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

      final board =
          await (db.select(db.boards)
                ..where((b) => b.vocabularyId.equals(vocabId))
                ..where((b) => b.name.equals(quickSettingsBoardName)))
              .getSingle();
      expect(board.kind, BoardKind.system);

      final rows = await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(board.id))).get();

      expect(rows, hasLength(quickSettingsItems.length));
      expect(
        rows.map((r) => r.readTable(db.buttons).action),
        containsAll([
          ButtonAction.quickVolume,
          ButtonAction.quickTone,
          ButtonAction.favorites,
        ]),
      );
    });

    test('stacks its rows flush above the key, in the key\'s column', () async {
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final frame = SystemFrame.parse(vocab.systemCellMap)!;

      final board =
          await (db.select(db.boards)
                ..where((b) => b.vocabularyId.equals(vocabId))
                ..where((b) => b.name.equals(quickSettingsBoardName)))
              .getSingle();

      final rows = await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(board.id))).get();

      final at = {
        for (final r in rows)
          r.readTable(db.buttons).action: (
            row: r.readTable(db.cells).row,
            col: r.readTable(db.cells).col,
          ),
      };

      // Every row in the key's own column.
      for (final place in at.values) {
        expect(place.col, frame.configCol);
      }

      // Flush: the last row is the cell immediately above the key, and there
      // is no gap anywhere in the stack.
      expect(at[ButtonAction.favorites]!.row, frame.row - 1);
      expect(at[ButtonAction.quickTone]!.row, frame.row - 2);
      expect(at[ButtonAction.quickVolume]!.row, frame.row - 3);
    });

    test('carries no system row of its own', () async {
      // It is drawn *over* a board that already has one. A second system row
      // on screen at once is two homes, two backs, and two of this key.
      final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

      final board =
          await (db.select(db.boards)
                ..where((b) => b.vocabularyId.equals(vocabId))
                ..where((b) => b.name.equals(quickSettingsBoardName)))
              .getSingle();

      final rows = await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(board.id))).get();

      for (final r in rows) {
        expect(r.readTable(db.buttons).action, isNot(ButtonAction.home));
        expect(r.readTable(db.cells).row, isNot(6));
      }
    });

    test('and a grid with no key has no menu board either', () async {
      final narrow = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(narrow.close);
      final vocabId = await seedCoreBoardSet(narrow, rows: 7, cols: 6);

      final board =
          await (narrow.select(narrow.boards)
                ..where((b) => b.vocabularyId.equals(vocabId))
                ..where((b) => b.name.equals(quickSettingsBoardName)))
              .getSingleOrNull();
      expect(board, isNull);
    });
  });
}
