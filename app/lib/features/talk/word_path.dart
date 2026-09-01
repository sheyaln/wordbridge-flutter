/// Finding a word somebody knows is in there somewhere.
///
/// A board set is a few hundred words across a dozen boards, and the person
/// who needs a word is often not the person who placed it. Hunting for it by
/// opening every category costs the conversation the word was for.
///
/// What comes back is a location and the movements that reach it, so the same
/// answer can be read out loud — `home → more categories → numbers` — and
/// walked. A finder that only says which board a word is on has answered a
/// different question: the board is not the hard part, the way to it is.
library;

import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/seed/core_board_set.dart';
import '../../db/tables.dart';

/// One key to press, and where pressing it leaves you.
///
/// `row` and `col` are where the key sits on the board in view when the step is
/// taken, not on the board it opens. The frame keys are at the same coordinates
/// on every board, so a step is a location rather than a particular button.
///
/// `label` is what the key reads, which is not always what it opens: a category
/// slot shows a different word on each turn of the wheel, and a caregiver may
/// have renamed the key that turns it.
///
/// `boardId` is the board in view afterwards, and is null only for a turn of
/// the wheel — that changes what the slots read without moving off the board.
typedef PathStep = ({
  String label,
  int row,
  int col,
  ButtonAction action,
  String? boardId,
});

/// One place a word can be found, and the way to it from home.
///
/// `steps` is empty for a word on the home board, which is a route rather than
/// the absence of one.
typedef WordPath = ({
  String label,
  String buttonId,
  String boardId,
  int row,
  int col,
  List<PathStep> steps,
});

/// Where a word is, and how to get to it.
///
/// Matches on what the key reads and on what it says, because those differ and
/// either one is what somebody remembers. A key labeled `juice` that speaks
/// `I want juice` answers to both words, and one labeled `I want a drink`
/// answers to `drink`.
///
/// Ranked so that a key whose label starts with the query comes before one that
/// merely contains it somewhere, and a match on the label before a match on the
/// message. Then by how few movements the route costs: the same word two
/// presses away and five presses away are two different answers, and offering
/// the long one first offers the wrong one.
///
/// A word may genuinely hold locations on two boards, and both are returned.
/// They are two movements to two places; keeping only one would hide the near
/// one behind the far one.
///
/// A pinned question is the exception, and not really an exception: it is one
/// key at one location that every board carries, so it is reported once, from
/// home, where it costs no movements at all. Listing it a dozen times would say
/// there are a dozen ways to reach it and push everything else off the list.
///
/// Nothing is offered that the board will not draw. Hidden words, deleted ones,
/// words above [vocabLevel] and words on a board that no visible key reaches
/// are all left out — a location somebody cannot walk to is a dead end, and a
/// finder is the one place they would trust it.
///
/// [vocabLevel] is the ceiling the grid is drawing at. Null is no ceiling,
/// which is what a caregiver looking for where they put something wants.
///
/// The frame keys themselves are not vocabulary and are never returned. They
/// are at one location on every board, so `back` would answer with a dozen
/// identical results and push the words off the end of the list.
///
/// Deterministic: same database, same query, same list in the same order.
/// The way to every board a fixed key reaches, from home.
///
/// The single answer to "how is this board arrived at", so that anything asking
/// — the finder offering a word, the trail naming the way one was reached —
/// gets the same one. Two derivations of the route drift, and a trail that
/// disagreed with the finder would be teaching a movement the finder does not
/// make.
///
/// A board no visible key reaches is absent rather than present with no route,
/// because there is nothing to say about how to get there.
Future<Map<String, List<PathStep>>> boardRoutes(
  WordbridgeDatabase db, {
  required String vocabularyId,
}) async {
  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return const {};

  final placed = await _placedButtons(db, vocabularyId, null);
  return _routes(
    vocabulary,
    SystemFrame.parse(vocabulary.systemCellMap),
    placed,
  );
}

