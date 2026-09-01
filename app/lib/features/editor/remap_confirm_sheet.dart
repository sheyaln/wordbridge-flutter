import 'package:flutter/material.dart';

import '../usage/usage_queries.dart';
import 'remap.dart';

/// Shown before a word is moved.
///
/// The whole argument for this app lives in this sheet. Moving a learned word
/// is a real cost and it is not ours to refuse: what this does is say what the
/// cost is, in the user's own recorded practice, and leave the decision with
/// the person who actually knows them.
///
/// So the tone matters: this is information, not a scolding. The caregiver
/// moving a word usually has a good reason, and the sheet should read like a
/// colleague pointing something out rather than a system refusing.
class RemapConfirmSheet extends StatelessWidget {
  const RemapConfirmSheet({
    super.key,
    required this.impact,
    required this.warning,
    required this.destination,
  });

  final RemapImpact impact;
  final String? warning;

  /// Human-readable target, e.g. "row 3, column 5".
  final String destination;

  /// Returns true if the caregiver chose to go ahead.
  static Future<bool> show(
    BuildContext context, {
    required RemapImpact impact,
    required String? warning,
    required String destination,
  }) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RemapConfirmSheet(
        impact: impact,
        warning: warning,
        destination: destination,
      ),
    );
    return proceed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final learned = impact.isLearned;

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
                  learned ? Icons.warning_amber_rounded : Icons.info_outline,
                  color: learned ? Colors.orange.shade800 : Colors.blueGrey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    learned
                        ? 'This position has been learned'
                        : 'Move "${impact.label}"',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (warning != null)
              Text(warning!, style: const TextStyle(fontSize: 16, height: 1.4))
            else
              Text(
                '"${impact.label}" has not been used from this spot yet, so '
                'moving it costs nothing.',
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),

            if (impact.taps > 0) ...[
              const SizedBox(height: 20),
              _Stats(impact: impact),
            ],

            const SizedBox(height: 20),
            Text(
              'Moving to $destination.',
              style: const TextStyle(color: Colors.black54),
            ),

            if (learned) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                // The safe alternative most caregivers actually want, offered
                // rather than assumed — adding beside a word keeps every
                // existing pattern intact.
                child: const Text(
                  'If you are adding vocabulary rather than correcting a '
                  'placement, putting the new word in an empty cell leaves '
                  'this pattern untouched.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Leave it where it is'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: learned
                      ? FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                        )
                      : null,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Move anyway'),
                ),
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

  final RemapImpact impact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Stat(value: '${impact.taps}', label: 'taps here'),
            const SizedBox(width: 24),
            _Stat(value: '${impact.days}', label: 'days used'),
            if (impact.firstUsed != null) ...[
              const SizedBox(width: 24),
              _Stat(
                value:
                    '${calendarDaysBetween(impact.firstUsed!, DateTime.now())}',
                label: 'days since first use',
              ),
            ],
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
