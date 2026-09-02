/// Walking the way to a word, one key at a time.
///
/// The finder's whole argument (§4.42): it presses the keys rather than
/// arriving at the board. A finder that teleported would teach that the way to
/// a word is to search for it, to somebody whose board is built on the way
/// being a fixed sequence — and it would give every word a second motor path,
/// which is the thing §4.8 refuses a tappable breadcrumb over.
///
/// So the route is turned into the moments it passes through, and the screen
/// stops at each one long enough to be seen. What is walked is the same route
/// the trail names, out of the same table, so the two cannot teach different
/// movements.
library;

import '../../db/tables.dart';
import 'word_path.dart';

/// Who presses the keys on the way to a found word (§4.47).
///
/// Watching a route is not learning it. A motor plan is built by making the
/// movement — which is what this whole app is for — so pressing the keys and
/// being shown them pressed are two different things, and which one a profile
/// wants depends on whether the person at the tablet is looking a word up or
/// learning where it lives.
enum WalkMode {
  /// The board goes through the route itself, a beat on each key.
  presses('The board presses the keys'),

  /// The key to press next is highlighted, and waits there until it is.
  ///
  /// "Ring" is what the code calls the thing it draws; it is not a word
  /// anybody reading this screen has been given. The option says what a person
  /// sees — a key, highlighted — in the same terms as the option beside it.
  waits('The highlighted key waits to be pressed');

  const WalkMode(this.label);

  final String label;
}

/// One moment of a walk: the board in view, and the key to press from here.
///
/// [press] is null on the last beat only, which is the board holding the word.
/// The word itself is never pressed — arriving is the finder's job and pressing
/// is the user's, and a word spoken by something they did not touch is a word
/// they did not say.
typedef RouteBeat = ({String boardId, int categoryPage, PathStep? press});

/// The moments a route passes through, starting from home.
///
/// Home first, always. Routes are recorded from home because that is where the
/// motor plan starts; beginning a walk wherever the person happened to be would
/// press a sequence that only works from there, which is the opposite of what
/// the walk is for.
///
/// A turn of the wheel moves the page rather than the board — it changes what
/// the category slots read without leaving the board — so it produces a beat
/// with the same board and the next page.
List<RouteBeat> routeBeats({
  required List<PathStep> steps,
  required String rootBoardId,
  required int wheelPages,
}) {
  final beats = <RouteBeat>[];
  var boardId = rootBoardId;
  var page = 0;

  for (final step in steps) {
    beats.add((boardId: boardId, categoryPage: page, press: step));

    switch (step.action) {
      case ButtonAction.cycleCategories:
        page = (page + 1) % wheelPages;
      case ButtonAction.home:
        page = 0;
        boardId = rootBoardId;
      default:
        if (step.boardId != null) boardId = step.boardId!;
    }
  }

  // The board the word is on, with nothing left to press. A word already on the
  // home board is this beat and no other — a route of no steps is still a
  // route, and the answer to "where is it" is "in front of you".
  beats.add((boardId: boardId, categoryPage: page, press: null));
  return beats;
}
