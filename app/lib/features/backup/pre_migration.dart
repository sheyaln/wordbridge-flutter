/// A copy of the board taken on the launch after an update, before the update
/// is allowed to touch it.
///
/// *"Latest update reset everything on my sons ipad."* That is the failure this
/// whole feature exists for, and it has exactly one moment: the first launch
/// after an app update, between the new code starting and the migration
/// running. A snapshot taken any later is a snapshot of the damage.
///
/// It cannot be taken by [BackupService.takeSnapshot], which copies through the
/// live connection — by the time there is a live connection drift has already
/// migrated. It cannot be taken inside `onUpgrade` either, because `VACUUM` is
/// not allowed inside a transaction. So the version is read out of the file's
/// own header, without a connection, and the copy is made through a raw handle
/// before drift is given the file.
library;

import 'dart:io';

import 'backup_service.dart';
import 'snapshot.dart';

/// What a launch-time check decided, so that a caller has something to report.
///
/// [SnapshotAttempt] on its own cannot say "there was nothing to do", which is
/// the answer on almost every launch and is not a failure.
enum PreMigrationOutcome {
  /// The database on disk is at the version this app reads. Nothing was copied.
  upToDate,

  /// There is no database yet, so there is nothing to lose.
  firstLaunch,

  /// Not a database this app wrote, or not readable. Nothing was copied, and
  /// nothing here is going to guess at what it is.
  unrecognized,

  /// A migration was due and a snapshot was taken first.
  snapshotTaken,

  /// A migration was due and the snapshot failed. The app carries on: a backup
  /// that can stop a device from starting is a worse failure than the one it
  /// guards against.
  snapshotFailed,
}

typedef PreMigrationResult = ({
  PreMigrationOutcome outcome,
  SnapshotAttempt? attempt,
});

/// Copies the board if the file on disk is older than the app about to open it.
///
/// Call before the first query, and before anything else has opened the file —
/// [BackupService.snapshotFile] cannot check that, and this is where the
/// guarantee comes from.
///
/// [database] is a function rather than a file because finding the file is one
/// of the things that can fail: it goes through `path_provider`, which needs a
/// platform that answers. Locating it inside the guard keeps every failure on
/// this side of the boundary.
///
/// Never throws. Every way this can fail ends in a launch that still talks,
/// because the alternative is a nonspeaking person holding a tablet that will
/// not start because its backup would not write.
Future<PreMigrationResult> snapshotBeforeMigration({
  required Future<File> Function() database,
  required int appVersion,
  required BackupService backup,
}) async {
  try {
    final file = await database();

    if (!await file.exists()) {
      return (outcome: PreMigrationOutcome.firstLaunch, attempt: null);
    }

    final onDisk = await snapshotSchemaVersion(file);
    if (onDisk == null) {
      return (outcome: PreMigrationOutcome.unrecognized, attempt: null);
    }

    // Newer than this app is not a migration either — drift will refuse to
    // open it, and refusing loudly is better than a copy that implies the app
    // knew what it was holding.
    if (onDisk >= appVersion) {
      return (outcome: PreMigrationOutcome.upToDate, attempt: null);
    }

    final attempt = await backup.snapshotFile(file);
    return (
      outcome: attempt.snapshot == null
          ? PreMigrationOutcome.snapshotFailed
          : PreMigrationOutcome.snapshotTaken,
      attempt: attempt,
    );
  } catch (e) {
    return (
      outcome: PreMigrationOutcome.snapshotFailed,
      attempt: (
        snapshot: null,
        problem: 'The board could not be backed up before this update. $e',
      ),
    );
  }
}
