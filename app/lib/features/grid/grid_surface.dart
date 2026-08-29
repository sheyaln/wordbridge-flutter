import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import '../../theme/fitzgerald.dart';
import '../symbols/symbol_resolver.dart';
import 'grid_geometry.dart';
import 'symbol_view.dart';

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
    this.showHidden = false,
    this.resolver,
    this.symbolPackIds = const ['core'],
    this.isAvailable,
  });

  final int rows;
  final int cols;
  final List<PlacedCell> cells;

  /// Buttons above this level are not rendered. They keep their locations.
  final int vocabLevel;

  /// Renders masked words dimmed instead of blank.
  ///
  /// Only ever true in the editor. A caregiver deciding where to put a new
  /// word needs to see that a location is already spoken for; the AAC user
  /// must not, or the mask means nothing.
  final bool showHidden;

  final ColourScheme colourScheme;
  final void Function(PlacedCell) onSelect;

  /// Absent in tests and wherever pictures are not wanted; the grid then
  /// renders labels only, which is a complete, working board.
  final SymbolResolver? resolver;

  /// Packs to look in, in order, for buttons that have no symbol of their own.
  final List<String> symbolPackIds;

  /// Whether a button can be used right now.
  ///
  /// Used for word endings, which only make sense after certain kinds of
  /// word. A button that fails this is drawn as a reserved blank — it keeps
  /// its location and reappears in exactly the same place, so a temporarily
  /// unusable key never becomes a moved one.
  final bool Function(Button)? isAvailable;

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
                    showHidden: showHidden,
                    resolver: resolver,
                    symbolPackIds: symbolPackIds,
                    isAvailable: isAvailable,
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
    required this.showHidden,
    required this.resolver,
    required this.symbolPackIds,
    required this.isAvailable,
    required this.onSelect,
  });

  final PlacedCell placed;
  final int vocabLevel;
  final ColourScheme colourScheme;
  final bool showHidden;
  final SymbolResolver? resolver;
  final List<String> symbolPackIds;
  final bool Function(Button)? isAvailable;
  final void Function(PlacedCell) onSelect;

  bool get _isMasked {
    final b = placed.button;
    if (b == null || b.hidden || b.vocabLevel > vocabLevel) return true;
    return !(isAvailable?.call(b) ?? true);
  }

  Widget _content(Button button) {
    final resolver = this.resolver;
    if (resolver == null) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          button.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: button.isSystem ? FontWeight.w500 : FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      );
    }

    // The picture chosen for this button wins; a button with none takes
    // whatever the packs carry for its word. A button neither illustrates
    // renders as text, which is a complete button, not a degraded one.
    return SymbolView(
      resolver: resolver,
      symbolId: button.symbolId,
      label: button.label,
      packIds: symbolPackIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = placed.button;

    if (_isMasked) {
      // A masked location must not speak. Whatever is behind it — a word above
      // the current level, an ending that does not apply yet, a word switched
      // off — the user cannot see it, and a blank that says a word nobody
      // chose is worse than one that does nothing at all.
      //
      // The editor is the exception: a caregiver taps exactly these locations
      // to put something in them, and needs to know what is already there.
      if (!showHidden || button == null) {
        return _ReservedCell(onTap: showHidden ? () => onSelect(placed) : null);
      }
      return _MaskedCell(label: button.label, onTap: () => onSelect(placed));
    }

    final colour = Fitzgerald.colourFor(colourScheme, button!.partOfSpeech);

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
          child: Center(child: _content(button)),
        ),
      ),
    );
  }
}

/// A location held open for future vocabulary. Drawn, not omitted.
class _ReservedCell extends StatelessWidget {
  const _ReservedCell({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
        ),
      ),
    );
  }
}

/// A word the user cannot currently see, shown only to a caregiver.
///
/// Drawn dimmed rather than blank so it reads as "occupied, not yet revealed"
/// — the distinction that keeps someone from putting a new word on top of a
/// position already reserved for this one.
class _MaskedCell extends StatelessWidget {
  const _MaskedCell({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F0F0),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFCCCCCC),
              style: BorderStyle.solid,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Opacity(
                  opacity: 0.45,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
