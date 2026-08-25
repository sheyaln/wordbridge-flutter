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
import '../symbols/symbol_resolver.dart';
import '../usage/logger.dart';
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
    this.profileId = 'default',
    this.userName,
  });

  final WordbridgeDatabase db;
  final SpeechEngine speech;
  final String vocabularyId;
  final UsageLogger logger;
  final PinAuth auth;
  final SymbolResolver? resolver;
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
    _load();
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
      (rows) => rows
          .map(
            (r) => (
              cell: r.readTable(widget.db.cells),
              button: r.readTableOrNull(widget.db.buttons),
            ),
          )
          .toList(),
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
        _utterance.add(button.message);
        await widget.speech.speak(button.speakText ?? button.message);
        if (_autoReturn && _currentBoardId != _rootBoardId) {
          setState(() => _currentBoardId = _rootBoardId);
        }

      case ButtonAction.navigate:
        setState(() {
          _previousBoardId = _currentBoardId;
          _currentBoardId = button.targetBoardId;
        });

      case ButtonAction.home:
        setState(() => _currentBoardId = _rootBoardId);

      case ButtonAction.back:
        setState(() => _currentBoardId = _previousBoardId ?? _rootBoardId);

      case ButtonAction.backspace:
        _utterance.backspace();

      case ButtonAction.clear:
        _utterance.clear();

      case ButtonAction.speakBar:
        await widget.speech.speak(_utterance.text);

      case ButtonAction.morpheme:
      case ButtonAction.none:
        break;
    }
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
    required this.onClear,
  });

  final UtteranceBar utterance;
  final VoidCallback onSpeak;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: utterance,
      builder: (context, _) {
        return Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onSpeak,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      utterance.isEmpty ? '' : utterance.text,
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
              IconButton(
                icon: const Icon(Icons.volume_up),
                iconSize: 32,
                onPressed: onSpeak,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                iconSize: 32,
                onPressed: onClear,
              ),
            ],
          ),
        );
      },
    );
  }
}
