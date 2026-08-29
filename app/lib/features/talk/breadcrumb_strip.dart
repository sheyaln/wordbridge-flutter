import 'package:flutter/material.dart';

/// One step of a route, and the board it landed on.
class Crumb {
  const Crumb({
    required this.label,
    required this.boardId,
    this.turnsWheel = false,
  });

  /// Whether this step turned the category wheel rather than changing board.
  ///
  /// A turn survives being followed by a category, because reaching a category
  /// on the second turn genuinely costs both presses. Everything else the
  /// route collected before that category does not, since a category key is
  /// on the system row of whatever board was showing.
  final bool turnsWheel;

  /// What the key read when it was pressed. A category key shows a different
  /// word on each turn of the wheel, and the crumb says the one the user saw.
  final String label;

  /// The board in view after this step. `back` rewinds the trail to the crumb
  /// naming the board it returns to, so a step has to carry it.
  final String boardId;
}

/// The route to the word just spoken, along the bottom of the screen.
///
/// A display, never a control. A crumb that jumped back to a board would be a
/// second way of reaching it, and a word's motor path is one sequence — so
/// nothing here takes a tap, and none of the prediction strip's target
/// machinery applies: no fixed slots, no settle delay, nothing to press early.
///
/// The height is fixed whatever the trail says, so the grid below it is the
/// same size at one step as at five.
class BreadcrumbStrip extends StatelessWidget {
  const BreadcrumbStrip({
    super.key,
    required this.route,
    this.destination,
    this.originLabel = 'home',
  });

  /// The steps walked since the board was last at home.
  final List<Crumb> route;

  /// The word the route reached, once one has been spoken.
  final String? destination;

  /// Where every route starts. Drawn even when nothing has been walked, so a
  /// one-step route reads as a route rather than as a stray word.
  final String originLabel;

  /// Enough for the text and no more. This is read from across a table, not
  /// reached for, so it costs the grid a third of what a row of targets does.
  static const height = 36.0;

  static const _separator = ' → ';
  static const _elision = '…';

  static const _stepStyle = TextStyle(fontSize: 16, color: Color(0xFF616161));

  static const _separatorStyle = TextStyle(
    fontSize: 16,
    color: Color(0xFF9E9E9E),
  );

  /// The word the route reached, weighted so the informative end of the trail
  /// is the part the eye lands on.
  static const _destinationStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Color(0xFF212121),
  );

  @override
  Widget build(BuildContext context) {
    final steps = <_Step>[
      _Step(originLabel, _stepStyle),
      for (final crumb in route) _Step(crumb.label, _stepStyle),
      if (destination != null) _Step(destination!, _destinationStyle),
    ];

    return Container(
      height: height,
      width: double.infinity,
      color: const Color(0xFFEFEFEF),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) => Text.rich(
          TextSpan(
            children: _spansFrom(
              _fittingStart(steps, constraints.maxWidth),
              steps,
            ),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// The earliest step that can be kept with the whole tail still on screen.
  ///
  /// A trail too long for the width is elided from the left. The destination
  /// and the steps nearest it are what somebody needs to repeat the route; the
  /// head of a trail is the one part that is always the same word. Scrolling
  /// is the other way to fit it and is refused: a strip a stray touch can move
  /// is a control, and this is a display.
  int _fittingStart(List<_Step> steps, double maxWidth) {
    for (var start = 0; start < steps.length - 1; start++) {
      if (_widthOf(_spansFrom(start, steps)) <= maxWidth) return start;
    }
    // A single word wider than the screen has no better answer than the
    // ordinary ellipsis the `Text` applies.
    return steps.length - 1;
  }

  List<InlineSpan> _spansFrom(int start, List<_Step> steps) {
    final spans = <InlineSpan>[
      if (start > 0) const TextSpan(text: _elision, style: _separatorStyle),
    ];

    for (var i = start; i < steps.length; i++) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: _separator, style: _separatorStyle));
      }
      spans.add(TextSpan(text: steps[i].text, style: steps[i].style));
    }
    return spans;
  }

  static double _widthOf(List<InlineSpan> spans) {
    final painter = TextPainter(
      text: TextSpan(children: spans),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _Step {
  const _Step(this.text, this.style);

  final String text;
  final TextStyle style;
}
