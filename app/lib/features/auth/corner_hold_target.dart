import 'dart:async';

import 'package:flutter/material.dart';

import 'caregiver_gesture.dart';
import 'hold_ring.dart';

/// The one-point way into caregiver mode, which is always available.
///
/// A visible settings button on the talk screen is an anti-pattern: the AAC
/// user will find it, and everything behind it can undo months of learned
/// positions. The gesture has to be something a person exploring a grid does
/// not produce by accident.
///
/// A sustained corner press works because it combines three things no stray
/// touch has at once: a specific location, an unbroken hold, and duration.
/// Nothing is drawn until the hold is already underway, so there is no
/// affordance inviting exploration.
///
/// Whatever it is placed over keeps working. The target adds a meaning to a
/// location; it never takes one away.
///
/// It stays on every board whatever gesture the device is set to, because it
/// is the only door reachable with one hand, a stylus or a head pointer. Where
/// something faster has been chosen it slows down rather than disappearing —
/// see [CaregiverEntry.oneHandedFallback] for why that trade is the right way
/// round.
class CornerHoldTarget extends StatefulWidget {
  const CornerHoldTarget({
    super.key,
    required this.onTriggered,
    this.holdDuration = CaregiverEntry.defaultCornerHold,
    this.revealAfter,
    this.size = defaultSize,
  });

  /// Edge length of the target, in logical pixels.
  ///
  /// Public so that whatever places it and whatever reasons about where it
  /// lands work from one number rather than two that agree today.
  static const double defaultSize = 56;

  final VoidCallback onTriggered;
  final Duration holdDuration;

  /// How long before the user sees anything at all.
  ///
  /// A quarter of the hold unless given, so a target set to fifteen seconds
  /// stays as blank for as long into its hold as a two-second one does. Fixed,
  /// it would spend the other fourteen seconds advertising itself.
  final Duration? revealAfter;

  final double size;

  @override
  State<CornerHoldTarget> createState() => _CornerHoldTargetState();
}

class _CornerHoldTargetState extends State<CornerHoldTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.holdDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _reset();
            widget.onTriggered();
          }
        });

  Timer? _revealTimer;
  bool _visible = false;

  void _start(_) {
    _revealTimer = Timer(widget.revealAfter ?? widget.holdDuration ~/ 4, () {
      if (mounted) setState(() => _visible = true);
    });
    _controller.forward(from: 0);
  }

  void _reset([_]) {
    _revealTimer?.cancel();
    _controller.stop();
    _controller.value = 0;
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void didUpdateWidget(CornerHoldTarget old) {
    super.didUpdateWidget(old);
    if (old.holdDuration != widget.holdDuration) {
      _controller.duration = widget.holdDuration;
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _start,
      onPointerUp: _reset,
      onPointerCancel: _reset,
      // Translucent, so every touch also reaches whatever is underneath. On a
      // screen where a control that quietly does nothing is a control the user
      // cannot report, the entrance to caregiver mode must not be able to cost
      // anyone a key wherever it is placed.
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _visible
            ? AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => HoldRing(progress: _controller.value),
              )
            : null,
      ),
    );
  }
}
