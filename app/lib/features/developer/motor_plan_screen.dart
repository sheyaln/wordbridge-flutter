import 'package:flutter/material.dart';

import '../../db/database.dart';
import 'motor_plan_check.dart';

/// Records where every word is, and says what has moved since.
///
/// The invariant this whole app is built on is that a word never changes
/// location, and until now there was no way to ask a real device whether it
/// still holds. The test suite asks it of a freshly seeded database; the
/// devices that matter are the ones that have had a top-up, an import, a row
/// moved and a pin taken back, months apart, and none of that happens in a
/// test.
///
/// Two controls, because it is two operations: take a fingerprint, then later
/// compare against it. Anything else — a check with nothing to check against,
/// a fingerprint that silently replaced the one being used — would answer a
/// question nobody asked.
class MotorPlanScreen extends StatefulWidget {
  const MotorPlanScreen({
    super.key,
    required this.db,
    required this.vocabularyId,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;

  @override
  State<MotorPlanScreen> createState() => _MotorPlanScreenState();
}

class _MotorPlanScreenState extends State<MotorPlanScreen> {
  late final _store = MotorPlanStore(widget.db);

  MotorPlanFingerprint? _taken;
  MotorPlanCheck? _result;
  bool _reading = true;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final taken = await _store.read();
    if (mounted) {
      setState(() {
        _taken = taken;
        _reading = false;
      });
    }
  }

  Future<void> _take() async {
    final plan = await motorPlanOf(widget.db, widget.vocabularyId);
    await _store.write(widget.vocabularyId, plan);
    if (!mounted) return;
    setState(() => _result = null);
    await _read();
  }

  Future<void> _check() async {
    final taken = _taken;
    if (taken == null) return;

    final now = await motorPlanOf(widget.db, widget.vocabularyId);
    if (!mounted) return;
    setState(() => _result = compareMotorPlans(taken.plan, now));
  }

  @override
  Widget build(BuildContext context) {
    final taken = _taken;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Motor plan')),
      body: _reading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: Text(
                    taken == null
                        ? 'Take a fingerprint'
                        : 'Take a new fingerprint',
                  ),
                  subtitle: Text(
                    taken == null
                        ? 'Records the board and the location of every word, '
                              'including the ones that are hidden.'
                        : 'Replaces the one taken '
                              '${_when(taken.takenAt)}, and starts the '
                              'comparison over from where the words are now.',
                  ),
                  isThreeLine: true,
                  onTap: _take,
                ),
                if (taken != null)
                  ListTile(
                    leading: const Icon(Icons.rule),
                    title: const Text('Check against it'),
                    subtitle: Text(
                      '${taken.plan.length} words, recorded '
                      '${_when(taken.takenAt)}'
                      '${taken.vocabularyId == widget.vocabularyId ? '' : ', on a different board set'}',
                    ),
                    isThreeLine: true,
                    onTap: _check,
                  ),
                if (taken != null && taken.vocabularyId != widget.vocabularyId)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'That fingerprint was taken on another board set, so '
                      'every word will read as removed and a different set as '
                      'added. Take a new one.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
                if (result != null) ...[
                  const Divider(height: 32),
                  ..._report(context, result),
                ],
              ],
            ),
    );
  }

  List<Widget> _report(BuildContext context, MotorPlanCheck result) {
    final colors = Theme.of(context).colorScheme;

    return [
      ListTile(
        leading: Icon(
          result.holds ? Icons.check_circle_outline : Icons.error_outline,
          color: result.holds ? colors.primary : colors.error,
        ),
        title: Text(
          result.holds
              ? 'Nothing has moved'
              : '${result.moved.length} '
                    '${result.moved.length == 1 ? 'word is' : 'words are'} '
                    'somewhere else',
        ),
        subtitle: Text(
          '${result.unchanged} still where they were, '
          '${result.added.length} added, ${result.removed.length} removed',
        ),
      ),
      // The moves first and in full. Everything else on this screen is
      // bookkeeping; this is the failure the app exists to prevent, and a list
      // that made somebody scroll to find it would be reporting it quietly.
      for (final move in result.moved)
        ListTile(
          dense: true,
          title: Text(move.label),
          subtitle: Text(
            '${_path(move.was)}  became  ${_path(move.now)}',
            style: TextStyle(color: colors.error),
          ),
        ),
      if (result.added.isNotEmpty)
        ListTile(
          dense: true,
          title: const Text('Added since'),
          subtitle: Text(result.added.join(', ')),
        ),
      if (result.removed.isNotEmpty)
        ListTile(
          dense: true,
          title: const Text('Gone since'),
          subtitle: Text(result.removed.join(', ')),
        ),
    ];
  }

  static String _path(MotorPath path) =>
      '${path.boardId} ${path.row},${path.col}';

  /// Close enough to place the fingerprint in a session, which is all anybody
  /// reads this for.
  static String _when(DateTime at) {
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours} h ago';
    return '${ago.inDays} d ago';
  }
}
