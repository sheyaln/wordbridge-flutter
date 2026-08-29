import 'dart:async';

import 'package:flutter/material.dart';

import 'hold_ring.dart';

/// Two locations at opposite ends of the board, held at the same time.
///
/// A single held point is findable by accident: a hand resting on a tablet
/// produces one, and so does a user working across a grid with their palm
/// down. Two contacts at opposite ends of the same board, unbroken for
/// seconds, is not something either produces — and unlike an invisible target
/// it can be written in one sentence and taught.
///
/// It takes rectangles rather than buttons because the *locations* are the
/// gesture. What occupies them differs by board and by page — home and the
/// forward-paging key on the shipped frame, a reserved blank where a board has
/// no second page — and the gesture has to mean the same thing on all of them.
///
/// Every touch still reaches whatever is underneath. Suppressing the two keys
/// when the hold completes is the caller's job, because the caller is what
/// knows a key from a location.
class CornerPairHold extends StatefulWidget {
  const CornerPairHold({
    super.key,
    required this.first,
    required this.second,
    required this.hold,
    required this.onComplete,
    required this.onTouched,
  });

  /// The two locations, in the coordinates of the stack this sits in.
  final Rect first;
  final Rect second;

  final Duration hold;

  /// Both locations held for [hold]. Neither key may act on the release that
  /// follows.
  final VoidCallback onComplete;

  /// A fresh contact on either location.
  ///
  /// The moment a previously completed hold stops suppressing anything: the
  /// keys act on release, and a release arrives after the caller has already
  /// been told the hold finished.
  final VoidCallback onTouched;

  @override
  State<CornerPairHold> createState() => _CornerPairHoldState();
}

class _CornerPairHoldState extends State<CornerPairHold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.hold)
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          _stop();
          widget.onComplete();
        });

  /// The pointer resting on each location, if any. Held by identity so a
  /// second finger landing on one corner cannot stand in for the first.
  int? _onFirst;
  int? _onSecond;

  Timer? _revealTimer;
  bool _visible = false;

  /// How long before anything is drawn. A quarter of the hold, so the rule
  /// holds however long the caregiver has set it to.
  Duration get _revealAfter => widget.hold ~/ 4;

  void _down(bool first, PointerDownEvent event) {
    widget.onTouched();

    if (first) {
      _onFirst ??= event.pointer;
    } else {
      _onSecond ??= event.pointer;
    }

    if (_onFirst == null || _onSecond == null) return;

    _revealTimer?.cancel();
    _revealTimer = Timer(_revealAfter, () {
      if (mounted) setState(() => _visible = true);
    });
    _controller.forward(from: 0);
  }

  void _lift(bool first, PointerEvent event) {
    if (first && _onFirst == event.pointer) {
      _onFirst = null;
    } else if (!first && _onSecond == event.pointer) {
      _onSecond = null;
    }
    // Releasing either end abandons the hold, and both keys then do what they
    // have always done. Nothing needs suppressing on the way out: they act on
    // release, and this release is the one saying the gesture was not what the
    // user meant.
    _stop();
  }

  void _stop() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _controller.stop();
    _controller.value = 0;
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void didUpdateWidget(CornerPairHold old) {
    super.didUpdateWidget(old);
    if (old.hold != widget.hold) _controller.duration = widget.hold;
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _anchor(bool first, Rect rect) {
    return Positioned.fromRect(
      rect: rect,
      child: Listener(
        onPointerDown: (event) => _down(first, event),
        onPointerUp: (event) => _lift(first, event),
        onPointerCancel: (event) => _lift(first, event),
        // Translucent, so the key underneath keeps every touch. A gesture that
        // cost somebody their home key would be a board that stopped answering
        // in a way its user cannot report.
        behavior: HitTestBehavior.translucent,
        child: _visible
            ? AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => HoldRing(progress: _controller.value),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [_anchor(true, widget.first), _anchor(false, widget.second)],
    );
  }
}
