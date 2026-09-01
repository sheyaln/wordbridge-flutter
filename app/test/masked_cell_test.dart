import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';

/// A location the user cannot see must not say anything.
///
/// Every mask goes through one path — words above the current level, words
/// switched off, and endings that do not apply yet — so this covers all three.
/// A blank square that speaks the word behind it teaches a user that the board
/// says things they did not choose.
void main() {
  Cell cell(int row, int col) => Cell(
    id: '$row:$col',
    boardId: 'board',
    row: row,
    col: col,
    spanRows: 1,
    spanCols: 1,
    state: CellState.occupied,
    createdAt: 0,
  );

  Button button({
    required String label,
    int vocabLevel = 1,
    bool hidden = false,
  }) => Button(
    id: label,
    cellId: '0:0',
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

  Future<List<String>> tapAt(
    WidgetTester tester, {
    required PlacedCell placed,
    required int vocabLevel,
    bool showHidden = false,
    bool Function(Button)? isAvailable,
  }) async {
    final spoken = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: GridSurface(
              rows: 1,
              cols: 1,
              cells: [placed],
              vocabLevel: vocabLevel,
              showHidden: showHidden,
              isAvailable: isAvailable,
              colorConvention: ColorConvention.modifiedFitzgerald,
              onSelect: (p) {
                if (p.button != null) spoken.add(p.button!.label);
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GridSurface));
    await tester.pump();
    return spoken;
  }

  testWidgets('a word above the current level cannot be spoken', (
    tester,
  ) async {
    final spoken = await tapAt(
      tester,
      placed: (cell: cell(0, 0), button: button(label: 'turn', vocabLevel: 2)),
      vocabLevel: 1,
    );

    expect(
      spoken,
      isEmpty,
      reason: 'tapping a blank square spoke the word hidden behind it',
    );
  });

  testWidgets('a word switched off cannot be spoken', (tester) async {
    final spoken = await tapAt(
      tester,
      placed: (cell: cell(0, 0), button: button(label: 'shit', hidden: true)),
      vocabLevel: 3,
    );

    expect(spoken, isEmpty);
  });

  testWidgets('an ending that does not apply yet cannot be spoken', (
    tester,
  ) async {
    final spoken = await tapAt(
      tester,
      placed: (cell: cell(0, 0), button: button(label: '+ed')),
      vocabLevel: 3,
      isAvailable: (_) => false,
    );

    expect(spoken, isEmpty);
  });

  testWidgets('a visible word still speaks', (tester) async {
    // The fix must not make the board inert.
    final spoken = await tapAt(
      tester,
      placed: (cell: cell(0, 0), button: button(label: 'want')),
      vocabLevel: 3,
    );

    expect(spoken, ['want']);
  });

  testWidgets('an empty location says nothing', (tester) async {
    final spoken = await tapAt(
      tester,
      placed: (cell: cell(0, 0), button: null),
      vocabLevel: 3,
    );

    expect(spoken, isEmpty);
  });

  testWidgets('the editor can still reach a masked location', (tester) async {
    // A caregiver taps exactly these locations to put something in them, and
    // has to be able to see what is already there.
    final spoken = await tapAt(
      tester,
      placed: (cell: cell(0, 0), button: button(label: 'turn', vocabLevel: 2)),
      vocabLevel: 1,
      showHidden: true,
    );

    expect(spoken, ['turn']);
  });
}
