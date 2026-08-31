import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/grid/cell_layout.dart';
import 'package:wordbridge/features/grid/grid_geometry.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';

/// §4.6b. The one place a location becomes a rectangle.
///
/// Both boards draw the same board set — the user's and the caregiver's — and
/// they place a cell identically or they are not looking at the same thing. It
/// was written out twice before this existed, which is two chances to drift on
/// the one measurement in this app that may never differ.
void main() {
  Cell cellAt(int row, int col, {int spanRows = 1, int spanCols = 1}) => Cell(
    id: '$row:$col',
    boardId: 'b',
    row: row,
    col: col,
    spanRows: spanRows,
    spanCols: spanCols,
    state: CellState.emptyReserved,
    createdAt: 0,
  );

  List<PlacedCell> grid(int rows, int cols) => [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++) (cell: cellAt(r, c), button: null),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(600, 400),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );
  }

  group('where a cell lands', () {
    testWidgets('every location is drawn, occupied or not', (tester) async {
      await pump(
        tester,
        CellLayout(
          rows: 3,
          cols: 4,
          cells: grid(3, 4),
          cellBuilder: (placed) => const ColoredBox(color: Colors.blue),
        ),
      );

      // Reserved locations render as quiet blanks rather than collapsing,
      // which is the visible half of "vocabulary grows into place".
      // Scoped to the layout: the app's own background is a ColoredBox too.
      expect(
        find.descendant(
          of: find.byType(CellLayout),
          matching: find.byType(ColoredBox),
        ),
        findsNWidgets(12),
      );
    });

    testWidgets('at exactly the rectangle the geometry gives it', (
      tester,
    ) async {
      const size = Size(600, 400);
      await pump(
        tester,
        CellLayout(
          rows: 3,
          cols: 4,
          cells: grid(3, 4),
          cellBuilder: (placed) => const SizedBox.expand(),
        ),
        size: size,
      );

      final geometry = GridGeometry(rows: 3, cols: 4, size: size);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 4; c++) {
          final rect = tester.getRect(find.byKey(ValueKey('$r:$c')));
          final expected = geometry.rectFor(r, c);
          expect(rect.width, closeTo(expected.width, 0.01), reason: '$r,$c');
          expect(rect.height, closeTo(expected.height, 0.01), reason: '$r,$c');
        }
      }
    });

    testWidgets('and a cell that spans takes the room of what it spans', (
      tester,
    ) async {
      await pump(
        tester,
        CellLayout(
          rows: 2,
          cols: 2,
          cells: [
            (cell: cellAt(0, 0, spanCols: 2), button: null),
            (cell: cellAt(1, 0), button: null),
            (cell: cellAt(1, 1), button: null),
          ],
          cellBuilder: (placed) => const SizedBox.expand(),
        ),
      );

      final wide = tester.getRect(find.byKey(const ValueKey('0:0')));
      final one = tester.getRect(find.byKey(const ValueKey('1:0')));
      expect(wide.width, greaterThan(one.width * 1.5));
    });
  });

  group('what it does not decide', () {
    testWidgets('what goes in the rectangle', (tester) async {
      // The whole point of the hook: the user reads the picture, the caregiver
      // reads the word and judges the picture, and neither board should have
      // to own the placement to say so.
      await pump(
        tester,
        CellLayout(
          rows: 1,
          cols: 2,
          cells: grid(1, 2),
          cellBuilder: (placed) =>
              Text('${placed.cell.row},${placed.cell.col}'),
        ),
      );

      expect(find.text('0,0'), findsOneWidget);
      expect(find.text('0,1'), findsOneWidget);
    });
  });

  group('keying', () {
    testWidgets('is by location, so a board swap reuses the widget', (
      tester,
    ) async {
      // Keyed by content, swapping boards would tear the grid down and build
      // it again — and a word moving away would take its square with it.
      await pump(
        tester,
        CellLayout(
          rows: 1,
          cols: 2,
          cells: grid(1, 2),
          cellBuilder: (placed) => const SizedBox.expand(),
        ),
      );

      expect(find.byKey(const ValueKey('0:0')), findsOneWidget);
      expect(find.byKey(const ValueKey('0:1')), findsOneWidget);
    });
  });

  group('what is drawn over the grid', () {
    testWidgets('is given the same geometry the cells were placed with', (
      tester,
    ) async {
      // An overlay anchored to a location rather than to whichever key happens
      // to occupy it — the finder's ring, and the two-corner hold.
      const size = Size(600, 400);
      await pump(
        tester,
        CellLayout(
          rows: 2,
          cols: 2,
          cells: grid(2, 2),
          cellBuilder: (placed) => const SizedBox.expand(),
          overlay: (geometry) => [
            Positioned.fromRect(
              rect: geometry.rectFor(1, 1),
              child: const ColoredBox(key: ValueKey('ring'), color: Colors.red),
            ),
          ],
        ),
        size: size,
      );

      expect(
        tester.getRect(find.byKey(const ValueKey('ring'))),
        tester.getRect(find.byKey(const ValueKey('1:1'))),
      );
    });

    testWidgets('and nothing is drawn where there is no overlay', (
      tester,
    ) async {
      await pump(
        tester,
        CellLayout(
          rows: 1,
          cols: 1,
          cells: grid(1, 1),
          cellBuilder: (placed) => const SizedBox.expand(),
        ),
      );

      expect(find.byKey(const ValueKey('ring')), findsNothing);
    });
  });
}
