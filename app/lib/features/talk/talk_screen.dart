import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value, leftOuterJoin;
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import '../auth/corner_hold_target.dart';
import '../auth/pin.dart';
import '../auth/pin_gate.dart';
import '../caregiver/caregiver_home.dart';
import '../grid/grid_surface.dart';
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

  /// Taps are ignored until this moment, after the board has changed.
  ///
  /// A finger already on its way down when the screen changes lands on
  /// whatever now occupies that location. Without this, moving at speed
  /// through a learned sequence puts words into the sentence that nobody
  /// chose.
  DateTime _operableAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _settleTimer;

  bool get _settling => DateTime.now().isBefore(_operableAt);

  int get wheelPages => _wheel?.pages ?? 1;

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

  /// Starts the delay, and schedules the rebuild that ends it.
  void _settle() {
    final delay =
        widget.settings?.settleDelay ?? const Duration(milliseconds: 500);
    if (delay <= Duration.zero) return;

    _settleTimer?.cancel();
    _operableAt = DateTime.now().add(delay);
    _settleTimer = Timer(delay, () {
      if (mounted) setState(() {});
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
    _utterance.removeListener(_onUtteranceChanged);
    widget.settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final vocab = await (widget.db.select(
      widget.db.vocabularies,
    )..where((v) => v.id.equals(widget.vocabularyId))).getSingle();

    setState(() {
      _vocab = vocab;
      _rootBoardId = vocab.rootBoardId;
      _currentBoardId = vocab.rootBoardId;
      _wheel = _CategoryWheel.parse(vocab.systemCellMap);
    });

    await _refreshSuggestions();
  }

  Stream<List<PlacedCell>> _cellsFor(String boardId) {
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

    return query.watch().map(
      (rows) => rows.map((r) {
        final cell = r.readTable(widget.db.cells);
        final button = r.readTableOrNull(widget.db.buttons);

        // "Back" has nowhere to go from the root board, so it is not drawn
        // there. Its location stays reserved rather than being given to
        // something else, so the button is in the same place every time it is
        // actually usable — hiding it is a rendering decision, not a move.
        final deadBack =
            button?.action == ButtonAction.back && boardId == _rootBoardId;
        if (deadBack) return (cell: cell, button: null);

        return (cell: cell, button: _throughWheel(cell, button));
      }).toList(),
    );
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
    );
  }

  Future<void> _onSelect(PlacedCell placed) async {
    final button = placed.button;
    if (button == null) return;

    // The board has only just changed, so this tap was aimed at the previous
    // screen. Drop it rather than speak it.
    if (_settling) return;

    // Order matters. Speech happens before anything is recorded, and the log
    // call cannot throw, so no amount of database trouble can cost the user a
    // word.
    _record(placed, button);

    switch (button.action) {
      case ButtonAction.speak:
        _utterance.add(button.message, pos: button.partOfSpeech);
        await widget.speech.speak(button.speakText ?? button.message);
        if (_autoReturn && _currentBoardId != _rootBoardId) {
          setState(() {
            _currentBoardId = _rootBoardId;
            _previousBoardId = null;
            _settle();
          });
        }

      case ButtonAction.navigate:
        setState(() {
          _previousBoardId = _currentBoardId;
          _currentBoardId = button.targetBoardId;
          _settle();
        });

      case ButtonAction.home:
        // Home is a reset, not a step. Anything that walked the user here is
        // discarded, so the next "back" cannot rewind into a board they have
        // already left.
        setState(() {
          _currentBoardId = _rootBoardId;
          _previousBoardId = null;
          _settle();
        });

      case ButtonAction.back:
        setState(() {
          _currentBoardId = _previousBoardId ?? _rootBoardId;
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
    await widget.speech.speak(_utterance.text);

    if (_predicting && words.isNotEmpty) {
      unawaited(
        _prediction
            .learn(words)
            .then((_) => _refreshSuggestions())
            .catchError((Object _) {}),
      );
    }
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
    _utterance.add(button.message, pos: button.partOfSpeech);
    await widget.speech.speak(button.speakText ?? button.message);

    unawaited(_recordSuggestion(button));
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
      previousPos: previous?.pos,
      previousInflected: previous?.inflected ?? false,
      atStart: previous == null,
    );
  }

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
        await widget.speech.speak(button.label);
        return;
      }

      final past = button.message == 'past';
      final form = copulaFor(_utterance.last?.text, past: past);
      _utterance.add(form, pos: PartOfSpeech.verb);
      await widget.speech.speak(form);
      return;
    }

    final inflected = _utterance.replaceLast((w) => applyMorpheme(w, kind));
    if (inflected == null) return;
    await widget.speech.speak(inflected);
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
                      return Padding(
                        padding: const EdgeInsets.all(gridInset),
                        child: AbsorbPointer(
                          absorbing: _settling,
                          child: GridSurface(
                            rows: vocab.gridRows,
                            cols: vocab.gridCols,
                            cells: cells,
                            vocabLevel: widget.vocabLevel,
                            resolver: widget.resolver,
                            isAvailable: _isAvailable,
                            colourScheme: vocab.colourScheme,
                            onSelect: _onSelect,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned.fromRect(
              rect: caregiverGestureRect,
              child: CornerHoldTarget(onTriggered: _openCaregiver),
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
    required this.onBackspace,
    required this.onClear,
  });

  final UtteranceBar utterance;
  final VoidCallback onSpeak;
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
              _BarButton(
                icon: Icons.volume_up_rounded,
                tooltip: 'Speak',
                onPressed: empty ? null : onSpeak,
                size: 40,
                colour: const Color(0xFF1B5E20),
                background: const Color(0xFFDCEDC8),
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

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 30,
    this.colour = Colors.black54,
    this.background,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
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
            child: Icon(
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
