import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/developer/board_overlay.dart';
import 'package:wordbridge/features/developer/developer_mode.dart';
import 'package:wordbridge/features/grid/grid_geometry.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';

/// Developer mode must be free.
///
/// Two things are being guarded here and the first one is the whole reason the
/// layer is shaped the way it is. **A press must never be delayed.** The board
/// is somebody's voice, and a long press recognizer on the key itself would
/// put a second contender in the gesture arena for every press — so the hold
/// is a translucent layer over the grid with a timer of its own, and a tap
/// through it has to speak in the same frame it always did.
///
/// The second is that nothing developer mode draws may take a touch, move a
/// key, or leave a word spoken that nobody chose: the release that ends a
/// completed hold is a release on a key, and a board that said the word under
/// every inspected location would put words into the sentence every time
/// somebody looked at one.
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
    String? symbolId,
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
    symbolId: symbolId,
    createdAt: 0,
    updatedAt: 0,
  );

  group('what a location says about itself', () {
    test('its own coordinates, as the database counts them', () {
      expect(
        developerTags(
          (cell: cell(3, 5), button: button(label: 'want')),
          view: const DeveloperView(coordinates: true),
          vocabLevel: 3,
        ),
        ['3,5'],
      );
    });

    test('and nothing at all when every overlay is off', () {
      expect(
        developerTags(
          (cell: cell(3, 5), button: button(label: 'want')),
          view: const DeveloperView(),
          vocabLevel: 3,
        ),
        isEmpty,
      );
    });

    test('why a blank location is blank', () {
      // The four cases the board has for drawing nothing, which are otherwise
      // indistinguishable: a caregiver looking at two identical gray squares
      // cannot tell a reserved location from a word somebody switched off.
      List<String> state(PlacedCell placed, {bool available = true}) =>
          developerTags(
            placed,
            view: const DeveloperView(cellState: true),
            vocabLevel: 1,
            isAvailable: (_) => available,
          );

      expect(state((cell: cell(0, 0), button: null)), ['free']);
      expect(
        state((cell: cell(0, 0), button: button(label: 'shit', hidden: true))),
        ['hidden'],
      );
      expect(
        state((cell: cell(0, 0), button: button(label: 'turn', vocabLevel: 2))),
        ['level 2'],
      );
      expect(
        state((
          cell: cell(0, 0),
          button: button(label: '+ed'),
        ), available: false),
        ['not yet'],
      );
      expect(
        state((cell: cell(0, 0), button: button(label: 'want'))),
        isEmpty,
        reason: 'a drawn word was marked as though it were being withheld',
      );
    });

    test('and where its picture came from', () {
      List<String> source(String? symbolId) => developerTags(
        (cell: cell(0, 0), button: button(label: 'want', symbolId: symbolId)),
        view: const DeveloperView(pictureSource: true),
        vocabLevel: 3,
      );

      // The distinction the picker exists to change: a wrong picture teaches a
      // false association, and "somebody chose this" and "the word matched
      // this" want different actions.
      expect(source(null), ['by word']);
      expect(source('symbol-123'), ['own picture']);
      expect(source('symbol-removed'), ['no picture']);
    });
  });

  group('the board under the overlay', () {
    /// A grid one cell wide, so a tap anywhere in the surface is a tap on it.
    Future<List<String>> pumpAndTap(
      WidgetTester tester, {
      DeveloperView? developer,
      void Function(PlacedCell)? onHold,
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
                cells: [(cell: cell(0, 0), button: button(label: 'want'))],
                vocabLevel: 3,
                colorConvention: ColorConvention.modifiedFitzgerald,
                developer: developer,
                onDeveloperHold: onHold,
                onSelect: (p) => spoken.add(p.button!.label),
              ),
            ),
          ),
        ),
      );

      return spoken;
    }

    testWidgets('a tap still speaks, in the frame it always did', (
      tester,
    ) async {
      // §5 non-negotiable 2, and the reason the hold is a Listener rather than
      // a long press recognizer. Nothing here waits out the hold: one tap, one
      // frame, one word. A failure means the arena is deciding between the tap
      // and something else before the key may act.
      final spoken = await pumpAndTap(
        tester,
        developer: DeveloperView(coordinates: true, hold: DeveloperMode.hold),
        onHold: (_) {},
      );

      await tester.tap(find.text('want'));
      await tester.pump();

      expect(spoken, ['want']);
    });

    testWidgets('and the tags are drawn over it without taking the touch', (
      tester,
    ) async {
      final spoken = await pumpAndTap(
        tester,
        developer: const DeveloperView(coordinates: true),
      );

      expect(find.text('0,0'), findsOneWidget);

      // Aimed at the tag itself, which is the touch most likely to be stolen.
      await tester.tap(find.text('0,0'), warnIfMissed: false);
      await tester.pump();

      expect(spoken, ['want']);
    });

    testWidgets('nothing is drawn at all with developer mode off', (
      tester,
    ) async {
      await pumpAndTap(tester);
      expect(find.text('0,0'), findsNothing);
    });

    testWidgets('and every tag at once fits the smallest cell this app draws', (
      tester,
    ) async {
      // A 10 by 14 grid on a small tablet gives a cell barely thirty points
      // high. An overflow is an error reported from paint, on the one screen
      // in this app that is not allowed to produce one.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: GridSurface(
                rows: 14,
                cols: 10,
                cells: [
                  for (var row = 0; row < 14; row++)
                    for (var col = 0; col < 10; col++)
                      (
                        cell: cell(row, col),
                        button: button(
                          label: 'communication',
                          vocabLevel: 3,
                          symbolId: 'symbol-123',
                        ),
                      ),
                ],
                vocabLevel: 1,
                colorConvention: ColorConvention.modifiedFitzgerald,
                developer: const DeveloperView(
                  coordinates: true,
                  cellState: true,
                  pictureSource: true,
                ),
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('holding a location', () {
    late List<String> spoken;
    late List<({int row, int col})> held;

    /// Puts a finger down and lets the hold run out.
    ///
    /// Two pumps, not one. A ticker records its start time on the first frame
    /// after it is started, so a single long pump advances the clock past the
    /// hold and hands the controller an elapsed time of zero.
    Future<TestGesture> holdOn(WidgetTester tester, Finder key) async {
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump();
      await tester.pump(DeveloperMode.hold + const Duration(milliseconds: 50));
      return gesture;
    }

    Future<void> pumpBoard(
      WidgetTester tester, {
      Duration? hold = DeveloperMode.hold,
    }) async {
      spoken = [];
      held = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: GridSurface(
                rows: 1,
                cols: 2,
                cells: [
                  (cell: cell(0, 0), button: button(label: 'want')),
                  (cell: cell(0, 1), button: button(label: 'more')),
                ],
                vocabLevel: 3,
                colorConvention: ColorConvention.modifiedFitzgerald,
                developer: DeveloperView(hold: hold),
                onSelect: (p) => spoken.add(p.button!.label),
                onDeveloperHold: (p) =>
                    held.add((row: p.cell.row, col: p.cell.col)),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('opens it, and the release does not speak it', (tester) async {
      await pumpBoard(tester);

      final gesture = await holdOn(tester, find.text('want'));

      expect(held, [(row: 0, col: 0)]);

      await gesture.up();
      await tester.pump();

      expect(
        spoken,
        isEmpty,
        reason: 'inspecting a location also said the word in it',
      );
    });

    testWidgets('and the next tap on it speaks again', (tester) async {
      // The suppression is for one release, not for the location. A key that
      // stayed dead after being looked at would be a board that quietly
      // stopped answering.
      await pumpBoard(tester);

      final gesture = await holdOn(tester, find.text('want'));
      await gesture.up();
      await tester.pump();

      await tester.tap(find.text('want'));
      await tester.pump();

      expect(spoken, ['want']);
    });

    testWidgets('a hold that slides onto another key opens neither', (
      tester,
    ) async {
      await pumpBoard(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('want')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveTo(tester.getCenter(find.text('more')));
      await tester.pump(DeveloperMode.hold + const Duration(milliseconds: 50));

      expect(
        held,
        isEmpty,
        reason: 'a hold that moved opened a location nobody chose',
      );

      await gesture.up();
      await tester.pump();
    });

    testWidgets('and a hold cannot happen at all when it is switched off', (
      tester,
    ) async {
      await pumpBoard(tester, hold: null);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('want')),
      );
      await tester.pump();
      await tester.pump(DeveloperMode.hold * 3);
      await gesture.up();
      await tester.pump();

      expect(held, isEmpty);
      expect(spoken, ['want'], reason: 'the key stopped answering');
    });
  });

  group('finding the location under a finger', () {
    const geometry = GridGeometry(rows: 4, cols: 6, size: Size(600, 400));

    test('answers with the location whose rectangle holds the point', () {
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 6; col++) {
          expect(geometry.locationAt(geometry.rectFor(row, col).center), (
            row: row,
            col: col,
          ));
        }
      }
    });

    test('and with nothing for the gutter and for off the grid', () {
      // A hold that landed in the gap between two keys must open neither,
      // rather than rounding onto whichever one is nearer.
      expect(geometry.locationAt(const Offset(1, 1)), isNull);
      expect(geometry.locationAt(const Offset(-5, 10)), isNull);
      expect(geometry.locationAt(const Offset(10, 10000)), isNull);
    });
  });
}
