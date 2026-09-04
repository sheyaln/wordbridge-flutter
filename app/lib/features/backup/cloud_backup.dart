import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../db/database.dart';
import 'backup_service.dart';
import 'cloud_destination.dart';
import 'snapshot.dart';

/// What one attempt at a copy in the account did.
///
/// All three can be set at once, and the combination that matters is a
/// [snapshot] with a [problem]: the board was copied onto the tablet and did
/// not reach the account. That is a real backup and a real problem, and a
/// caregiver screen has to be able to say both.
typedef CloudAttempt = ({
  Snapshot? snapshot,
  CloudBackup? copy,
  String? problem,
});

/// Everything the backups screen shows about the account's copies.
///
/// [checked] is whether [lastCopiedUp] was read from the account itself or from
/// what this device remembers writing. Offline, only the second is available,
/// and a screen that presented it as the first would be claiming a file is
/// somewhere it has not looked.
///
/// [leftBehind] is the name of a place copies used to go to and no longer do.
/// It is here rather than in a dialog nobody will see twice: a family who moved
/// their backups from iCloud to Drive still has copies of a disabled person's
/// speech sitting in iCloud, and a screen that stopped mentioning them the
/// moment they stopped being listed would be hiding them.
typedef CloudView = ({
  bool answered,
  bool on,
  String label,
  CloudPlace place,
  List<CloudPlace> places,
  String? leftBehind,
  bool reachable,
  DateTime? lastCopiedUp,
  bool checked,
  List<CloudBackup> backups,
  String? problem,
});

/// Whether copies go to the account, and what the last attempt did.
///
/// Device-scoped, in `app_state` beside the caregiver gesture and the device
/// id, and deliberately not a per-profile setting: one snapshot is the whole
/// database, so it holds every profile on the tablet. A per-profile switch
/// would let one person's yes carry another person's usage log — a record of
/// their private speech — into an account they were never asked about.
///
/// [answer] is nullable because "never asked" and "no" have to stay different
/// answers. A tablet set up before this existed must not start uploading
/// because an update shipped a default.
class CloudBackupStore {
  const CloudBackupStore(this._db);

  final WordbridgeDatabase _db;

  static const answerKey = 'cloudBackup';
  static const lastCopiedUpKey = 'cloudBackupAt';
  static const problemKey = 'cloudBackupProblem';
  static const leftBehindKey = 'cloudBackupLeftIn';

  /// What a device set up from here is offered, with the answer preselected.
  ///
  /// Named so setup and this store cannot drift into disagreeing about what is
  /// being encouraged. It is a preselected answer on a screen, never a value
  /// this store returns on its own — see [answer].
  static const offeredAtSetup = true;

