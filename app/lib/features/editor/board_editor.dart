import 'package:drift/drift.dart' hide Column;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/tables.dart';
import '../../theme/fitzgerald.dart';
import '../../db/ids.dart';
import '../../db/seed/band_layout.dart';
import '../grid/cell_layout.dart';
import '../grid/grid_geometry.dart';
import '../grid/region_label_strip.dart';
import '../grid/region_labels.dart';
import '../grid/grid_surface.dart';
import '../grid/symbol_view.dart';
import '../symbols/auto_symbol.dart';
import '../symbols/global_symbols_pack.dart';
import '../symbols/symbol_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import 'pinning.dart';
import 'placement_rules.dart';
import 'remap.dart';
import 'row_move.dart';
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
    this.openCellId,
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

  /// A location to act on as soon as the board is loaded, as though it had
  /// been tapped.
  ///
  /// For arriving from somewhere that already knows the location — the
  /// developer sheet, which is opened by holding that exact cell on the talk
  /// screen. Without it the caregiver is handed a grid and asked to find the
  /// square they were just looking at, which on an 84 cell board means
  /// counting rows.
  ///
  /// It opens what a tap would open and nothing more, so there is one route
  /// into adding a word and one set of refusals guarding it.
  final String? openCellId;

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

  /// Whether the location this editor was opened on has already been acted on.
  ///
  /// A load happens again after a row move and after a row is named, and
  /// reopening the add-a-word sheet on each of those would be a prompt nobody
  /// asked for on top of the work they just did.
  bool _opened = false;

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
    if (!mounted) return;
    setState(() {
      _vocab = vocab;
      _board = board;
    });

    if (widget.openCellId != null && !_opened) {
      _opened = true;
      await _openRequestedCell(widget.openCellId!);
    }
  }

  /// Acts on the location this editor was opened for, if it is still there.
  ///
  /// Read fresh rather than passed in, because between the hold on the talk
  /// screen and this frame the location may have been filled — and the tap
  /// path already knows what to do about that.
  Future<void> _openRequestedCell(String cellId) async {
    final db = widget.db;
    final row = await (db.select(db.cells).join([
      leftOuterJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
    ])..where(db.cells.id.equals(cellId))).getSingleOrNull();
    if (row == null || !mounted) return;

    await _onCellTapped((
      cell: row.readTable(db.cells),
      button: row.readTableOrNull(db.buttons),
    ));
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
      if (await _refused(placed.cell)) return;
      await _completeMove(moving, placed.cell);
      return;
    }

    if (placed.button == null) {
      if (await _refused(placed.cell)) return;
      await _addWord(placed.cell);
      return;
    }

    await _showActions(placed.button!);
  }

  /// Says why a location will not take a word, and reports whether it refused.
  ///
  /// Asked before the move sheet and before the word is typed, so a caregiver
  /// is told at the point they chose the location rather than after they have
  /// done the work of naming a word.
  Future<bool> _refused(Cell cell) async {
    final why = await refusalToPlaceAt(
      widget.db,
      vocabularyId: widget.vocabularyId,
      row: cell.row,
    );
    if (why == null) return false;

    if (mounted) {
      setState(() => _moving = null);
      _snack(why);
    }
    return true;
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

    await _remap.recordCreate(
      vocabularyId: widget.vocabularyId,
      buttonId: buttonId,
      cellId: cell.id,
    );
  }

  /// Asks what goes on the location, offering the phrases first (§4.42).
  ///
  /// A caregiver staring at an empty cell has to think of the phrase before
  /// they can type it, and the ones worth having are the ones nobody thinks of
  /// until the moment they are needed. So the list comes first and the text
  /// field last, the same shape as naming a row.
  Future<String?> _promptForWord() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const SafeArea(child: _AddAWord()),
    );
  }

  Future<void> _showActions(Button button) async {
    final impact = await _remap.impactOfMoving(button.id);

    // Three cases, not two (§4.66). A button in the pinned column is either a
    // pin of a word that lives elsewhere — where unpinning is the safe thing
    // and the obvious place to ask for it — or a word that lives only there,
    // where neither offer is true. Collapsing both into "no pin" offered the
    // pinned copy the chance to be pinned.
    final copy = await isPinnedCopy(widget.db, button);
    final onlyHere =
        !button.isSystem &&
        !copy &&
        await livesInPinnedColumn(widget.db, button);
    final pinned = copy
        ? await rowInPinnedColumn(widget.db, button)
        : button.isSystem || onlyHere
        ? null
        : await pinnedRowOf(widget.db, button);
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
                      ? 'Nothing recorded at this location in the last '
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
              // A word that lives only in the pinned column is neither
              // pinnable nor unpinnable, and says which rather than offering
              // an action that refuses after it is tapped.
              if (onlyHere)
                ListTile(
                  leading: const Icon(Icons.push_pin),
                  title: const Text('Already on every board'),
                  subtitle: Text(
                    '"${button.label}" lives in the pinned column and nowhere '
                    'else, so it is reachable from every board already. It '
                    'cannot be unpinned, because there is no other location '
                    'for it to fall back to.',
                  ),
                  isThreeLine: true,
                  enabled: false,
                )
              // Offered whether or not it can be done, and refused with the
              // reason. §4.15's argument again.
              else if (pinned == null)
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: const Text('Reach this from every board'),
                  subtitle: const Text(
                    'Adds it to the pinned column, so it costs the same '
                    'movements wherever you are. It keeps the location it has.',
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pin(button);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.push_pin),
                  title: const Text('Stop reaching this from every board'),
                  subtitle: const Text(
                    'Takes the pinned locations back. The word stays where '
                    'it lives, because the pin was a second route to it '
                    'rather than a move.',
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _unpin(button, pinned);
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

  /// Takes a pin back, and says what it does not touch.
  Future<void> _unpin(Button button, int row) async {
    final vocabulary = await (widget.db.select(
      widget.db.vocabularies,
    )..where((v) => v.id.equals(widget.vocabularyId))).getSingle();
    if (!mounted) return;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop reaching "${button.label}" from every board?'),
        content: Text(
          'Its pinned locations go back to being empty and reserved. '
          '"${button.label}" itself does not move. It keeps the location it '
          'has always had, and the movements to it are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Leave it pinned'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unpin it'),
          ),
        ],
      ),
    );
    if (agreed != true) return;

    await unpinWord(widget.db, vocabulary: vocabulary, row: row);
    if (mounted) _snack('"${button.label}" is no longer on every board.');
  }

  /// Gives a word a second, shorter route to itself (§4.16).
  ///
  /// A copy rather than a move, so nothing that has been learned changes, and
  /// the cost is stated in the units it is paid in: one location on every
  /// board, not one location.
  Future<void> _pin(Button button) async {
    final refusal = await refusalToPin(widget.db, button);
    if (!mounted) return;
    if (refusal != null) {
      _snack(refusal);
      return;
    }

    final boards =
        await (widget.db.select(widget.db.boards)
              ..where((b) => b.vocabularyId.equals(widget.vocabularyId))
              ..where((b) => b.deletedAt.isNull()))
            .get();
    if (!mounted) return;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reach "${button.label}" from every board?'),
        content: Text(pinCost(label: button.label, boards: boards.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pin it'),
          ),
        ],
      ),
    );
    if (agreed != true) return;

    await pinWord(widget.db, button);
    if (mounted) {
      _snack('"${button.label}" is now on every board.');
    }
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

  /// What a caregiver can do to a row: name it, or move it to another page.
  ///
  /// Both hang off the row's own label, because that is the thing on screen
  /// that *is* the row — a control for it anywhere else would be a control for
  /// something the caregiver has to work out they are pointing at.
  Future<void> _onRowTapped(int line, RegionNames names, BandAxis axis) async {
    final board = _board;
    if (board == null) return;

    // Only rows move. A board banded by columns has no "next page" a column
    // could go to that means anything, and inventing one would move words
    // sideways across a board they were laid out along.
    final pages = axis == BandAxis.rows
        ? await pagesOfGroup(widget.db, board)
        : const <Board>[];
    if (!mounted) return;

    final elsewhere = [
      for (final p in pages)
        if (p.id != board.id) p,
    ];
    if (elsewhere.isEmpty) {
      await _nameLine(line, names);
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Row ${line + 1} of "${board.name}"'),
              subtitle: Text(
                names.forLine(line) == null
                    ? 'Not named yet'
                    : 'Called "${names.forLine(line)}"',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Say what this row is for'),
              subtitle: const Text('Shown above it when labels are on'),
              onTap: () => Navigator.of(sheetContext).pop('name'),
            ),
            ListTile(
              leading: const Icon(Icons.low_priority),
              title: const Text('Move this row to another page'),
              subtitle: const Text(
                'Every word on it moves. It keeps the same row, one page '
                'across, and moving it back puts them all where they were.',
              ),
              isThreeLine: true,
              onTap: () => Navigator.of(sheetContext).pop('move'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    if (chosen == 'name') {
      await _nameLine(line, names);
    } else {
      await _moveRow(line, board, elsewhere);
    }
  }

  /// Moves a whole row to another page, once somebody has been told what it
  /// costs (§4.42).
  Future<void> _moveRow(int line, Board board, List<Board> elsewhere) async {
    final destination = elsewhere.length == 1
        ? elsewhere.single
        : await showModalBottomSheet<Board>(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('Move it to')),
                  const Divider(height: 1),
                  for (final page in elsewhere)
                    ListTile(
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: Text(page.name),
                      onTap: () => Navigator.of(sheetContext).pop(page),
                    ),
                ],
              ),
            ),
          );
    if (destination == null || !mounted) return;

    final refusal = await refusalToMoveRow(
      widget.db,
      from: board,
      line: line,
      to: destination,
    );
    if (!mounted) return;
    if (refusal != null) {
      _snack(refusal);
      return;
    }

    final cost = await rowMoveCost(widget.db, from: board, line: line);
    if (!mounted) return;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move row ${line + 1} to "${destination.name}"?'),
        content: SingleChildScrollView(
          child: Text(
            rowMoveWarning(
              cost: cost,
              toBoardName: destination.name,
              userName: widget.userName,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Leave it here'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move the row'),
          ),
        ],
      ),
    );
    if (agreed != true) return;

    await moveRow(widget.db, from: board, line: line, to: destination);
    if (mounted) {
      _snack('Row ${line + 1} is now on "${destination.name}".');
    }
    await _load();
  }

  /// Lets a caregiver say what a run of locations is for (§4.26).
  ///
  /// Chosen from the names the shipped layout already uses, so the vocabulary
  /// of the board stays the same between the rows that came with it and the
  /// ones somebody added — with free text last, because a row built for one
  /// child's swimming club is not on any list.
  Future<void> _nameLine(int line, RegionNames names) async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) =>
          SafeArea(child: _NameALine(current: names.forLine(line))),
    );
    if (chosen == null || !mounted) return;

    final updated = chosen.isEmpty
        ? names.without(line)
        : names.with_(line, chosen);

    await (widget.db.update(
      widget.db.boards,
    )..where((b) => b.id.equals(widget.boardId))).write(
      BoardsCompanion(
        lineNames: Value(updated.isEmpty ? null : RegionNames.encode(updated)),
        updatedAt: Value(nowMs()),
      ),
    );
    await _load();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        // A refusal explains a row, which takes longer to read than
        // "Moved \"x\"" does.
        duration: const Duration(seconds: 8),
      ),
    );
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
              // Three answers, because two of them mean the button did
              // nothing for different reasons. Told "nothing to undo" when the
              // truth is "that location is taken now", a caregiver goes
              // looking for history that is still there.
              _snack(switch (await _remap.undoLast(widget.vocabularyId)) {
                UndoOutcome.undone => 'Change undone',
                UndoOutcome.nothing => 'Nothing to undo',
                UndoOutcome.blocked =>
                  'That change cannot be taken back now, because something has '
                      'taken the location it needs.',
              });
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
                    child: Text(
                      'Moving "${moving.label}". Select an empty location',
                    ),
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
                final regions = BoardRegions.decode(_board?.bandMap);
                final names = RegionNames.decode(_board?.lineNames);
                // Down the side by default. A board a caregiver made has no
                // bands and no axis, and naming a row is what §4.26 asked for.
                final axis = regions?.axis ?? BandAxis.rows;
                final byColumn = axis == BandAxis.columns;
                final labels = editableRegionLabels(
                  regions: regions,
                  names: names,
                  lines: byColumn ? vocab.gridCols : vocab.gridRows,
                );

                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final board = _EditorBoard(
                        rows: vocab.gridRows,
                        cols: vocab.gridCols,
                        cells: cells,
                        colorConvention: vocab.colorConvention,
                        resolver: widget.resolver,
                        pickedUpButtonId: moving?.id,
                        onSelect: _onCellTapped,
                      );

                      final strip = SizedBox(
                        width: byColumn ? null : regionLabelExtent,
                        height: byColumn ? regionLabelExtent : null,
                        child: RegionLabelStrip(
                          labels: labels,
                          rows: vocab.gridRows,
                          cols: vocab.gridCols,
                          axis: axis,
                          gridWidth: box.maxWidth,
                          gridHeight: box.maxHeight,
                          onTap: (line) => _onRowTapped(line, names, axis),
                        ),
                      );

                      return byColumn
                          ? Column(
                              children: [
                                strip,
                                Expanded(child: board),
                              ],
                            )
                          : Row(
                              children: [
                                strip,
                                Expanded(child: board),
                              ],
                            );
                    },
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
    required this.colorConvention,
    required this.resolver,
    required this.pickedUpButtonId,
    required this.onSelect,
  });

  final int rows;
  final int cols;
  final List<PlacedCell> cells;
  final ColorConvention colorConvention;

  /// Absent wherever pictures are not wanted; the board then reads as labels
  /// only and says nothing about which pictures are missing, because it does
  /// not know.
  final SymbolResolver? resolver;

  final String? pickedUpButtonId;
  final void Function(PlacedCell) onSelect;

  @override
  Widget build(BuildContext context) {
    // The same placement the user's board draws from (§4.6b). A location half
    // a millimetre apart on the two boards is not the same location, and this
    // is the board a caregiver audits the other one from.
    return CellLayout(
      rows: rows,
      cols: cols,
      cells: cells,
      cellBuilder: (placed) => placed.button == null
          ? _ReservedCell(onTap: () => onSelect(placed))
          : _WordCell(
              button: placed.button!,
              colorConvention: colorConvention,
              resolver: resolver,
              pickedUp: placed.button!.id == pickedUpButtonId,
              onTap: () => onSelect(placed),
            ),
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
    required this.colorConvention,
    required this.resolver,
    required this.pickedUp,
    required this.onTap,
  });

  final Button button;
  final ColorConvention colorConvention;
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
          : Fitzgerald.colorFor(widget.colorConvention, button.partOfSpeech),
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
                    color: _noPicture,
                  ),
                ),
              if (_stillLooking)
                const Positioned(
                  top: 2,
                  right: 2,
                  child: _Marker(icon: Icons.more_horiz, color: _resolving),
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
  const _Marker({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

/// Choosing what a row is for.
///
/// A list rather than a text field, because every band the app ships already
/// has a name written for a reader — `drinks`, `doing`, `people you know` —
/// and picking from that list keeps the vocabulary of the board consistent
/// between the rows that came with it and the ones somebody added. Free text
/// is last and not first, for the row built for one child's swimming club.
class _NameALine extends StatefulWidget {
  const _NameALine({required this.current});

  final String? current;

  @override
  State<_NameALine> createState() => _NameALineState();
}

class _NameALineState extends State<_NameALine> {
  late final _typed = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          const ListTile(
            title: Text(
              'What is this row for?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'A name here is shown above the row when "Label each row" is on. '
              'Rebuilding the board set or changing the grid lays every row '
              'out afresh, and these are dropped rather than moved onto a row '
              'that is not the one you named.',
            ),
            isThreeLine: true,
          ),
          const Divider(height: 1),
          if (widget.current != null)
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('No name'),
              subtitle: const Text('Falls back to what the layout calls it'),
              onTap: () => Navigator.of(context).pop(''),
            ),
          for (final name in namesToOffer)
            ListTile(
              leading: Icon(
                name == widget.current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(name),
              onTap: () => Navigator.of(context).pop(name),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _typed,
                  decoration: const InputDecoration(
                    labelText: 'Or a name of your own',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_typed.text.trim()),
                  child: const Text('Use this name'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What goes on an empty location: a phrase off the list, or anything typed.
///
/// The phrases are grouped by the moment they are for rather than by word
/// class. Interrupting, buying time, correcting somebody, ending a
/// conversation — those are the moments an AAC user is most often talked over
/// in, and the phrase that ends one is worth a location on any board.
class _AddAWord extends StatefulWidget {
  const _AddAWord();

  @override
  State<_AddAWord> createState() => _AddAWordState();
}

class _AddAWordState extends State<_AddAWord> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          // The way out is at the top, where it is always on screen. At the
          // bottom it would be behind twenty phrases and a keyboard, and a
          // caregiver who opened this by mistake would be left guessing that
          // tapping the dimmed part of the screen works.
          ListTile(
            title: const Text(
              'What goes here?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'A phrase off the list, or anything you type. Either way it is '
              'an ordinary key: it speaks what it says and it keeps this '
              'location.',
            ),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          const Divider(height: 1),
          for (final group in readyMadePhrases.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                group.key,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            for (final phrase in group.value)
              ListTile(
                dense: true,
                title: Text(phrase),
                onTap: () => Navigator.of(context).pop(phrase),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _typed,
                  decoration: const InputDecoration(
                    labelText: 'Or a word or phrase of your own',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_typed.text.trim()),
                  child: const Text('Add it'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Phrases a caregiver can put on a board without having to think of them.
///
/// Grouped by the moment they are for. Every one of them is something an AAC
/// user needs at a speed the board cannot otherwise reach: by the time a
/// sentence has been built word by word, the conversation has moved on.
const readyMadePhrases = <String, List<String>>{
  'Getting a word in': [
    'wait, I am typing',
    'let me finish',
    'I have something to say',
    'ask me, not them',
  ],
  'Buying time': ['give me a minute', 'I am thinking', 'I will tell you later'],
  'Putting it right': [
    'that is not what I meant',
    'you got it wrong',
    'start again',
    'I said no',
  ],
  'Answers that are not yes or no': [
    'I do not know',
    'I do not mind',
    'maybe later',
    'ask somebody else',
  ],
  'Ending it': [
    'I am done',
    'leave me alone',
    'I want to go home',
    'that is enough',
  ],
};
