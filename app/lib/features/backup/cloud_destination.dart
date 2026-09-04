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

/// Where on this device a copy goes.
///
/// The two answers are not variations on one idea. [account] is a place the
/// operating system hands over without anybody choosing anything; [folder] is
/// a place a caregiver named, in a provider this app holds no credential for
/// and never will. An iPad can do either. An Android tablet can only do the
/// second, which is why it has been the only one until now.
enum CloudPlace {
  /// The app's own space inside the account the device is already signed in
  /// to — on Apple, the iCloud container.
  account,

  /// A folder somebody picked once, wherever they picked it: iCloud Drive,
  /// Google Drive, Dropbox, OneDrive, the tablet itself.
  folder,
}

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
  ///
  /// The last thing the platform said, not a constant. Once a folder has been
  /// picked this is the provider's own name, so a sentence about a failed copy
  /// says "Google Drive" rather than something the family would have to go and
  /// work out.
  String get label;

  /// Where copies go now, as far as the last answer from the platform said.
  ///
  /// Read without asking, because it is needed by sentences thrown from deep
  /// inside an upload and it only changes when somebody changes it.
  CloudPlace get place;

  /// The places this device can be asked to use, in the order they are offered.
  ///
  /// Empty where nothing can keep a copy at all, which is the honest state for
  /// a desktop build.
  List<CloudPlace> get places;

  /// Whether a copy written now would arrive. Refreshes [place] and [label].
  Future<CloudStatus> status();

  /// Asks for whatever the platform needs before a copy can be written.
  ///
  /// [CloudPlace.account] needs nothing: the account is the device's own and
  /// the app's container comes with it. [CloudPlace.folder] needs a folder,
  /// picked once through the system picker — this app holds no Google or
  /// Dropbox credential of its own and never will, so the caregiver names the
  /// place and the system hands back a permission scoped to it.
  ///
  /// Called when somebody switches the copies on, and never on its own. It can
  /// put a picker in front of whoever is holding the tablet, which must not be
  /// something a launch does.
  Future<CloudStatus> connect();

  /// Sends copies to [place] from now on, asking for whatever it needs.
  ///
  /// [pick] opens the folder picker even where a folder is already held, which
  /// is the way back from one that has gone.
  ///
  /// Nothing already written is moved or deleted — see [CloudBackupService] in
  /// `cloud_backup.dart`, which is where that decision is explained and where
  /// the caregiver is told about it.
  Future<CloudStatus> use(CloudPlace place, {bool pick = false});

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

/// What this device can be asked to do with a copy.
///
/// Derived here rather than asked of the platform, so the setup screen can
/// offer the choice before anything has been signed in to, picked or reached.
///
/// Apple gets both. The container needs nobody to choose anything and comes
/// back after a reinstall; the picker reaches every File Provider extension on
/// the device, which is the same freedom Android has had from the start and
/// the only route to a family's Google Drive that does not put an OAuth client
/// of ours in the middle.
List<CloudPlace> cloudPlaces() {
  if (Platform.isIOS || Platform.isMacOS) {
    return const [CloudPlace.account, CloudPlace.folder];
  }
  if (Platform.isAndroid) return const [CloudPlace.folder];
  return const [];
}

/// What to call a place before the platform has named one.
///
/// There is a real name for a folder once one exists — the provider's, from
/// the platform — and this is what stands in until then. It has to read as an
/// instruction rather than a location, because at the moment it is shown there
/// is nowhere yet.
String cloudLabel([CloudPlace place = CloudPlace.account]) {
  if (Platform.isAndroid) return 'Google Drive';
  // Before the platform is recognised, not after it: the two places are told
  // apart by what they *are* rather than by who is asking. Naming them from
  // the platform first gave a host that is neither Apple nor Android one
  // string for both, and the setup screen offers them as a list — so it drew
  // two option cards reading "Keep a copy in your cloud storage" and asked
  // somebody to choose between them.
  if (place == CloudPlace.folder) return unpickedFolder;
  if (Platform.isIOS || Platform.isMacOS) return 'iCloud';
  return 'your cloud storage';
}

const unpickedFolder = 'a folder you choose';

/// The account's copies, over the platform channel that reaches them.
///
/// **Apple: either the app's own iCloud container or a folder somebody picked.**
/// The container is the default and is deliberately not the automatic iCloud
/// device backup that sweeps up an app's documents folder. That is the
/// mechanism behind *"we lost months of custom button and phrase building
/// because we thought the iCloud backup would protect us"* — it cannot be
/// triggered, listed or verified, it gives no date, and it only comes back onto
/// a wiped device. Files this app writes into its own container are files it
/// can count, date and fetch one at a time, which is what makes the "last
/// backed up" line a fact rather than a hope. CloudKit's private database would
/// keep the data in the same account, but a snapshot is one opaque SQLite file
/// and record storage buys nothing for it.
///
/// The folder is the same act Android has always had, through
/// `UIDocumentPickerViewController` in folder mode and a security-scoped
/// bookmark: it reaches Google Drive, Dropbox, OneDrive or anything else with a
/// File Provider extension on the device. It exists because a family whose
/// files live in Drive should not have to keep a second copy in iCloud to be
/// backed up, and because the container needs an entitlement while the picker
/// needs none.
///
/// **Android: a folder the caregiver picks once, through the system document
/// picker.** Their Google Drive, their OneDrive, their SD card — whichever
/// providers are on the tablet — held afterwards as a persisted URI permission,
/// so the pick happens once and every copy after it is automatic.
///
/// The rejected alternative on both platforms was Drive's REST API with OAuth:
/// it is the closer match to a hidden container, but it needs a client tied to
/// the signing key and Google's verification of a sensitive scope —
/// infrastructure on our side of the line, for a feature whose whole claim is
/// that there is no our side. Android's own Auto Backup was rejected for the
/// same reason as the iCloud device backup: silent, capped at 25 MB,
/// unlistable, restore-on-reinstall only.
///
/// A platform with no implementation gets [notAvailableHere] rather than a
/// crash, which is the honest state for a fork or a desktop build.
class PlatformCloudDestination implements CloudDestination {
  factory PlatformCloudDestination({
    MethodChannel? channel,
    String? label,
    CloudPlace? place,
    List<CloudPlace>? places,
  }) {
    final offered = places ?? cloudPlaces();
    final chosen = place ?? offered.firstOrNull ?? CloudPlace.account;

    return PlatformCloudDestination._(
      channel ?? const MethodChannel(channelName),
      offered,
      chosen,
      label ?? cloudLabel(chosen),
    );
  }

