import 'dart:async';

import 'package:flutter/material.dart';

/// The way into caregiver mode.
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
class CornerHoldTarget extends StatefulWidget {
  const CornerHoldTarget({
    super.key,
    required this.onTriggered,
    this.holdDuration = const Duration(seconds: 2),
    this.revealAfter = const Duration(milliseconds: 500),
    this.size = 56,
  });

  final VoidCallback onTriggered;
  final Duration holdDuration;

  /// How long before the user sees anything at all.
  final Duration revealAfter;

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
    _revealTimer = Timer(widget.revealAfter, () {
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
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _visible
            ? AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      value: _controller.value,
                      strokeWidth: 3,
                      color: Colors.black26,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
