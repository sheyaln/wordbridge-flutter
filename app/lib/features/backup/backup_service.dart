import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../db/database.dart';
import 'snapshot.dart';

/// A snapshot that was taken, or the reason one was not.
///
/// Both fields can be set at once: a snapshot that was written while the old
/// ones could not be cleared away is a real backup and a real problem, and a
/// caregiver screen has to be able to say so.
typedef SnapshotAttempt = ({Snapshot? snapshot, String? problem});

/// Whether the board came back, and if not, what stopped it.
///
/// [problem] is written to be read to a parent rather than logged. When a
/// restore is refused they are holding a device that is not working, and
/// "something went wrong" leaves them with nowhere to go next.
typedef RestoreAttempt = ({bool restored, String? problem});

/// Puts a board back, keeping a copy of the one it replaces.
///
/// The way every restore should be reached. A caregiver choosing between five
/// dates is choosing partly by guess — the damage they are undoing is usually
/// several days old by the time anybody works out what changed — and a wrong
/// guess would otherwise cost them everything done since. The copy is what
/// makes trying one safe, and it is also the answer to "I restored the wrong
/// one".
///
/// The snapshot being restored from is exempt from the prune. Without that, a
/// device already holding [BackupService.keep] snapshots would push the oldest
/// out to make room for the copy — and the oldest is exactly the one a
/// caregiver reaching that far back has chosen.
///
/// A copy that fails does not stop the restore. The caregiver asked for their
/// board back, and refusing to give it to them because a backup would not
/// write is the failure this whole feature exists against; it is recorded in
/// [BackupService.lastAttempt] either way.
Future<RestoreAttempt> restoreKeepingACopy(
  BackupService backup,
  Snapshot snapshot,
) async {
  await backup.takeSnapshot(doNotPrune: snapshot.path);
  return backup.restore(snapshot);
}

