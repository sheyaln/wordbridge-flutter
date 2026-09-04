import 'package:flutter/material.dart';

import 'remap.dart';

/// Asking before removing a word.
///
/// Reached the same way as a grid change and a seed rebuild, and for the same
/// reason: those are the operations that cost learned positions, and one
/// vocabulary across all three is worth more than three shades of severity.
/// Anything short of typing is a button somebody presses while thinking about
/// something else.
///
/// The sentence that matters is not "this word will be gone". It is that the
/// location goes back into circulation, so whatever lands there next is
/// reached by the movement this word had — by a person with no way to say the
/// board answered with something they did not mean.
class WordDeleteSheet extends StatefulWidget {
  const WordDeleteSheet({
    super.key,
    required this.label,
    required this.impact,
    required this.boardName,
    this.alsoAt = 0,
  });

  final String label;
  final RemapImpact impact;

  /// Where the location being freed is, so a caregiver knows which board is
  /// about to have a gap in it.
  final String boardName;

  /// How many further locations this word holds, which is how many a pinned
  /// word holds beyond the one being looked at (§4.16).
  ///
  /// Said out loud because the sentence above it — one location on one board
  /// goes back into circulation — is not true of a pinned word, and a caregiver
  /// who reads it and types DELETE has agreed to something smaller than what
  /// happens.
  final int alsoAt;

  static const word = 'DELETE';

  /// True when the caregiver typed the word and confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String label,
    required RemapImpact impact,
    required String boardName,
    int alsoAt = 0,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => WordDeleteSheet(
          label: label,
          impact: impact,
          boardName: boardName,
          alsoAt: alsoAt,
        ),
      ) ??
      false;

  @override
  State<WordDeleteSheet> createState() => _WordDeleteSheetState();
}

class _WordDeleteSheetState extends State<WordDeleteSheet> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  String get _practice {
    final impact = widget.impact;
    if (impact.taps == 0) {
      return 'This location has taken no recorded taps in the last '
          '${impact.windowDays} days.';
    }
    return 'This location has taken ${impact.taps} '
        '${impact.taps == 1 ? 'tap' : 'taps'} across ${impact.days} '
        '${impact.days == 1 ? 'day' : 'days'} in the last '
        '${impact.windowDays} days.';
  }

  @override
  Widget build(BuildContext context) {
    final ready = _typed.text.trim().toUpperCase() == WordDeleteSheet.word;

    return AlertDialog(
      title: Text('Remove "${widget.label}"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_practice),
            const SizedBox(height: 12),
            Text(
              'Its location on ${widget.boardName} goes back to being empty, '
              'so a word put there later is reached by the movement '
              '"${widget.label}" had. Hiding it instead keeps the location '
              'held, and nothing can take it.',
            ),
            if (widget.alsoAt > 0) ...[
              const SizedBox(height: 12),
              Text(
                '"${widget.label}" is pinned, so it is one word at '
                '${widget.alsoAt + 1} locations and every one of them goes. To '
                'take the pinned locations back and keep the word, unpin it '
                'instead.',
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'This can be undone straight away, and only while nothing else '
              'has taken the location.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Text('Type ${WordDeleteSheet.word} to continue.'),
            const SizedBox(height: 8),
            TextField(
              controller: _typed,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Remove'),
        ),
      ],
    );
  }
}
