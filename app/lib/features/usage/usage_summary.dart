import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import 'logger.dart';
import 'usage_queries.dart';

/// The two figures at the top, read together because they are read against
/// each other.
typedef _Counts = ({int taps, int differentWords});

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

  /// One future per panel, held rather than started from [build], which runs
  /// again for reasons that have nothing to do with the figures: an ancestor
  /// rebuilding, a theme or text-size change, the tab coming back. Replaced
  /// only by the four things that change the answer — the window, the profile,
  /// recording being switched on, and emptying the log — or by a caregiver
  /// retrying one that failed.
  ///
  /// Split three ways rather than combined, so a database that answers two
  /// questions and fails the third costs one panel instead of the screen. They
  /// are still started in one pass, which is what makes the sentences and the
  /// counts describe the same stretch of a log that is being written to while
  /// it is read; a retry re-reads its own panel alone and can therefore leave
  /// it a moment newer than the others, which beats leaving it blank.
  Future<_Counts>? _counts;
  Future<List<Utterance>>? _recent;
  Future<List<WordCount>>? _mostUsed;

  /// A local read that has not answered by now is not going to. Without this a
  /// locked or wedged database leaves a progress bar moving over a panel that
  /// will never fill, which tells a caregiver the opposite of the truth.
  static const _readTimeout = Duration(seconds: 10);

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

  Future<_Counts> _readCounts() async {
    final window = _window;
    final (taps, differentWords) = await (
      _q.totalTaps(widget.profileId, window: window),
      _q.numberOfDifferentWords(widget.profileId, window: window),
    ).wait.timeout(_readTimeout);

    return (taps: taps, differentWords: differentWords);
  }

  Future<List<Utterance>> _readRecent() => _q
      .recentUtterances(widget.profileId, window: _window)
      .timeout(_readTimeout);

  Future<List<WordCount>> _readMostUsed() =>
      _q.mostUsedWords(widget.profileId, window: _window).timeout(_readTimeout);

  void _readAll() {
    _counts = _readCounts();
    _recent = _readRecent();
    _mostUsed = _readMostUsed();
  }

  void _forget() {
    _counts = null;
    _recent = null;
    _mostUsed = null;
  }

  @override
  void didUpdateWidget(UsageSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) _forget();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.logger.enabledChanges,
      builder: (context, enabled, _) {
        if (!enabled) {
          // Nothing is being recorded while this is off, so there is no reason
          // to hold a read; switching it back on asks the database again.
          _forget();
          return const _LoggingOff();
        }
        return _figures(context);
      },
    );
  }

  Widget _figures(BuildContext context) {
    final counts = _counts ??= _readCounts();
    final recent = _recent ??= _readRecent();
    final mostUsed = _mostUsed ??= _readMostUsed();

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
            _readAll();
          }),
        ),
        const SizedBox(height: 24),

        _Panel<_Counts>(
          future: counts,
          what: 'the counts',
          onRetry: () => setState(() {
            _counts = _readCounts();
          }),
          // The shape of the answer while it is on its way. It resolves either
          // way, so nobody is left reading a dash.
          waiting: const Row(
            children: [
              _Stat(value: '0', label: 'words spoken'),
              SizedBox(width: 32),
              _Stat(value: '0', label: 'different words'),
            ],
          ),
          builder: (context, d) => Row(
            children: [
              _Stat(value: '${d.taps}', label: 'words spoken'),
              const SizedBox(width: 32),
              // The metric SLPs track for vocabulary growth, and the one
              // that ends up in funding paperwork.
              _Stat(value: '${d.differentWords}', label: 'different words'),
            ],
          ),
        ),

        const SizedBox(height: 32),
        const _Heading('Recent sentences'),
        _Panel<List<Utterance>>(
          future: recent,
          what: 'the recent sentences',
          onRetry: () => setState(() {
            _recent = _readRecent();
          }),
          builder: (context, items) {
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
        _Panel<List<WordCount>>(
          future: mostUsed,
          what: 'the most-used words',
          onRetry: () => setState(() {
            _mostUsed = _readMostUsed();
          }),
          builder: (context, items) {
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
          'Kept on this tablet. This is a record of one person\'s speech, so '
          'treat a copy of it the way you would treat anything else they said '
          'in private.',
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

    if (ok != true) return;

    try {
      await _q.deleteAllFor(widget.profileId);
    } catch (_) {
      // Somebody who asked for a transcript of their child's speech to be
      // destroyed must not walk away believing it was when it was not.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The recorded use could not be deleted and is still on this '
            'device. Try again.',
          ),
        ),
      );
      return;
    }

    if (mounted) setState(_readAll);
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

/// One panel of the report: on its way, unreadable with a way back, or the
/// figures themselves.
class _Panel<T extends Object> extends StatelessWidget {
  const _Panel({
    required this.future,
    required this.what,
    required this.onRetry,
    required this.builder,
    this.waiting = const LinearProgressIndicator(),
  });

  final Future<T> future;

  /// Named in the failure line, so a caregiver can tell which of the three
  /// panels is missing rather than which widget threw.
  final String what;

  final VoidCallback onRetry;
  final Widget Function(BuildContext, T) builder;
  final Widget waiting;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) return _Failed(what: what, onRetry: onRetry);
      final data = snap.data;
      if (data == null) return waiting;
      return builder(context, data);
    },
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.what, required this.onRetry});

  final String what;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Could not read $what. The log is still on this device and nothing '
          'in it was lost.',
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onRetry, child: const Text('Try again')),
        ),
      ],
    ),
  );
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
            'Turn on usage tracking to see which words are used and how '
            'often.',
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
