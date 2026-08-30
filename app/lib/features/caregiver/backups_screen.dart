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
      if (mounted) setState(() => _snapshots = found);
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

  @override
  Widget build(BuildContext context) {
    final snapshots = _snapshots;

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
                    'A backup is the whole board — every word, every picture, '
                    'every location, and what has been used. It is taken '
                    'automatically before an update, and stays on this device. '
                    'Nothing is sent anywhere.',
                  ),
                  isThreeLine: true,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _backUpNow,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Back up now'),
                  ),
                ),
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

/// What a restore costs, said before it happens.
///
/// The same voice as the remap warning: name the thing being given up, in the
/// user's own terms, and let the caregiver decide. What makes this one bearable
/// is the last sentence — the board on the device is copied first, so choosing
/// the wrong date is not the end of anything.
String restoreWarning({required BoardSize board, required Snapshot snapshot}) {
  final words = board.words == 1 ? '1 word' : '${board.words} words';
  final boards = board.boards == 1 ? '1 board' : '${board.boards} boards';

  return 'The board on this device — $words across $boards — will be replaced '
      'by the one from ${snapshotWhen(snapshot.takenAt)}. Anything added, '
      'moved or hidden since then goes with it.\n\n'
      'A copy of the board as it is right now is saved first, so you can come '
      'back to it.';
}