  PlatformCloudDestination._(
    this._channel,
    this._places,
    this._place,
    this._label,
  );

  static const channelName = 'org.wordbridge/cloud_backup';

  final MethodChannel _channel;
  final List<CloudPlace> _places;

  CloudPlace _place;
  String _label;

  @override
  List<CloudPlace> get places => _places;

  @override
  CloudPlace get place => _place;

  @override
  String get label => _label;

  @override
  Future<CloudStatus> status() => _ask('place');

  @override
  Future<CloudStatus> connect() => _ask('connect');

  @override
  Future<CloudStatus> use(CloudPlace place, {bool pick = false}) =>
      _ask('connect', {'place': place.name, 'pick': pick});

  /// Asks where copies go and whether one would arrive, in one trip.
  ///
  /// The reply carries the place and its name alongside the answer so that
  /// every sentence written afterwards names where copies are actually going,
  /// rather than where they were going when the app started.
  Future<CloudStatus> _ask(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      _remember(reply);

      final reachable = reply?['reachable'] == true;
      return (
        reachable: reachable,
        problem: reachable ? null : noDestination(_label, _place),
      );
    } on PlatformException catch (e) {
      return (reachable: false, problem: refusalFor(e, _label).message);
    } on MissingPluginException {
      return (reachable: false, problem: notAvailableHere);
    }
  }

  void _remember(Map<String, Object?>? reply) {
    final said = reply?['place'];
    if (said is String) {
      final place = switch (said) {
        'account' => CloudPlace.account,
        'folder' => CloudPlace.folder,
        _ => _place,
      };
      // A platform that moved the copies without naming the new place leaves
      // the old place's name behind, and the old name is the one thing that
      // must not survive the move: it would send a caregiver to look for their
      // backups where they no longer are.
      if (place != _place) _label = cloudLabel(place);
      _place = place;
    }

    final named = reply?['label'];
    if (named is String && named.isNotEmpty) _label = named;
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

    // The name the platform actually used, not the one it was asked for. A
    // document provider is free to rename a file it creates, and a snapshot's
    // date lives in its name — a copy filed as "wordbridge-… (1).db" is a copy
    // no listing will ever offer as a way back, so it is better to find that
    // out here, on the upload, than on the day somebody needs it.
    final stored = written?['name'];
    final filed = stored is String && stored.isNotEmpty ? stored : name;
    final takenAt = snapshotTakenAt(filed);

    if (id is! String || bytes is! int || takenAt == null) {
      throw CloudRefusal(didNotArrive(label));
    }

    return (id: id, name: filed, takenAt: takenAt, bytes: bytes);
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
  'capability' => CloudRefusal(noCapability(label)),
  'folder' => const CloudRefusal(noFolderChosen),
  'gone' => CloudRefusal(folderGone(label)),
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

/// What to say when the platform reported only that a copy cannot be written.
///
/// Two places, two entirely unrelated fixes, and the platform side has no
/// business writing the app's own copy — so the sentence is chosen from the
/// same place the label is. A tablet sending to a folder has almost always not
/// been given one; a tablet sending to its own iCloud container is signed out.
/// Telling somebody who picked Google Drive to sign in to iCloud sends them to
/// a screen where nothing is wrong.
String noDestination(String label, CloudPlace place) =>
    place == CloudPlace.folder ? noFolderChosen : notSignedIn(label);

const noFolderChosen =
    'No folder has been chosen for backups yet. Choose one under Backups.';

String notSignedIn(String label) =>
    'This tablet is not signed in to $label. Sign in through the device '
    'settings, and backups will start going up.';

/// Signed in, and the app still cannot see the account.
///
/// Kept apart from [notSignedIn] because the two send a caregiver to
/// completely different places, and one of them is a place where nothing is
/// wrong. This build was never given the iCloud capability, so the account is
/// there and the container is not — nothing about the device or the sign-in
/// can change that, and a caregiver who goes looking will find iCloud working
/// perfectly everywhere else on the iPad and conclude the app is lying.
///
/// It says what still works, because that is what somebody standing there
/// needs: this is not a backup that has stopped, it is one route to the
/// account that was never open.
String noCapability(String label) =>
    'This copy of Wordbridge AAC cannot reach $label, even though the tablet '
    'is signed in — the app was built without it. Backups on this device '
    'still work, and a folder can be chosen instead under Backups.';

/// A folder that was chosen and is not there any more.
///
/// Kept apart from never having chosen one, because it is a different event:
/// copies were going somewhere and have stopped. A provider app uninstalled, a
/// permission the system dropped, a folder somebody deleted — the platform
/// cannot tell those apart and a caregiver does not need it to. What they need
/// is the second sentence.
String folderGone(String label) =>
    'This tablet can no longer reach the backup folder in $label. Backups on '
    'this device still work. Choose the folder again under Backups.';

String didNotArrive(String label) =>
    'The backup could not be copied to $label. It is still on this device.';