Future<List<WordPath>> findWords(
  WordbridgeDatabase db, {
  required String vocabularyId,
  required String query,
  int limit = 20,
  int? vocabLevel,
}) async {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty || limit <= 0) return const [];

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return const [];

  final placed = await _placedButtons(db, vocabularyId, vocabLevel);
  final frame = SystemFrame.parse(vocabulary.systemCellMap);
  final routes = _routes(vocabulary, frame, placed);

  final found = <({int rank, WordPath path})>[];
  for (final entry in placed) {
    if (entry.button.isSystem) continue;

    final rank = _rank(entry.button, needle);
    if (rank == null) continue;

    final steps = routes[entry.cell.boardId];
    if (steps == null) continue;

    found.add((
      rank: rank,
      path: (
        label: entry.button.label,
        buttonId: entry.button.id,
        boardId: entry.cell.boardId,
        row: entry.cell.row,
        col: entry.cell.col,
        steps: steps,
      ),
    ));
  }

  found.sort(_bestFirst);

  final paths = <WordPath>[];
  final pinned = <int>{};
  for (final f in found) {
    if (paths.length >= limit) break;
    // Nearest first, so the copy that survives is home's, at no movements.
    if (_isPinnedQuestion(vocabulary, frame, f.path.row, f.path.col) &&
        !pinned.add(f.path.row)) {
      continue;
    }
    paths.add(f.path);
  }

  return paths;
}

/// Whether a location is one of the questions pinned down the side of every
/// board.
///
/// Matched on the location, the way the rest of the frame is: that is what
/// makes the copies one key rather than one key per board. The system row is
/// excluded because the far end of it is a paging key, and what a caregiver put
/// on a page that has no paging key is their own word in its own place.
bool _isPinnedQuestion(
  Vocabulary vocabulary,
  SystemFrame? frame,
  int row,
  int col,
) =>
    col == vocabulary.gridCols - 1 &&
    row != (frame?.row ?? vocabulary.gridRows - 1);

/// How well a key answers to [needle], lower being better, or null for one that
/// does not answer to it at all.
///
/// The start of a word is what somebody types when they are looking for it, so
/// a key that begins with what they typed outranks one that happens to contain
/// it. Both the message and the vocalization count as what the key says: they
/// are the same string until a caregiver makes them differ, and after that both
/// are on screen or in the air.
int? _rank(Button button, String needle) {
  final label = button.label.toLowerCase();
  final message = button.message.toLowerCase();
  final spoken = (button.speakText ?? button.message).toLowerCase();

  if (label.startsWith(needle)) return 0;
  if (message.startsWith(needle) || spoken.startsWith(needle)) return 1;
  if (label.contains(needle)) return 2;
  if (message.contains(needle) || spoken.contains(needle)) return 3;
  return null;
}

/// Best match first, then nearest, then alphabetical, then by location.
///
/// The last of these is the id, which is not a presentation order at all: it is
/// there to make the comparison total. Dart's sort is not stable, so two
/// results it calls equal would swap places depending on how many other results
/// there were, and a list that reshuffles under the finger is the thing this
/// app exists to avoid.
int _bestFirst(({int rank, WordPath path}) a, ({int rank, WordPath path}) b) {
  final byRank = a.rank.compareTo(b.rank);
  if (byRank != 0) return byRank;

  final byCost = a.path.steps.length.compareTo(b.path.steps.length);
  if (byCost != 0) return byCost;

  final byLabel = a.path.label.compareTo(b.path.label);
  if (byLabel != 0) return byLabel;

  final byRow = a.path.row.compareTo(b.path.row);
  if (byRow != 0) return byRow;

  final byCol = a.path.col.compareTo(b.path.col);
  if (byCol != 0) return byCol;

  return a.path.buttonId.compareTo(b.path.buttonId);
}

/// Every word and key currently drawn, with the location it is drawn at.
///
/// One query for the whole board set. A query per board would be a dozen round
/// trips with somebody waiting on the answer, and the graph of navigate keys
/// needs every board anyway.
Future<List<_Placed>> _placedButtons(
  WordbridgeDatabase db,
  String vocabularyId,
  int? vocabLevel,
) async {
  var drawn =
      db.buttons.vocabularyId.equals(vocabularyId) &
      db.buttons.hidden.equals(false) &
      db.buttons.deletedAt.isNull();

  if (vocabLevel != null) {
    drawn = drawn & db.buttons.vocabLevel.isSmallerOrEqualValue(vocabLevel);
  }

  final rows =
      await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])
            ..where(drawn)
            ..orderBy([
              OrderingTerm.asc(db.cells.row),
              OrderingTerm.asc(db.cells.col),
              OrderingTerm.asc(db.buttons.id),
            ]))
          .get();

  return [
    for (final row in rows)
      _Placed(row.readTable(db.buttons), row.readTable(db.cells)),
  ];
}

