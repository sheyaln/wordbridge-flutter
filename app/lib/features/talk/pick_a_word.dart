import 'dart:async';

import 'package:drift/drift.dart' show Value, innerJoin;
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/seed/core_board_set.dart';
import '../../db/tables.dart';
import '../grid/grid_surface.dart';
import '../symbols/symbol_resolver.dart';
import 'type_a_word.dart';

/// Picking a word by browsing the boards, the way the person already knows
/// them (§4.81).
///
/// **The board is the index.** Somebody choosing a favorite is choosing a word
/// they already say, and they already know where it is — so the fastest way to
/// name it is the route they use to say it. A search box asks them to spell a
/// word instead, which is a different skill and one many users of this app do
/// not have.
///
/// Navigation is the board's own: the category keys along the system row, the
/// cycle key, the paging keys, home and back. Nothing here teaches a second way
/// around; it is the board, with the words made pickable instead of speakable.
///
/// **System keys are not pickable.** "home" and "more words" are how you move,
/// not things anybody wants to say, and a favorites list with "back a page" on
/// it would be a list that had misunderstood the question. They still work —
/// they just navigate rather than answer.
class PickAWord extends StatefulWidget {
  const PickAWord({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.vocabLevel,
    this.resolver,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final int? vocabLevel;
  final SymbolResolver? resolver;

  /// The word that was picked or typed, or null if nobody chose either.
  static Future<String?> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required String vocabularyId,
    int? vocabLevel,
    SymbolResolver? resolver,
  }) => Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => PickAWord(
        db: db,
        vocabularyId: vocabularyId,
        vocabLevel: vocabLevel,
        resolver: resolver,
      ),
    ),
  );

  @override
  State<PickAWord> createState() => _PickAWordState();
}

class _PickAWordState extends State<PickAWord> {
  Vocabulary? _vocab;
  String? _rootBoardId;
  String? _boardId;
  String? _previousBoardId;
  List<PlacedCell> _cells = const [];

  /// Which turn of the category wheel is showing, so the keys open what they
  /// open on the board this was launched from.
  int _categoryPage = 0;
  SystemFrame? _frame;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final vocab = await (widget.db.select(
      widget.db.vocabularies,
    )..where((v) => v.id.equals(widget.vocabularyId))).getSingle();

    final root =
        await (widget.db.select(widget.db.boards)
              ..where((b) => b.vocabularyId.equals(widget.vocabularyId))
              ..where((b) => b.kind.equalsValue(BoardKind.root))
              ..where((b) => b.deletedAt.isNull()))
            .getSingleOrNull();
    if (root == null || !mounted) return;