/// Lossless local copies of the board, and putting one back.
///
/// The failure this exists to prevent is a caregiver losing months of work —
/// custom words, chosen pictures, the locations a person has learned — to an
/// update or a device swap, and finding out that what they thought was a
/// backup was not one.
///
/// So this copies the database, not the vocabulary. The OBF/OBZ export in
/// `features/interop` is an interchange format for moving words between
/// programs, and it leaves behind the band maps, the names given to rows, the
/// usage history and every profile setting. Offering it as a backup would
/// recreate the exact failure: a caregiver who believes they are safe and is
/// not. A backup here is byte-for-byte the same database, or it is not a
/// backup.
///
/// Snapshots include the usage log, which is a record of a disabled person's
/// private speech, and they stay on the tablet it was said on.
///
/// Taking a snapshot never throws. It runs while somebody may be mid-sentence,
/// and a backup that can interrupt speech is worse than no backup at all;
/// every failure comes back as a [SnapshotAttempt.problem] a caregiver screen
/// can show, and is also kept in [lastAttempt] for the ones nobody was
/// watching.
class BackupService {
  BackupService(
    this._db, {
    Future<Directory> Function()? documentsDirectory,
    DateTime Function()? clock,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _clock = clock ?? DateTime.now;

  final WordbridgeDatabase _db;
  final Future<Directory> Function() _documentsDirectory;
  final DateTime Function() _clock;

  /// How many snapshots are kept.
  ///
  /// The damage this guards against is rarely noticed the day it happens — an
  /// update flattens a board, or a well-meaning helper rearranges one, and it
  /// is a week before anybody works out what changed. One snapshot is no use
  /// then, because the damage is already inside it. Five gives a caregiver
  /// several distinct points to step back to.
  ///
  /// Bounded because a full tablet is the same outage by a different route: a
  /// communication device that will not launch has stopped being one, and
  /// growing a backup folder without limit is a slow way to get there.
  static const keep = 5;

  /// Where snapshots live, under the application documents directory.
  ///
  /// Documents, never the cache. The OS empties caches when a device runs
  /// short of space, and it does not ask first — a backup that the system is
  /// free to delete is not a backup.
  static const folder = 'backups';

  /// The copy taken when caregiver mode opens (§4.41 part 4b).
  ///
  /// One file, overwritten each time, and deliberately not one of [keep]. A
  /// caregiver exploring what the editor can do is the case this exists for,
  /// and letting that exploration push a week-old backup out of the ring would
  /// trade the thing they might need for the thing they probably will not.
  ///
  /// Named so that [snapshotTakenAt] does not recognize it, which is what
  /// keeps it out of [snapshots] and out of the prune. It is a way back from
  /// this session, not a date in a list of dates.
  static const sessionFileName = 'wordbridge-session.db';

  /// The most recent attempt, including one nobody was waiting on.
  SnapshotAttempt? get lastAttempt => _lastAttempt;
  SnapshotAttempt? _lastAttempt;

  /// Copies the board as it stands, over any previous session copy.
  ///
  /// Never throws and never prunes. It runs while somebody may be mid-sentence
  /// — opening caregiver mode does not stop the board working — so a failure
  /// here costs the caregiver a way back and must not cost anybody a word.
  Future<SnapshotAttempt> takeSessionSnapshot() async {
    try {
      final file = File(p.join((await _directory()).path, sessionFileName));
      // Overwritten rather than kept: what it is for is the session about to
      // start, and the one from last week describes a board nobody is looking
      // at. `VACUUM INTO` refuses a file that already exists.
      if (await file.exists()) await file.delete();

      await _db.customStatement('VACUUM INTO ?', [file.path]);

      final version = await snapshotSchemaVersion(file);
      if (version == null) {
        if (await file.exists()) await file.delete();
        return (
          snapshot: null,
          problem:
              'The copy of the board could not be written completely and has '
              'been discarded. Check there is free space on this device.',
        );
      }

      return (
        snapshot: (
          path: file.path,
          takenAt: (await file.stat()).modified,
          bytes: await file.length(),
          schemaVersion: version,
        ),
        problem: null,
      );
    } catch (e) {
      return (snapshot: null, problem: 'The board could not be copied. $e');
    }
  }

  /// The session copy, or null where there is not one to go back to.
  ///
  /// Its time comes from the file rather than from its name, unlike every
  /// other snapshot. That is safe precisely because this one never leaves the
  /// device or survives being copied around: it is written and read within one
  /// sitting, on the tablet that wrote it.
  Future<Snapshot?> sessionSnapshot() async {
    try {
      final file = File(p.join((await _directory()).path, sessionFileName));
      if (!await file.exists()) return null;

      final version = await snapshotSchemaVersion(file);
      if (version == null) return null;

      return (
        path: file.path,
        takenAt: (await file.stat()).modified,
        bytes: await file.length(),
        schemaVersion: version,
      );
    } catch (_) {
      // A way back that cannot be read is not one, and the list of dates below
      // it still works.
      return null;
    }
  }

  Future<Directory> _directory() async {
    final directory = Directory(
      p.join((await _documentsDirectory()).path, folder),
    );
    await directory.create(recursive: true);
    return directory;
  }

  /// Copies the database, then prunes back to [keep].
  ///
  /// SQLite writes the copy itself rather than anything here reading the file,
  /// because the app holds the database open and the pages on disk at any
  /// instant are not guaranteed to be a database anybody can open. `VACUUM
  /// INTO` takes a read transaction and produces a consistent file, so a
  /// snapshot taken mid-sentence is still a snapshot.
  ///
  /// [doNotPrune] names a snapshot the prune must leave alone. Only one caller
  /// needs it — see [restoreKeepingACopy], where the snapshot about to be
  /// restored from would otherwise be the one this pushes over the limit.
  Future<SnapshotAttempt> takeSnapshot({String? doNotPrune}) => _write(
    (destination) => _db.customStatement('VACUUM INTO ?', [destination]),
    doNotPrune: doNotPrune,
  );

  /// Copies a database file that nothing has open yet.
  ///
  /// For the one moment the live database cannot be asked to copy itself: the
  /// launch after an update, before drift has opened the file and migrated it.
  /// The caller owns that guarantee — there is no way from here to tell whether
  /// something else holds the file, and a snapshot taken against a connection
  /// mid-write is not one.
  ///
  /// `VACUUM INTO` again rather than a plain copy, for the case that makes a
  /// backup worth having. A run killed mid-write leaves a rollback journal
  /// beside the database, and the database on its own is then a file that needs
  /// a rollback nobody copied. Opening it is the recovery, so the copy is
  /// written by a connection that has already performed it.
  Future<SnapshotAttempt> snapshotFile(File source) => _write((destination) {
    final handle = raw.sqlite3.open(source.path);
    try {
      handle.execute('VACUUM INTO ?', [destination]);
    } finally {
      handle.close();
    }
  });

  /// Names a snapshot, has [copy] write it, reads it back, and prunes.
  ///
  /// Everything except the copy itself, so that the live database and a file
  /// on disk cannot end up with two ideas of what a snapshot is called, how
  /// many are kept, or what counts as one having been written.
  ///
  /// The result is read back before it counts as written. An unreadable backup
  /// is worse than none, because it is believed.
  Future<SnapshotAttempt> _write(
    FutureOr<void> Function(String destination) copy, {
    String? doNotPrune,
  }) async {
    try {
      final directory = await _directory();
      final takenAt = _clock();
      final file = File(p.join(directory.path, snapshotFileName(takenAt)));

      if (await file.exists()) {
        return _record((
          snapshot: null,
          problem:
              'A backup from this moment already exists. Nothing was '
              'changed. Try again in a second.',
        ));
      }

      await copy(file.path);

      final version = await snapshotSchemaVersion(file);
      if (version == null) {
        // Written, but not a database anything can open, so it is deleted
        // rather than left to be found and trusted later.
        if (await file.exists()) await file.delete();
        return _record((
          snapshot: null,
          problem:
              'The backup could not be written completely and has been '
              'discarded. Check there is free space on this device.',
        ));
      }

      final snapshot = (
        path: file.path,
        takenAt: takenAt,
        bytes: await file.length(),
        schemaVersion: version,
      );

      // A prune that fails leaves a good backup behind, so it is reported
      // alongside the snapshot rather than instead of it.
      String? pruneProblem;
      try {
        await _prune(doNotPrune: doNotPrune);
      } catch (_) {
        pruneProblem =
            'The backup was saved, but older ones could not be removed. '
            'This device may be low on space.';
      }

      return _record((snapshot: snapshot, problem: pruneProblem));
    } catch (e) {
      return _record((
        snapshot: null,
        problem: 'The backup could not be saved. $e',
      ));
    }
  }

  /// What exists to restore from, newest first.
  ///
  /// Anything in the folder that is not a snapshot this wrote is left out,
  /// rather than listed and refused later. A caregiver choosing a way back
  /// should only be shown ways back that work.
  Future<List<Snapshot>> snapshots() async {
    final directory = await _directory();
    final found = <Snapshot>[];

    await for (final entry in directory.list()) {
      if (entry is! File) continue;

      final takenAt = snapshotTakenAt(entry.path);
      if (takenAt == null) continue;

      final version = await snapshotSchemaVersion(entry);
      if (version == null) continue;

      found.add((
        path: entry.path,
        takenAt: takenAt,
        bytes: await entry.length(),
        schemaVersion: version,
      ));
    }

    found.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return found;
  }

  /// Puts a snapshot back, all of it or none of it.
  ///
  /// The snapshot is attached to the connection the app is already using and
  /// the tables are copied across inside one transaction. The rejected design
  /// was to overwrite the database file and make the app relaunch: it is less
  /// code, but it hands a caregiver a device that has to be restarted before
  /// it will speak again, and it does that at the one moment they have already
  /// established something is wrong. It also has no way back — once the file
  /// is overwritten, a restore that turns out to have been the wrong choice
  /// has nothing to undo it with. Copying inside a transaction keeps the app
  /// running, and a failure anywhere in it rolls back to the board that was
  /// there before.
  ///
  /// Foreign keys are deferred for the duration rather than the copy being
  /// ordered around them. Every table is emptied before any is refilled, so
  /// there is no order in which the intermediate states are all valid; what
  /// has to be valid is the finished board, and SQLite checks exactly that at
  /// the commit. It also means a table added in a later schema version is
  /// carried across without anyone having to remember where in an order it
  /// belongs.
  ///
  /// Returns a refusal rather than throwing, for the same reason a snapshot
  /// does: this is reachable from a screen the caregiver opened while the
  /// person is still using the board.
  Future<RestoreAttempt> restore(Snapshot snapshot) async {
    final source = File(snapshot.path);
    File? upgraded;

    try {
      if (!await source.exists()) {
        return (
          restored: false,
          problem: 'That backup is no longer on this device.',
        );
      }

      final version = await snapshotSchemaVersion(source);
      if (version == null) {
        return (
          restored: false,
          problem: 'That file is not a Wordbridge AAC backup.',
        );
      }

      if (version > _db.schemaVersion) {
        return (
          restored: false,
          problem:
              'That backup was made by a newer version of Wordbridge AAC '
              '(backup $version, this app reads ${_db.schemaVersion}). '
              'Update the app and try again. Nothing has been changed.',
        );
      }

      var attach = source.path;

      if (version < _db.schemaVersion) {
        // The case this whole feature exists for: an update flattened a board
        // and the way back is a snapshot from before it. That snapshot is at
        // the older schema, so it is brought forward the same way a real
        // device is — by opening it and letting the migration run.
        //
        // On a copy, so that a snapshot stays exactly what it was and can be
        // restored again later.
        upgraded = File('${source.path}.upgrading');
        if (await upgraded.exists()) await upgraded.delete();
        await source.copy(upgraded.path);

        // `forTesting` is simply the constructor that takes an executor;
        // nothing about this is a test.
        final staged = WordbridgeDatabase.forTesting(NativeDatabase(upgraded));
        try {
          await staged.customSelect('SELECT 1').getSingle();
        } finally {
          await staged.close();
        }

        if (await snapshotSchemaVersion(upgraded) != _db.schemaVersion) {
          return (
            restored: false,
            problem:
                'That backup could not be brought up to date and has not '
                'been used. Nothing has been changed.',
          );
        }
        attach = upgraded.path;
      }

      return await _copyBack(attach);
    } catch (e) {
      return (
        restored: false,
        problem:
            'The backup could not be restored. Nothing has been '
            'changed. $e',
      );
    } finally {
      if (upgraded != null && await upgraded.exists()) {
        await upgraded.delete();
      }
    }
  }

  Future<RestoreAttempt> _copyBack(String path) async {
    const alias = 'restore_source';
    await _db.customStatement('ATTACH DATABASE ? AS $alias', [path]);

    try {
      // Checked before anything is deleted. A snapshot with a reference to a
      // location that is not there would fail at the commit anyway, but a
      // caregiver is better told the backup is damaged than handed whatever
      // SQLite says about it.
      final broken = await _db
          .customSelect('PRAGMA $alias.foreign_key_check')
          .get();
      if (broken.isNotEmpty) {
        return (
          restored: false,
          problem:
              'That backup is damaged and has not been used. Nothing has '
              'been changed.',
        );
      }

      final tables = [for (final table in _db.allTables) table.actualTableName];

      await _db.transaction(() async {
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');

        for (final table in tables) {
          await _db.customStatement('DELETE FROM main."$table"');
        }
        for (final table in tables) {
          await _db.customStatement(
            'INSERT INTO main."$table" SELECT * FROM $alias."$table"',
          );
        }
      });

      // Raw statements are invisible to the query streams the talk screen is
      // built on, so without this the board on screen would still be the one
      // that was just replaced.
      _db.markTablesUpdated(_db.allTables);

      return (restored: true, problem: null);
    } finally {
      await _db.customStatement('DETACH DATABASE $alias');
    }
  }

  Future<void> _prune({String? doNotPrune}) async {
    for (final old in (await snapshots()).skip(keep)) {
      if (old.path == doNotPrune) continue;
      await File(old.path).delete();
    }
  }

  SnapshotAttempt _record(SnapshotAttempt attempt) {
    _lastAttempt = attempt;
    return attempt;
  }
}
