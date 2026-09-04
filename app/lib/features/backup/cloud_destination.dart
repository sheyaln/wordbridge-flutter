import 'dart:io';

import 'package:flutter/services.dart';

import 'snapshot.dart';

/// A backup sitting in the account signed in on this device.
///
/// [id] is whatever the platform needs to fetch it again — a file name in the
/// iCloud container, a document URI on Android. Nothing reads it; it is handed
/// straight back.
///
/// [takenAt] comes out of [name] rather than from the file, for the reason
/// [snapshotFileName] exists at all: a cloud provider rewrites modification
/// times when it syncs, and a caregiver on a replacement tablet is choosing by
/// date.
typedef CloudBackup = ({String id, String name, DateTime takenAt, int bytes});

/// Whether a copy could be written right now, and if not, what to do about it.
///
/// [problem] is addressed to a caregiver holding the tablet: "sign in to
/// iCloud" is something they can act on, and it is the most common answer.
typedef CloudStatus = ({bool reachable, String? problem});

/// Somewhere the user's own account keeps copies of the board.
///
/// The whole point of this interface is what it does *not* have: no server of
/// ours, no account of ours, no credentials compiled into the app. A copy goes
/// to the iCloud or Google account already signed in on the tablet, and the
/// only party who can read it is the person who owns that account. Anything
/// needing an intake — see `features/reporting/report_sender.dart`, the one
/// place in the app that opens a socket to us — would be a different feature
/// with a different privacy answer.
///
/// Faked whole in tests. Nothing here may be reached by a unit test on a
/// machine with no account signed in and no network.
abstract class CloudDestination {
  /// What to call it in front of a caregiver.
  String get label;

  /// Whether a copy written now would arrive.
  Future<CloudStatus> status();

  /// Asks for whatever the platform needs before a copy can be written.
  ///
  /// iCloud needs nothing: the account is the device's own and the app's
  /// container comes with it. Android needs a folder, picked once through the
  /// system document picker — this app holds no Google credential of its own
  /// and never will, so the caregiver names the place and the system hands
  /// back a permission scoped to it.
  ///
  /// Called when somebody switches the copies on, and never on its own. It can
  /// put a picker in front of whoever is holding the tablet, which must not be
  /// something a launch does.
  Future<CloudStatus> connect();

  /// What the account holds, newest first, ignoring anything that is not one
  /// of ours.
  Future<List<CloudBackup>> list();

  /// Puts [file] in the account under [name], replacing any file of that name.
  Future<CloudBackup> upload(File file, String name);

  /// Fetches one back into [to], which is overwritten.
  Future<void> download(CloudBackup backup, File to);

  Future<void> delete(CloudBackup backup);
}

