import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/developer/cell_sheet.dart';
import 'package:wordbridge/features/editor/board_editor.dart';
import 'package:wordbridge/features/grid/grid_surface.dart' show PlacedCell;
import 'package:wordbridge/features/speech/neural/neural_engine.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

class _PlatformVoice implements SpeechEngine {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> speakUtterance(String text) => speak(text);
  @override
  Future<void> init() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<List<VoiceOption>> voices() async => const [];
  @override
  Future<void> useVoice(VoiceOption voice) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVolume(double volume) async {}
}

/// What a held location has to be able to answer.
///
/// The four questions anybody asks of this board are all about a location:
/// what is there, why is it blank, where did that picture come from, and which
/// voice says it. Answering any of them otherwise means leaving the board,
/// opening caregiver mode, finding the right board in the editor and counting
/// rows to the square you were already looking at.
///
/// The one that has to be right rather than merely useful is the second. A
/// blank square on this board has four different meanings and they are drawn
/// identically, so a wrong answer here would send somebody looking for a bug
/// in the wrong half of the app.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;
  late String homeId;

  Button button({
    required String label,
    int vocabLevel = 1,
    bool hidden = false,
  }) => Button(
    id: label,
    cellId: 'c',
    vocabularyId: 'v',
    label: label,
    message: label,
    action: ButtonAction.speak,
    hidden: hidden,
    vocabLevel: vocabLevel,
    isSystem: false,
    createdAt: 0,
    updatedAt: 0,
  );

  group('why a location is drawing nothing', () {
    test('a word somebody switched off', () {
      expect(
        whyNotDrawn(button: button(label: 'shit', hidden: true), vocabLevel: 3),
        contains('Switched off'),
      );
    });

    test('a word above this profile', () {
      final why = whyNotDrawn(
        button: button(label: 'turn', vocabLevel: 3),
        vocabLevel: 1,
      );

      // Both numbers, because the useful sentence is the comparison and not
      // either half of it.
      expect(why, contains('Level 3'));
      expect(why, contains('level 1'));
    });

    test('an ending the sentence cannot take yet', () {
      expect(
        whyNotDrawn(
          button: button(label: '+ed'),
          vocabLevel: 3,
          isAvailable: (_) => false,
        ),
        contains('ending'),
      );
    });

    test('and nothing at all for a word that is drawn, or a free location', () {
      // "There is nothing here" is the answer, not a reason, and a reason
      // offered for a drawn word would send somebody looking for a fault.
      expect(whyNotDrawn(button: button(label: 'want'), vocabLevel: 3), isNull);
      expect(whyNotDrawn(button: null, vocabLevel: 3), isNull);
    });
  });

  group('the sheet a held location opens', () {
    late Directory documents;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      documents = Directory.systemTemp.createTempSync('wordbridge-developer');

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
      homeId = await materializeBoard(
        db,
        vocabularyId: vocabId,
        name: 'home',
        kind: BoardKind.root,
      );
    });

    tearDown(() async {
      await db.close();
      documents.deleteSync(recursive: true);
    });

    Future<PlacedCell> placed(int row, int col, {String? label}) async {
      final cell = await cellAt(db, boardId: homeId, row: row, col: col);
      if (label == null) return (cell: cell, button: null);

      final id = await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: label,
        message: label,
      );
      final row_ = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(id))).getSingle();
      return (cell: cell, button: row_);
    }

    Future<void> pumpSheet(
      WidgetTester tester,
      PlacedCell cell, {
      SpeechEngine? speech,
      int vocabLevel = 3,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => DeveloperCellSheet.show(
                  context,
                  db: db,
                  vocabularyId: vocabId,
                  placed: cell,
                  vocabLevel: vocabLevel,
                  speech: speech,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the board and the location, in the numbers the '
        'database uses', (tester) async {
      await pumpSheet(tester, await placed(2, 3, label: 'want'));

      expect(find.text('want'), findsOneWidget);
      expect(find.textContaining('home, row 2, column 3'), findsOneWidget);
    });

    testWidgets('says what is behind a location that looks empty', (
      tester,
    ) async {
      // The point of the whole thing: a hidden word and a reserved location
      // are drawn identically, and only one of them is somewhere a new word
      // may go.
      final cell = await placed(1, 1, label: 'shit');
      await (db.update(db.buttons)..where((b) => b.id.equals(cell.button!.id)))
          .write(const ButtonsCompanion(hidden: Value(true)));
      final hidden = await placed(1, 1);
      final button = await (db.select(
        db.buttons,
      )..where((b) => b.cellId.equals(hidden.cell.id))).getSingle();

      await pumpSheet(tester, (cell: hidden.cell, button: button));

      expect(find.text('shit'), findsOneWidget);
      expect(find.text('Not drawn right now'), findsOneWidget);
      expect(find.textContaining('Switched off'), findsOneWidget);
    });

    testWidgets('and offers a word only where there is room for one', (
      tester,
    ) async {
      await pumpSheet(tester, await placed(0, 0));
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Put a word here'), findsOneWidget);
      expect(find.text('Not drawn right now'), findsNothing);
    });

    testWidgets('offers both voices where there are two', (tester) async {
      // The comparison is the point, and it is made on one word without
      // changing what the tablet is set to.
      final platform = _PlatformVoice();
      await pumpSheet(
        tester,
        await placed(2, 2, label: 'more'),
        speech: NeuralSpeechEngine(
          platform,
          documentsDirectory: () async => documents,
        ),
      );

      expect(find.text('Say it with the neural voice'), findsOneWidget);
      expect(find.text('Say it with the device voice'), findsOneWidget);

      await tester.tap(find.text('Say it with the device voice'));
      await tester.pumpAndSettle();

      expect(platform.spoken, ['more']);
    });

    testWidgets('opens the editor on the board the location belongs to', (
      tester,
    ) async {
      // The sheet closes and the editor opens behind it, so the navigator has
      // to be taken before the pop: pushing through a context whose route is
      // already leaving pushes onto something on its way out.
      await pumpSheet(tester, await placed(1, 2, label: 'want'));

      await tester.tap(find.text('Edit "home"'));
      await tester.pumpAndSettle();

      expect(find.byType(BoardEditor), findsOneWidget);
      expect(find.text('Edit: home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('and one where there is one', (tester) async {
      // Offering a choice between a voice and itself says something false.
      await pumpSheet(
        tester,
        await placed(2, 2, label: 'more'),
        speech: _PlatformVoice(),
      );

      expect(find.text('Say it'), findsOneWidget);
      expect(find.text('Say it with the neural voice'), findsNothing);
    });
  });

  group('opening the editor on the location that was held', () {
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
      homeId = await materializeBoard(
        db,
        vocabularyId: vocabId,
        name: 'home',
        kind: BoardKind.root,
      );
    });

    tearDown(() => db.close());

    testWidgets('asks what goes there, rather than handing over a grid', (
      tester,
    ) async {
      // Being handed the board and asked to find the square again means
      // counting rows on an 84 cell grid, on the board whose layout is least
      // likely to be in anybody's head.
      final cell = await cellAt(db, boardId: homeId, row: 2, col: 3);

      await tester.pumpWidget(
        MaterialApp(
          home: BoardEditor(
            db: db,
            vocabularyId: vocabId,
            boardId: homeId,
            openCellId: cell.id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What goes here?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('and asks nothing when it was opened on no location', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BoardEditor(db: db, vocabularyId: vocabId, boardId: homeId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What goes here?'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
