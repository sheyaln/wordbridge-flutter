import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../interop/board_files.dart';

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
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final BoardFileStore store;

  /// Told when a file became a person, so the list behind can redraw.
  final VoidCallback? onImported;

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

  Future<void> _export() async {
    setState(() => _busy = 'Writing the file…');
    try {
      final file = await widget.store.exportVocabulary(widget.vocabularyId);
      _say('Wrote ${file.name}.');
    } catch (e) {
      _say('The board could not be written out: $e');
    }
    if (mounted) setState(() => _busy = null);
    await _refresh();
  }

  Future<void> _import(BoardFile file) async {
    final agreed = await _confirm(
      title: 'Bring in "${file.name}"?',
      body:
          'It arrives as a new person, so nothing on this board moves and the '
          'tablet keeps speaking exactly as it does now. Switch to them from '
          '"Who is using this" when you want to see it.',
      action: 'Bring it in',
    );
    if (!agreed) return;

    setState(() => _busy = 'Reading ${file.name}…');
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
      _say('Brought in as a new person.');
    } else {
      await _showNotes(outcome.notes);
    }
  }

  Future<void> _delete(BoardFile file) async {
    final agreed = await _confirm(
      title: 'Delete "${file.name}"?',
      body:
          'Only the file. Any board already brought in from it stays exactly '
          'where it is.',
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
  Future<void> _showNotes(List<String> notes) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Brought in, with these differences'),
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
            title: const Text('Write this board set out'),
            subtitle: const Text(
              'One .obz file holding every board, its words, its pictures and '
              'the links between them. Open Files on this tablet, then '
              'wordbridge → boards, to mail it or copy it somewhere.',
            ),
            isThreeLine: true,
            trailing: FilledButton(
              onPressed: _busy == null ? _export : null,
              child: const Text('Export'),
            ),
          ),

          const Divider(height: 32),
          const _Header('Files on this tablet'),

          if (files == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (files.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'None yet. Anything exported here shows up in this list, and '
                'so does any .obf or .obz put into Files → wordbridge → '
                'boards from somewhere else.',
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
                    FilledButton.tonal(
                      onPressed: _busy == null ? () => _import(file) : null,
                      child: const Text('Bring in'),
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

/// Says what this is not, above the button that would otherwise be mistaken
/// for it.
class _NotABackup extends StatelessWidget {
  const _NotABackup();

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colours.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colours.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This is not a backup',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colours.onTertiaryContainer),
                ),
                const SizedBox(height: 6),
                Text(
                  'An exported file carries the words, the pictures and the '
                  'links. It does not carry which locations are empty on '
                  'purpose, how much of the vocabulary is shown, what is '
                  'hidden, or anything recorded. Use Backups to keep a board '
                  'safe. Use this to give it to somebody, or to another '
                  'program.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colours.onTertiaryContainer),
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
