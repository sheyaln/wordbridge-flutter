import 'package:flutter/material.dart';

import 'grid_geometry.dart';
import 'grid_surface.dart' show PlacedCell;

/// Puts cells at their permanent coordinates, and nothing else.
///
/// The one place a location becomes a rectangle. Two boards draw the same
/// board set — the user's and the caregiver's — and they must place a cell
/// identically or they are not looking at the same thing: a caregiver auditing
/// where a word sits would be auditing a picture of somewhere else, and the
/// editor's "tap the location you mean" would mean a different location.
///
/// It was written out twice before this existed (§4.6b). What differed between
/// the two was never the placement; it was what goes *in* the rectangle, which
/// is what [cellBuilder] is for.
///
/// Nothing here decides what a cell looks like, whether it may be pressed, or
/// what a press means. A caller that wants gestures over the whole grid adds
/// them through [overlay], which is handed the same geometry so an overlay is
/// anchored to a location rather than to whatever key happens to occupy it.
class CellLayout extends StatelessWidget {
  const CellLayout({
    super.key,
    required this.rows,
    required this.cols,
    required this.cells,
    required this.cellBuilder,
    this.overlay,
  });

  final int rows;
  final int cols;
  final List<PlacedCell> cells;

  /// What to draw in one location.
  final Widget Function(PlacedCell placed) cellBuilder;

  /// Anything drawn over the grid, given the geometry it is anchored to.
  final List<Widget> Function(GridGeometry geometry)? overlay;

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
                // Keyed by location, not by content. Swapping boards then
                // reuses the same widget rather than tearing down the grid,
                // and a word moving away leaves its square standing.
                child: KeyedSubtree(
                  key: ValueKey('${placed.cell.row}:${placed.cell.col}'),
                  child: cellBuilder(placed),
                ),
              ),
            ...?overlay?.call(geometry),
          ],
        );
      },
    );
  }
}
