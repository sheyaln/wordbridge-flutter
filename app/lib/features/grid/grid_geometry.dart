import 'dart:ui';

/// Exact pixel rectangles for every location on a grid.
///
/// Positions are computed once from the measured surface and every cell is
/// placed absolutely. Flow layouts (wrap, flex) are unusable here: sub-pixel
/// rounding shifts targets by a pixel or two between rebuilds, which is
/// invisible on screen and quietly corrosive to a motor plan built on hitting
/// the same physical spot without looking.
class GridGeometry {
  const GridGeometry({
    required this.rows,
    required this.cols,
    required this.size,
    this.gutter = 4.0,
  });

  final int rows;
  final int cols;
  final Size size;
  final double gutter;

  double get cellWidth => (size.width - gutter * (cols + 1)) / cols;
  double get cellHeight => (size.height - gutter * (rows + 1)) / rows;

  Rect rectFor(int row, int col, {int spanRows = 1, int spanCols = 1}) {
    final left = gutter + col * (cellWidth + gutter);
    final top = gutter + row * (cellHeight + gutter);
    final width = cellWidth * spanCols + gutter * (spanCols - 1);
    final height = cellHeight * spanRows + gutter * (spanRows - 1);
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Minimum comfortable target: 44pt (Apple HIG) / 48dp (Material).
  static const minTouchTarget = 48.0;

  bool get meetsMinimumTouchTarget =>
      cellWidth >= minTouchTarget && cellHeight >= minTouchTarget;
}
