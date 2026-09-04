import 'package:flutter/widgets.dart';

/// Nothing. `applyProfileOrientation` holds the device to one aspect, so the
/// box this is drawn into is already the box it was derived for.
Widget holdBoardAspect({
  required int rows,
  required int cols,
  required Widget child,
}) => child;
