import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../interop/board_files.dart';
import '../interop/board_share.dart';

/// Taking a board set out of wordbridge, and bringing one in.
///
/// §4.41 part 3: the readers and writers have existed and been tested since
/// the interop milestone, and nothing in the app called any of them — so a
/// caregiver could not get a board out or in. Being able to leave is the
/// argument for supporting the format at all.
///
/// The screen says what the format cannot carry, before anything is pressed.
/// An export that a caregiver mistakes for a backup is the §4.41 failure with
/// extra steps: they believe they are safe and they are not.
class BoardFilesScreen extends StatefulWidget {
  const BoardFilesScreen({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.store,
    this.onImported,
    this.share = shareBoardFile,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final BoardFileStore store;

  /// Told when a file became a person, so the list behind can redraw.
  final VoidCallback? onImported;

  /// Where a file goes when somebody presses share.
  final ShareBoardFile share;

  @override
  State<BoardFilesScreen> createState() => _BoardFilesScreenState();
}

class _BoardFilesScreenState extends State<BoardFilesScreen> {
  List<BoardFile>? _files;
  String? _busy;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final files = await widget.store.files();
    if (mounted) setState(() => _files = files);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export(ExportScope scope, {String? boardId}) async {
    setState(() => _busy = 'Exporting…');
    ExportOutcome? outcome;
    try {
      outcome = await widget.store.export(
        vocabularyId: widget.vocabularyId,
        scope: scope,
        boardId: boardId,
      );
    } catch (e) {
      _say('That could not be exported: $e');
    }
    if (mounted) setState(() => _busy = null);
    await _refresh();

    if (outcome == null || !mounted) return;
    if (outcome.notes.isEmpty) {
      _say('Wrote ${outcome.file.name}.');
    } else {
      await _showNotes('Exported, with these differences', outcome.notes);
    }
  }

  /// Picks a board, then — only when it opens others — asks what to do about
  /// them.
  ///
  /// The second question is not asked when there is nothing to ask about, and
  /// it is asked before the file is written rather than reported after: a
  /// caregiver emailing one page to a school is entitled to know that four of
  /// its keys will open nothing on the other side.
  Future<void> _exportOneBoard() async {
    final boards = await widget.store.exportableBoards(widget.vocabularyId);
    if (!mounted || boards.isEmpty) return;

    final chosen = await showDialog<ExportableBoard>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which board?'),
        children: [
          for (final board in boards)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(board),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(board.name),
                subtitle: Text(
                  board.opens == 0
                      ? 'Opens no other board'
                      : 'Opens ${board.opens} other board'
                            '${board.opens == 1 ? '' : 's'}',
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    if (chosen.opens == 0) {
      await _export(ExportScope.board, boardId: chosen.id);
      return;
    }

    final withLinked = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '"${chosen.name}" opens ${chosen.opens} other board'
          '${chosen.opens == 1 ? '' : 's'}',
        ),
        content: Text(
          'Take them too and you get one .obz holding '
          '${chosen.opens + 1} boards, with the keys between them working.\n\n'
          'Take this board alone and you get one .obf. The keys that opened '
          'the other boards keep their names, so whoever imports it is told '
          'which pages are missing — but those keys will not open anything.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('This board alone'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Take all ${chosen.opens + 1}'),
          ),
        ],
      ),
    );
    if (withLinked == null || !mounted) return;

    await _export(
      withLinked ? ExportScope.category : ExportScope.board,
      boardId: chosen.id,
    );
  }

  Future<void> _share(BoardFile file, Rect? origin) async {
    final problem = await widget.share(file, origin: origin);
    if (problem != null) _say(problem);
  }

  Future<void> _import(BoardFile file) async {
    final agreed = await _confirm(
      title: 'Import "${file.name}"?',
      body:
          'It arrives as a new profile, so nothing on this board set moves. '
          'Switch to it from Profile when you want to see it.',
      action: 'Import',
    );
    if (!agreed) return;

    setState(() => _busy = 'Importing ${file.name}…');
    final outcome = await widget.store.import(file);
    if (!mounted) return;
    setState(() => _busy = null);

    final problem = outcome.problem;
    if (problem != null) {
      _say(problem);
      return;
    }

    widget.onImported?.call();
    if (outcome.notes.isEmpty) {
      _say('Imported as a new profile.');
    } else {
      await _showNotes('Imported, with these differences', outcome.notes);
    }
  }

  Future<void> _delete(BoardFile file) async {
    final agreed = await _confirm(
      title: 'Delete "${file.name}"?',
      body:
          'Deletes the file only. Any board set already imported from it is '
          'unaffected.',
      action: 'Delete',
    );
    if (!agreed) return;

    await widget.store.remove(file);
    await _refresh();
  }

  /// What the format could not carry, said rather than logged.
  ///
  /// A caregiver about to hand somebody a board needs to know a link went
  /// nowhere or a page arrived a different size, and they need to know it now
  /// rather than the first time a key does nothing.
  Future<void> _showNotes(String title, List<String> notes) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: Text(notes.join('\n\n'))),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return agreed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;

    return Scaffold(
      appBar: AppBar(title: const Text('Import and export')),
      body: ListView(
        children: [
          const _NotABackup(),

          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Export this board set'),
            subtitle: const Text(
              'One .obz file with every board, its words, symbols and links. '
              'Find it in Files under Wordbridge AAC, boards.',
            ),
            isThreeLine: true,
            trailing: FilledButton(
              onPressed: _busy == null
                  ? () => _export(ExportScope.boardSet)
                  : null,
              child: const Text('Export'),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.grid_view),
            title: const Text('Export one board'),
            subtitle: const Text(
              'A single page, or a category with the pages it opens. For '
              'sending somebody one board rather than a whole set.',
            ),
            isThreeLine: true,
            trailing: FilledButton.tonal(
              onPressed: _busy == null ? _exportOneBoard : null,
              child: const Text('Choose'),
            ),
          ),

          const Divider(height: 32),
          const _Header('Files on this device'),

          if (files == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (files.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'None yet. Anything exported appears here, as does any .obf '
                'or .obz file placed in Files under Wordbridge AAC, boards.',
              ),
            )
          else
            for (final file in files)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(file.name),
                subtitle: Text('${_kilobytes(file.bytes)} · ${_when(file.at)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete "${file.name}"',
                      onPressed: _busy == null ? () => _delete(file) : null,
                    ),
                    // Wrapped so the sheet can be anchored to this button
                    // rather than to the screen: on iPad a popover with
                    // nowhere to point does not open.
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.share_outlined),
                        tooltip: 'Send "${file.name}" somewhere',
                        onPressed: _busy == null
                            ? () => _share(file, _originOf(context))
                            : null,
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: _busy == null ? () => _import(file) : null,
                      child: const Text('Import'),
                    ),
                  ],
                ),
              ),

          if (_busy != null)
            ListTile(
              leading: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text(_busy!),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Says what this is not, above the button that would otherwise be mistaken
/// for it.
class _NotABackup extends StatelessWidget {
  const _NotABackup();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colors.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This is not a backup',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colors.onTertiaryContainer),
                ),
                const SizedBox(height: 6),
                Text(
                  'An exported file carries the boards, their words, symbols '
                  'and links. It leaves behind the row groupings, any names '
                  'you gave rows, everything recorded about use, and this '
                  'profile\'s own settings. Use Backups to keep a board set '
                  'safe; use this to move one to another program or person.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

String _kilobytes(int bytes) =>
    bytes < 1024 ? '$bytes bytes' : '${(bytes / 1024).round()} KB';

String _when(DateTime at) =>
    '${at.day}/${at.month}/${at.year}, '
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';