/// The way to each board from home, for every board that has one.
///
/// Two kinds of movement reach a board, and they are not the same kind of fact.
///
/// A category is reached by a key on the system row of whatever board is open,
/// so it is one press from anywhere — behind however many turns of the wheel it
/// sits on. Which turn that is does not depend on the visit, so the route is
/// the category's own and is recorded here directly, the way the breadcrumb
/// trail records it. Categories past the first window have no key of their own
/// at all; only the wheel reaches them.
///
/// Everything else is reached by pressing a real button that navigates. Paging
/// is this — `more words` is an ordinary navigate key, so page three of a
/// category falls out as the category's route plus two presses — and so is a
/// board a caregiver made and hung off a button of their own. Those are walked
/// rather than guessed at, because the alternative is naming a board and
/// leaving somebody to find it, which is the work the finder was for.
///
/// Nearest first, so a board two different keys reach is described by the
/// shorter movement.
Map<String, List<PathStep>> _routes(
  Vocabulary vocabulary,
  SystemFrame? frame,
  List<_Placed> placed,
) {
  final routes = <String, List<PathStep>>{};
  final pending = <String>[];

  void seed(String boardId, List<PathStep> steps) {
    if (routes.containsKey(boardId)) return;
    routes[boardId] = steps;
    pending.add(boardId);
  }

  final root = vocabulary.rootBoardId;
  if (root == null) return routes;
  seed(root, const []);

  if (frame != null) {
    final slots = frame.categoryCols.length;
    final cycleCol = frame.cycleCol;
    final cycleLabel = _cycleLabelOn(placed, root, frame);

    for (var i = 0; i < frame.categories.length; i++) {
      final turns = i ~/ slots;

      // A frame with more categories than slots and no key to turn them is a
      // frame that cannot reach the ones past the window. Saying so is the
      // honest answer; a route through a key that is not on the board is not.
      if (turns > 0 && cycleCol == null) continue;

      seed(frame.categories[i].boardId, [
        for (var turn = 0; turn < turns; turn++)
          (
            label: cycleLabel,
            row: frame.row,
            col: cycleCol!,
            action: ButtonAction.cycleCategories,
            boardId: null,
          ),
        (
          label: frame.categories[i].name,
          row: frame.row,
          col: frame.categoryCols[i % slots],
          action: ButtonAction.navigate,
          boardId: frame.categories[i].boardId,
        ),
      ]);
    }
  }

  final navigate = <String, List<PathStep>>{};
  for (final entry in placed) {
    final target = entry.button.targetBoardId;
    if (entry.button.action != ButtonAction.navigate || target == null) {
      continue;
    }
    navigate.putIfAbsent(entry.cell.boardId, () => []).add((
      label: entry.button.label,
      row: entry.cell.row,
      col: entry.cell.col,
      action: ButtonAction.navigate,
      boardId: target,
    ));
  }

  while (pending.isNotEmpty) {
    // The shortest route still to be extended, so a board reached both from
    // home and from the far side of the wheel is described by the way from
    // home. Ties keep the order they were found in, which the categories'
    // fixed order makes an order of its own.
    var nearest = 0;
    for (var i = 1; i < pending.length; i++) {
      if (routes[pending[i]]!.length < routes[pending[nearest]]!.length) {
        nearest = i;
      }
    }

    final from = pending.removeAt(nearest);
    for (final step in navigate[from] ?? const <PathStep>[]) {
      final to = step.boardId!;
      if (routes.containsKey(to)) continue;
      routes[to] = [...routes[from]!, step];
      pending.add(to);
    }
  }

  return routes;
}

/// What the key that turns the wheel reads on the home board.
///
/// Read from the board rather than assumed, so a caregiver who renamed it hears
/// the route described in the words that are in front of them. Home, because
/// that is where the route starts.
String _cycleLabelOn(
  List<_Placed> placed,
  String rootBoardId,
  SystemFrame frame,
) {
  for (final entry in placed) {
    if (entry.cell.boardId == rootBoardId &&
        entry.cell.row == frame.row &&
        entry.cell.col == frame.cycleCol) {
      return entry.button.label;
    }
  }
  return cycleCategoriesLabel;
}

class _Placed {
  const _Placed(this.button, this.cell);

  final Button button;
  final Cell cell;
}
