import 'package:flutter/material.dart';

import '../../db/seed/band_layout.dart';
import 'grid_geometry.dart';
import 'region_labels.dart';

/// Height of the strip that names column regions, and width of the one that
/// names row regions.
///
/// Chrome, outside the grid. Nothing here may take a location: the reserved
/// lines are exactly where a caregiver's own words are meant to land, and a
/// label that consumed one would be teaching the layout by damaging it.
const regionLabelExtent = 22.0;

/// Names each run of locations by what it is for.
///
/// Off unless a caregiver asks for it. This is scaffolding for the people
/// teaching a board, not for the person speaking on it, and it costs the grid
/// the space it occupies.
///
/// A band's label sits over the lines it owns, including the ones it holds
/// open and never filled — a reserved column is the most useful thing on the
/// board to be able to name, and the one with no word of its own to give it
/// away.
class RegionLabelStrip extends StatelessWidget {
  const RegionLabelStrip({
    super.key,
    required this.regions,
    required this.rows,
    required this.cols,
    required this.axis,
    required this.gridWidth,
    required this.gridHeight,
  });

  final BoardRegions regions;
  final int rows;
  final int cols;

  /// The grid's own measurements, so the strip lines up with it on the axis it
  /// does not share.
  final double gridWidth;
  final double gridHeight;

  /// Which way the labels run, which is the axis the bands claim.
  final BandAxis axis;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The same geometry the grid is drawn from, so a label sits over its
        // band however the cells round. Only one axis of the strip matches the
        // grid — the other is the strip's own thickness — and only that axis
        // is read back out.
        final geometry = GridGeometry(
          rows: rows,
          cols: cols,
          size: axis == BandAxis.columns
              ? Size(constraints.maxWidth, gridHeight)
              : Size(gridWidth, constraints.maxHeight),
        );

        return Stack(
          children: [
            for (final band in regions.bands)
              Positioned.fromRect(
                rect: _rectFor(geometry, band, constraints),
                child: _Label(
                  text: regionLabel(band.name),
                  colour: colour,
                  // Down the side, the strip is as narrow as a label is tall,
                  // so the word has to run along the row rather than across
                  // it. Reading bottom to top is the convention a spine uses
                  // and keeps the first letter next to the first cell.
                  quarterTurns: axis == BandAxis.columns ? 0 : 3,
                ),
              ),
          ],
        );
      },
    );
  }

  Rect _rectFor(
    GridGeometry geometry,
    ({String name, int first, int last}) band,
    BoxConstraints constraints,
  ) {
    if (axis == BandAxis.columns) {
      final start = geometry.rectFor(0, band.first);
      final end = geometry.rectFor(0, band.last);
      return Rect.fromLTRB(start.left, 0, end.right, constraints.maxHeight);
    }

    final start = geometry.rectFor(band.first, 0);
    final end = geometry.rectFor(band.last, 0);
    return Rect.fromLTRB(0, start.top, constraints.maxWidth, end.bottom);
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.text,
    required this.colour,
    required this.quarterTurns,
  });

  final String text;
  final Color colour;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final edge = BorderSide(color: colour.withValues(alpha: 0.4));

    return Padding(
      padding: quarterTurns == 0
          ? const EdgeInsets.symmetric(horizontal: 2)
          : const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: quarterTurns == 0
              ? Border(bottom: edge)
              : Border(right: edge),
        ),
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: Center(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: colour,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
