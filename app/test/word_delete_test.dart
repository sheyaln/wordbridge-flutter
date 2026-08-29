import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/board_editor.dart';

/// Removing a word, and choosing where a moved one lands.
///
/// Both are Tier 3 edits: they cost a location somebody may have learned, so
/// neither happens on a single tap and both say what they cost first.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;
  late String homeId;
  late String foodId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );

    vocabId = newId();
    final ts = nowMs();
    await db
        .into(db.vocabularies)
        .insert(
          VocabulariesCompanion.insert(
            id: vocabId,
            name: 'test',
            gridRows: 4,
            gridCols: 5,
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    homeId = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: 'home',
      kind: BoardKind.root,
    );
    foodId = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: 'food',
      kind: BoardKind.category,
    );
  });

  Future<String> placeAt(
    String boardId,
    int row,
    int col,
    String label, {
    bool isSystem = false,
    ButtonAction action = ButtonAction.speak,
  }) async {
    final cell = await cellAt(db, boardId: boardId, row: row, col: col);
    return placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: label,
      action: action,
      isSystem: isSystem,
    );
  }

  Future<void> pumpEditor(WidgetTester tester, String boardId) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BoardEditor(db: db, vocabularyId: vocabId, boardId: boardId),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<Cell> cellOf(String boardId, int row, int col) =>
      cellAt(db, boardId: boardId, row: row, col: col);

  group('removing a word', () {
    testWidgets('takes the word typed out, and nothing less', (tester) async {
      await placeAt(homeId, 0, 0, 'trampoline');
      await pumpEditor(tester, homeId);

      await tester.tap(find.byKey(const ValueKey('0:0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove this word'));
      await tester.pumpAndSettle();

      final remove = find.widgetWithText(FilledButton, 'Remove');
      expect(
        tester.widget<FilledButton>(remove).onPressed,
        isNull,
        reason: 'the word can be removed without typing anything',
      );

      // A near miss is still a miss.
      await tester.enterText(find.byType(TextField), 'delet');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(remove).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(remove).onPressed,
        isNotNull,
        reason: 'case is not the point; typing it out is',
      );

      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(
        (await cellOf(homeId, 0, 0)).state,
        CellState.emptyReserved,
        reason: 'the location was not released, so this was only a hide',
      );

      await teardownScreen(tester);
    });

    testWidgets('says what the location goes back to being', (tester) async {
      await placeAt(homeId, 0, 0, 'trampoline');
      await pumpEditor(tester, homeId);

      await tester.tap(find.byKey(const ValueKey('0:0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove this word'));
      await tester.pumpAndSettle();

      // Not "this word will be gone" — the sentence that matters is the one
      // about the location, because that is what a later word inherits.
      expect(find.textContaining('goes back to being empty'), findsOneWidget);
      expect(find.textContaining('home'), findsWidgets);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect((await cellOf(homeId, 0, 0)).state, CellState.occupied);

      await teardownScreen(tester);
    });

    testWidgets('refuses a key every board carries, and says why', (
      tester,
    ) async {
      await placeAt(
        homeId,
        3,
        0,
        'home',
        isSystem: true,
        action: ButtonAction.home,
      );
      await pumpEditor(tester, homeId);

      await tester.tap(find.byKey(const ValueKey('3:0')));
      await tester.pumpAndSettle();

      expect(
        find.text('Remove this word'),
        findsOneWidget,
        reason:
            'a control that is simply absent reads as a bug and explains '
            'nothing',
      );

      await tester.tap(find.text('Remove this word'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('cannot be navigated'), findsOneWidget);
      expect((await cellOf(homeId, 3, 0)).state, CellState.occupied);

      await teardownScreen(tester);
    });
  });

  group('moving a word to another board', () {
    testWidgets('opens that board and places it where it is tapped', (
      tester,
    ) async {
      await placeAt(homeId, 0, 0, 'trampoline');
      await pumpEditor(tester, homeId);

      await tester.tap(find.byKey(const ValueKey('0:0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to another board'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('food'));
      await tester.pumpAndSettle();

      // The destination board itself, not a list of coordinates.
      expect(find.text('Edit: food'), findsOneWidget);
      expect(
        find.textContaining('Row 1, column 1'),
        findsNothing,
        reason: 'the coordinate menu is still what picks the location',
      );
      expect(find.textContaining('Moving "trampoline"'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('1:2')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move anyway'));
      await tester.pumpAndSettle();

      final moved = await (db.select(
        db.buttons,
      )..where((b) => b.label.equals('trampoline'))).getSingle();
      final target = await cellOf(foodId, 1, 2);

      expect(moved.cellId, target.id);
      expect((await cellOf(homeId, 0, 0)).state, CellState.emptyReserved);
      expect(
        find.text('Edit: food'),
        findsOneWidget,
        reason:
            'the caregiver was sent away from the board they just put the '
            'word on',
      );

      await teardownScreen(tester);
    });

    testWidgets('cancelling goes back rather than stranding the caregiver', (
      tester,
    ) async {
      await placeAt(homeId, 0, 0, 'trampoline');
      await pumpEditor(tester, homeId);

      await tester.tap(find.byKey(const ValueKey('0:0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to another board'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('food'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Edit: home'), findsOneWidget);

      final held = await (db.select(
        db.buttons,
      )..where((b) => b.label.equals('trampoline'))).getSingle();
      expect(
        held.cellId,
        (await cellOf(homeId, 0, 0)).id,
        reason: 'cancelling moved the word anyway',
      );

      await teardownScreen(tester);
    });
  });
}
