import 'package:flutter/material.dart';

import 'board_delete.dart';

/// Shown before a board with words on it is removed, and instead of removing
/// one that cannot be.
///
/// Same argument as the sheet a word's move goes through: say what it costs in
/// the user's own recorded practice and let the person who knows them decide.
/// A refusal gets the same sheet rather than a missing button, because "why
/// not" is the useful half of a refusal and an absent control answers nothing.
class BoardDeleteSheet extends StatelessWidget {
  const BoardDeleteSheet({
    super.key,
    required this.impact,
    required this.warning,
  });

  final BoardDeleteImpact impact;
  final String? warning;

  /// Returns true if the caregiver chose to go ahead. Always false for a board
  /// that cannot be removed.
  static Future<bool> show(
    BuildContext context, {
    required BoardDeleteImpact impact,
    required String? userName,
  }) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BoardDeleteSheet(
        impact: impact,
        warning: impact.warningFor(userName),
      ),
    );
    return proceed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final refused = !impact.canDelete;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  refused ? Icons.lock_outline : Icons.warning_amber_rounded,
                  color: refused ? Colors.blueGrey : Colors.orange.shade800,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    refused
                        ? 'This board has to stay'
                        : 'Remove "${impact.boardName}"?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              refused ? impact.reason! : warning ?? '',
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),

            if (!refused && impact.words > 0) ...[
              const SizedBox(height: 20),
              _Stats(impact: impact),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(refused ? 'Close' : 'Keep it'),
                ),
                if (!refused) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Remove it'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.impact});

  final BoardDeleteImpact impact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Stat(value: '${impact.words}', label: 'words on it'),
            const SizedBox(width: 24),
            _Stat(value: '${impact.taps}', label: 'taps there'),
            const SizedBox(width: 24),
            _Stat(value: '${impact.days}', label: 'days used'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'From the last ${impact.windowDays} days. Any older use is not '
          'counted.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
