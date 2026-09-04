import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../backup/backup_service.dart';
import '../backup/cloud_backup.dart';
import '../backup/cloud_destination.dart';
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
  const BackupsScreen({
    super.key,
    required this.db,
    required this.backup,
    this.cloud,
  });

  final WordbridgeDatabase db;
  final BackupService backup;

  /// The copies in the family's own account, where a build has somewhere to
  /// put them. Absent, the screen is what it was: backups on this device only.
  final CloudBackupService? cloud;

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  List<Snapshot>? _snapshots;

  /// The copy taken when caregiver mode opened, if there is one.
  Snapshot? _session;

  /// What the account holds, read fresh each time this screen loads.
  CloudView? _cloud;

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

    // Separately, and after. Reaching an account can be slow and can fail, and
    // neither may cost a caregiver the list of dates on the tablet in front of
    // them — that list is the one that always works.
    await _loadCloud();
  }

  Future<void> _loadCloud() async {
    final cloud = widget.cloud;
    if (cloud == null) return;

    try {
      final view = await cloud.view();
      if (mounted) setState(() => _cloud = view);
    } catch (_) {
      // The section renders from the last thing it knew, or not at all. There
      // is nothing here a caregiver could do with the failure of a lookup.
    }
  }

  Future<void> _backUpNow() async {
    setState(() => _busy = true);

    // One button, one meaning. With the account switched on it copies up as
    // well; two buttons would be two ideas of what "back up now" did, and a
    // caregiver pressing the wrong one would believe they had a copy off the
    // tablet when they did not.
    final cloud = widget.cloud;
    final problem = cloud != null && await cloud.on
        ? (await cloud.backUpNow()).problem
        : (await widget.backup.takeSnapshot()).problem;

    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
    await _load();
  }

  Future<void> _setCloud(bool on) async {
    final cloud = widget.cloud;
    if (cloud == null) return;

    setState(() => _busy = true);
    if (on) {
      await cloud.turnOn();
    } else {
      await cloud.turnOff();
    }
    // Immediately, rather than at the next launch. Somebody who has just
    // switched this on is watching for it to have done something.
    if (on) await cloud.keepUpToDate();

    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  /// Sends copies somewhere else, once whoever asked knows what it leaves.
  Future<void> _sendTo(CloudPlace place, {bool pick = false}) async {
    final cloud = widget.cloud;
    final view = _cloud;
    if (cloud == null || view == null) return;

    if (!await _agreeToLeave(view, place, pick: pick)) return;

    setState(() => _busy = true);
    final attempt = await cloud.sendTo(place, pick: pick);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = attempt.problem;
    });
    await _load();
  }

  /// Asks before copies stop going where they have been going.
  ///
  /// Not asked where there is nothing to leave behind. A confirmation about
  /// nothing is what teaches somebody to dismiss the one that is about a
  /// record of their child's speech sitting in an account they are about to
  /// stop looking at.
  Future<bool> _agreeToLeave(
    CloudView view,
    CloudPlace place, {
    required bool pick,
  }) async {
    if (view.backups.isEmpty && view.lastCopiedUp == null) return true;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Send backups to '
          '${pick ? 'a different folder' : cloudPlaceTitle(view, place)} '
          'instead?',
        ),
        content: Text(leavingWarning(view)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep using ${view.label}'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change where they go'),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _restoreFromCloud(CloudBackup copy, String label) async {
    final board = await describeBoard(widget.db);
    if (!mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Use the copy from ${snapshotWhen(copy.takenAt)}?'),
        content: Text(
          cloudRestoreWarning(board: board, copy: copy, label: label),
        ),
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
    final result = await widget.cloud!.restore(copy);
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
            '${snapshotWhen(copy.takenAt)}.',
          ),
        ),
      );
    }
  }

  Future<void> _forgetCloud(String label) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove every copy from $label?'),
        content: Text(
          'Every backup this tablet put in $label is deleted from the '
          'account, including the usage recorded in each one. The board on '
          'this device and the backups on this device are untouched.\n\n'
          'There is no way to undo this from here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete them'),
          ),
        ],
      ),
    );
    if (go != true) return;

    setState(() => _busy = true);
    final problem = await widget.cloud!.forget();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
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
    final cloud = _cloud;

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
                    'automatically when an update changes how the board is '
                    'stored.',
                  ),
                  isThreeLine: true,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Backups are saved in Files under Wordbridge AAC. A '
                    'backup only on the device does not survive losing the '
                    'device.\n\n'
                    'A backup includes any usage recorded, which is one '
                    'person\'s speech. Any copy of it carries that too.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                if (cloud != null)
                  _CloudSection(
                    view: cloud,
                    busy: _busy,
                    onChanged: _setCloud,
                    onPlace: _sendTo,
                    onPick: () => _sendTo(CloudPlace.folder, pick: true),
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
                      '${snapshotWhen(session.takenAt)}. A copy as it is now '
                      'is saved first, so this is reversible.',
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
                      'Use Back up now, above. One is also taken when an '
                      'update changes how the board is stored.',
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

                // Listed separately rather than merged with the dates above.
                // The two lists usually hold the same dates, and the one that
                // matters is the one that is somewhere else — a caregiver
                // holding a replacement tablet needs to see that these are
                // reachable from a device that has never held the board.
                if (cloud != null &&
                    cloud.reachable &&
                    (cloud.on || cloud.backups.isNotEmpty)) ...[
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(
                      'In ${cloud.label}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      cloud.backups.isEmpty
                          ? 'Nothing has been copied up yet.'
                          : 'Restoring one of these fetches it back onto this '
                                'tablet first. A copy of the board as it is '
                                'now is saved before it is replaced.',
                    ),
                  ),
                  for (final copy in cloud.backups)
                    ListTile(
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: Text(snapshotWhen(copy.takenAt)),
                      subtitle: Text(snapshotSize(copy.bytes)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => _restoreFromCloud(copy, cloud.label),
                    ),
                  if (cloud.backups.isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text('Remove every copy from ${cloud.label}'),
                      subtitle: Text(
                        'Deletes them from the account. The board and the '
                        'backups on this device are untouched.',
                      ),
                      isThreeLine: true,
                      onTap: _busy ? null : () => _forgetCloud(cloud.label),
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}

/// Whether a copy of the board goes to the family's own account, and what the
/// last attempt did.
///
/// Says where a copy goes and who can read it, in the same breath as offering
/// it. A backup that quietly starts sending a disabled person's speech
/// somewhere is not a feature anybody consented to, and a switch whose
/// destination is only explained in a policy is a switch nobody read.
class _CloudSection extends StatelessWidget {
  const _CloudSection({
    required this.view,
    required this.busy,
    required this.onChanged,
    required this.onPlace,
    required this.onPick,
  });

  final CloudView view;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final ValueChanged<CloudPlace> onPlace;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chooseable =
        view.on && (view.places.length > 1 || view.place == CloudPlace.folder);

    return Column(
      children: [
        SwitchListTile(
          value: view.on,
          isThreeLine: true,
          secondary: Icon(view.on ? Icons.cloud_done : Icons.cloud_off),
          title: Text('Keep a copy in ${view.label}'),
          // Two sentences rather than one with the name dropped into it. A
          // folder is not an account somebody signed in to, and before one is
          // chosen there is no name to put in the sentence at all.
          subtitle: Text(
            view.place == CloudPlace.folder
                ? 'Copies go to a folder you choose, in whichever account you '
                      'chose it from. They stay there: we never receive them '
                      'and cannot read them.'
                : 'Copies go to the ${view.label} account already signed in '
                      'on this tablet. They stay in that account: we never '
                      'receive them and cannot read them.',
          ),
          onChanged: busy ? null : onChanged,
        ),
        if (view.on)
          ListTile(
            dense: true,
            leading: const Icon(Icons.schedule),
            title: Text(lastCopiedUp(view)),
            subtitle: Text(
              view.reachable
                  ? 'A copy goes up when the app opens, at most once a day, '
                        'and whenever an update changes how the board is '
                        'stored.'
                  : 'This is what this tablet remembers sending. It could not '
                        'reach ${view.label} to check just now.',
            ),
          ),
        if (view.problem != null)
          ListTile(
            leading: Icon(Icons.error_outline, color: colors.error),
            title: Text(view.problem!),
          ),
        if (chooseable) ...[
          const ListTile(
            dense: true,
            title: Text(
              'Where the copies go',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (view.places.length > 1)
            for (final place in view.places)
              ListTile(
                leading: Icon(
                  place == view.place
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(cloudPlaceTitle(view, place)),
                subtitle: Text(cloudPlaceNote(place)),
                isThreeLine: true,
                onTap: busy || place == view.place
                    ? null
                    : () => onPlace(place),
              ),
          // Offered wherever copies go to a folder, including where that is
          // the only place this device has. It is both "use a different one"
          // and the only way back from a folder the tablet has lost, and
          // without it that recovery is switching the whole feature off and
          // on again.
          if (view.place == CloudPlace.folder)
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Choose a different folder'),
              subtitle: const Text(
                'Opens the picker again — to move to another provider, or to '
                'point this tablet back at a folder it can no longer reach.',
              ),
              isThreeLine: true,
              onTap: busy ? null : onPick,
            ),
        ],
        if (view.leftBehind != null)
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('Older copies are still in ${view.leftBehind}'),
            subtitle: Text(
              'They stopped being added to when backups moved to '
              '${view.label}, and are not listed here any more. Delete them '
              'in ${view.leftBehind} itself, or switch back to it here and '
              'use "Remove every copy".',
            ),
            isThreeLine: true,
          ),
      ],
    );
  }
}

/// What to call one of the places on the chooser.
///
/// The place copies go to now names itself, because the platform reports the
/// provider: a caregiver reads "Google Drive" rather than the name of a folder
/// they chose eight months ago. The other one is named by what choosing it
/// would do, there being nothing there yet to name.
String cloudPlaceTitle(CloudView view, CloudPlace place) {
  if (place == view.place && view.label != unpickedFolder) return view.label;
  return place == CloudPlace.account
      ? cloudLabel(CloudPlace.account)
      : 'A folder you choose';
}

/// What choosing one of them gets, in the terms the choice is made in.
///
/// Neither is better. The container needs nobody to pick anything and comes
/// back after the app is reinstalled; the folder reaches the account the
/// family already keeps everything else in. Which of those matters is not
/// something this app knows.
String cloudPlaceNote(CloudPlace place) => switch (place) {
  CloudPlace.account =>
    'Wordbridge\'s own folder in the ${cloudLabel()} account already signed '
        'in on this tablet. Nothing to choose, and it is still there after '
        'the app is reinstalled.',
  CloudPlace.folder =>
    'Any folder this tablet can reach: Google Drive, Dropbox, OneDrive, or '
        'the tablet\'s own storage. You choose it once, and copies go there '
        'by themselves after that.',
};

/// What changing where the copies go costs, said before it happens.
///
/// The copies already made are not moved and not deleted — see
/// [CloudBackupService.sendTo] — so this has to name them, say they are staying
/// where they are, and say how to get rid of them. A family moving their
/// backups to Drive would otherwise leave a record of a disabled person's
/// speech in an iCloud account they have stopped looking at.
String leavingWarning(CloudView view) {
  final copies = switch (view.backups.length) {
    0 => 'Any copies already in ${view.label} stay',
    1 => 'The one copy already in ${view.label} stays',
    final many => 'The $many copies already in ${view.label} stay',
  };

  return '$copies where they are. Wordbridge stops adding to them and '
      'stops listing them here.\n\n'
      'To get rid of them: delete them in ${view.label} itself, or come back '
      'here, switch to ${view.label} again and use "Remove every copy".\n\n'
      'The backups on this tablet are copied to the new place straight away.';
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
/// A caregiver reaching for this is undoing their own last few minutes rather
/// than choosing between dates, so the point it makes is that the board goes
/// back to what they walked in on.
String sessionRestoreWarning({
  required BoardSize board,
  required Snapshot session,
}) {
  final words = board.words == 1 ? '1 word' : '${board.words} words';
  final boards = board.boards == 1 ? '1 board' : '${board.boards} boards';

  return 'The board set, $words across $boards, goes back to how it stood at '
      '${snapshotWhen(session.takenAt)}, when settings were opened. Anything '
      'added, moved or hidden since then goes with it.\n\n'
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

  return 'The board set on this device, $words across $boards, will be '
      'replaced by the one from ${snapshotWhen(snapshot.takenAt)}. Anything '
      'added, moved or hidden since then goes with it.\n\n'
      'A copy as it is now is saved first, so this is reversible.';
}

/// The one fact the cloud row exists to show, said in full sentences.
///
/// "Never copied up" has to be findable, for the same reason [lastBackedUp]
/// spells out an empty list: the failure being guarded against is a family who
/// believed a backup existed. A date that came from the account itself and one
/// this tablet merely remembers writing are different claims, and the second
/// says so.
String lastCopiedUp(CloudView view) {
  final at = view.lastCopiedUp;
  if (at == null) return 'Nothing copied to ${view.label} yet';

  final when = snapshotWhen(at);
  return view.checked
      ? 'Last copied to ${view.label} $when'
      : 'Last copied to ${view.label} $when, as far as this tablet knows';
}

/// What restoring from the account costs, said before it happens.
///
/// The same shape as [restoreWarning], and it names the account, because the
/// copy being reached for may have been made on a different tablet — the case
/// this whole feature exists for is the one where the old tablet is gone.
String cloudRestoreWarning({
  required BoardSize board,
  required CloudBackup copy,
  required String label,
}) {
  final words = board.words == 1 ? '1 word' : '${board.words} words';
  final boards = board.boards == 1 ? '1 board' : '${board.boards} boards';

  return 'The board set on this device, $words across $boards, will be '
      'replaced by the copy in $label from ${snapshotWhen(copy.takenAt)}. '
      'Anything added, moved or hidden since then goes with it.\n\n'
      'A copy as it is now is saved on this device first, so this is '
      'reversible.';
}
