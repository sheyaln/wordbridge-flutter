import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../auth/hold_ring.dart';
import '../editor/symbol_picker.dart' show removedPictureSymbolId;
import '../grid/grid_geometry.dart';
import '../grid/grid_surface.dart' show PlacedCell;
import 'developer_mode.dart';

/// What one location says about itself while developer mode is on.
///
/// A pure function of rows the grid is already holding, so nothing drawn over
/// a board somebody speaks on can throw, wait, or ask the database anything.
/// Short strings, in the order they answer the three questions worth asking of
/// a location: where is it, why is it blank, and where did its picture come
/// from.
///
/// Coordinates are zero based, as the `cells` table numbers them. The editor
/// counts from one because it is talking to a caregiver about a grid they can
/// see; this is talking about a row.
List<String> developerTags(
  PlacedCell placed, {
  required DeveloperView view,
  required int vocabLevel,
  bool Function(Button)? isAvailable,
}) {
  final cell = placed.cell;
  final button = placed.button;

  return [
    if (view.coordinates) '${cell.row},${cell.col}',
    if (view.cellState)
      if (button == null)
        'free'
      else if (button.hidden)
        'hidden'
      else if (button.vocabLevel > vocabLevel)
        'level ${button.vocabLevel}'
      else if (!(isAvailable?.call(button) ?? true))
        'not yet',
    if (view.pictureSource && button != null)
      if (button.symbolId == removedPictureSymbolId)
        'no picture'
      else if (button.symbolId != null)
        'own picture'
      else
        'by word',
  ];
}

/// The tags, drawn over the grid and never into it.
///
/// Over rather than in, for the reason the finder's ring is: a board somebody
/// has learned has to be the same board with developer mode on, and a tag that
/// changed how a key lays out would move the picture and the word inside it.
/// It never takes a touch either, so no location can be made to stop answering
/// by switching an overlay on.
class DeveloperOverlay extends StatelessWidget {
  const DeveloperOverlay({
    super.key,
    required this.geometry,
    required this.cells,
    required this.view,
    required this.vocabLevel,
    this.isAvailable,
  });

  final GridGeometry geometry;
  final List<PlacedCell> cells;
  final DeveloperView view;
  final int vocabLevel;
  final bool Function(Button)? isAvailable;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final placed in cells)
            if (developerTags(
                  placed,
                  view: view,
                  vocabLevel: vocabLevel,
                  isAvailable: isAvailable,
                )
                case final tags when tags.isNotEmpty)
              Positioned.fromRect(
                rect: geometry.rectFor(
                  placed.cell.row,
                  placed.cell.col,
                  spanRows: placed.cell.spanRows,
                  spanCols: placed.cell.spanCols,
                ),
                child: _Tags(tags),
              ),
        ],
      ),
    );
  }
}

/// Top left of the location, where a picture is least likely to be.
///
/// On its own ground rather than plain text, because these are drawn over
/// eleven button colors and white text on yellow says nothing.
///
/// Scaled down rather than allowed to run over the edge. A 10 by 14 grid on a
/// small tablet gives a cell barely thirty points high, and an overflow on the
/// talk screen is an error reported from paint — on the one screen in this app
/// that is not allowed to produce one.
class _Tags extends StatelessWidget {
  const _Tags(this.tags);

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tag in tags)
                    Text(
                      tag,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 9,
                        height: 1.2,
                        color: Color(0xFFFFFFFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A location held down, over the grid rather than on the keys.
///
/// **Nothing is added to the tap path.** A long press recognizer on the key
/// itself would put a second contender in the gesture arena for every press on
/// the board, and this is the one screen where a press is somebody's voice. So
/// this is the shape the caregiver gestures already use: a translucent
/// [Listener] over the grid with a timer of its own, which every touch passes
/// straight through. The key underneath is untouched and speaks exactly as
/// fast as it did before.
///
/// Suppressing the press that ends a completed hold is the caller's job, for
/// the reason the two corner hold gives: the caller is what knows a key from a
/// location.
class DeveloperHold extends StatefulWidget {
  const DeveloperHold({
    super.key,
    required this.geometry,
    required this.hold,
    required this.onHeld,
    required this.onTouched,
  });

  final GridGeometry geometry;
  final Duration hold;

  /// A location held for [hold].
  final void Function(int row, int col) onHeld;

  /// A fresh contact anywhere on the grid, which is where a previously
  /// completed hold stops suppressing the key it fired on.
  final VoidCallback onTouched;

  @override
  State<DeveloperHold> createState() => _DeveloperHoldState();
}

class _DeveloperHoldState extends State<DeveloperHold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.hold)
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          final at = _at;
          _stop();
          if (at != null) widget.onHeld(at.row, at.col);
        });

  /// Which location the finger went down on, and which pointer it was.
  ///
  /// Held by identity so a second finger landing elsewhere cannot carry on a
  /// hold the first one abandoned.
  ({int row, int col})? _at;
  int? _pointer;

  Timer? _revealTimer;
  bool _visible = false;

  /// A quarter of the hold, so the ring is feedback for somebody already
  /// holding rather than an affordance inviting the gesture.
  Duration get _revealAfter => widget.hold ~/ 4;

  void _down(PointerDownEvent event) {
    widget.onTouched();
    if (_pointer != null) return;

    final at = widget.geometry.locationAt(event.localPosition);
    if (at == null) return;

    _pointer = event.pointer;
    _at = at;
    _revealTimer = Timer(_revealAfter, () {
      if (mounted) setState(() => _visible = true);
    });
    _controller.forward(from: 0);
  }

  /// Abandons the hold the moment the finger leaves the location it started
  /// on. A hold that slid across three keys and fired on the third would open
  /// a location nobody chose.
  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if (widget.geometry.locationAt(event.localPosition) != _at) _stop();
  }

  void _lift(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _stop();
  }

  void _stop() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _controller.stop();
    _controller.value = 0;
    _pointer = null;
    _at = null;
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void didUpdateWidget(DeveloperHold old) {
    super.didUpdateWidget(old);
    if (old.hold != widget.hold) _controller.duration = widget.hold;
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;

    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _lift,
      onPointerCancel: _lift,
      // Translucent, so the key underneath keeps every touch. A gesture that
      // cost somebody a word would be a board that stopped answering in a way
      // its user cannot report.
      behavior: HitTestBehavior.translucent,
      child: at == null || !_visible
          ? const SizedBox.expand()
          : Stack(
              children: [
                Positioned.fromRect(
                  rect: widget.geometry.rectFor(at.row, at.col),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) =>
                        HoldRing(progress: _controller.value),
                  ),
                ),
              ],
            ),
    );
  }
}
