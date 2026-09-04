/// Holding the board to the shape it was built for.
///
/// The grid is derived once, at setup, from the space available and the icon
/// size chosen — and the derivation aims at square cells. On a tablet the app
/// then locks the device to that orientation, so the box the grid is drawn
/// into never changes and neither does the shape of a cell.
///
/// A window has no such lock. Dragging its corner redraws the same grid into a
/// box of a different aspect: every cell changes width and height while
/// keeping its row and its column. That is the motor plan broken in the only
/// units a hand knows, and it arrives by the one route
/// `motor_plan_invariant_test.dart` cannot see, because not a word has moved.
library;

export 'board_aspect_native.dart'
    if (dart.library.js_interop) 'board_aspect_web.dart';
