/// Turning two setup answers into a grid size.
///
/// The caregiver picks an orientation and an icon size; the number of rows and
/// columns follows. They do not pick rows and columns directly, because those
/// are not things anyone knows the answer to — "how big does a button need to
/// be for this person to hit it reliably" is.
///
/// **This runs on a settings change and at no other time.** Not on rotation,
/// not on a device change, not when an OS update shifts the safe area. Exactly
/// one trigger, and it is a person deliberately choosing it. Anything implicit
/// would relayout a board someone is mid-sentence on, which is the failure
/// this project exists to prevent — and an ambiguous trigger is one nobody can
/// audit afterwards.
library;

import 'dart:ui';

import '../../db/seed/core_board_set.dart';
import '../grid/grid_geometry.dart';

/// Chosen, never sensed. The app locks to it.
enum BoardOrientation {
  landscape('Landscape', 'The tablet is used on its side.'),
  portrait('Portrait', 'The tablet is used upright.');

  const BoardOrientation(this.label, this.description);

  final String label;
  final String description;
}

/// Matched to motor ability, not to taste.
///
/// Larger targets for imprecise reach; smaller ones where accuracy allows more
/// vocabulary to be visible at once. The trade is real in both directions —
/// bigger buttons mean fewer words on screen and more navigation.
enum IconSize {
  small(68, 'Small', 'Most words visible. Needs accurate pointing.'),
  medium(88, 'Medium', 'A balance of vocabulary and target size.'),
  large(116, 'Large', 'Easier to hit. Fewer words on each board.'),
  extraLarge(152, 'Extra large', 'For imprecise reach, or a whole hand.');

  const IconSize(this.targetLogicalPixels, this.label, this.description);

  /// Target edge length of one cell, in logical pixels.
  final int targetLogicalPixels;

  final String label;
  final String description;
}

/// A grid size, and whether it can actually be used.
class GridChoice {
  const GridChoice({
    required this.orientation,
    required this.iconSize,
    required this.rows,
    required this.cols,
    required this.refusal,
  });

  final BoardOrientation orientation;
  final IconSize iconSize;
  final int rows;
  final int cols;

  /// Why this combination cannot be offered, or null when it can.
  ///
  /// Refusing is the honest answer. A board quietly missing half its
  /// vocabulary because the icons were too big for the screen is worse than
  /// being told the icons are too big for the screen.
  final String? refusal;

  bool get isUsable => refusal == null;

  /// How many words this grid can hold across every board it materialises.
  int get locationsPerBoard => rows * cols;

  /// Works out the grid for a chosen orientation and icon size.
  ///
  /// [screen] is the device's full logical size in any orientation; the short
  /// and long sides are taken from it, so the answer does not depend on which
  /// way the tablet happens to be held while the caregiver is answering.
  static GridChoice derive({
    required Size screen,
    required BoardOrientation orientation,
    required IconSize iconSize,
    double chromeHeight = _utteranceBarHeight,
    double padding = 8,
    double gutter = 4,
  }) {
    final short = screen.shortestSide;
    final long = screen.longestSide;

    final width =
        (orientation == BoardOrientation.landscape ? long : short) -
        padding * 2;
    final height =
        (orientation == BoardOrientation.landscape ? short : long) -
        chromeHeight -
        padding * 2;

    final target = iconSize.targetLogicalPixels.toDouble();
    final cols = _fit(width, target, gutter);
    final rows = _fit(height, target, gutter);

    // Asked of the layout engine rather than of a size threshold. A grid can
    // be wide enough for the frame and still be one the seed refuses, and a
    // refusal a caregiver reads at setup is worth having where a crash on
    // "build the board" is not.
    final refusal = boardSetRefusal(rows: rows, cols: cols) == null
        ? null
        : '${iconSize.label} icons in ${orientation.label.toLowerCase()} '
              'leave room for only ${rows}x$cols, which is too small to hold '
              'the keys and the words every board needs to reach.';

    return GridChoice(
      orientation: orientation,
      iconSize: iconSize,
      rows: rows,
      cols: cols,
      refusal: refusal,
    );
  }

  /// Every combination, so setup can show what each one costs rather than
  /// making the caregiver discover it by trying.
  static List<GridChoice> options(Size screen) => [
    for (final orientation in BoardOrientation.values)
      for (final iconSize in IconSize.values)
        derive(screen: screen, orientation: orientation, iconSize: iconSize),
  ];

  /// How many cells of [target] fit, counting gutters *between* them:
  /// `n * target + (n - 1) * gutter <= available`.
  ///
  /// The outer gutters are not charged against the target, so a cell can come
  /// out up to a gutter under it — about a pixel at tablet sizes, against a
  /// target that is itself a judgement call rather than a measured threshold.
  /// Charging them would cost a whole row or column on a dozen real device and
  /// icon-size combinations, and a row of vocabulary is worth more than a
  /// pixel of button. `grid_choice_test` allows exactly that tolerance.
  static int _fit(double available, double target, double gutter) {
    if (available <= 0) return 0;
    final n = (available + gutter) ~/ (target + gutter);
    return n < 0 ? 0 : n;
  }

  /// Kept in step with the utterance bar's own height. The bar is a fixed
  /// chrome cost that the grid never gets to use.
  static const _utteranceBarHeight = 80.0;

  /// Actual cell size once the grid is drawn, which is a little larger than
  /// the target because the leftover space is shared out rather than wasted.
  double cellEdge(Size screen) {
    final geometry = GridGeometry(
      rows: rows,
      cols: cols,
      size: Size(
        (orientation == BoardOrientation.landscape
                ? screen.longestSide
                : screen.shortestSide) -
            16,
        (orientation == BoardOrientation.landscape
                ? screen.shortestSide
                : screen.longestSide) -
            _utteranceBarHeight -
            16,
      ),
    );
    return geometry.cellWidth < geometry.cellHeight
        ? geometry.cellWidth
        : geometry.cellHeight;
  }
}
