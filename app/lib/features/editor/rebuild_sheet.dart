import 'package:flutter/material.dart';

import '../../db/database.dart';
import 'rebuild_from_seed.dart';

/// Asking before rebuilding a board set from the shipped vocabulary.
///
/// The same class of act as changing the grid, so it is reached the same way:
/// the cost stated in real counts first, then a word typed out. Anything less
/// than typing is a button somebody presses while thinking about something
/// else.
class RebuildSheet extends StatefulWidget {
  const RebuildSheet({
    super.key,
    required this.db,
    required this.profileId,
    required this.vocabularyId,
    this.userName,
  });

  final WordbridgeDatabase db;
  final String profileId;
  final String vocabularyId;
  final String? userName;

  /// Returns the new vocabulary id, or null if nothing was rebuilt.
  static Future<String?> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required String profileId,
    required String vocabularyId,
    String? userName,
  }) => showDialog<String>(
    context: context,
    builder: (_) => RebuildSheet(
      db: db,
      profileId: profileId,
      vocabularyId: vocabularyId,
      userName: userName,
    ),
  );

  @override
  State<RebuildSheet> createState() => _RebuildSheetState();
}

class _RebuildSheetState extends State<RebuildSheet> {
  final _typed = TextEditingController();
  static const _word = 'REBUILD';

  late final Future<RebuildImpact> _impact = rebuildImpact(
    widget.db,
    profileId: widget.profileId,
    vocabularyId: widget.vocabularyId,
  );

  bool _running = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _rebuild() async {
    setState(() => _running = true);
    try {
      final rebuilt = await rebuildFromSeed(
        widget.db,
        profileId: widget.profileId,
        vocabularyId: widget.vocabularyId,
      );
      if (mounted) Navigator.of(context).pop(rebuilt);
    } catch (error) {
      if (!mounted) return;
      setState(() => _running = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not rebuild: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.userName ?? 'This person';

    return AlertDialog(
      title: const Text('Rebuild from the shipped vocabulary'),
      content: FutureBuilder<RebuildImpact>(
        future: _impact,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
              'Could not read what the current boards hold, so there is no '
              'way to say what a rebuild would cost. Nothing has changed.',
            );
          }

          final impact = snapshot.data;
          if (impact == null) {
            return const SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final ready = _typed.text.trim().toUpperCase() == _word;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Builds a new board set at ${impact.rows} by ${impact.cols}, '
                  'from the vocabulary this version of the app ships. Every '
                  'word lands where the current version puts it, which is not '
                  'where the boards in use put it.',
                ),
                const SizedBox(height: 12),
                if (impact.handAdded.isEmpty)
                  const Text(
                    'Nothing on these boards was added by hand, so nothing '
                    'you wrote is lost.',
                  )
                else ...[
                  Text(
                    '${impact.handAdded.length} '
                    '${impact.handAdded.length == 1 ? "word" : "words"} added '
                    'by hand will be gone, and will have to be added again:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(impact.handAdded.join(', ')),
                ],
                const SizedBox(height: 12),
                if (impact.recordedTaps > 0)
                  Text(
                    '$who has tapped these boards ${impact.recordedTaps} '
                    'times. That history is kept and stays readable, but it '
                    'describes locations the new boards do not use.',
                  ),
                const SizedBox(height: 16),
                const Text('Type REBUILD to continue.'),
                const SizedBox(height: 8),
                TextField(
                  controller: _typed,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixIcon: ready
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('Keep these boards'),
        ),
        FilledButton(
          onPressed: _running || _typed.text.trim().toUpperCase() != _word
              ? null
              : _rebuild,
          child: _running
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Rebuild'),
        ),
      ],
    );
  }
}
