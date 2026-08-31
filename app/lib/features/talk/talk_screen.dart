import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        ComparableExpr,
        OrderingTerm,
        Value,
        innerJoin,
        leftOuterJoin;
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/seed/band_layout.dart';
import '../../db/tables.dart';
import '../auth/caregiver_gesture.dart';
import '../auth/corner_hold_target.dart';
import '../auth/pin.dart';
import '../auth/pin_gate.dart';
import '../caregiver/caregiver_home.dart';
import '../grid/grid_surface.dart';
import '../grid/region_label_strip.dart';
import '../grid/region_labels.dart';
import '../prediction/prediction_strip.dart';
import '../prediction/word_prediction.dart';
import '../speech/speech_engine.dart';
import '../profiles/profile_settings.dart';
import '../symbols/global_symbols_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import '../usage/logger.dart';
import '../utterance/morphology.dart';
import '../utterance/utterance.dart';
import 'breadcrumb_strip.dart';
import 'find_a_word.dart';
import 'route_walk.dart';
import 'type_a_word.dart';
import 'word_path.dart';

/// Height of the utterance bar. Fixed chrome; the grid gets what is left.
///
/// `GridChoice` derives rows and columns from the same figure, so the two have
/// to move together or a board is laid out for a screen it is not drawn on.
const utteranceBarHeight = 80.0;

/// Gap between the grid and the edge of the screen.
const gridInset = 8.0;

/// Where the caregiver gesture sits, in the talk screen's own coordinates.
///
/// The utterance bar's band, at the left end. The grid begins below the bar,
/// so no reach for a cell can land here however small the cells get — the
/// clearance is the bar itself, not a margin that shrinks with the grid.
///
/// It shares that band with the Speak button, which keeps every touch: the
/// target passes them through, and the button's own tooltip claims a long
/// press, so a hold that opens caregiver mode does not also speak.
const caregiverGestureRect = Rect.fromLTWH(
  0,
  0,
  CornerHoldTarget.defaultSize,
  CornerHoldTarget.defaultSize,
);

/// The only screen the AAC user sees.
class TalkScreen extends StatefulWidget {
  const TalkScreen({
    super.key,
    required this.db,
    required this.speech,
    required this.vocabularyId,
    required this.logger,
    required this.auth,
    this.resolver,
    this.registry,
    this.fetcher,
    this.settings,
    this.profileId = 'default',
    this.userName,
    this.vocabLevel = 3,
    this.onSwitchProfile,
  });

  final WordbridgeDatabase db;
  final SpeechEngine speech;
  final String vocabularyId;
  final UsageLogger logger;
  final PinAuth auth;
  final SymbolResolver? resolver;
  final SymbolRegistry? registry;
  final GlobalSymbolsPack? fetcher;
  final ProfileSettings? settings;
  final String profileId;
  final String? userName;

  /// Buttons at or below this level are drawn. Raising it reveals words where
  /// they have always been; it never moves anything.
  final int vocabLevel;

  final void Function(Profile)? onSwitchProfile;

  @override
  State<TalkScreen> createState() => TalkScreenState();
}

class TalkScreenState extends State<TalkScreen> {
  final _utterance = UtteranceBar();

  Vocabulary? _vocab;
  String? _rootBoardId;
  String? _currentBoardId;

  _CategoryWheel? _wheel;

  /// Which turn of the category wheel is showing. Only ever non-zero when
  /// there are more categories than slots along the system row.
  int _categoryPage = 0;

  /// One level deep. Board navigation is a shallow map, not a stack: any
  /// category is one movement from anywhere, and depth that accumulates makes
  /// a word's motor path depend on how the user got there.
  String? _previousBoardId;

  /// Returns to the root board after a word is spoken, so the next word
  /// always starts from the same place. Without it a two-tap word is only
  /// two taps sometimes.
  bool get _autoReturn => widget.settings?.autoReturn ?? true;

  /// Taps are ignored while this is set, just after the board has changed.
  ///
  /// A finger already on its way down when the screen changes lands on
  /// whatever now occupies that location. Without this, moving at speed
  /// through a learned sequence puts words into the sentence that nobody
  /// chose.
  ///
  /// A flag the timer clears, rather than a deadline compared against the wall
  /// clock. The timer and the clock are the same thing in production and two
  /// different things under a test harness, and a gate on the tap path is worth
  /// being able to test.
  bool _settling = false;
  Timer? _settleTimer;

  /// Something is waiting on a voice.
  ///
  /// Only ever true long enough to see under an engine that has to synthesise;
  /// the platform engine returns before a frame is drawn, so the ring never
  /// appears for it.
  bool _speaking = false;

