import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../backup/backup_service.dart';
import '../backup/snapshot.dart';

/// The backups, where a caregiver can see them.
///
/// A backup nobody can see is one nobody trusts, and the parents in §1 did not
/// discover their backup was worthless until they needed it. So this says what
/// exists, when the last one was taken, and what restoring one would cost —
/// before it is needed, in the plainest terms available.
///
/// The list is short on purpose. Five dates is a choice somebody can make while
/// upset; twenty is a filing system.
class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key, required this.db, required this.backup});

  final WordbridgeDatabase db;
  final BackupService backup;

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  List<Snapshot>? _snapshots;

  /// The copy taken when caregiver mode opened, if there is one.
  Snapshot? _session;

  String? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the folder, and survives not being able to.
  ///
  /// A caregiver who cannot even be shown the list is in the worst position
  /// this screen has to handle, and throwing here would replace the one place
  /// that could tell them so with the fallback board.
  Future<void> _load() async {
    try {
      final found = await widget.backup.snapshots();
      final session = await widget.backup.sessionSnapshot();
      if (mounted) {
        setState(() {
          _snapshots = found;
          _session = session;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _snapshots = const [];
          _problem = 'The backups on this device could not be read. $e';
        });
      }
    }
  }

  Future<void> _backUpNow() async {
    setState(() => _busy = true);
    final attempt = await widget.backup.takeSnapshot();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = attempt.problem;
    });
    await _load();
  }

  Future<void> _restore(Snapshot snapshot) async {
    final board = await describeBoard(widget.db);
    if (!mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Go back to ${snapshotWhen(snapshot.takenAt)}?'),
        content: Text(restoreWarning(board: board, snapshot: snapshot)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Leave the board as it is'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Put this board back'),
          ),
        ],
      ),
    );
    if (go != true) return;

    setState(() => _busy = true);
    final result = await restoreKeepingACopy(widget.backup, snapshot);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = result.problem;
    });
    await _load();

    if (result.restored && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The board is back the way it was on '
            '${snapshotWhen(snapshot.takenAt)}.',
          ),
        ),
      );
    }
  }

  /// Takes back everything done since this screen's session began.
  ///
  /// What §4.42 asked for as a Save button, and better on the case actually
  /// described — exploring, changing several things, and wanting out of all of
  /// them — without re-introducing the uncommitted work §1's four parents lost.
  /// Everything is still written the moment it is done; this is a way back,
  /// not a way to defer.
  Future<void> _putItBack(Snapshot session) async {
    final board = await describeBoard(widget.db);
    if (!mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Put the board back the way you found it?'),
        content: Text(sessionRestoreWarning(board: board, session: session)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep the changes'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Put it back'),
          ),
        ],
      ),
    );
    if (go != true) return;

    setState(() => _busy = true);
    final result = await restoreKeepingACopy(widget.backup, session);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = result.problem;
    });
    await _load();

    if (result.restored && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The board is back the way you found it.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshots = _snapshots;
    final session = _session;

    return Scaffold(
      appBar: AppBar(title: const Text('Backups')),
      body: snapshots == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.history_toggle_off),
                  title: Text(lastBackedUp(snapshots)),
                  subtitle: const Text(
                    'A backup is the whole board set: every word, picture and '
                    'location, plus any usage recorded. One is taken '
                    'automatically before every update.',
                  ),
                  isThreeLine: true,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Backups are saved on this tablet, in Files under '
                    'wordbridge. Copy one to iCloud Drive or Google Drive from '
                    'there. A backup that is only on the tablet does not '
                    'survive losing the tablet.\n\n'
                    'A backup includes any usage recorded, which is a record '
                    'of one person\'s speech. Somewhere shared is somewhere '
                    'other people can read it.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _backUpNow,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Back up now'),
                  ),
                ),
                if (session != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore),
                    title: const Text('Restore to when settings were opened'),
                    subtitle: Text(
                      'Undoes every change made since '
                      '${snapshotWhen(session.takenAt)}. A copy of the board '
                      'set as it is now is saved first, so this is reversible.',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => _putItBack(session),
                  ),
                  const Divider(height: 1),
                ],
                if (_problem != null)
                  ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(_problem!),
                  ),
                const Divider(height: 1),
                if (snapshots.isEmpty)
                  const ListTile(
                    title: Text('No backups yet'),
                    subtitle: Text(
                      'One will be taken before the next update, and you can '
                      'take one now.',
                    ),
                  ),
                for (final snapshot in snapshots)
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: Text(snapshotWhen(snapshot.takenAt)),
                    subtitle: Text(snapshotSize(snapshot.bytes)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => _restore(snapshot),
                  ),
              ],
            ),
    );
  }
}