  Future<String?> _value(String key) async {
    final row = await (_db.select(
      _db.appState,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) => _db
      .into(_db.appState)
      .insertOnConflictUpdate(AppStateCompanion.insert(key: key, value: value));

  Future<void> _clear(String key) =>
      (_db.delete(_db.appState)..where((s) => s.key.equals(key))).go();

  /// Yes, no, or nobody has been asked.
  Future<bool?> answer() async => switch (await _value(answerKey)) {
    'yes' => true,
    'no' => false,
    _ => null,
  };

  Future<void> setAnswer(bool on) => _write(answerKey, on ? 'yes' : 'no');

  /// When this device last put a copy in the account, as it remembers it.
  ///
  /// Kept locally so the backups screen has a date to show on a tablet that
  /// cannot reach the account. Nothing decides anything from it except whether
  /// a daily copy is due.
  Future<DateTime?> lastCopiedUp() async {
    final stored = int.tryParse(await _value(lastCopiedUpKey) ?? '');
    return stored == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);
  }

  /// Why the last attempt failed, or null where it did not.
  ///
  /// Stored rather than held in memory because most attempts happen at launch
  /// with nobody watching. A backup that silently stopped working three weeks
  /// ago is the failure this whole feature exists against, so the sentence
  /// survives until an attempt succeeds.
  Future<String?> lastProblem() => _value(problemKey);

  Future<void> recordCopiedUp(DateTime at) async {
    await _write(lastCopiedUpKey, '${at.toUtc().millisecondsSinceEpoch}');
    await _clear(problemKey);
  }

  Future<void> recordProblem(String problem) => _write(problemKey, problem);

  /// What the place copies used to go to was called, while anything was left
  /// there.
  ///
  /// A name rather than a [CloudPlace], because the only thing done with it is
  /// reading it out to somebody. Two providers a caregiver reads the same name
  /// for are the same place as far as that sentence goes, and the enum would
  /// need the name carried beside it anyway.
  Future<String?> leftBehind() => _value(leftBehindKey);

  Future<void> rememberLeftBehind(String? label) =>
      label == null ? _clear(leftBehindKey) : _write(leftBehindKey, label);

  /// Forgets that this device ever copied anything up.
  ///
  /// For the moment the copies themselves are removed: a "last backed up"
  /// date left behind after that would point at a file that is no longer
  /// anywhere, which is the exact species of lie this feature exists to stop
  /// telling.
  Future<void> forget() async {
    await _clear(lastCopiedUpKey);
    await _clear(problemKey);
  }
}

/// Copies of the board in the account signed in on this tablet.
///
/// A destination for the artifact [BackupService] already produces, and not a
/// second kind of backup: the same byte-for-byte database file, named the same
/// way, restored through the same code that keeps a copy of what it replaces.
/// A cloud backup that were its own format would be a second thing to get
/// wrong on the one day it is needed.
///
/// The account belongs to the family. Nothing here reaches a server of ours,
/// and there is no account of ours for it to reach — see [CloudDestination].
///
/// Nothing here throws. It runs at launch, unattended, while somebody may be
/// about to speak; every failure comes back as a [CloudAttempt.problem] and is
/// written down in [CloudBackupStore] so that a screen opened three weeks later
/// still says the copies stopped.
class CloudBackupService {
  CloudBackupService({
    required this.backup,
    required this.store,
    required this.destination,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The local snapshots this mirrors. Every cloud copy is one of these files,
  /// unchanged.
  final BackupService backup;

  final CloudBackupStore store;
  final CloudDestination destination;
  final DateTime Function() _clock;

  /// How long a copy in the account is allowed to go stale before a launch
  /// takes a new one.
  ///
  /// Twenty hours rather than twenty-four so that a tablet switched on at
  /// roughly the same time each morning is not skipped by a few minutes'
  /// drift, which would turn a daily backup into an every-other-day one
  /// without anything appearing to be wrong.
  static const between = Duration(hours: 20);

  String get label => destination.label;

  Future<bool> get on async => await store.answer() == true;

  /// Says yes, and asks the platform for whatever it needs.
  ///
  /// Where copies go to a folder that is a picker, and the picker is the reason
  /// this is a deliberate act on a screen rather than something a launch does.
  /// A refusal is written down rather than thrown: the answer is stored either
  /// way, so a caregiver who dismissed the picker finds the reason on the
  /// screen they are already looking at instead of a switch that silently
  /// went back off.
  Future<void> turnOn() async {
    await store.setAnswer(true);

    try {
      if ((await destination.status()).reachable) return;
      final connected = await destination.connect();
      if (!connected.reachable && connected.problem != null) {
        await store.recordProblem(connected.problem!);
      }
    } catch (_) {
      // The switch is on and the next copy will report for itself. Nothing
      // here is worth failing the act of saying yes.
    }
  }

  /// Stops copies going up. Nothing already in the account is touched.
  ///
  /// Deleting what is there would be the wrong reading of "stop backing up":
  /// the copies are the family's, in the family's account, and one of them may
  /// be the only surviving board. Removing them is a separate, named act —
  /// [forget].
  Future<void> turnOff() => store.setAnswer(false);

  /// Sends copies somewhere else from now on, and says what that costs.
  ///
  /// [pick] opens the folder picker even where a folder is already held, which
  /// is both "use a different one" and the way back from one that has gone.
  ///
  /// **What is already in the old place stays in the old place.** Moving it
  /// would mean fetching every copy down and pushing it back up over whatever
  /// connection the tablet has, and a move that failed halfway would leave a
  /// family with their board in neither place. Deleting it would be the same
  /// misreading of "somewhere else" that [turnOff] refuses: those copies are
  /// the family's, and one of them may be the only surviving board. So they
  /// stay — and because a copy of somebody's speech left quietly in an account
  /// nobody is looking at any more is the thing this feature must not create,
  /// the name of the old place is written down and the screen keeps saying it
  /// until the copies go or the place is chosen again.
  ///
  /// The mirror runs immediately afterwards, so a tablet is not left with the
  /// old place no longer being written to and the new one still empty.
  Future<CloudAttempt> sendTo(CloudPlace place, {bool pick = false}) async {
    // So that what is compared afterwards is where the platform says copies go
    // now, not where it said they went when the screen was opened.
    await destination.status();

    final wasIn = destination.place;
    final wasCalled = destination.label;
    final leaving = await _holdsAnything() ? wasCalled : null;

    final moved = await destination.use(place, pick: pick);

    // A re-pick lands on the same place under the same name and is still a
    // move. Anything else moved only if the platform says it did: a picker
    // somebody dismissed changes nothing, and treating it as a move would
    // throw away a date that is still true.
    final changed = pick
        ? moved.reachable
        : destination.place != wasIn || destination.label != wasCalled;

    if (!changed) {
      if (moved.problem != null) await store.recordProblem(moved.problem!);
      return (snapshot: null, copy: null, problem: moved.problem);
    }

    // Both described the old place. A date carried forward would claim a copy
    // sits somewhere nothing has ever written to, and a failure carried forward
    // would be reported against a place that never had it.
    await store.forget();
    await store.rememberLeftBehind(
      leaving != null && leaving != destination.label ? leaving : null,
    );

    final mirrored = await _mirror();
    return (
      snapshot: null,
      copy: mirrored.copy,
      problem: mirrored.problem ?? moved.problem,
    );
  }

  /// Whether the place copies go to now holds any of ours.
  ///
  /// Asked only to decide whether somebody is about to leave copies behind, so
  /// a folder that cannot be read falls back to whether this device remembers
  /// ever sending anything. Over-warning costs a sentence; under-warning leaves
  /// a record of a disabled person's speech in an account nobody is watching.
  Future<bool> _holdsAnything() async {
    try {
      return (await destination.list()).isNotEmpty;
    } catch (_) {
      return await store.lastCopiedUp() != null;
    }
  }

  /// Takes a snapshot and copies it up, because somebody pressed a button.
  ///
  /// The snapshot is taken whether or not the account can be reached. A
  /// caregiver pressing this wants a backup; refusing them the one that always
  /// works because the other one is offline would be an odd way to protect
  /// their board.
  Future<CloudAttempt> backUpNow() async {
    final attempt = await backup.takeSnapshot();
    if (attempt.snapshot == null) {
      return (snapshot: null, copy: null, problem: attempt.problem);
    }

    final mirrored = await _mirror();
    return (
      snapshot: attempt.snapshot,
      copy: mirrored.copy,
      // A prune that failed locally still matters, and is not overwritten by
      // an upload that worked.
      problem: mirrored.problem ?? attempt.problem,
    );
  }

  /// The unattended copy: called at launch and from nowhere a person is
  /// waiting.
  ///
  /// Returns null when there was nothing to do, which is the answer on most
  /// launches and is not a failure. Takes a fresh snapshot only when the
  /// newest one on the device has gone stale, so the local ring of
  /// [BackupService.keep] stays a set of distinct points to step back to
  /// rather than the last five days.
  Future<CloudAttempt?> keepUpToDate() async {
    if (!await on) return null;

    try {
      Snapshot? taken;
      String? refused;
      if (await _stale()) {
        final attempt = await backup.takeSnapshot();
        taken = attempt.snapshot;
        refused = attempt.problem;
      }

      final mirrored = await _mirror();

      // Written down after the mirror rather than before it. A successful
      // upload clears the stored problem, and a tablet that could not write
      // its own backup still has one worth keeping — the copies in the account
      // being fine says nothing about the device somebody is holding.
      if (refused != null) await store.recordProblem(refused);

      final problem = refused ?? mirrored.problem;
      if (taken == null && mirrored.copy == null && problem == null) {
        return null;
      }
      return (snapshot: taken, copy: mirrored.copy, problem: problem);
    } catch (_) {
      return _fail(didNotArrive(destination.label));
    }
  }

  /// Whether the newest snapshot on the device is older than [between].
  Future<bool> _stale() async {
    try {
      final newest = (await backup.snapshots()).firstOrNull;
      if (newest == null) return true;
      return _clock().toUtc().difference(newest.takenAt.toUtc()) >= between;
    } catch (_) {
      // A folder that cannot be read is not a reason to write another file
      // into it. [_mirror] reports the same failure with a sentence in it.
      return false;
    }
  }

  /// Puts every local snapshot the account lacks into it, newest first.
  ///
  /// The account mirrors the device rather than accumulating: what a caregiver
  /// restores from should be the same short list of dates in both places, and
  /// an account that kept everything forever would eventually be a list of
  /// twenty dates nobody can choose between.
  ///
  /// Nothing is deleted from the account because the device no longer has it.
  /// A replacement tablet has no local snapshots at all, and the copies in the
  /// account are the only board left; a mirror that ran in that direction
  /// would delete them on first launch.
  Future<CloudAttempt> _mirror() async {
    if (!await on) return (snapshot: null, copy: null, problem: null);

    try {
      final local = await backup.snapshots();
      final remote = await destination.list();
      final alreadyUp = {for (final up in remote) up.name};

      CloudBackup? newest;
      for (final snapshot in local.take(BackupService.keep)) {
        final name = p.basename(snapshot.path);
        if (alreadyUp.contains(name)) continue;

        final copy = await destination.upload(File(snapshot.path), name);
        // Newest first, so the first one written is the one the screen reports
        // as the last backup. Every other missing one still goes up: switching
        // this on is meant to put what the device already has into the
        // account, not to start the history over from today.
        newest ??= copy;
      }

      await _prune();

      if (newest != null) await store.recordCopiedUp(_clock());
      return (snapshot: null, copy: newest, problem: null);
    } on CloudRefusal catch (e) {
      return _fail(e.message);
    } catch (_) {
      return _fail(didNotArrive(destination.label));
    }
  }

  /// Trims the account back to [BackupService.keep], oldest first.
  ///
  /// A failure here is swallowed rather than reported. The copies are up,
  /// which is what was asked for, and telling a caregiver their backup failed
  /// because an old one would not delete would send them looking for a problem
  /// that is not theirs.
  Future<void> _prune() async {
    try {
      for (final old in (await destination.list()).skip(BackupService.keep)) {
        await destination.delete(old);
      }
    } catch (_) {
      // Left where it is. The copies that matter are up.
    }
  }

  Future<CloudAttempt> _fail(String problem) async {
    try {
      await store.recordProblem(problem);
    } catch (_) {
      // The board is what matters, not the note about the board.
    }
    return (snapshot: null, copy: null, problem: problem);
  }

  /// What the account holds, or an empty list where it cannot be asked.
  Future<List<CloudBackup>> list() async {
    try {
      return await destination.list();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches one back and puts it on the board, keeping a copy of what it
  /// replaces.
  ///
  /// The downloaded file is left in the backups folder afterwards, on purpose.
  /// A tablet that has just been restored from the account then holds that
  /// snapshot locally, and the next thing to go wrong does not need a network
  /// or an account to be undone.
  ///
  /// It is read all the way through before it is used. A connection that drops
  /// mid-download leaves a file whose first 64 bytes are a perfectly good
  /// SQLite header, so [snapshotSchemaVersion] recognizes it and every listing
  /// afterwards offers it as a way back — an unreadable backup that is
  /// believed, which is the one outcome worse than no backup at all.
  ///
  /// Checked by opening it rather than by comparing its length against the size
  /// the account reported. Those two numbers are not the same thing: iCloud
  /// reports a displayable size that can include metadata, and a file it has
  /// evicted from this device reports differently again, so a length
  /// comparison would refuse valid restores on the platform that needs them
  /// most.
  Future<RestoreAttempt> restore(CloudBackup copy) async {
    File? fetched;
    try {
      final into = await backup.fileFor(copy.name);
      fetched = into;
      await destination.download(copy, into);

      final version = await snapshotSchemaVersion(into);
      if (version == null || !_wholeDatabase(into)) {
        if (await into.exists()) await into.delete();
        return (
          restored: false,
          problem:
              'That backup did not come down from ${destination.label} in '
              'one piece and has been discarded. Nothing has been changed. '
              'Try again when this device has a better connection.',
        );
      }

      return await restoreKeepingACopy(backup, (
        path: into.path,
        takenAt: copy.takenAt,
        bytes: await into.length(),
        schemaVersion: version,
      ));
    } on CloudRefusal catch (e) {
      await _discard(fetched);
      return (restored: false, problem: e.message);
    } catch (e) {
      await _discard(fetched);
      return (
        restored: false,
        problem:
            'That backup could not be fetched from ${destination.label}. '
            'Nothing has been changed. $e',
      );
    }
  }

  /// Whether SQLite can read every page of the file, not just its header.
  ///
  /// `quick_check` is what tells a whole database from the first third of one.
  /// Read-only, so a file that turns out to be damaged is not written to on the
  /// way to finding out.
  bool _wholeDatabase(File file) {
    try {
      final handle = raw.sqlite3.open(file.path, mode: raw.OpenMode.readOnly);
      try {
        final rows = handle.select('PRAGMA quick_check');
        return rows.length == 1 && rows.first.values.first == 'ok';
      } finally {
        handle.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _discard(File? partial) async {
    try {
      if (partial != null && await partial.exists()) await partial.delete();
    } catch (_) {
      // A half-written file left behind is not a database, so nothing will
      // offer it as a way back. The refusal being reported matters more.
    }
  }

  /// Removes every copy from the account.
  ///
  /// The answer to "take my child's speech back out of iCloud", and the reason
  /// [turnOff] does not do it silently. What is on the tablet is untouched.
  Future<String?> forget() async {
    try {
      for (final copy in await destination.list()) {
        await destination.delete(copy);
      }
      await store.forget();
      await store.setAnswer(false);
      return null;
    } on CloudRefusal catch (e) {
      return e.message;
    } catch (_) {
      return 'The copies in ${destination.label} could not all be removed. '
          'Nothing on this device has changed.';
    }
  }

  /// Everything the backups screen needs, in one read.
  ///
  /// The account is looked at while the copies are switched off too, as long as
  /// this device remembers making some. [turnOff] leaves them where they are on
  /// purpose, and a caregiver who then decides they want them gone has to be
  /// able to reach them — a screen that hid them behind the switch would leave
  /// a family's only route to deleting them being to switch the copies back on.
  ///
  /// A device that never sent anything looks at nothing, which is what keeps a
  /// tablet that said no from touching an account on every screen open.
  Future<CloudView> view() async {
    final answer = await store.answer();
    final remembered = await store.lastCopiedUp();
    final stored = await store.lastProblem();
    final left = await store.leftBehind();
    final on = answer == true;

    if (!on && remembered == null) {
      return (
        answered: answer != null,
        on: false,
        label: destination.label,
        place: destination.place,
        places: destination.places,
        leftBehind: left == destination.label ? null : left,
        reachable: false,
        lastCopiedUp: null,
        checked: false,
        backups: const <CloudBackup>[],
        problem: null,
      );
    }

    final status = await destination.status();
    final backups = status.reachable ? await list() : const <CloudBackup>[];

    return (
      answered: answer != null,
      on: on,
      label: destination.label,
      place: destination.place,
      places: destination.places,
      // Dropped once copies are going back to the place they were left in:
      // they are listed again from there, and a line saying they are somewhere
      // else would be pointing at the screen it is on.
      leftBehind: left == destination.label ? null : left,
      reachable: status.reachable,
      // The account's own answer where there is one, because a date this
      // device remembers writing says nothing about a file somebody has since
      // deleted from their iCloud.
      lastCopiedUp: status.reachable
          ? backups.firstOrNull?.takenAt
          : remembered,
      checked: status.reachable,
      backups: backups,
      // Only while it is on. A switch somebody turned off is not a state to
      // keep reporting a failure about.
      problem: on ? (status.problem ?? stored) : null,
    );
  }
}
