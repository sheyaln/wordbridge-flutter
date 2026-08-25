import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import '../../theme/fitzgerald.dart';
import 'grid_geometry.dart';

/// One location and whatever currently occupies it.
typedef PlacedCell = ({Cell cell, Button? button});

/// Renders a board as absolutely positioned cells.
///
/// Every location is drawn, occupied or not, so the grid a user sees is the
/// same shape whether it holds 36 words or 84. Reserved locations render as
/// quiet blanks rather than collapsing, which is the visible half of the
/// promise that vocabulary grows into place instead of rearranging.
class GridSurface extends StatelessWidget {
  const GridSurface({
    super.key,
    required this.rows,
    required this.cols,
    required this.cells,
    required this.vocabLevel,
    required this.colourScheme,
    required this.onSelect,
  });

  final int rows;
  final int cols;
  final List<PlacedCell> cells;

  /// Buttons above this level are not rendered. They keep their locations.
  final int vocabLevel;

  final ColourScheme colourScheme;
  final void Function(PlacedCell) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = GridGeometry(
          rows: rows,
          cols: cols,
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );

        return Stack(
          children: [
            for (final placed in cells)
              Positioned.fromRect(
                rect: geometry.rectFor(
                  placed.cell.row,
                  placed.cell.col,
                  spanRows: placed.cell.spanRows,
                  spanCols: placed.cell.spanCols,
                ),
                // Keyed by location, not by content, so swapping boards
                // reuses the same widget rather than tearing down the grid.
                child: KeyedSubtree(
                  key: ValueKey('${placed.cell.row}:${placed.cell.col}'),
                  child: _Cell(
                    placed: placed,
                    vocabLevel: vocabLevel,
                    colourScheme: colourScheme,
                    onSelect: onSelect,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.placed,
    required this.vocabLevel,
    required this.colourScheme,
    required this.onSelect,
  });

  final PlacedCell placed;
  final int vocabLevel;
  final ColourScheme colourScheme;
  final void Function(PlacedCell) onSelect;

  bool get _isVisible {
    final b = placed.button;
    return b != null && !b.hidden && b.vocabLevel <= vocabLevel;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const _ReservedCell();

    final button = placed.button!;
    final colour = Fitzgerald.colourFor(colourScheme, button.partOfSpeech);

    return Material(
      color: colour,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        // Speaking on press rather than release: the gap between them is
        // perceptible, and responsiveness is what makes a device feel like a
        // voice. Release and dwell modes are per-profile settings.
        onTap: () => onSelect(placed),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                button.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: button.isSystem
                      ? FontWeight.w500
                      : FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A location held open for future vocabulary. Drawn, not omitted.
class _ReservedCell extends StatelessWidget {
  const _ReservedCell();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
    );
  }
}
