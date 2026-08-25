import 'package:flutter/material.dart';

import '../../db/database.dart';
import 'logger.dart';
import 'usage_queries.dart';

/// What the AAC user has been saying.
///
/// Deliberately small. The temptation with logging is to build a reporting
/// product; what a parent or SLP actually wants is which words are getting
/// used and what sentences came out. Charts can wait indefinitely.
class UsageSummary extends StatefulWidget {
  const UsageSummary({
    super.key,
    required this.db,
    required this.profileId,
    required this.logger,
  });

  final WordbridgeDatabase db;
  final String profileId;
  final UsageLogger logger;

  @override
  State<UsageSummary> createState() => _UsageSummaryState();
}

class _UsageSummaryState extends State<UsageSummary> {
  late final UsageQueries _q = UsageQueries(widget.db);

  Duration _window = const Duration(days: 7);

  @override
  Widget build(BuildContext context) {
    if (!widget.logger.enabled) return const _LoggingOff();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Today')),
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
          ],
          selected: {_window.inDays},
          onSelectionChanged: (s) =>
              setState(() => _window = Duration(days: s.first)),
        ),
        const SizedBox(height: 24),

        FutureBuilder<List<int>>(
          future: Future.wait([
            _q.totalTaps(widget.profileId, window: _window),
            _q.numberOfDifferentWords(widget.profileId, window: _window),
          ]),
          builder: (context, snap) {
            final d = snap.data;
            return Row(
              children: [
                _Stat(value: '${d?[0] ?? '—'}', label: 'words spoken'),
                const SizedBox(width: 32),
                // The metric SLPs track for vocabulary growth, and the one
                // that ends up in funding paperwork.
                _Stat(value: '${d?[1] ?? '—'}', label: 'different words'),
              ],
            );
          },
        ),

        const SizedBox(height: 32),
        const _Heading('Recent sentences'),
        FutureBuilder<List<Utterance>>(
          future: _q.recentUtterances(widget.profileId),
          builder: (context, snap) {
            final items = snap.data;
            if (items == null) return const LinearProgressIndicator();
            if (items.isEmpty) return const _Empty('Nothing recorded yet.');
            return Column(
              children: [
                for (final u in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(u.text, style: const TextStyle(fontSize: 16)),
                    trailing: Text(
                      _ago(u.at),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: 32),
        const _Heading('Most used'),
        FutureBuilder<List<WordCount>>(
          future: _q.mostUsedWords(widget.profileId, window: _window),
          builder: (context, snap) {
            final items = snap.data;
            if (items == null) return const LinearProgressIndicator();
            if (items.isEmpty) return const _Empty('Nothing recorded yet.');

            final max = items.first.count;
            return Column(
              children: [
                for (final w in items.take(15))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            w.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, c) => Container(
                              height: 14,
                              width: c.maxWidth * (w.count / max),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade300,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${w.count}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: 40),
        const Text(
          'This never leaves the device. Nothing is uploaded and nobody else '
          'can see it.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _confirmDelete,
          child: const Text('Delete all recorded use'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all recorded use?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _q.deleteAllFor(widget.profileId);
      if (mounted) setState(() {});
    }
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

class _LoggingOff extends StatelessWidget {
  const _LoggingOff();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.visibility_off, size: 48, color: Colors.black26),
          SizedBox(height: 16),
          Text(
            'Recording is off',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          // Framed as a decision rather than a setting someone forgot: a log
          // of this is a transcript of a disabled person's speech, and turning
          // it on should be a choice somebody made on purpose.
          Text(
            'wordbridge does not record what gets said unless you turn it on. '
            'Everything stays on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(color: Colors.black45)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );
}
