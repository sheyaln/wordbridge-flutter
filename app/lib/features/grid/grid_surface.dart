import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import '../../theme/fitzgerald.dart';
import '../auth/corner_pair_hold.dart';
import '../symbols/symbol_pack.dart';
import '../symbols/symbol_resolver.dart';
import 'cell_layout.dart';
import 'symbol_view.dart';

/// One location and whatever currently occupies it.
typedef PlacedCell = ({Cell cell, Button? button});

/// Renders a board as absolutely positioned cells.
///
/// Every location is drawn, occupied or not, so the grid a user sees is the
/// same shape whether it holds 36 words or 84. Reserved locations render as
/// quiet blanks rather than collapsing, which is the visible half of the
/// promise that vocabulary grows into place instead of rearranging.
class GridSurface extends StatefulWidget {
  const GridSurface({
    super.key,
    required this.rows,
    required this.cols,
    required this.cells,
    required this.vocabLevel,
    required this.colorConvention,
    required this.onSelect,
    this.showHidden = false,
    this.viewAll = false,
    this.resolver,
    this.symbolPackIds = boardSymbolPackIds,
    this.isAvailable,
    this.pairHold,
    this.onPairHold,
    this.pointAt,
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

  /// Draws every word, whatever its level and whether or not it is hidden.
  ///
  /// §4.42's view-all: a caregiver seeing the whole board and then leaving it
  /// exactly as it was. Nothing is written — no level is raised and nothing is
  /// unhidden — so turning it off restores the board to the cell.
  ///
  /// It does not break §5 non-negotiable 8. A location the user cannot see
  /// never speaks; this makes them all visible, so all of them may.
  final bool viewAll;

  final ColorConvention colorConvention;
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

  /// How long the two bottom corners have to be held together to ask for
  /// caregiver mode, or null where that gesture is not the device's.
  final Duration? pairHold;

  /// Both bottom corners held for [pairHold].
  final VoidCallback? onPairHold;

  /// A location to point at — the next key on a route the finder is walking,
  /// or the word it walked to.
  ///
  /// Drawn over the grid rather than into the key, and it never intercepts a
  /// touch. A board somebody has learned has to look the same whether or not
  /// something is pointing at it, and the key under the ring is the one they
  /// are being shown how to press.
  final ({int row, int col})? pointAt;

  @override
  State<GridSurface> createState() => _GridSurfaceState();
}

class _GridSurfaceState extends State<GridSurface> {
  /// Whether the last thing the two bottom corners did was open caregiver
  /// mode.
  ///
  /// A key acts on release, and both are still held when the gesture
  /// completes, so the releases that end it would otherwise send the user home
  /// and onto a second page on their way into settings. Cleared by the next
  /// contact rather than by that release: the release is dispatched to this
  /// widget before it reaches the key underneath, so clearing there would
  /// clear it a moment too early.
  bool _pairFired = false;

  bool _isPairAnchor(Cell cell) =>
      cell.row == widget.rows - 1 &&
      (cell.col == 0 || cell.col == widget.cols - 1);

  void _select(PlacedCell placed) {
    if (_pairFired && _isPairAnchor(placed.cell)) return;
    widget.onSelect(placed);
  }

  @override
  Widget build(BuildContext context) {
    final pairHold = widget.pairHold;

    return CellLayout(
      rows: widget.rows,
      cols: widget.cols,
      cells: widget.cells,
      cellBuilder: (placed) => _Cell(
        placed: placed,
        vocabLevel: widget.vocabLevel,
        colorConvention: widget.colorConvention,
        showHidden: widget.showHidden,
        viewAll: widget.viewAll,
        resolver: widget.resolver,
        symbolPackIds: widget.symbolPackIds,
        isAvailable: widget.isAvailable,
        onSelect: _select,
      ),
      overlay: (geometry) => [
        if (widget.pointAt case final at?)
          Positioned.fromRect(
            rect: geometry.rectFor(at.row, at.col),
            child: const IgnorePointer(child: _Pointer()),
          ),

        // Over the grid, and anchored to the two locations rather than to
        // the keys that happen to occupy them — the bottom right is a
        // reserved blank on a board with no second page, and the gesture
        // has to mean the same thing there.
        if (pairHold != null && widget.onPairHold != null)
          Positioned.fill(
            child: CornerPairHold(
              first: geometry.rectFor(widget.rows - 1, 0),
              second: geometry.rectFor(widget.rows - 1, widget.cols - 1),
              hold: pairHold,
              onTouched: () => _pairFired = false,
              onComplete: () {
                _pairFired = true;
                widget.onPairHold!();
              },
            ),
          ),
      ],
    );
  }
}

/// The ring that says "this key, next".
///
/// Two rings rather than one. A key's color is its part of speech, so a single
/// ring in any one color is the color of some other part of speech and
/// disappears against the keys of that kind — a dark ring inside a light one
/// reads on all of them.
class _Pointer extends StatelessWidget {
  const _Pointer();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black87, width: 4),
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.placed,
    required this.vocabLevel,
    required this.colorConvention,
    required this.showHidden,
    required this.viewAll,
    required this.resolver,
    required this.symbolPackIds,
    required this.isAvailable,
    required this.onSelect,
  });

  final PlacedCell placed;
  final int vocabLevel;
  final ColorConvention colorConvention;
  final bool showHidden;
  final bool viewAll;
  final SymbolResolver? resolver;
  final List<String> symbolPackIds;
  final bool Function(Button)? isAvailable;
  final void Function(PlacedCell) onSelect;

  bool get _isMasked {
    final b = placed.button;
    if (b == null) return true;
    // Every word, whatever it would ordinarily be spared from. A reserved
    // location is still reserved: there is nothing there to show.
    if (viewAll) return false;
    if (b.hidden || b.vocabLevel > vocabLevel) return true;
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

    final color = Fitzgerald.colorFor(colorConvention, button!.partOfSpeech);

    return Material(
      color: color,
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
