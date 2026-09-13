/// Putting a board back without opening the database.
///
/// Everything else in this folder works through the live connection, which is
/// right while there is one: a restore that copies table by table inside a
/// transaction keeps the app running and rolls back cleanly. It is also
/// unavailable in the one case that strands a nonspeaking person — the
/// database file will not open at all, so there is no connection to copy
/// through, no profile to read and no PIN to check.
///
/// So this works on files. It reads the backups folder with the header reader
/// in `snapshot.dart`, swaps a chosen copy into the place drift looks, and
/// keeps whatever was there. Nothing here opens a database, and nothing here
/// throws: every failure comes back as a sentence a frightened caregiver can
/// read.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'snapshot.dart';

/// One way back, and whether this build can take it.
///
/// A copy made by a newer build is listed rather than hidden. It is the
/// evidence that the board still exists, which is the first thing a caregiver
/// holding a tablet that will not talk needs to know, and hiding it would say
/// the opposite.
typedef RecoveryOption = ({Snapshot snapshot, bool usable, String? refusal});

/// What the recovery screen has to offer, or why it has nothing.
typedef RecoveryOptions = ({List<RecoveryOption> options, String? problem});

/// Whether the repair happened, and if not, what stopped it.
typedef RecoveryResult = ({bool done, String? problem});

/// The board that was set aside, named after the moment it was set aside.
///
/// Deliberately not a name [snapshotTakenAt] accepts: it is not a way back,
/// and it must not appear in a list of dates or be reached by the prune.
const _asidePrefix = 'wordbridge-unopened-';

/// The way back for a device whose database cannot be opened.
class BoardRecovery {
  /// Takes where the board sits, and which schema this build reads.
  ///
  /// Both passed in rather than reached for, because `db/database.dart` is
  /// what has failed by the time anything here is called and nothing on the
  /// crash board's path may import it.
  BoardRecovery(
    this._database, {
    required this.appSchemaVersion,
    Future<Directory> Function()? documentsDirectory,
    DateTime Function()? clock,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _clock = clock ?? DateTime.now;

  final int appSchemaVersion;

  final Future<File> Function() _database;
  final Future<Directory> Function() _documentsDirectory;
  final DateTime Function() _clock;

  /// What is on this tablet to go back to, newest first.
  ///
  /// The copy taken when caregiver mode last opened is listed beside the dated
  /// ones. It is kept out of the caregiver's list of dates because there it is
  /// a way back from one sitting; here, any openable board beats fourteen
  /// words.
  Future<RecoveryOptions> options() async {
    try {
      final directory = await _folder(create: false);
      if (!await directory.exists()) {
        return (options: const <RecoveryOption>[], problem: null);
      }

      final found = <Snapshot>[];
      await for (final entry in directory.list()) {
        if (entry is! File) continue;

        final name = p.basename(entry.path);
        final takenAt =
            snapshotTakenAt(name) ??
            (name == sessionSnapshotFileName
                ? (await entry.stat()).modified
                : null);
        if (takenAt == null) continue;

        // Read from the file's own header, so one truncated copy costs the
        // list one row rather than all of it.
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
      return (options: [for (final s in found) _describe(s)], problem: null);
    } catch (e) {
      return (
        options: const <RecoveryOption>[],
        problem:
            'The backups on this tablet could not be listed. Nothing has '
            'been changed. $e',
      );
    }
  }

  RecoveryOption _describe(Snapshot snapshot) =>
      snapshot.schemaVersion > appSchemaVersion
      ? (
          snapshot: snapshot,
          usable: false,
          refusal:
              'Made by a newer version of Wordbridge AAC (backup '
              '${snapshot.schemaVersion}, this app reads $appSchemaVersion). '
              'Update the app to use it.',
        )
      : (snapshot: snapshot, usable: true, refusal: null);

  /// Puts a copy where drift looks, and keeps the board it displaces.
  ///
  /// The copy is written beside the board and swapped in at the end, so every
  /// way this can fail before the swap leaves the tablet exactly as it was.
  ///
  /// A snapshot at an older schema is not brought forward here. Drift migrates
  /// it on the next launch, and `snapshotBeforeMigration` copies it first, so
  /// the ordinary update path does the work and does it with a backup in hand.
  Future<RecoveryResult> restore(Snapshot snapshot) async {
    try {
      final source = File(snapshot.path);
      if (!await source.exists()) {
        return (
          done: false,
          problem: 'That backup is no longer on this tablet.',
        );
      }

      final version = await snapshotSchemaVersion(source);
      if (version == null) {
        return (
          done: false,
          problem:
              'That file is not a Wordbridge AAC backup. Nothing has been '
              'changed.',
        );
      }

      if (version > appSchemaVersion) {
        return (
          done: false,
          problem:
              'That backup was made by a newer version of Wordbridge AAC '
              '(backup $version, this app reads $appSchemaVersion). Update '
              'the app and try again. Nothing has been changed.',
        );
      }

      final board = await _database();
      final incoming = File('${board.path}.incoming');
      if (await incoming.exists()) await incoming.delete();
      await source.copy(incoming.path);

      // Read back before it counts as written. A half-copied board put in
      // place of one that would not open is the same outage with a backup
      // spent on it.
      if (await snapshotSchemaVersion(incoming) != version) {
        if (await incoming.exists()) await incoming.delete();
        return (
          done: false,
          problem:
              'The backup could not be copied completely and has not been '
              'used. Check there is free space on this device. Nothing has '
              'been changed.',
        );
      }

      await _setAside(board);
      await incoming.rename(board.path);

      return (done: true, problem: null);
    } catch (e) {
      return (
        done: false,
        problem: 'That backup could not be put back on this tablet. $e',
      );
    }
  }

  /// Moves the board out of the way so the next launch builds a new one.
  ///
  /// The answer when there is nothing to restore from, which is the common
  /// case: snapshots are taken when a caregiver asks for one, before a
  /// migration, and on the cloud timer where that is switched on, so a tablet
  /// can reach this screen having never made one. A board built from the seed
  /// is not the board somebody learned — every location is new and it is
  /// stated as a loss on the way in — but it is a whole vocabulary against
  /// fourteen words.
  Future<RecoveryResult> startAgain() async {
    try {
      await _setAside(await _database());
      return (done: true, problem: null);
    } catch (e) {
      return (
        done: false,
        problem: 'The board on this tablet could not be set aside. $e',
      );
    }
  }

  /// Moves the board, and its journals, into the backups folder.
  ///
  /// Never deleted. A database this build cannot open still holds everything
  /// added since the last backup, and a repaired or updated build may read it;
  /// deleting it here would make this screen the thing that lost the board.
  ///
  /// The write-ahead log and the shared-memory file travel with it. Left
  /// behind they describe the database that was moved away, and SQLite would
  /// find them beside the one that replaced it.
  Future<void> _setAside(File board) async {
    final directory = await _folder(create: true);
    final base = '$_asidePrefix${snapshotStamp(_clock())}';
    final extension = p.extension(board.path);

    for (final journal in const ['', '-wal', '-shm']) {
      final file = File('${board.path}$journal');
      if (!await file.exists()) continue;

      final destination = p.join(directory.path, '$base$extension$journal');
      try {
        await file.rename(destination);
      } on FileSystemException {
        // Across a device boundary a rename is a copy, and documents and
        // backups are not guaranteed to share one.
        await file.copy(destination);
        await file.delete();
      }
    }
  }

  Future<Directory> _folder({required bool create}) async {
    final directory = Directory(
      p.join((await _documentsDirectory()).path, snapshotFolder),
    );
    if (create) await directory.create(recursive: true);
    return directory;
  }
}