    setState(() {
      _vocab = vocab;
      _frame = SystemFrame.parse(vocab.systemCellMap);
      _rootBoardId = root.id;
      _boardId = root.id;
    });
    await _loadBoard(root.id);
  }

  Future<void> _loadBoard(String boardId) async {
    final found = await (widget.db.select(widget.db.cells).join([
      innerJoin(
        widget.db.buttons,
        widget.db.buttons.cellId.equalsExp(widget.db.cells.id),
      ),
    ])..where(widget.db.cells.boardId.equals(boardId))).get();

    if (!mounted) return;
    setState(() {
      _cells = [
        for (final r in found)
          (
            cell: r.readTable(widget.db.cells),
            button: r.readTable(widget.db.buttons),
          ),
      ];
    });
  }

  /// What a category key opens on this turn of the wheel.
  ///
  /// Read off the recorded frame rather than recomputed, exactly as the talk
  /// screen does, so a key here opens the board it opens there.
  ({String name, String boardId})? _categoryAt(int col) {
    final frame = _frame;
    if (frame == null) return null;

    final slot = frame.categoryCols.indexOf(col);
    if (slot < 0) return null;

    final perPage = frame.categoryCols.length;
    final index = _categoryPage * perPage + slot;
    if (index >= frame.categories.length) return null;
    return frame.categories[index];
  }

  int get _wheelPages {
    final frame = _frame;
    if (frame == null || frame.categoryCols.isEmpty) return 1;
    return (frame.categories.length / frame.categoryCols.length).ceil();
  }

  Future<void> _select(PlacedCell placed) async {
    final button = placed.button;
    if (button == null) return;

    switch (button.action) {
      case ButtonAction.navigate:
        final target =
            _categoryAt(placed.cell.col)?.boardId ?? button.targetBoardId;
        if (target == null) return;
        setState(() {
          _previousBoardId = _boardId;
          _boardId = target;
        });
        await _loadBoard(target);

      case ButtonAction.home:
        final root = _rootBoardId;
        if (root == null) return;
        setState(() {
          _previousBoardId = null;
          _boardId = root;
          _categoryPage = 0;
        });
        await _loadBoard(root);

      case ButtonAction.back:
        final destination = _previousBoardId ?? _rootBoardId;
        if (destination == null) return;
        setState(() {
          _boardId = destination;
          _previousBoardId = null;
        });
        await _loadBoard(destination);

      case ButtonAction.cycleCategories:
        setState(() => _categoryPage = (_categoryPage + 1) % _wheelPages);

      // Everything else on the system row moves you around or does something
      // to a sentence there is none of here. Ignored rather than made
      // pickable: none of them is a word.
      case ButtonAction.clear:
      case ButtonAction.backspace:
      case ButtonAction.speakBar:
      case ButtonAction.quickSettings:
      case ButtonAction.quickVolume:
      case ButtonAction.quickTone:
      case ButtonAction.favorites:
      case ButtonAction.keypad:
      case ButtonAction.none:
        return;

      // A word. Its label is what a favorite is made of — the same string the
      // board draws and the same one the list will draw.
      case ButtonAction.speak:
      case ButtonAction.punctuate:
      case ButtonAction.morpheme:
        if (button.isSystem) return;
        Navigator.of(context).pop(button.label);
    }
  }

  /// Whether a location is drawn at all here.
  ///
  /// The keys that move you around are drawn, because moving around is how you
  /// find the word. The quick settings key is not: this picker was opened
  /// *from* that menu, it picks nothing, and a key that is visible and does
  /// nothing is one a person learns to distrust.
  bool _shown(PlacedCell placed) =>
      placed.button?.action != ButtonAction.quickSettings;

  /// Drawn the way the board draws it, with the category keys showing whatever
  /// the wheel is turned to.
  PlacedCell _asDrawn(PlacedCell placed) {
    final button = placed.button;
    if (button == null || button.action != ButtonAction.navigate) return placed;

    final showing = _categoryAt(placed.cell.col);
    if (showing == null) return placed;

    return (
      cell: placed.cell,
      button: button.copyWith(
        label: showing.name,
        targetBoardId: Value(showing.boardId),
      ),
    );
  }

  Future<void> _type() async {
    final typed = await TypeAWord.show(context);
    if (typed == null || typed.isEmpty || !mounted) return;
    if (!context.mounted) return;
    Navigator.of(context).pop(typed);
  }

  @override
  Widget build(BuildContext context) {
    final vocab = _vocab;

    return Scaffold(
      appBar: AppBar(title: const Text('Pick a word')),
      body: Column(
        children: [
          // Above the board, because it is the way out of it: somebody who has
          // browsed and not found their word is here precisely because the
          // board does not have it.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _type,
                icon: const Icon(Icons.keyboard),
                label: const Text('Type a word instead'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tap the word you want to keep. The keys along the bottom move '
              'you around, the same as they do on the board.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: vocab == null
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: GridSurface(
                      rows: vocab.gridRows,
                      cols: vocab.gridCols,
                      cells: [
                        for (final c in _cells)
                          if (_shown(c)) _asDrawn(c),
                      ],
                      vocabLevel: widget.vocabLevel ?? 99,
                      resolver: widget.resolver,
                      colorConvention: vocab.colorConvention,
                      onSelect: _select,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
