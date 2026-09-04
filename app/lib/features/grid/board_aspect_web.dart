import 'package:flutter/widgets.dart';

/// The grid in a box of its own shape, centred in whatever the window is.
///
/// `cols / rows` is the aspect that keeps a cell square, which is what the
/// grid was derived for — so a cell is the same shape at every window size
/// instead of the same fraction of a window that is free to change. The cost
/// is a margin down two sides of a badly proportioned window, which is the
/// right thing to spend: a practised reach lands on a square that is where it
/// was, and does not land on a rectangle that has been squashed since
/// yesterday.
Widget holdBoardAspect({
  required int rows,
  required int cols,
  required Widget child,
}) => Center(
  child: AspectRatio(aspectRatio: cols / rows, child: child),
);