  /// Every route to speech goes through here, so the ring cannot appear for
  /// one of them and not another.
  ///
  /// There are five: a tapped word, the bar's speak key, a suggestion, a word
  /// ending, and the copula correcting the word before it. All five can now
  /// wait on a synthesis, and a key that gives no sign it was pressed is a key
  /// somebody presses twice.
  Future<void> _saying(Future<void> Function() speak) async {
    if (mounted) setState(() => _speaking = true);
    try {
      await speak();
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  int get wheelPages => _wheel?.pages ?? 1;

  /// The route the finder is walking, and how far along it is.
  ///
  /// Empty except while a walk is running. The walk presses the keys rather
  /// than arriving at the board (§4.42), so it is a sequence in time and has to
  /// be held somewhere between beats.
  List<RouteBeat> _walk = const [];
  int _walkAt = 0;
  Timer? _walkTimer;

  /// The word being walked to, held because the last beat needs its location.
  WordPath? _walking;

  /// Who presses the keys on the way (§4.47).
  WalkMode get _walkMode => widget.settings?.walkMode ?? WalkMode.presses;

  /// How long each key is shown before the walk moves on.
  ///
  /// Long enough to see which key was pressed and where it sits, which is the
  /// thing being taught. Faster than this and the board simply changes several
  /// times, which teaches nothing and looks like a fault.
  static const walkBeat = Duration(milliseconds: 1100);

  /// The location the grid is pointing at: the next key, or the word arrived
  /// at.
  ({int row, int col})? _pointAt;

  /// Walks the way to a word, one key at a time, and stops on the word.
  ///
  /// The word is not pressed. Arriving is the finder's part and speaking is the
  /// user's — a word said by something they did not touch is a word they did
  /// not say, and the press is the movement the whole walk exists to teach.
  ///
  /// Under [WalkMode.waits] every key before the word is that same movement, so
  /// the ring stops over each one and the person makes it themselves.
  void walkTo(WordPath path) {
    final root = _rootBoardId;
    if (root == null) return;

    _walkTimer?.cancel();
    setState(() {
      _walking = path;
      _walk = routeBeats(
        steps: path.steps,
        rootBoardId: root,
        wheelPages: wheelPages,
      );
      _walkAt = 0;
      // A walk starts from home whatever the trail said, so nothing the user
      // did before it describes where they now are.
      _route.clear();
      _reached = null;
      _showBeat();
    });
  }

  /// Puts the board where the current beat says, and points at its key.
  void _showBeat() {
    final path = _walking;
    if (path == null) return;

    final beat = _walk[_walkAt];
    _currentBoardId = beat.boardId;
    _categoryPage = beat.categoryPage;
    _previousBoardId = null;

    final press = beat.press;
    if (press == null) {
      // Arrived. The ring moves off the keys and onto the word.
      _pointAt = (row: path.row, col: path.col);
      _route
        ..clear()
        ..addAll(_routeTo(path.boardId) ?? const []);
      _walk = const [];
      return;
    }

    _pointAt = (row: press.row, col: press.col);
    if (_walkMode == WalkMode.waits) return;

    _walkTimer = Timer(walkBeat, _nextBeat);
  }

  /// Moves the walk on by one, however the beat was earned.
  void _nextBeat() {
    if (!mounted || _walk.isEmpty) return;
    setState(() {
      _walkAt++;
      _showBeat();
    });
  }

  /// Whether a press is the one the ring is waiting for.
  ///
  /// Only under [WalkMode.waits]: while the board is pressing for itself, a
  /// press on the same key is still the user taking over.
  bool _isGuidedPress(PlacedCell placed) =>
      _walkMode == WalkMode.waits &&
      _walk.isNotEmpty &&
      _pointAt == (row: placed.cell.row, col: placed.cell.col);

  /// Ends a walk, and takes the ring off the board.
  ///
  /// Any press that is not the one being waited for stops it. A walk that
  /// carried on changing the board under somebody who had started using it
  /// would be moving the board while they aimed at it, which is the failure
  /// `_settling` exists for.
  void _stopWalk() {
    _walkTimer?.cancel();
    _walkTimer = null;
    _walk = const [];
    _walking = null;
    _pointAt = null;
  }

  bool get _predicting => widget.settings?.prediction ?? false;

  late WordPrediction _prediction = _predictionForLevel();

  /// The engine reads the ceiling once, at construction, so a level that moves
  /// while the board is open needs a new one. An engine left on the old level
  /// offers words the grid is not drawing, or withholds words it is.
  WordPrediction _predictionForLevel() => WordPrediction(
    widget.db,
    profileId: widget.profileId,
    vocabularyId: widget.vocabularyId,
    vocabLevel: widget.vocabLevel,
  );

  /// The level the strip is currently filtering on.
  @visibleForTesting
  int get predictionLevel => _prediction.vocabLevel;

  /// What the strip is showing. Held rather than rebuilt inline so a rebuild
  /// for any other reason cannot change it — the suggestions move only when
  /// the sentence does.
  List<Button> _suggestions = const [];

  /// Drops a suggestion set that arrives after the sentence has moved on.
  int _suggestionRequest = 0;

  Future<void> _refreshSuggestions() async {
    if (!_predicting) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }

    final request = ++_suggestionRequest;
    final last = _utterance.last;
    final words = await _prediction.suggest(
      previous: last?.text,
      previousPos: last?.pos,
    );

    if (!mounted || request != _suggestionRequest) return;
    setState(() => _suggestions = words);
  }

  bool get _showTrail => widget.settings?.breadcrumbs ?? false;

  /// The steps walked since the board was last at home.
  final List<Crumb> _route = [];

  /// The word the route reached, held after the board has moved on.
  String? _reached;

  /// The board the recorded route stands on.
  String? get _routeBoard =>
      _route.isEmpty ? _rootBoardId : _route.last.boardId;

  /// Drops a trail that no longer describes the way to where the user is.
  ///
  /// A finished trail stays on screen after auto-return has taken the board
  /// home — one that vanished at the moment it finished would never be read.
  /// It stops being the route the instant a step is taken from somewhere it
  /// does not account for, so the check happens at that step rather than on a
  /// timer: nothing on this screen moves except when the user moves it.
  ///
  /// Read before the board changes, while [_currentBoardId] is still where the
  /// step was taken from.
  void _restartTrailIfStale() {
    if (_routeBoard != _currentBoardId) _route.clear();
  }

  /// Records a step onto [boardId], which is the board in view afterwards.
  ///
  /// The trail is the way back to a word, not a record of what was pressed, so
  /// it holds a path rather than a history. Pressing the same category three
  /// times is one movement to repeat, and a category reached from another
  /// category is still one movement from home — the keys sit on the system row
  /// of every board, so where somebody happened to be when they pressed one
  /// says nothing about how to get there again.
  void _stepTo(String? boardId, String label) {
    _restartTrailIfStale();
    _reached = null;
    if (boardId == null) return;

    final route = _routeTo(boardId);
    if (route != null) {
      _route
        ..clear()
        ..addAll(route);
      return;
    }

    final at = _route.lastIndexWhere((crumb) => crumb.boardId == boardId);
    if (at >= 0) {
      _route.removeRange(at + 1, _route.length);
      return;
    }

    _route.add(Crumb(label: label, boardId: boardId));
  }

  /// The way to every board a fixed key reaches, as the finder computes it.
  ///
  /// Read once. Which movements reach a board is decided when the board set is
  /// built, so working it out again on every press would be a query for an
  /// answer that cannot have moved.
  Map<String, List<PathStep>> _routes = const {};

  /// The whole way to a board from home, or null for one no fixed key reaches.
  ///
  /// Read from the same table the word finder offers routes out of, so the way
  /// the trail names and the way the finder walks cannot come apart. A board
  /// arrived at by pressing something is described by the shortest way there
  /// rather than by the way this visit took — somebody who spun past their
  /// category and round again, or paged forward and back, went further than
  /// they need to next time, and the trail is for next time.
  List<Crumb>? _routeTo(String boardId) {
    final steps = _routes[boardId];
    if (steps == null) return null;

    return [
      for (final step in steps)
        // A turn of the wheel changes what the slots read without moving off
        // the board, so it has no board of its own to name.
        Crumb(label: step.label, boardId: step.boardId ?? _rootBoardId ?? ''),
    ];
  }

  /// Notes that the wheel moved.
  ///
  /// It leaves the board where it is and adds no step of its own — where a
  /// category sits on the wheel is recorded when the category is chosen, and
  /// what the turning key is called is read off the board rather than off the
  /// press. What it does end is the last completed route, which described a
  /// word the user has now moved on from.
  void _turnedWheel() {
    _restartTrailIfStale();
    _reached = null;
  }

  /// Rewinds the route to the board `back` returns to.
  ///
  /// Appending the step instead would show a route nobody can walk: a second
  /// `back` from the same place moves nothing, and a trail that keeps the dead
  /// end in view is not a route to repeat. Where the destination is not in the
  /// trail the route is dropped rather than guessed at.
  void _rewindTo(String? boardId) {
    _reached = null;
    if (boardId == null || boardId == _rootBoardId) {
      _route.clear();
      return;
    }
    final at = _route.lastIndexWhere((crumb) => crumb.boardId == boardId);
    _route.removeRange(at + 1, _route.length);
  }

  /// Completes the trail with the word it reached.
  void _markReached(String label) {
    if (!mounted) return;
    setState(() {
      _restartTrailIfStale();
      _reached = label;
    });
  }

  /// Starts the delay, and schedules the rebuild that ends it.
  void _settle() {
    final delay =
        widget.settings?.settleDelay ?? const Duration(milliseconds: 500);
    if (delay <= Duration.zero) return;

    _settleTimer?.cancel();
    _settling = true;
    _settleTimer = Timer(delay, () {
      if (mounted) setState(() => _settling = false);
    });
  }

  @override
  void initState() {
    super.initState();
    // Which endings are offered depends on the sentence so far, so the grid
    // has to rebuild whenever the bar changes.
    _utterance.addListener(_onUtteranceChanged);
    // Whether the strip is drawn is read during build, so a caregiver turning
    // it on has to reach the board without going back out and in again.
    widget.settings?.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void didUpdateWidget(TalkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Raising the level reveals words that are already placed, so the board
    // has to show them without being rebuilt from scratch. The grid reads the
    // level during build; the strip has its own copy and needs replacing.
    if (oldWidget.vocabLevel != widget.vocabLevel) {
      _prediction = _predictionForLevel();
      _refreshSuggestions();
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
    _refreshSuggestions();
  }

  void _onUtteranceChanged() {
    if (mounted) setState(() {});
    _refreshSuggestions();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _walkTimer?.cancel();
    _utterance.removeListener(_onUtteranceChanged);
    widget.settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final vocab = await (widget.db.select(
      widget.db.vocabularies,
    )..where((v) => v.id.equals(widget.vocabularyId))).getSingle();

    // Read once for the whole vocabulary. A board's regions are decided when it
    // is built and never change afterwards, so re-reading them as the user
    // moves between boards would be a query per tap for an answer that cannot
    // have moved.
    final boards = await (widget.db.select(
      widget.db.boards,
    )..where((b) => b.vocabularyId.equals(widget.vocabularyId))).get();

    final lowest = await _lowestContentLevels(vocab);
    final routes = await boardRoutes(
      widget.db,
      vocabularyId: widget.vocabularyId,
    );

    setState(() {
      _vocab = vocab;
      _rootBoardId = vocab.rootBoardId;
      _currentBoardId = vocab.rootBoardId;
      _wheel = _CategoryWheel.parse(vocab.systemCellMap);
      _bandMaps = {for (final b in boards) b.id: b.bandMap};
      _lowestContentLevel = lowest;
      _routes = routes;
    });

    await _readCaregiverEntry();
    await _refreshSuggestions();
  }

  /// The lowest level at which each board draws anything of its own.
  ///
  /// Only the content area counts. The frame — the system row along the bottom
  /// and the pinned question column down the side — is identical on every
  /// board, so it says nothing about whether going to one is worth a movement.
  Future<Map<String, int>> _lowestContentLevels(Vocabulary vocab) async {
    final rows =
        await (widget.db.select(widget.db.buttons).join([
              innerJoin(
                widget.db.cells,
                widget.db.cells.id.equalsExp(widget.db.buttons.cellId),
              ),
            ])..where(
              widget.db.buttons.vocabularyId.equals(widget.vocabularyId) &
                  widget.db.buttons.hidden.equals(false) &
                  widget.db.cells.row.isSmallerThanValue(vocab.gridRows - 1) &
                  widget.db.cells.col.isSmallerThanValue(vocab.gridCols - 1),
            ))
            .get();

    final lowest = <String, int>{};
    for (final row in rows) {
      final boardId = row.readTable(widget.db.cells).boardId;
      final level = row.readTable(widget.db.buttons).vocabLevel;
      final held = lowest[boardId];
      if (held == null || level < held) lowest[boardId] = level;
    }
    return lowest;
  }

  Map<String, int> _lowestContentLevel = const {};

  /// Whether a board has anything to show the person using it right now.
  bool _drawsContent(String? boardId) {
    final lowest = boardId == null ? null : _lowestContentLevel[boardId];
    return lowest != null && lowest <= widget.vocabLevel;
  }

  /// Each board's regions, as recorded when it was built.
  Map<String, String?> _bandMaps = const {};

  /// How caregiver mode is asked for on this device.
  ///
  /// Held rather than read on demand because it is consulted while the board
  /// is being built, and starts at the standard gesture so the door exists
  /// before the read comes back. The read only ever slows the one-point hold
  /// down or arms a second gesture; it never removes the one already drawn.
  CaregiverEntry _entry = const CaregiverEntry.standard();

  Future<void> _readCaregiverEntry() async {
    final entry = await CaregiverEntryStore(widget.db).read();
    if (mounted && entry != _entry) setState(() => _entry = entry);
  }

  bool get _showRegions => widget.settings?.regionLabels ?? false;

  String? get _currentBandMap =>
      _currentBoardId == null ? null : _bandMaps[_currentBoardId];

  String? _cellsBoardId;
  Stream<List<PlacedCell>>? _cells;

  /// The open board's locations as they are stored, held for as long as that
  /// board stays open.
  ///
  /// A `StreamBuilder` re-subscribes whenever it is handed a different stream
  /// object, so building one during `build` costs a teardown and a fresh
  /// subscription on every tap, plus a re-read of the board wherever drift's
  /// own stream cache does not happen to absorb it. One board, one
  /// subscription; what each location currently shows is decided in
  /// [_asDrawn], at render time.
  ///
  /// The subscription belongs to the `StreamBuilder`, which cancels it when
  /// this stream is replaced and when the screen goes away.
  Stream<List<PlacedCell>> _cellsFor(String boardId) {
    final held = _cells;
    if (held != null && _cellsBoardId == boardId) return held;

    final query =
        widget.db.select(widget.db.cells).join([
            leftOuterJoin(
              widget.db.buttons,
              widget.db.buttons.cellId.equalsExp(widget.db.cells.id),
            ),
          ])
          ..where(widget.db.cells.boardId.equals(boardId))
          ..orderBy([
            OrderingTerm.asc(widget.db.cells.row),
            OrderingTerm.asc(widget.db.cells.col),
          ]);

    _cellsBoardId = boardId;
    return _cells = query.watch().map(
      (rows) => [
        for (final r in rows)
          (
            cell: r.readTable(widget.db.cells),
            button: r.readTableOrNull(widget.db.buttons),
          ),
      ],
    );
  }

  /// What a stored location shows right now.
  ///
  /// Both substitutions turn on state that moves while the query stands still
  /// — the turn of the wheel, and which board is the root — so they belong to
  /// drawing the board rather than to reading it. Folded into the stream they
  /// would hold whatever was true when the subscription opened, and the cycle
  /// key would stop changing the category keys.
  ///
  /// The board is taken from the location itself rather than from whichever
  /// board is open, so rows still in view from the board being left are drawn
  /// under their own rules.
  PlacedCell _asDrawn(PlacedCell placed) {
    final cell = placed.cell;
    final button = placed.button;

    // "Back" has nowhere to go from the root board, so it is not drawn there.
    // Its location stays reserved rather than being given to something else,
    // so the button is in the same place every time it is actually usable —
    // hiding it is a rendering decision, not a move.
    final deadBack =
        button?.action == ButtonAction.back && cell.boardId == _rootBoardId;
    if (deadBack) return (cell: cell, button: null);

    // Same rule for a page with nothing on it at this level. The frame is on
    // every board, so pressing "more words" onto an empty page leaves the user
    // looking at the keys they just left, with no word to show for the
    // movement and no way to say the board has stopped answering.
    if (_isPagingKey(cell, button) && !_drawsContent(button!.targetBoardId)) {
      return (cell: cell, button: null);
    }

    final shown = _throughWheel(cell, button);

    // And for a category whose board holds nothing this level draws. A key
    // onto a blank board is worse than not having the board: it teaches that
    // navigating is pointless, to somebody who cannot report that it is.
    //
    // Read after the wheel has spoken, because which category a slot offers
    // depends on the turn — the slot itself never moves, so this hides a key
    // rather than closing a location.
    if (shown != null &&
        shown.action == ButtonAction.navigate &&
        shown.isSystem &&
        !_drawsContent(shown.targetBoardId)) {
      return (cell: cell, button: null);
    }

    return (cell: cell, button: shown);
  }

  /// Whether a location holds one of the two keys that turn a page.
  ///
  /// Read off the system row rather than off a label: the row carries home and
  /// back, which are their own actions, the category slots, which the wheel
  /// owns, and the cycle key. A system navigation key that is not a category
  /// slot is a paging key, and that stays true whatever the key is called.
  bool _isPagingKey(Cell cell, Button? button) {
    final wheel = _wheel;
    return wheel != null &&
        button != null &&
        button.isSystem &&
        button.action == ButtonAction.navigate &&
        cell.row == wheel.row &&
        !wheel.cols.contains(cell.col);
  }

  /// Substitutes whichever category a slot is showing on this turn.
  ///
  /// The button stays where it is and keeps its location's history; only the
  /// name on it and the board it opens change. Every category is one movement
  /// away plus however many turns of the wheel, rather than two movements away
  /// behind a board of categories.
  Button? _throughWheel(Cell cell, Button? button) {
    final wheel = _wheel;
    if (button == null || wheel == null || cell.row != wheel.row) return button;

    final slot = wheel.cols.indexOf(cell.col);
    if (slot < 0) return button;

    final entry = wheel.at(_categoryPage, slot);
    if (entry == null) return null;

    return button.copyWith(
      label: entry.name,
      targetBoardId: Value(entry.boardId),
      // The slot shows a different category on each turn, so its picture has
      // to come from the name it is showing rather than from the button
      // underneath.
      symbolId: const Value(null),
    );
  }

  Future<void> _onSelect(PlacedCell placed) async {
    final button = placed.button;
    if (button == null) return;

    // The board has only just changed, so this tap was aimed at the previous
    // screen. Drop it rather than speak it.
    if (_settling) return;

    // The key the ring is waiting for. The press earns the next beat and the
    // beat moves the board, rather than this press navigating on its own: two
    // routes to one board are two chances to disagree, and a walk must never
    // arrive somewhere the finder did not name.
    //
    // It is still recorded. A guided press is real practice at that location,
    // and the tap counts the editor quotes before a move (§7) are the reason
    // that matters.
    if (_isGuidedPress(placed)) {
      _record(placed, button);
      _nextBeat();
      return;
    }

    // The user has taken over. Whatever the walk was going to press next, they
    // are pressing something now, and a board that kept moving under them would
    // be the failure `_settling` exists for arriving by another route.
    if (_walk.isNotEmpty || _pointAt != null) setState(_stopWalk);

    // Order matters. Speech happens before anything is recorded, and the log
    // call cannot throw, so no amount of database trouble can cost the user a
    // word.
    _record(placed, button);

    switch (button.action) {
      case ButtonAction.speak:
        final repaired = _utterance.add(
          button.message,
          pos: button.partOfSpeech,
        );
        _markReached(button.label);
        await _saying(() => widget.speech.speak(_withRepair(repaired, button)));
        if (_autoReturn && _currentBoardId != _rootBoardId) {
          setState(() {
            _currentBoardId = _rootBoardId;
            _previousBoardId = null;
            _settle();
          });
        }

      case ButtonAction.navigate:
        setState(() {
          _stepTo(button.targetBoardId, button.label);
          _previousBoardId = _currentBoardId;
          _currentBoardId = button.targetBoardId;
          _settle();
        });

      case ButtonAction.home:
        // Home is a reset, not a step. Anything that walked the user here is
        // discarded, so the next "back" cannot rewind into a board they have
        // already left, and the trail does not describe a route away from the
        // board they are now on.
        setState(() {
          _route.clear();
          _reached = null;
          _currentBoardId = _rootBoardId;
          _previousBoardId = null;
          // The wheel turns in place, so a category key means a different
          // board on each turn. Leaving it where it stood would make home a
          // place the board only half returns to, and the sequence to a word
          // would depend on which turn somebody had stopped on.
          _categoryPage = 0;
          _settle();
        });

      case ButtonAction.back:
        setState(() {
          final destination = _previousBoardId ?? _rootBoardId;
          _rewindTo(destination);
          _currentBoardId = destination;
          _settle();
        });

      case ButtonAction.backspace:
        _utterance.backspace();

      case ButtonAction.clear:
        _utterance.clear();

      case ButtonAction.speakBar:
        await _speakSentence();

      case ButtonAction.cycleCategories:
        setState(() {
          _turnedWheel();
          _categoryPage = (_categoryPage + 1) % wheelPages;
          _settle();
        });

      case ButtonAction.punctuate:
        // Speaks the whole sentence rather than the mark. Tone is a property
        // of the sentence, so hearing it is the only feedback that tells the
        // user the question mark did anything.
        _utterance.punctuate(button.message);
        if (!_utterance.isEmpty) await _speakSentence();

      case ButtonAction.morpheme:
        await _applyMorpheme(button);

      case ButtonAction.none:
        break;
    }
  }

  /// Speaks the sentence, and lets prediction watch it.
  ///
  /// A sentence the user chose to say is the thing worth learning from. Words
  /// arriving in the bar are not that: they include everything tried and
  /// backed out of, and a bar built and then cleared was never said at all.
  ///
  /// The strip is useful before it has learned anything because it ships
  /// knowing ordinary English — see `starterPredictions`.
  Future<void> _speakSentence() async {
    final words = _utterance.words;
    // The bar, not a tap — and the only call in the app that goes to
    // `speakUtterance`. §4.5's named exception to §5 non-negotiable 1 lives
    // here and nowhere else: one press, one wait, one sentence, for a profile
    // that asked for a voice which has to be synthesised. Under an engine
    // with no such cost this is the same call as any other.
    //
    // The ring goes up for the whole call rather than only for a synthesis,
    // because nothing here knows which it will be — and a key that looks
    // unpressed for a second is a key somebody presses again.
    await _saying(() => widget.speech.speakUtterance(_utterance.text));

    if (_predicting && words.isNotEmpty) {
      unawaited(
        _prediction
            .learn(words)
            .then((_) => _refreshSuggestions())
            .catchError((Object _) {}),
      );
    }
  }

  /// Puts a typed word into the sentence.
  ///
  /// For the word that is not on the board and is not going to be — a place
  /// name, a visitor, the title of something somebody watched once. Adding a
  /// location for it would cost that location on every board in the set, and
  /// most of these are said once.
  ///
  /// Not spoken again here. The typing screen says the finished word as it
  /// hands it over, which is the feedback that the typing worked; saying it a
  /// second time on arrival would make one word two.
  ///
  /// No part of speech, because nothing here knows one. The endings and the
  /// copula read the word before them, and a typed word tells them nothing —
  /// which is honest: guessing would offer "+ed" on a person's name.
  Future<void> _typeWord() async {
    final word = await TypeAWord.show(context, speech: widget.speech);
    if (word == null || !mounted) return;

    _addTypedWord(word);
  }

  /// Puts a word the board does not have into the sentence.
  ///
  /// One route, because two screens now hand one back — the typing screen and
  /// the finder, when what somebody typed turned out not to be there (§4.46).
  void _addTypedWord(String word) {
    setState(() {
      _utterance.add(word);
      _reached = null;
    });
  }

  /// Looks for a word, and either walks the way to it or says it as typed.
  ///
  /// A word that is there is arrived at by the movements that reach it — see
  /// [walkTo] — and nothing is added to the sentence. A word that is not there
  /// has already been spoken by the finder and goes straight in, exactly as the
  /// typing screen's does.
  Future<void> _findWord() async {
    final found = await FindAWord.show(
      context,
      db: widget.db,
      vocabularyId: widget.vocabularyId,
      vocabLevel: widget.vocabLevel,
      speech: widget.speech,
    );
    if (found == null || !mounted) return;

    switch (found) {
      case RouteToWord(:final path):
        walkTo(path);
      case TypedWord(:final word):
        _addTypedWord(word);
    }
  }

  /// Ends the sentence with a mark, and says it.
  ///
  /// Speaks the whole sentence rather than the mark, because tone belongs to
  /// the sentence and hearing it is the only feedback that tells the user the
  /// mark did anything. That is the whole reason a mark is worth a control:
  /// "you are ok" and "are you ok?" are the same words.
  Future<void> _endSentence(String mark) async {
    _utterance.punctuate(mark);
    if (!_utterance.isEmpty) await _speakSentence();
  }

  /// Finds the button the strip was showing, without going back to the disk.
  ///
  /// The strip deals in words so that it stays a display; the buttons behind
  /// them are already held here.
  void _onSuggestionWord(String word) {
    for (final button in _suggestions) {
      if (button.message == word) {
        _onSuggestion(button);
        return;
      }
    }
  }

  /// Puts a suggested word into the sentence, exactly as its own button would.
  ///
  /// The word keeps its part of speech, so the endings offered after it are
  /// the same ones that would follow a tap on the board. A suggestion is a
  /// shortcut to a button and has to behave like one.
  ///
  /// Nothing is read from the database first — the button arrived with the
  /// suggestion — so speech starts here as fast as it does from the grid.
  Future<void> _onSuggestion(Button button) async {
    final repaired = _utterance.add(button.message, pos: button.partOfSpeech);
    await _saying(() => widget.speech.speak(_withRepair(repaired, button)));

    unawaited(_recordSuggestion(button));
  }

  /// What to say for a word that corrected the word in front of it.
  ///
  /// The pair is spoken rather than the correction alone: hearing "are" on its
  /// own after "is" leaves the two to be assembled by someone who cannot see
  /// the bar, while "are you" is the phrase as it now stands. Nothing is said
  /// twice — this replaces the word's own utterance rather than following it.
  String _withRepair(String? repaired, Button button) {
    final spoken = button.speakText ?? button.message;
    return repaired == null ? spoken : '$repaired $spoken';
  }

  /// Logs the word against the location it lives at, marked as a suggestion.
  ///
  /// The location is right — that is where the word is — but the tap count a
  /// caregiver sees before moving something has to mean "reached for here",
  /// and this was not that.
  ///
  /// Runs after the word has been spoken and is never awaited, so no amount of
  /// database trouble can cost the user a word.
  Future<void> _recordSuggestion(Button button) async {
    try {
      final cellId = button.cellId;
      if (cellId == null) return;

      final cell = await (widget.db.select(
        widget.db.cells,
      )..where((c) => c.id.equals(cellId))).getSingleOrNull();
      if (cell == null) return;

      widget.logger.log(
        profileId: widget.profileId,
        vocabularyId: widget.vocabularyId,
        boardId: cell.boardId,
        cellId: cell.id,
        buttonId: button.id,
        label: button.label,
        action: button.action,
        source: UsageSource.prediction,
      );
    } catch (_) {
      // A suggestion that was spoken but not recorded is a gap in a report.
      // A suggestion that throws is a word the user does not get.
    }
  }

  /// Whether a button can be used given what has been said so far.
  ///
  /// Only word endings are ever withheld; ordinary vocabulary is always
  /// available. When the setting is off, everything shows all the time and
  /// the board never changes shape.
  bool _isAvailable(Button button) {
    final previous = _utterance.last;

    if (button.action != ButtonAction.morpheme) {
      if (!(widget.settings?.filterVerbs ?? false)) return true;
      if (button.isSystem) return true;
      return verbIsOfferable(
        pos: button.partOfSpeech,
        previousText: previous?.text,
        previousPos: previous?.pos,
      );
    }

    if (!(widget.settings?.contextualGrammar ?? true)) return true;
    return grammarHelperApplies(
      kind: button.morphemeKind,
      tense: button.message,
      previousText: previous?.text,
      previousPos: previous?.pos,
      previousInflected: previous?.inflected ?? false,
      atStart: previous == null,
      copulaCycles: _copulaMode == CopulaMode.toggle,
    );
  }

  CopulaMode get _copulaMode =>
      widget.settings?.copulaMode ?? CopulaMode.toggle;

  /// Inflects the last word, or appends an agreeing form of "to be".
  ///
  /// Two different operations behind one action, because they are two ways of
  /// answering the same need: the suffix keys rewrite what is already there
  /// ("want" becomes "wanted"), while the copula adds a word that depends on
  /// what is there ("I" gets "am", "they" get "are").
  Future<void> _applyMorpheme(Button button) async {
    final kind = button.morphemeKind;

    if (kind == null) {
      // Articles and copulas add a word rather than rewriting one, so they
      // share a path that appends.
      if (button.message == 'article') {
        _utterance.add(button.label, pos: PartOfSpeech.determiner);
        await _saying(() => widget.speech.speak(button.label));
        return;
      }

      // Every press speaks the form it produced, whether it appended one or
      // changed the one already there. A key that goes silent is one the user
      // has to learn an exception for, and under the cycling mode the sound is
      // the only thing telling them which form they have landed on.
      final form = _utterance.addCopula(
        past: button.message == 'past',
        mode: _copulaMode,
      );
      await _saying(() => widget.speech.speak(form));
      return;
    }

    final inflected = _utterance.replaceLast((w) => applyMorpheme(w, kind));
    if (inflected == null) return;
    await _saying(() => widget.speech.speak(inflected));
  }

  void _record(PlacedCell placed, Button button) {
    widget.logger.log(
      profileId: widget.profileId,
      vocabularyId: widget.vocabularyId,
      boardId: placed.cell.boardId,
      cellId: placed.cell.id,
      buttonId: button.id,
      label: button.label,
      action: button.action,
      source: UsageSource.touch,
    );

    if (button.action == ButtonAction.clear ||
        button.action == ButtonAction.speakBar) {
      widget.logger.endUtterance();
    }
  }

  Future<void> _openCaregiver() async {
    final unlocked = await PinGate.show(context, widget.auth);
    if (!unlocked || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaregiverHome(
          db: widget.db,
          vocabularyId: widget.vocabularyId,
          profileId: widget.profileId,
          logger: widget.logger,
          speech: widget.speech,
          settings: widget.settings,
          registry: widget.registry,
          fetcher: widget.fetcher,
          resolver: widget.resolver,
          userName: widget.userName,
          onSwitchProfile: widget.onSwitchProfile,
        ),
      ),
    );

    // The gesture is changeable from in there, and the change has to be live
    // on the way out: a caregiver who switches it and then cannot get back in
    // has no way to discover they are locked out except by being locked out.
    await _readCaregiverEntry();

    // A top-up can put the first word on a page that had none, and the key
    // that reaches it has to come back with it.
    final vocab = _vocab;
    if (vocab == null) return;
    final lowest = await _lowestContentLevels(vocab);
    if (mounted) setState(() => _lowestContentLevel = lowest);
  }

  @override
  Widget build(BuildContext context) {
    final vocab = _vocab;
    final boardId = _currentBoardId;

    if (vocab == null || boardId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _UtteranceBarView(
                  utterance: _utterance,
                  onSpeak: _speakSentence,
                  speaking: _speaking,
                  onPunctuate: _endSentence,
                  onType: _typeWord,
                  onFind: _findWord,
                  onBackspace: _utterance.backspace,
                  onClear: _utterance.clear,
                ),
                // Above the grid and below the sentence, where it reads as
                // part of the sentence being built rather than part of the
                // board. Absent entirely when off, so a profile that does not
                // use it does not pay for it in grid height.
                if (_predicting)
                  PredictionStrip(
                    words: [for (final b in _suggestions) b.message],
                    settleDelay:
                        widget.settings?.settleDelay ??
                        const Duration(milliseconds: 500),
                    onSelect: _onSuggestionWord,
                  ),
                Expanded(
                  child: StreamBuilder<List<PlacedCell>>(
                    stream: _cellsFor(boardId),
                    builder: (context, snapshot) {
                      final cells = snapshot.data;
                      if (cells == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final regions = _showRegions
                          ? BoardRegions.decode(_currentBandMap)
                          : null;

                      return Padding(
                        padding: const EdgeInsets.all(gridInset),
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final grid = AbsorbPointer(
                              absorbing: _settling,
                              child: GridSurface(
                                rows: vocab.gridRows,
                                cols: vocab.gridCols,
                                cells: [for (final c in cells) _asDrawn(c)],
                                vocabLevel: widget.vocabLevel,
                                resolver: widget.resolver,
                                isAvailable: _isAvailable,
                                colourScheme: vocab.colourScheme,
                                onSelect: _onSelect,
                                pairHold: _entry.pairHold,
                                onPairHold: _openCaregiver,
                                pointAt: _pointAt,
                              ),
                            );

                            if (regions == null || regions.isEmpty) return grid;

                            // Chrome beside the grid rather than in it. A label
                            // that took a location would be teaching the layout
                            // by damaging it, and the lines it most needs to
                            // name are the reserved ones.
                            //
                            // It runs along whichever edge the bands do: the
                            // root board bands by column so its labels sit
                            // above, a category board bands by row so they run
                            // down the side. Drawn across the wrong edge, every
                            // label lands on top of the others.
                            final byColumn = regions.axis == BandAxis.columns;
                            final strip = SizedBox(
                              width: byColumn ? null : regionLabelExtent,
                              height: byColumn ? regionLabelExtent : null,
                              child: RegionLabelStrip(
                                regions: regions,
                                rows: vocab.gridRows,
                                cols: vocab.gridCols,
                                axis: regions.axis,
                                gridWidth: box.maxWidth,
                                gridHeight: box.maxHeight,
                              ),
                            );

                            return byColumn
                                ? Column(
                                    children: [
                                      strip,
                                      Expanded(child: grid),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      strip,
                                      Expanded(child: grid),
                                    ],
                                  );
                          },
                        ),
                      );
                    },
                  ),
                ),
                // Below the grid, where the route reads left to right and ends
                // under the board it was walked on. Absent entirely when off,
                // so a profile that does not use it does not pay for it in
                // grid height.
                if (_showTrail)
                  BreadcrumbStrip(route: _route, destination: _reached),
              ],
            ),
            Positioned.fromRect(
              rect: caregiverGestureRect,
              child: CornerHoldTarget(
                holdDuration: _entry.cornerHold,
                onTriggered: _openCaregiver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UtteranceBarView extends StatelessWidget {
  const _UtteranceBarView({
    required this.utterance,
    required this.onSpeak,
    required this.speaking,
    required this.onPunctuate,
    required this.onType,
    required this.onFind,
    required this.onBackspace,
    required this.onClear,
  });

  final UtteranceBar utterance;
  final VoidCallback onSpeak;

  /// A voice is being made right now, so the speak key shows a ring.
  final bool speaking;
  final void Function(String mark) onPunctuate;
  final VoidCallback onType;
  final VoidCallback onFind;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Space between speaking and deleting.
  ///
  /// The two most important controls here do opposite things, and one of them
  /// is destructive. A user with imprecise reach who means to speak and lands
  /// one button over should not lose the sentence they just built. So speak
  /// sits at the far left, the destructive pair at the far right, with the
  /// whole sentence between them.
  static const _separation = 24.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: utterance,
      builder: (context, _) {
        final empty = utterance.isEmpty;

        return Container(
          height: utteranceBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Colors.white,
          child: Row(
            children: [
              // Deliberately the largest target on the bar.
              //
              // It turns into a ring while a voice is being made. Making one
              // takes a second or so, and a key that looks exactly the same
              // during it reads as a press that did not register — so the
              // person presses again, and the board says it twice.
              _BarButton(
                icon: Icons.volume_up_rounded,
                tooltip: speaking ? 'Speaking…' : 'Speak',
                onPressed: empty ? null : onSpeak,
                busy: speaking,
                size: 40,
                colour: const Color(0xFF1B5E20),
                background: const Color(0xFFDCEDC8),
              ),
              const SizedBox(width: 4),
              // Punctuation marks the sentence rather than adding a word to
              // it, so it belongs where the sentence is and not on a grid
              // where it would cost a location on every board. Beside speak
              // and well away from the destructive pair: it produces speech,
              // which is what those two are separated from.
              //
              // Both marks behind one control, and it always opens. A button
              // that applied the last mark on a plain press would be one press
              // for a question and two for the other, decided by something the
              // person cannot see — a key whose behaviour depends on history is
              // the one thing this board never has.
              _BarMenu(
                // Both marks, because the control carries both. One of them
                // would read as the key doing that one thing, and a person who
                // wanted the other would have no reason to press it.
                face: (colour) => Text(
                  '?!',
                  style: TextStyle(
                    fontSize: 27,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: colour,
                  ),
                ),
                tooltip: 'End the sentence',
                enabled: !empty,
                items: [
                  (
                    mark: '?',
                    label: 'Make it a question',
                    icon: Icons.question_mark_rounded,
                  ),
                  (
                    mark: '!',
                    label: 'Say it like you mean it',
                    icon: Icons.priority_high_rounded,
                  ),
                ],
                onChosen: onPunctuate,
              ),
              const SizedBox(width: 4),
              // The ways to a word that is not on the board in front of you.
              // One control rather than a button each, because these are
              // reached for rarely and deliberately, and the bar's room belongs
              // to the two that are not — speaking, and clearing.
              //
              // Behind a list from the start, so the finder could join it
              // without the control changing shape under somebody who had
              // learned it. It has now joined it.
              _BarMenu<String>(
                face: (colour) =>
                    Icon(Icons.search_rounded, size: 30, color: colour),
                tooltip: 'Another way to a word',
                items: const [
                  // The finder first. It answers "where is the word", which is
                  // the question asked far more often than "this word is not
                  // on the board at all" — and it is the one that ends with the
                  // person having learned something.
                  (
                    mark: 'find',
                    label: 'Find a word',
                    icon: Icons.travel_explore_outlined,
                  ),
                  (
                    mark: 'type',
                    label: 'Type a word',
                    icon: Icons.keyboard_alt_outlined,
                  ),
                ],
                onChosen: (mark) => mark == 'find' ? onFind() : onType(),
              ),
              const SizedBox(width: _separation),

              Expanded(
                child: GestureDetector(
                  onTap: empty ? null : onSpeak,
                  behavior: HitTestBehavior.opaque,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      utterance.text,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: _separation),
              _BarButton(
                icon: Icons.backspace_outlined,
                tooltip: 'Delete last word',
                onPressed: empty ? null : onBackspace,
              ),
              const SizedBox(width: 4),
              _BarButton(
                icon: Icons.close_rounded,
                tooltip: 'Clear',
                onPressed: empty ? null : onClear,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A bar control that offers a short list rather than doing one thing.
///
/// For the things a person reaches for rarely and deliberately. The bar is the
/// only place a control is free — a key on the grid costs a location on every
/// board — but it is not unlimited, and a button per feature would crowd out
/// the two that matter most, which are speak and clear.
///
/// Every entry is one press once the list is open, and the list always opens.
/// Nothing here is faster for having been used before.
class _BarMenu<T> extends StatelessWidget {
  const _BarMenu({
    required this.face,
    required this.tooltip,
    required this.items,
    required this.onChosen,
    this.enabled = true,
  });

  /// Drawn in the colour the control's state calls for, so a face made of
  /// letters greys out with the rest of the bar rather than staying bright on a
  /// control that does nothing.
  final Widget Function(Color colour) face;
  final String tooltip;
  final List<({T mark, String label, IconData icon})> items;
  final void Function(T) onChosen;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<T>(
        enabled: enabled,
        tooltip: '',
        onSelected: onChosen,
        itemBuilder: (context) => [
          for (final item in items)
            PopupMenuItem<T>(
              value: item.mark,
              child: Row(
                children: [
                  Icon(item.icon, size: 20, color: Colors.black54),
                  const SizedBox(width: 10),
                  // Flexible rather than fixed: this list is opened from a
                  // control near the left edge of a bar whose width is the
                  // screen's, and a label that overflowed would be a choice
                  // nobody can read.
                  Flexible(
                    child: Text(
                      item.label,
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: face(enabled ? Colors.black54 : Colors.black12),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.size = 30,
    this.colour = Colors.black54,
    this.background,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Draws a ring where the icon is, without changing the size of the key or
  /// where it sits. The target has to stay exactly where the finger left it.
  final bool busy;
  final double size;
  final Color colour;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? (background ?? Colors.transparent)
            : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: busy
                ? SizedBox(
                    width: size,
                    height: size,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: enabled ? colour : Colors.black12,
                    ),
                  )
                : Icon(
                    icon,
                    size: size,
                    color: enabled ? colour : Colors.black12,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The category keys along the system row, and the full list they show a
/// window onto.
///
/// Read from the vocabulary rather than recomputed, so the window matches the
/// locations the board was actually built with.
class _CategoryWheel {
  const _CategoryWheel({
    required this.row,
    required this.cols,
    required this.entries,
  });

  final int row;
  final List<int> cols;
  final List<({String name, String boardId})> entries;

  int get pages =>
      cols.isEmpty ? 1 : (entries.length / cols.length).ceil().clamp(1, 99);

  /// The category a slot shows on a given turn, or null where the last turn
  /// runs out of categories before it runs out of slots.
  ({String name, String boardId})? at(int page, int slot) {
    if (cols.isEmpty) return null;
    final index = page * cols.length + slot;
    return index < entries.length ? entries[index] : null;
  }

  static _CategoryWheel? parse(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final cols = (map['categoryCols'] as List?)?.cast<int>();
      final categories = map['categories'] as List?;
      if (cols == null || categories == null || cols.isEmpty) return null;

      return _CategoryWheel(
        row: map['row'] as int,
        cols: cols,
        entries: [
          for (final entry in categories.cast<Map<String, dynamic>>())
            (
              name: entry['name'] as String,
              boardId: entry['boardId'] as String,
            ),
        ],
      );
    } catch (_) {
      // A board built before the wheel existed, or a malformed map. The keys
      // then behave as plain navigation, which is what they already are.
      return null;
    }
  }
}
