import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';
import '../grid/grid_surface.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import 'remap.dart';
import 'remap_confirm_sheet.dart';
import 'symbol_picker.dart';

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
    this.resolver,
    this.userName,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String boardId;
  final SymbolRegistry? registry;
  final SymbolResolver? resolver;
  final String? userName;

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
    _load();
  }

  Future<void> _load() async {
    final vocab = await (widget.db.select(
      widget.db.vocabularies,
    )..where((v) => v.id.equals(widget.vocabularyId))).getSingle();
    final board = await (widget.db.select(
      widget.db.boards,
    )..where((b) => b.id.equals(widget.boardId))).getSingle();
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

    await placeButton(
      widget.db,
      vocabularyId: widget.vocabularyId,
      cellId: cell.id,
      label: label.trim(),
      message: label.trim(),
    );

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
      builder: (context) => SafeArea(
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
                    ? 'Not used from this spot yet'
                    : '${impact.taps} taps here over ${impact.days} days',
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
                  Navigator.of(context).pop();
                  setState(() => _moving = button);
                  _snack('Now tap an empty location.');
                },
              ),
            if (widget.registry != null && widget.resolver != null)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Change the picture'),
                subtitle: const Text('Search the packs, or use your own photo'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await SymbolPicker.show(
                    context,
                    db: widget.db,
                    registry: widget.registry!,
                    resolver: widget.resolver!,
                    button: button,
                  );
                },
              ),
            if (!button.isSystem)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('Move to another board'),
                subtitle: const Text('Keeps the word, changes where it lives'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _moveToBoard(button);
                },
              ),
            ListTile(
              leading: Icon(
                button.hidden ? Icons.visibility : Icons.visibility_off,
              ),
              title: Text(button.hidden ? 'Show this word' : 'Hide this word'),
              subtitle: const Text('Keeps its location either way'),
              onTap: () async {
                Navigator.of(context).pop();
                await _remap.setHidden(
                  buttonId: button.id,
                  hidden: !button.hidden,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Moves a word onto a different board.
  ///
  /// The destination is picked first, then the location on it, because the
  /// two questions are genuinely separate — a word crossing boards still has
  /// to land somewhere specific, and landing "wherever there is room" is how
  /// layouts drift.
  Future<void> _moveToBoard(Button button) async {
    final boards = await (widget.db.select(
      widget.db.boards,
    )..where((b) => b.vocabularyId.equals(widget.vocabularyId))).get();

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
        await (widget.db.select(widget.db.cells)
              ..where(
                (c) =>
                    c.boardId.equals(destination.id) &
                    c.state.equalsValue(CellState.emptyReserved),
              )
              ..orderBy([
                (c) => OrderingTerm.asc(c.row),
                (c) => OrderingTerm.asc(c.col),
              ]))
            .get();

    if (free.isEmpty) {
      _snack('"${destination.name}" has no free locations.');
      return;
    }

    if (!mounted) return;
    final target = await showDialog<Cell>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Where on "${destination.name}"?'),
        children: [
          for (final cell in free.take(40))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(cell),
              child: Text('Row ${cell.row + 1}, column ${cell.col + 1}'),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;

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
      destination:
          '${destination.name}, row ${target.row + 1}, '
          'column ${target.col + 1}',
    );
    if (!proceed) return;

    await _remap.moveButton(buttonId: button.id, toCellId: target.id);
    if (mounted) _snack('Moved "${button.label}" to ${destination.name}');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                    onPressed: () => setState(() => _moving = null),
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
                  child: GridSurface(
                    rows: vocab.gridRows,
                    cols: vocab.gridCols,
                    cells: cells,
                    // The editor shows everything, including words hidden from
                    // the user, so a caregiver can see what a location holds
                    // rather than mistaking it for free space.
                    vocabLevel: 99,
                    showHidden: true,
                    colourScheme: vocab.colourScheme,
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