/// Why something could not be done to the copies in the account.
///
/// A sentence, not a code. Everything that throws one of these is reachable
/// from a screen a caregiver is reading, on a day when the reason they are
/// reading it is that something has already gone wrong.
class CloudRefusal implements Exception {
  const CloudRefusal(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What to call the account's storage on this platform.
///
/// Derived here rather than asked of the platform, so the setup screen can name
/// it before anything has been signed in to or reached. There are two answers
/// and neither depends on the state of an account.
String cloudLabel() {
  if (Platform.isIOS || Platform.isMacOS) return 'iCloud';
  if (Platform.isAndroid) return 'Google Drive';
  return 'your cloud storage';
}

/// The account's copies, over the platform channel that reaches them.
///
/// **iOS and macOS: the app's own iCloud container, under Documents.**
/// Deliberately not the automatic iCloud device backup that sweeps up an app's
/// documents folder. That is the mechanism behind *"we lost months of custom
/// button and phrase building because we thought the iCloud backup would
/// protect us"* — it cannot be triggered, listed or verified, it gives no date,
/// and it only comes back onto a wiped device. Files this app writes into its
/// own container are files it can count, date and fetch one at a time, which is
/// what makes the "last backed up" line a fact rather than a hope. CloudKit's
/// private database would keep the data in the same account, but a snapshot is
/// one opaque SQLite file and record storage buys nothing for it.
///
/// **Android: a folder the caregiver picks once, through the system document
/// picker.** Their Google Drive, their OneDrive, their SD card — whichever
/// providers are on the tablet — held afterwards as a persisted URI permission,
/// so the pick happens once and every copy after it is automatic. The rejected
/// alternative was Drive's `appDataFolder` through the Drive REST API: it is
/// the closer match to iCloud's hidden container, but it needs an OAuth client
/// tied to the upload key and Google verification of the `drive.appdata`
/// sensitive scope — infrastructure on our side of the line, for a feature
/// whose whole claim is that there is no our side. Android's own Auto Backup
/// was rejected for the same reason as the iCloud device backup: silent,
/// capped at 25 MB, unlistable, restore-on-reinstall only.
///
/// A platform with no implementation gets [notAvailableHere] rather than a
/// crash, which is the honest state for a fork or a desktop build.
class PlatformCloudDestination implements CloudDestination {
  PlatformCloudDestination({MethodChannel? channel, String? label})
    : _channel = channel ?? const MethodChannel(channelName),
      label = label ?? cloudLabel();

  static const channelName = 'org.wordbridge/cloud_backup';

  final MethodChannel _channel;

  @override
  final String label;

  @override
  Future<CloudStatus> status() async {
    try {
      final reachable = await _channel.invokeMethod<bool>('reachable') ?? false;
      return (
        reachable: reachable,
        problem: reachable ? null : notSignedIn(label),
      );
    } on PlatformException catch (e) {
      return (reachable: false, problem: refusalFor(e, label).message);
    } on MissingPluginException {
      return (reachable: false, problem: notAvailableHere);
    }
  }

  @override
  Future<CloudStatus> connect() async {
    try {
      final reachable = await _channel.invokeMethod<bool>('connect') ?? false;
      return (
        reachable: reachable,
        problem: reachable ? null : notSignedIn(label),
      );
    } on PlatformException catch (e) {
      return (reachable: false, problem: refusalFor(e, label).message);
    } on MissingPluginException {
      return (reachable: false, problem: notAvailableHere);
    }
  }

  @override
  Future<List<CloudBackup>> list() async {
    final found = <CloudBackup>[];

    for (final entry in await _invoke<List<Object?>>('list') ?? const []) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final name = entry['name'];
      final bytes = entry['bytes'];
      if (id is! String || name is! String || bytes is! int) continue;

      // Anything else the caregiver keeps in that folder is left out, for the
      // same reason the local list drops it: a restore that could only be
      // refused should not be offered as a way back.
      final takenAt = snapshotTakenAt(name);
      if (takenAt == null) continue;

      found.add((id: id, name: name, takenAt: takenAt, bytes: bytes));
    }

    found.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return found;
  }

  @override
  Future<CloudBackup> upload(File file, String name) async {
    final written = await _invoke<Map<Object?, Object?>>('upload', {
      'path': file.path,
      'name': name,
    });

    final id = written?['id'];
    final bytes = written?['bytes'];
    final takenAt = snapshotTakenAt(name);
    if (id is! String || bytes is! int || takenAt == null) {
      throw CloudRefusal(didNotArrive(label));
    }

    return (id: id, name: name, takenAt: takenAt, bytes: bytes);
  }

  @override
  Future<void> download(CloudBackup backup, File to) =>
      _invoke<void>('download', {'id': backup.id, 'path': to.path});

  @override
  Future<void> delete(CloudBackup backup) =>
      _invoke<void>('delete', {'id': backup.id});

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw refusalFor(e, label);
    } on MissingPluginException {
      throw const CloudRefusal(notAvailableHere);
    }
  }

  static const notAvailableHere =
      'This build cannot keep a copy in the cloud. Backups on this device '
      'still work.';
}

/// The closed set of sentences a caregiver reads about the account.
///
/// Nothing here repeats what the platform said. A backups screen is not a place
/// to learn about ubiquity containers or document URI permissions, and a
/// message assembled from a platform error is a message somebody else wrote —
/// the same rule `problemFor` follows for the report intake.
CloudRefusal refusalFor(PlatformException e, String label) => switch (e.code) {
  'signIn' => CloudRefusal(notSignedIn(label)),
  'folder' => const CloudRefusal(
    'No folder has been chosen for backups yet. Choose one under Backups.',
  ),
  'space' => CloudRefusal(
    'There is no room left in $label for this backup. Nothing on this device '
    'has changed.',
  ),
  'offline' => CloudRefusal(
    'This device could not reach $label. The backup is still on the tablet, '
    'and will go up next time.',
  ),
  'missing' => CloudRefusal(
    'That backup is no longer in $label. Nothing has been changed.',
  ),
  _ => CloudRefusal(didNotArrive(label)),
};

String notSignedIn(String label) =>
    'This tablet is not signed in to $label. Sign in through the device '
    'settings, and backups will start going up.';

String didNotArrive(String label) =>
    'The backup could not be copied to $label. It is still on this device.';
