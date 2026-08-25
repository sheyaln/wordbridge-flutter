import 'package:drift/drift.dart' show OrderingTerm, leftOuterJoin;
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
    this.settings,
    this.profileId = 'default',
    this.userName,
  });

  final WordbridgeDatabase db;
  final SpeechEngine speech;
  final String vocabularyId;
  final UsageLogger logger;
  final PinAuth auth;
  final SymbolResolver? resolver;
  final ProfileSettings? settings;
  final String profileId;
  final String? userName;

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
  final _utterance = UtteranceBar();

  Vocabulary? _vocab;
  String? _rootBoardId;
  String? _currentBoardId;

  /// One level deep. Board navigation is a shallow map, not a stack: any
  /// category is one movement from anywhere, and depth that accumulates makes
  /// a word's motor path depend on how the user got there.
  String? _previousBoardId;

  /// Returns to the root board after a word is spoken, so the next word
  /// always starts from the same place. Without it a two-tap word is only
  /// two taps sometimes.
  final bool _autoReturn = true;

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

        return (cell: cell, button: deadBack ? null : button);
      }).toList(),
    );
  }

  Future<void> _onSelect(PlacedCell placed) async {
    final button = placed.button;
    if (button == null) return;

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
          });
        }

      case ButtonAction.navigate:
        setState(() {
          _previousBoardId = _currentBoardId;
          _currentBoardId = button.targetBoardId;
        });

      case ButtonAction.home:
        // Home is a reset, not a step. Anything that walked the user here is
        // discarded, so the next "back" cannot rewind into a board they have
        // already left.
        setState(() {
          _currentBoardId = _rootBoardId;
          _previousBoardId = null;
        });

      case ButtonAction.back:
        setState(() => _currentBoardId = _previousBoardId ?? _rootBoardId);

      case ButtonAction.backspace:
        _utterance.backspace();

      case ButtonAction.clear:
        _utterance.clear();

      case ButtonAction.speakBar:
        await widget.speech.speak(_utterance.text);

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
    if (button.action != ButtonAction.morpheme) return true;
    if (!(widget.settings?.contextualGrammar ?? true)) return true;

    final previous = _utterance.last;
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
          userName: widget.userName,
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
                        child: GridSurface(
                          rows: vocab.gridRows,
                          cols: vocab.gridCols,
                          cells: cells,
                          vocabLevel: 3,
                          resolver: widget.resolver,
                          isAvailable: _isAvailable,
                          colourScheme: vocab.colourScheme,
                          onSelect: _onSelect,
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
