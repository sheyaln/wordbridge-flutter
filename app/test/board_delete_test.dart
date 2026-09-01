import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/vocabulary_top_up.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/caregiver/caregiver_home.dart';
import 'package:wordbridge/features/editor/board_delete.dart';
import 'package:wordbridge/features/editor/board_editor.dart';
import 'package:wordbridge/features/editor/grid_migration.dart';
import 'package:wordbridge/features/interop/obf_export.dart';
import 'package:wordbridge/features/prediction/word_prediction.dart';
import 'package:wordbridge/features/usage/logger.dart';

/// Removing a board a caregiver made by mistake.
///
/// The feature exists for one case — an empty board created two minutes ago —
/// and every other case is a refusal or a warning. Most of what is checked here
/// is those other cases: that nothing seeded can go, that no key is left
/// pointing at a board that is not there, that no location is freed, and that
/// every place which lists boards stops listing this one.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;
  late String rootBoardId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
    rootBoardId = (await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabId))).getSingle()).rootBoardId!;
  });

  tearDown(() async => db.close());

  Future<Board> boardNamed(String name) =>
      (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

  Future<Board> boardById(String id) =>
      (db.select(db.boards)..where((b) => b.id.equals(id))).getSingle();

  Future<Button> buttonById(String id) =>
      (db.select(db.buttons)..where((b) => b.id.equals(id))).getSingle();

  Future<String> caregiverBoard(String name) => materializeBoard(
    db,
    vocabularyId: vocabId,
    name: name,
    kind: BoardKind.category,
  );

  Future<String> placeOn(
    String boardId,
    int row,
    int col,
    String label, {
    ButtonAction action = ButtonAction.speak,
    String? target,
    PartOfSpeech? pos,
  }) async {
    final cell = await cellAt(db, boardId: boardId, row: row, col: col);
    return placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: label,
      action: action,
      targetBoardId: target,
      partOfSpeech: pos,
    );
  }

  /// A key on the home board that opens [target], on whichever location the
  /// seed happened to leave free.
  Future<String> keyTo(String target, String label) async {
    final cell =
        await (db.select(db.cells)
              ..where(
                (c) =>
                    c.boardId.equals(rootBoardId) &
                    c.state.equalsValue(CellState.emptyReserved),
              )
              ..limit(1))
            .getSingle();

    return placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: '',
      action: ButtonAction.navigate,
      targetBoardId: target,
    );
  }

  /// Usage rows written straight in, because the tap count has to span several
  /// calendar days and the logger only ever stamps now.
  Future<void> recordTaps(
    String buttonId,
    int count, {
    int days = 1,
    int agedDays = 0,
  }) async {
    final button = await buttonById(buttonId);
    final cell = await (db.select(
      db.cells,
    )..where((c) => c.id.equals(button.cellId!))).getSingle();

    for (var i = 0; i < count; i++) {
      await db
          .into(db.usageEvents)
          .insert(
            UsageEventsCompanion.insert(
              deviceId: 'test',
              profileId: 'default',
              vocabularyId: vocabId,
              boardId: cell.boardId,
              cellId: cell.id,
              buttonId: Value(buttonId),
              labelSnapshot: button.label,
              action: ButtonAction.speak,
              source: UsageSource.touch,
              sessionId: 's1',
              occurredAt: DateTime.now()
                  .subtract(Duration(days: agedDays + (i % days), hours: 1))
                  .millisecondsSinceEpoch,
            ),
          );
    }
  }

  /// What the caregiver home's board list shows.
  Future<List<Board>> listedBoards() =>
      (db.select(db.boards)
            ..where((b) => b.vocabularyId.equals(vocabId))
            ..where((b) => b.deletedAt.isNull()))
          .get();

  Future<List<Button>> buttonsOn(String boardId) async {
    final cellIds = [
      for (final c in await (db.select(
        db.cells,
      )..where((c) => c.boardId.equals(boardId))).get())
        c.id,
    ];
    return (db.select(db.buttons)..where((b) => b.cellId.isIn(cellIds))).get();
  }

  group('the easy case', () {
    test('an empty board goes with no ceremony', () async {
      final boardId = await caregiverBoard('breakfsat');

      final impact = await BoardDeletion.preview(db, boardId: boardId);
      expect(impact.canDelete, isTrue);
      expect(impact.isEmpty, isTrue);
      expect(impact.words, 0);
      expect(impact.warningFor('Maya'), isNull);

      await BoardDeletion.apply(db, boardId: boardId);

      expect((await boardById(boardId)).deletedAt, isNotNull);
      expect(
        (await listedBoards()).map((b) => b.id),
        isNot(contains(boardId)),
        reason: 'the caregiver board list still shows it',
      );
    });

    test('the row survives, so the history behind it does', () async {
      final boardId = await caregiverBoard('spare');
      await BoardDeletion.apply(db, boardId: boardId);

      final rows = await (db.select(
        db.boards,
      )..where((b) => b.id.equals(boardId))).get();
      expect(rows, hasLength(1), reason: 'a hard delete would take history');
    });
  });

  group('a board with words on it', () {
    late String boardId;
    late String toast;

    setUp(() async {
      boardId = await caregiverBoard('breakfast');
      toast = await placeOn(boardId, 0, 0, 'toast');
      await placeOn(boardId, 0, 1, 'jam');
      await placeOn(boardId, 1, 0, 'cereal');
    });

    test('the words and the taps against them are real counts', () async {
      await recordTaps(toast, 7, days: 3);

      final impact = await BoardDeletion.preview(db, boardId: boardId);
      expect(impact.words, 3);
      expect(impact.taps, 7);
      expect(impact.days, 3);
      expect(impact.isEmpty, isFalse);

      final warning = impact.warningFor('Maya')!;
      expect(warning, contains('3 words'));
      expect(warning, contains('Maya has tapped those locations 7 times'));
      expect(warning, contains('across 3 days'));
      expect(warning, contains('90 days'));
    });

    test('a hidden word is still a word that goes', () async {
      final held = await placeOn(boardId, 2, 0, 'marmalade');
      await hideButton(db, held);

      expect((await BoardDeletion.preview(db, boardId: boardId)).words, 4);
    });

    test('untapped locations say so rather than showing a bare zero', () async {
      final warning = (await BoardDeletion.preview(
        db,
        boardId: boardId,
      )).warningFor('Maya')!;
      expect(warning, contains('Nothing has been recorded at those locations'));
    });

    test('use older than the window is not counted', () async {
      await recordTaps(toast, 3, agedDays: 200);
      await recordTaps(toast, 2);

      final impact = await BoardDeletion.preview(db, boardId: boardId);
      expect(impact.taps, 2, reason: 'the window is not being applied');
    });

    test('the words go and every recorded tap stays', () async {
      await recordTaps(toast, 5);
      await BoardDeletion.apply(db, boardId: boardId);

      final button = await buttonById(toast);
      expect(button.deletedAt, isNotNull);
      expect(button.hidden, isTrue);

      final usage = await (db.select(
        db.usageEvents,
      )..where((e) => e.cellId.equals(button.cellId!))).get();
      expect(usage, hasLength(5), reason: 'usage rows were destroyed');
    });

    test('the edit is recorded with what it cost', () async {
      await recordTaps(toast, 4);
      await BoardDeletion.apply(db, boardId: boardId, profileId: 'default');

      final event = await (db.select(
        db.editEvents,
      )..where((e) => e.kind.equalsValue(EditKind.delete))).getSingle();
      expect(event.motorImpactTaps, 4);
      expect(event.beforeJson, contains('breakfast'));
    });
  });

  group('never orphan a key', () {
    test('a key that opened it keeps its cell and stops navigating', () async {
      final boardId = await caregiverBoard('breakfast');
      await placeOn(boardId, 0, 0, 'toast');
      final key = await keyTo(boardId, 'breakfast');

      final impact = await BoardDeletion.preview(db, boardId: boardId);
      expect(impact.keys, 1);
      expect(impact.warningFor('Maya'), contains('1 key opens this board'));

      await BoardDeletion.apply(db, boardId: boardId);

      final after = await buttonById(key);
      expect(after.targetBoardId, isNull, reason: 'the key still points at it');
      expect(after.action, ButtonAction.none);
      expect(after.hidden, isTrue, reason: 'a dead key is still drawn');

      final cell = await (db.select(
        db.cells,
      )..where((c) => c.id.equals(after.cellId!))).getSingle();
      expect(
        cell.state,
        CellState.occupied,
        reason: 'removing a board freed a location',
      );
    });

    test('no key anywhere is left pointing at a removed board', () async {
      final boardId = await caregiverBoard('breakfast');
      await keyTo(boardId, 'breakfast');
      await keyTo(boardId, 'breakfast again');

      await BoardDeletion.apply(db, boardId: boardId);

      final dangling = await (db.select(
        db.buttons,
      )..where((b) => b.targetBoardId.equals(boardId))).get();
      expect(dangling, isEmpty);
    });

    test('a board with only a key on it is not the easy case', () async {
      final boardId = await caregiverBoard('breakfast');
      await keyTo(boardId, 'breakfast');

      final impact = await BoardDeletion.preview(db, boardId: boardId);
      expect(impact.isEmpty, isFalse);
      expect(impact.warningFor('Maya'), isNotNull);
    });
  });

  group('what cannot go', () {
    test('the home board', () async {
      final impact = await BoardDeletion.preview(db, boardId: rootBoardId);
      expect(impact.refusal, BoardDeleteRefusal.homeBoard);
      expect(impact.reason, contains('home board'));
      expect(
        () => BoardDeletion.apply(db, boardId: rootBoardId),
        throwsStateError,
      );
    });

    test('a board with a place on the category wheel', () async {
      final food = await boardNamed('food');
      final impact = await BoardDeletion.preview(db, boardId: food.id);
      expect(impact.refusal, BoardDeleteRefusal.onTheCategoryWheel);
      expect(impact.reason, contains('category wheel'));
      expect(() => BoardDeletion.apply(db, boardId: food.id), throwsStateError);
    });

    test('a later page, which a key on every board opens', () async {
      final pages = await (db.select(
        db.boards,
      )..where((b) => b.name.like('% 2'))).get();
      expect(pages, isNotEmpty, reason: 'the seed produced no paged boards');

      for (final page in pages) {
        final impact = await BoardDeletion.preview(db, boardId: page.id);
        expect(
          impact.refusal,
          BoardDeleteRefusal.openedByAFixedKey,
          reason: '"${page.name}" is deletable',
        );
        expect(impact.reason, contains('every board'));
      }
    });

    test('one already removed', () async {
      final boardId = await caregiverBoard('spare');
      await BoardDeletion.apply(db, boardId: boardId);

      final impact = await BoardDeletion.preview(db, boardId: boardId);
      expect(impact.refusal, BoardDeleteRefusal.alreadyGone);
      expect(
        () => BoardDeletion.apply(db, boardId: boardId),
        throwsStateError,
        reason: 'a second delete would restamp deleted_at',
      );
    });

    test('every board the seed built refuses, and says why', () async {
      for (final board in await listedBoards()) {
        final impact = await BoardDeletion.preview(db, boardId: board.id);
        expect(
          impact.canDelete,
          isFalse,
          reason: 'seeded board "${board.name}" can be removed',
        );
        expect(impact.reason, isNotNull);
      }
    });
  });

  test('removing a caregiver board changes no turn of the wheel', () async {
    Future<String> wheel() async => (await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabId))).getSingle()).systemCellMap;

    final before = await wheel();

    final boardId = await caregiverBoard('breakfast');
    await placeOn(boardId, 0, 0, 'toast');
    await BoardDeletion.apply(db, boardId: boardId);

    expect(await wheel(), before);
  });

  test('no cell is created, destroyed or freed', () async {
    final boardId = await caregiverBoard('breakfast');
    await placeOn(boardId, 0, 0, 'toast');
    await placeOn(boardId, 0, 1, 'jam');
    await keyTo(boardId, 'breakfast');

    Future<Map<String, String>> cells() async => {
      for (final c in await db.select(db.cells).get())
        c.id: '${c.boardId}|${c.row}|${c.col}|${c.state.name}',
    };

    final before = await cells();
    await BoardDeletion.apply(db, boardId: boardId);
    expect(await cells(), before);
  });

  group('every read path', () {
    late String boardId;

    setUp(() async {
      // A name nothing in the seed uses, so finding it anywhere afterwards can
      // only mean the removed board leaked through.
      boardId = await caregiverBoard('brekfist');
      await placeOn(boardId, 0, 0, 'marmalade', pos: PartOfSpeech.noun);
      await BoardDeletion.apply(db, boardId: boardId);
    });

    test('the package export leaves it out', () async {
      // Decoded rather than searched as bytes: the archive is compressed, so a
      // word that is in it does not appear in the raw output either way.
      final archive = ZipDecoder().decodeBytes(await exportObz(db, vocabId));
      final documents = [
        for (final file in archive.files)
          if (file.isFile) String.fromCharCodes(file.content as List<int>),
      ];

      expect(documents, isNotEmpty);
      expect(
        documents.join(),
        contains('home'),
        reason: 'nothing was exported',
      );
      expect(documents.join(), isNot(contains('marmalade')));
      expect(documents.join(), isNot(contains('brekfist')));
    });

    test('exporting it on its own refuses', () async {
      expect(() => exportObf(db, boardId), throwsStateError);
    });

    test('a grid rebuild neither counts nor carries its words', () async {
      final impact = await GridMigration.preview(
        db,
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );
      expect(impact.customWords, 0, reason: 'a removed word was counted');

      final rebuilt = await GridMigration.apply(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        rows: 5,
        cols: 9,
      );
      final carried = await (db.select(
        db.buttons,
      )..where((b) => b.vocabularyId.equals(rebuilt))).get();
      expect(
        carried.map((b) => b.label),
        isNot(contains('marmalade')),
        reason: 'a rebuild put a removed board back in front of the user',
      );
    });

    test('the prediction strip does not offer its words', () async {
      await db
          .into(db.predictionPairs)
          .insert(
            PredictionPairsCompanion.insert(
              profileId: 'default',
              previous: 'want',
              word: 'marmalade',
              count: const Value(9),
            ),
          );

      final suggestions = await WordPrediction(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        vocabLevel: 3,
      ).suggest(previous: 'want');

      expect(suggestions.map((b) => b.label), isNot(contains('marmalade')));
    });

    test('a bulk unhide cannot bring its words back', () async {
      // What the strong-language switch does: match on label across the whole
      // vocabulary and set `hidden`, with no idea which board a word is on.
      await (db.update(db.buttons)..where(
            (b) => b.vocabularyId.equals(vocabId) & b.label.equals('marmalade'),
          ))
          .write(const ButtonsCompanion(hidden: Value(false)));

      await db
          .into(db.predictionPairs)
          .insert(
            PredictionPairsCompanion.insert(
              profileId: 'default',
              previous: 'want',
              word: 'marmalade',
              count: const Value(9),
            ),
          );

      final suggestions = await WordPrediction(
        db,
        profileId: 'default',
        vocabularyId: vocabId,
        vocabLevel: 3,
      ).suggest(previous: 'want');

      expect(
        suggestions.map((b) => b.label),
        isNot(contains('marmalade')),
        reason: 'a word off a removed board came back',
      );
    });

    test('topping up writes nothing to it', () async {
      final before = await buttonsOn(boardId);
      await topUpVocabulary(db, vocabularyId: vocabId);
      final after = await buttonsOn(boardId);

      expect(
        after.map((b) => b.id).toSet(),
        before.map((b) => b.id).toSet(),
        reason: 'new vocabulary was placed on a removed board',
      );
    });

    test('the board editor will not open it', () async {
      expect(
        () =>
            (db.select(db.boards)
                  ..where((b) => b.id.equals(boardId))
                  ..where((b) => b.deletedAt.isNull()))
                .getSingle(),
        throwsStateError,
      );
    });

    testWidgets('the editor does not offer it as somewhere to move a word', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: BoardEditor(
            db: db,
            vocabularyId: vocabId,
            boardId: rootBoardId,
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      await tester.tap(find.text('want'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.text('Move to another board'));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('Move "want" to'), findsOneWidget);
      expect(find.text('brekfist'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('food'),
        ),
        findsOneWidget,
        reason: 'the picker listed no boards at all',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('the caregiver home', () {
    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: CaregiverHome(
            db: db,
            vocabularyId: vocabId,
            profileId: 'default',
            logger: UsageLogger(db, deviceId: 'test'),
            userName: 'Maya',
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    /// Long enough for the read, the query stream and the sheet's slide up.
    /// `pumpAndSettle` is out: the board list holds a spinner until its first
    /// frame of data and a snackbar keeps its own timer running.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    /// The board set is longer than any screen, so the tile has to be scrolled
    /// to before its control can be pressed.
    Future<void> tapDelete(WidgetTester tester, String name) async {
      await tester.scrollUntilVisible(
        find.byTooltip('Remove "$name"'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Remove "$name"'));
      await settle(tester);
    }

    /// Drops the widget before the database goes, so the board list's query
    /// stream is not still open when it does.
    Future<void> closeHome(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('one tap removes an empty board a caregiver just made', (
      tester,
    ) async {
      await caregiverBoard('breakfsat');
      await pumpHome(tester);
      await tapDelete(tester, 'breakfsat');

      expect(find.text('breakfsat'), findsNothing);
      expect(find.text('Removed "breakfsat".'), findsOneWidget);
      await closeHome(tester);
    });

    testWidgets('a seeded board shows the reason rather than nothing', (
      tester,
    ) async {
      await pumpHome(tester);
      await tapDelete(tester, 'food');

      expect(find.text('This board has to stay'), findsOneWidget);
      expect(find.textContaining('category wheel'), findsOneWidget);
      expect(find.text('Remove it'), findsNothing);

      await tester.tap(find.text('Close'));
      await settle(tester);

      expect(find.text('food'), findsOneWidget, reason: 'the board went');
      await closeHome(tester);
    });

    testWidgets('a board with words on it states what would go', (
      tester,
    ) async {
      final boardId = await caregiverBoard('breakfast');
      final toast = await placeOn(boardId, 0, 0, 'toast');
      await placeOn(boardId, 0, 1, 'jam');
      await recordTaps(toast, 12, days: 4);

      await pumpHome(tester);
      await tapDelete(tester, 'breakfast');

      expect(find.text('Remove "breakfast"?'), findsOneWidget);
      expect(
        find.textContaining('Maya has tapped those locations 12 times'),
        findsOneWidget,
      );
      expect(find.text('12'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await settle(tester);

      expect((await boardById(boardId)).deletedAt, isNull);
      await closeHome(tester);
    });
  });
}
