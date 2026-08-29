import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import 'logger.dart';
import 'usage_queries.dart';

/// Every figure on the screen, read in one pass.
typedef _Figures = ({
  int taps,
  int differentWords,
  List<Utterance> recent,
  List<WordCount> mostUsed,
});

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

  int _days = 7;

  /// Held rather than started from [build], which runs again for reasons that
  /// have nothing to do with the figures: an ancestor rebuilding, a theme or
  /// text-size change, the tab coming back. Replaced only by the four things
  /// that change the answer — the window, the profile, recording being switched
  /// on, and emptying the log.
  Future<_Figures>? _figures;

  /// "Today" is a calendar day, ending at last midnight; the other two are
  /// rolling spans, which is what their labels say.
  UsageWindow get _window => _days == 1
      ? const UsageWindow.calendarDays(1)
      : UsageWindow.rollingDays(_days);

  /// Names the stretch of time that is empty, which an empty panel would
  /// otherwise report as an empty log.
  String get _nothingRecorded => _days == 1
      ? 'Nothing recorded today.'
      : 'Nothing recorded in the last $_days days.';

  /// One read behind all three panels, so the sentences and the counts describe
  /// the same log rather than two moments of it. These figures are read against
  /// each other and copied into funding letters; panels that disagree are worse
  /// than panels that arrive together a moment later.
  Future<_Figures> _read() async {
    final window = _window;
    final (taps, differentWords, recent, mostUsed) = await (
      _q.totalTaps(widget.profileId, window: window),
      _q.numberOfDifferentWords(widget.profileId, window: window),
      _q.recentUtterances(widget.profileId, window: window),
      _q.mostUsedWords(widget.profileId, window: window),
    ).wait;

    return (
      taps: taps,
      differentWords: differentWords,
      recent: recent,
      mostUsed: mostUsed,
    );
  }

  @override
  void didUpdateWidget(UsageSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) _figures = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.logger.enabled) {
      // Nothing is being recorded while this is off, so there is no reason to
      // hold a read; switching it back on asks the database again.
      _figures = null;
      return const _LoggingOff();
    }

    final figures = _figures ??= _read();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Today')),
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
          ],
          selected: {_days},
          onSelectionChanged: (s) => setState(() {
            _days = s.first;
            _figures = _read();
          }),
        ),
        const SizedBox(height: 24),

        FutureBuilder<_Figures>(
          future: figures,
          builder: (context, snap) {
            final d = snap.data;
            return Row(
              children: [
                _Stat(value: '${d?.taps ?? '—'}', label: 'words spoken'),
                const SizedBox(width: 32),
                // The metric SLPs track for vocabulary growth, and the one
                // that ends up in funding paperwork.
                _Stat(
                  value: '${d?.differentWords ?? '—'}',
                  label: 'different words',
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 32),
        const _Heading('Recent sentences'),
        FutureBuilder<_Figures>(
          future: figures,
          builder: (context, snap) {
            final items = snap.data?.recent;
            if (items == null) return const LinearProgressIndicator();
            if (items.isEmpty) return _Empty(_nothingRecorded);
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
        FutureBuilder<_Figures>(
          future: figures,
          builder: (context, snap) {
            final items = snap.data?.mostUsed;
            if (items == null) return const LinearProgressIndicator();
            if (items.isEmpty) return _Empty(_nothingRecorded);

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
                          child: Text(w.label, overflow: TextOverflow.ellipsis),
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
      if (mounted) {
        setState(() {
          _figures = _read();
        });
      }
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
            'Word usage is not being tracked',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          // Framed as a decision rather than a setting someone forgot: a log
          // of this is a transcript of a disabled person's speech, and turning
          // it on should be a choice somebody made on purpose.
          Text(
            'Turn this on to see which words get used and how often. '
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
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ],
  );
}
