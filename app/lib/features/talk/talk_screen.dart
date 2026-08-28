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
import '../speech/speech_engine.dart';
import '../profiles/profile_settings.dart';
import '../symbols/global_symbols_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import '../usage/logger.dart';
import '../utterance/morphology.dart';
import '../utterance/utterance.dart';

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
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
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
    _load();
  }

  void _onUtteranceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _utterance.removeListener(_onUtteranceChanged);
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
        await widget.speech.speak(_utterance.text);

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
        if (!_utterance.isEmpty) await widget.speech.speak(_utterance.text);

      case ButtonAction.morpheme:
        await _applyMorpheme(button);

      case ButtonAction.none:
        break;
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
                  onSpeak: () => widget.speech.speak(_utterance.text),
                  onBackspace: _utterance.backspace,
                  onClear: _utterance.clear,
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
                        padding: const EdgeInsets.all(8),
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
            // Bottom-left, away from the utterance bar's controls and outside
            // the grid's own padding, so an ordinary reach for a cell does not
            // land on it.
            Positioned(
              left: 0,
              bottom: 0,
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
          height: 80,
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
