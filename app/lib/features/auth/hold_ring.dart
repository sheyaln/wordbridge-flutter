import 'package:flutter/material.dart';

/// How a hold shows that it is being counted.
///
/// Feedback for somebody who already knows the gesture, not an affordance
/// advertising that one exists — which is why every hold draws it late rather
/// than on contact. Without it a caregiver counting seconds in their head lets
/// go early and concludes the gesture does not work.
class HoldRing extends StatelessWidget {
  const HoldRing({super.key, required this.progress});

  /// How much of the hold has elapsed, 0 to 1.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: 3,
          color: Colors.black26,
        ),
      ),
    );
  }
}
