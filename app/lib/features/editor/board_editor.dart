import 'package:drift/drift.dart' hide Column;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';
import '../../theme/fitzgerald.dart';
import '../grid/grid_geometry.dart';
import '../grid/grid_surface.dart';
import '../grid/symbol_view.dart';
import '../symbols/auto_symbol.dart';
import '../symbols/global_symbols_pack.dart';
import '../symbols/symbol_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import 'remap.dart';
import 'remap_confirm_sheet.dart';
import 'symbol_picker.dart';
import 'word_delete_sheet.dart';

/// Caregiver board editing.
///
/// Deliberately shaped so the safe operation is the easy one. Tapping an empty
/// location adds a word — no mode, no ceremony, because that is additive and
/// costs nothing. Moving an existing word takes two deliberate taps and a
/// sheet stating what it costs.
class BoardEditor extends StatefulWidget {
  const BoardEditor({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.boardId,
    this.registry,
    this.fetcher,
    this.resolver,
    this.userName,
    this.placing,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String boardId;
  final SymbolRegistry? registry;
  final SymbolResolver? resolver;

  /// Looks up a picture for a word as soon as it is added. Absent in tests and
  /// wherever the network is not wanted; the editor works either way.
  final GlobalSymbolsPack? fetcher;
  final String? userName;

  /// A word arriving from another board, already picked up.
  ///
  /// The destination board opens with it in hand and a tap puts it down, which
  /// is the same gesture as moving a word within a board. Choosing coordinates
  /// off a list asks somebody to translate "row 3, column 5" into a place on a
  /// grid whose whole argument is that position carries meaning — and they are
  /// least able to do that on a board whose layout they are not carrying in
  /// their head, which is exactly the board they are moving the word to.
  final Button? placing;

  @override
  State<BoardEditor> createState() => _BoardEditorState();
}

class _BoardEditorState extends State<BoardEditor> {
  late final RemapService _remap = RemapService(widget.db);

  Vocabulary? _vocab;
  Board? _board;

  /// The word picked up for moving, if any.
  Button? _moving;

  @override
  void initState() {
    super.initState();
    _moving = widget.placing;
    _load();
  }

  Future<void> _load() async {
    final vocab = await (widget.db.select(
      widget.db.vocabularies,
    )..where((v) => v.id.equals(widget.vocabularyId))).getSingle();
    // Throws for a board that has been removed rather than opening an editor
    // over cells nothing can reach any more.
    final board =
        await (widget.db.select(widget.db.boards)
              ..where((b) => b.id.equals(widget.boardId))
              ..where((b) => b.deletedAt.isNull()))
            .getSingle();
    if (mounted) {
      setState(() {
        _vocab = vocab;
        _board = board;
      });
    }
  }

  Stream<List<PlacedCell>> get _cells {
    final db = widget.db;
    final query =
        db.select(db.cells).join([
            leftOuterJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
          ])
          ..where(db.cells.boardId.equals(widget.boardId))
          ..orderBy([
            OrderingTerm.asc(db.cells.row),
            OrderingTerm.asc(db.cells.col),
          ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (r) => (
              cell: r.readTable(db.cells),
              button: r.readTableOrNull(db.buttons),
            ),
          )
          .toList(),
    );
  }

  Future<void> _onCellTapped(PlacedCell placed) async {
    final moving = _moving;

    if (moving != null) {
      if (placed.button != null) {
        _snack('That location already holds a word.');
        return;
      }
      await _completeMove(moving, placed.cell);
      return;
    }

    if (placed.button == null) {
      await _addWord(placed.cell);
      return;
    }

    await _showActions(placed.button!);
  }

  Future<void> _completeMove(Button button, Cell target) async {
    final impact = await _remap.impactOfMoving(button.id);
    final warning = await _remap.warningFor(
      button.id,
      userName: widget.userName,
    );

    if (!mounted) return;
    final proceed = await RemapConfirmSheet.show(
      context,
      impact: impact,
      warning: warning,
      destination: 'row ${target.row + 1}, column ${target.col + 1}',
    );

    if (!proceed) {
      setState(() => _moving = null);
      return;
    }

    await _remap.moveButton(buttonId: button.id, toCellId: target.id);
    if (!mounted) return;
    setState(() => _moving = null);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved "${button.label}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _remap.undoLast(widget.vocabularyId),
        ),
      ),
    );
  }

  Future<void> _addWord(Cell cell) async {
    final label = await _promptForWord();
    if (label == null || label.trim().isEmpty) return;

    final word = label.trim();
    final buttonId = await placeButton(
      widget.db,
      vocabularyId: widget.vocabularyId,
      cellId: cell.id,
      label: word,
      message: word,
    );

    // Looked up in the background. A word with no picture is a complete,
    // working button, so nothing here is worth making anyone wait for.
    final registry = widget.registry;
    if (registry != null) {
      unawaited(
        AutoSymbol(
          db: widget.db,
          registry: registry,
          fetcher: widget.fetcher,
        ).attachTo(buttonId: buttonId, label: word),
      );
    }

    await widget.db
        .into(widget.db.editEvents)
        .insert(
          EditEventsCompanion.insert(
            id: newId(),
            vocabularyId: widget.vocabularyId,
            cellId: Value(cell.id),
            kind: EditKind.create,
            changedAt: nowMs(),
          ),
        );
  }

  Future<String?> _promptForWord() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a word'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Word'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(Button button) async {
    final impact = await _remap.impactOfMoving(button.id);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        // Scrolls, because how many actions there are depends on the button
        // and on whether pictures are available at all. A sheet that runs off
        // the bottom hides whichever action ended up last.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  button.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  impact.taps == 0
                      ? 'Not used from this spot in the last '
                            '${impact.windowDays} days'
                      : '${impact.taps} taps here over ${impact.days} days, '
                            'in the last ${impact.windowDays}',
                ),
              ),
              const Divider(height: 1),
              if (!button.isSystem)
                ListTile(
                  leading: const Icon(Icons.open_with),
                  title: const Text('Move to another location'),
                  subtitle: impact.isLearned
                      ? const Text('This position looks learned')
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _moving = button);
                    _snack('Now tap an empty location.');
                  },
                ),
              if (widget.registry != null && widget.resolver != null)
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Change the picture'),
                  subtitle: const Text(
                    'Search the packs, or use your own photo',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await SymbolPicker.show(
                      context,
                      db: widget.db,
                      registry: widget.registry!,
                      resolver: widget.resolver!,
                      fetcher: widget.fetcher,
                      button: button,
                    );
                  },
                ),
              if (!button.isSystem)
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outlined),
                  title: const Text('Move to another board'),
                  subtitle: const Text(
                    'Keeps the word, changes where it lives',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _moveToBoard(button);
                  },
                ),
              ListTile(
                leading: Icon(
                  button.hidden ? Icons.visibility : Icons.visibility_off,
                ),
                title: Text(
                  button.hidden ? 'Show this word' : 'Hide this word',
                ),
                subtitle: Text(
                  button.isSystem
                      ? 'Not for a key every board carries'
                      : 'Keeps its location either way',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  // Hiding an ordinary word takes it off the board and keeps
                  // its location. Hiding home takes away the way off the
                  // board, from somebody with no way to report it.
                  if (button.isSystem) {
                    _snack(
                      '"${button.label}" is one of the keys every board '
                      'carries. Hidden, it would leave a board nobody can get '
                      'off. Its picture can still be changed.',
                    );
                    return;
                  }
                  await _remap.setHidden(
                    buttonId: button.id,
                    hidden: !button.hidden,
                  );
                },
              ),
              // Offered on the frame keys too, and refused there with a reason.
              // A control that is simply absent reads as a bug and explains
              // nothing — the same argument board deletion makes (§4.15).
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Remove this word'),
                subtitle: const Text('Frees its location for something else'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _deleteWord(button, impact);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Removes a word, once somebody has typed out that they mean it.
  Future<void> _deleteWord(Button button, RemapImpact impact) async {
    if (button.isSystem) {
      _snack(
        '"${button.label}" is one of the keys every board carries. Removing '
        'it would leave a board that cannot be navigated.',
      );
      return;
    }

    final confirmed = await WordDeleteSheet.show(
      context,
      label: button.label,
      impact: impact,
      boardName: _board?.name ?? 'this board',
    );
    if (!confirmed || !mounted) return;

    await _remap.deleteButton(buttonId: button.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${button.label}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final back = await _remap.restoreButton(button.id);
            if (!back && mounted) {
              _snack(
                'Something else has taken that location, so "${button.label}" '
                'cannot go back where it was.',
              );
            }
          },
        ),
      ),
    );
  }

  /// Moves a word onto a different board.
  ///
  /// The destination is picked first and the location second, because the two
  /// questions are genuinely separate — a word crossing boards still has to
  /// land somewhere specific, and landing "wherever there is room" is how
  /// layouts drift.
  ///
  /// The board is a list because boards are a list. The location is not: that
  /// board opens with the word in hand and a tap puts it down, so there is one
  /// gesture for placing a word rather than one for this board and another for
  /// every other.
  Future<void> _moveToBoard(Button button) async {
    final boards =
        await (widget.db.select(widget.db.boards)
              ..where((b) => b.vocabularyId.equals(widget.vocabularyId))
              ..where((b) => b.deletedAt.isNull()))
            .get();

    if (!mounted) return;
    final destination = await showDialog<Board>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move "${button.label}" to'),
        children: [
          for (final board in boards)
            if (board.id != widget.boardId)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(board),
                child: Text(board.name),
              ),
        ],
      ),
    );
    if (destination == null || !mounted) return;

    final free =
        await (widget.db.select(widget.db.cells)..where(
              (c) =>
                  c.boardId.equals(destination.id) &
                  c.state.equalsValue(CellState.emptyReserved),
            ))
            .get();

    if (free.isEmpty) {
      _snack('"${destination.name}" has no free locations.');
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BoardEditor(
          db: widget.db,
          vocabularyId: widget.vocabularyId,
          boardId: destination.id,
          registry: widget.registry,
          fetcher: widget.fetcher,
          resolver: widget.resolver,
          userName: widget.userName,
          placing: button,
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Puts the word back down where it was.
  ///
  /// A word that arrived from another board leaves with the caregiver: this
  /// board was opened to place it, and staying here having not placed it is a
  /// screen they did not ask for.
  void _cancelMove() {
    if (widget.placing != null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _moving = null);
  }

  @override
  Widget build(BuildContext context) {
    final vocab = _vocab;
    if (vocab == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final moving = _moving;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit: ${_board?.name ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last change',
            onPressed: () async {
              final undone = await _remap.undoLast(widget.vocabularyId);
              _snack(undone ? 'Change undone' : 'Nothing to undo');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (moving != null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Moving "${moving.label}" — tap an empty cell'),
                  ),
                  TextButton(
                    onPressed: _cancelMove,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<PlacedCell>>(
              stream: _cells,
              builder: (context, snapshot) {
                final cells = snapshot.data;
                if (cells == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: _EditorBoard(
                    rows: vocab.gridRows,
                    cols: vocab.gridCols,
                    cells: cells,
                    colourScheme: vocab.colourScheme,
                    resolver: widget.resolver,
                    pickedUpButtonId: moving?.id,
                    onSelect: _onCellTapped,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Packs the board draws from, in order, for words with no symbol of their own.
///
/// Must match what the talk screen renders through, or the caregiver audits
/// pictures the user is not looking at.

/// A word whose picture has not resolved.
const _noPicture = Color(0xFFEF6C00);

/// A word whose picture is still being looked for.
const _resolving = Color(0x8A000000);

/// The word picked up for moving.
const _pickedUp = Color(0xFF3F51B5);

const _hiddenGround = Color(0xFFF0F0F0);
const _hiddenOutline = Color(0xFFCCCCCC);
const _reservedGround = Color(0xFFFAFAFA);
const _reservedOutline = Color(0xFFEEEEEE);
const _radius = 6.0;

/// The board as a caregiver has to read it.
///
/// Distinct from [GridSurface] because the two audiences read different
/// things: the user reads the picture, the caregiver reads the word *and*
/// judges the picture. So this draws words the user cannot see, marks the ones
/// with no picture, and marks the one picked up for moving — none of which
/// belongs in front of the user.
///
/// Geometry comes from the same [GridGeometry] the user's board uses, so a
/// location is the same location on both.
class _EditorBoard extends StatelessWidget {
  const _EditorBoard({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.colourScheme,
    required this.resolver,
    required this.pickedUpButtonId,
    required this.onSelect,
  });

  final int rows;
  final int cols;
  final List<PlacedCell> cells;
  final ColourScheme colourScheme;

  /// Absent wherever pictures are not wanted; the board then reads as labels
  /// only and says nothing about which pictures are missing, because it does
  /// not know.
  final SymbolResolver? resolver;

  final String? pickedUpButtonId;
  final void Function(PlacedCell) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = GridGeometry(
          rows: rows,
          cols: cols,
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );

        return Stack(
          children: [
            for (final placed in cells)
              Positioned.fromRect(
                rect: geometry.rectFor(
                  placed.cell.row,
                  placed.cell.col,
                  spanRows: placed.cell.spanRows,
                  spanCols: placed.cell.spanCols,
                ),
                // Keyed by location, not by content, so a word moving away
                // leaves the square standing.
                child: KeyedSubtree(
                  key: ValueKey('${placed.cell.row}:${placed.cell.col}'),
                  child: placed.button == null
                      ? _ReservedCell(onTap: () => onSelect(placed))
                      : _WordCell(
                          button: placed.button!,
                          colourScheme: colourScheme,
                          resolver: resolver,
                          pickedUp: placed.button!.id == pickedUpButtonId,
                          onTap: () => onSelect(placed),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A free location. Drawn, not omitted, and tappable to fill.
class _ReservedCell extends StatelessWidget {
  const _ReservedCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _reservedGround,
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: _reservedOutline),
          ),
        ),
      ),
    );
  }
}

/// A word, with the picture the user sees on it.
///
/// The picture is why this screen gets opened: symbols are fetched
/// automatically and some land wrong, and a plausible wrong picture teaches a
/// false association to someone who cannot contradict it. So a word with no
/// picture is marked rather than left to look like a word that simply has a
/// short label, and a word still being looked up is marked differently again —
/// "none" and "not yet" ask for different actions.
class _WordCell extends StatefulWidget {
  const _WordCell({
    required this.button,
    required this.colourScheme,
    required this.resolver,
    required this.pickedUp,
    required this.onTap,
  });

  final Button button;
  final ColourScheme colourScheme;
  final SymbolResolver? resolver;
  final bool pickedUp;
  final VoidCallback onTap;

  @override
  State<_WordCell> createState() => _WordCellState();
}

class _WordCellState extends State<_WordCell> {
  SymbolImage? _image;
  bool _pending = true;

  /// Which resolution the picture on screen belongs to.
  int _generation = 0;

  StreamSubscription<SymbolRef>? _downloads;

  @override
  void initState() {
    super.initState();
    _resolve();

    // A download queued by the first resolution lands after the grid is
    // drawn. Without this the picture appears only on the next visit, and the
    // caregiver is looking at a mark that is no longer true.
    final resolver = widget.resolver;
    if (resolver != null) {
      _downloads = resolver.ready
          .where((ref) => _sameWord(ref.label, widget.button.label))
          .listen((_) => _resolve());
    }
  }

  @override
  void didUpdateWidget(_WordCell old) {
    super.didUpdateWidget(old);
    // Locations outlive the words on them and words outlive their pictures, so
    // this state can be handed a different word, or the same word with the
    // picture changed under it.
    if (old.button.label != widget.button.label ||
        old.button.symbolId != widget.button.symbolId) {
      _image = null;
      _pending = true;
      _resolve();
    }
  }

  @override
  void dispose() {
    _downloads?.cancel();
    super.dispose();
  }

  static bool _sameWord(String a, String b) =>
      a.toLowerCase().trim() == b.toLowerCase().trim();

  /// Off the path of every editor action: nothing here is awaited before the
  /// grid paints, and a resolution that never returns leaves a working screen.
  ///
  /// The same call the user's board draws through, so this screen shows what
  /// the user is looking at rather than a second opinion about it.
  Future<void> _resolve() async {
    final resolver = widget.resolver;
    if (resolver == null) return;

    final generation = ++_generation;
    final resolved = await resolver.resolveButton(
      symbolId: widget.button.symbolId,
      label: widget.button.label,
      packIds: boardSymbolPackIds,
    );

    if (!mounted || generation != _generation) return;
    setState(() {
      _image = resolved.image;
      _pending = false;
    });
  }

  bool get _stillLooking => widget.resolver != null && _pending;
  bool get _hasNoPicture =>
      widget.resolver != null && !_pending && _image == null;

  @override
  Widget build(BuildContext context) {
    final button = widget.button;
    final hidden = button.hidden;

    final (Color outline, double outlineWidth) = switch ((
      widget.pickedUp,
      _hasNoPicture,
      hidden,
    )) {
      (true, _, _) => (_pickedUp, 3.0),
      (_, true, _) => (_noPicture, 2.0),
      (_, _, true) => (_hiddenOutline, 1.0),
      _ => (Colors.transparent, 0.0),
    };

    Widget content = _content();
    if (hidden) content = Opacity(opacity: 0.45, child: content);

    return Material(
      color: hidden
          ? _hiddenGround
          : Fitzgerald.colourFor(widget.colourScheme, button.partOfSpeech),
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: outline, width: outlineWidth),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: Center(child: content),
              ),
              if (_hasNoPicture)
                const Positioned(
                  top: 2,
                  right: 2,
                  child: _Marker(
                    icon: Icons.add_photo_alternate_outlined,
                    colour: _noPicture,
                  ),
                ),
              if (_stillLooking)
                const Positioned(
                  top: 2,
                  right: 2,
                  child: _Marker(icon: Icons.more_horiz, colour: _resolving),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final image = _image;
    final label = widget.button.label;
    if (image == null) {
      return _CellLabel(label, large: true, italic: widget.button.hidden);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: SymbolPicture(image)),
        const SizedBox(height: 2),
        _CellLabel(label, large: false, italic: widget.button.hidden),
      ],
    );
  }
}

/// Corner mark saying what a cell needs, if anything.
///
/// A corner rather than the middle: a caregiver scanning 84 locations for the
/// ones to fix reads a column of marks far faster than 84 captions, and the
/// picture underneath stays fully visible while they do it.
class _Marker extends StatelessWidget {
  const _Marker({required this.icon, required this.colour});

  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }
}

class _CellLabel extends StatelessWidget {
  const _CellLabel(this.text, {required this.large, required this.italic});

  final String text;

  /// True where the word carries the cell alone and is set to be read across
  /// the room; false where it captions a picture.
  final bool large;

  /// Marks a word switched off for the user.
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: large ? 20 : 13,
          fontWeight: large ? FontWeight.w600 : FontWeight.w500,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          color: Colors.black87,
        ),
      ),
    );
  }
}