/// When a snapshot was taken, in the caregiver's own timezone.
///
/// Stored in UTC so the name sorts and survives being copied off the device;
/// shown local, because "3 Aug, 14:22" is only useful if it is the 14:22 they
/// remember.
String snapshotWhen(DateTime takenAt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final at = takenAt.toLocal();
  String pad(int v) => v.toString().padLeft(2, '0');

  return '${at.day} ${months[at.month - 1]} ${at.year}, '
      '${pad(at.hour)}:${pad(at.minute)}';
}

String snapshotSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The line at the top: the one fact this screen exists to show.
///
/// "Never backed up" is the sentence a caregiver has to be able to find, and it
/// is the reason the state is spelled out rather than left as an empty list.
String lastBackedUp(List<Snapshot> snapshots) => snapshots.isEmpty
    ? 'Never backed up'
    : 'Last backed up ${snapshotWhen(snapshots.first.takenAt)}';

/// How big the board on this device is, in the units a caregiver counts in.
///
/// Words and boards rather than rows and tables: the warning has to name what
/// is being replaced, and nobody is attached to a row count.
typedef BoardSize = ({int words, int boards});

Future<BoardSize> describeBoard(WordbridgeDatabase db) async {
  final buttons = await db.select(db.buttons).get();
  final boards = await db.select(db.boards).get();

  return (
    words: buttons.where((b) => !b.isSystem && b.deletedAt == null).length,
    boards: boards.where((b) => b.deletedAt == null).length,
  );
}

/// What putting the board back costs, said before it happens.
///
/// Deliberately shorter than [restoreWarning]. A caregiver reaching for this
/// is undoing their own last few minutes, not choosing between dates, and the
/// thing they need told is that it goes back to what they walked in on.
String sessionRestoreWarning({
  required BoardSize board,
  required Snapshot session,
}) {
  final words = board.words == 1 ? '1 word' : '${board.words} words';
  final boards = board.boards == 1 ? '1 board' : '${board.boards} boards';

  return 'The board set goes back to how it stood at '
      '${snapshotWhen(session.takenAt)}, when settings were opened. Anything '
      'added, moved or hidden since then goes with it. This board set is '
      '$words across $boards.\n\n'
      'A copy as it is now is saved first, so this is reversible.';
}

/// What a restore costs, said before it happens.
///
/// The same voice as the remap warning: name the thing being given up, in the
/// user's own terms, and let the caregiver decide. What makes this one bearable
/// is the last sentence — the board on the device is copied first, so choosing
/// the wrong date is not the end of anything.
String restoreWarning({required BoardSize board, required Snapshot snapshot}) {
  final words = board.words == 1 ? '1 word' : '${board.words} words';
  final boards = board.boards == 1 ? '1 board' : '${board.boards} boards';

  return 'The board set on this tablet, $words across $boards, will be '
      'replaced by the one from ${snapshotWhen(snapshot.takenAt)}. Anything '
      'added, moved or hidden since then goes with it.\n\n'
      'A copy of the board set as it is now is saved first, so this is '
      'reversible.';
}
