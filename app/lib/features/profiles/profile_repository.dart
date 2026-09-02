import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/seed/age_presets.dart';
import '../../db/seed/core_board_set.dart';
import 'profile_settings.dart';
import 'grid_choice.dart';

/// Creating, listing and resuming profiles.
///
/// Each profile owns its own vocabulary, settings and usage history. They are
/// not views onto shared data: two people who use this device have different
/// grids, different words and different private speech, and mixing any of
/// those is a bug with a person on the other end of it.
class ProfileRepository {
  ProfileRepository(this._db);

  final WordbridgeDatabase _db;

  static const _lastProfileKey = 'lastProfileId';

  Future<List<Profile>> list() =>
      (_db.select(_db.profiles)..where((p) => p.deletedAt.isNull())).get();

  Future<Profile?> byId(String id) => (_db.select(
    _db.profiles,
  )..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Which profile to open, without asking anyone.
  ///
  /// Launching goes straight back to whoever was last using the device. A
  /// chooser in the user's path is a screen they may not be able to read
  /// standing between them and the only way they have to speak — so the
  /// chooser lives behind the caregiver gate instead, and switching is a
  /// deliberate act by someone who can read it.
  Future<Profile?> resume() async {
    final remembered = await _appState(_lastProfileKey);
    if (remembered != null) {
      final profile = await byId(remembered);
      if (profile != null && profile.deletedAt == null) return profile;
    }

    final all = await list();
    return all.isEmpty ? null : all.first;
  }

  Future<void> remember(String profileId) async {
    await _db
        .into(_db.appState)
        .insertOnConflictUpdate(
          AppStateCompanion.insert(key: _lastProfileKey, value: profileId),
        );
  }

  /// Creates a profile and builds its board set at the chosen grid.
  ///
  /// The vocabulary is materialized once, here, from the answers given at
  /// setup. Nothing recomputes it afterwards unless a person deliberately
  /// changes one of those answers.
  ///
  /// [vocabLevel] decides how much of that vocabulary is drawn, never how much
  /// of it is placed: every word takes its location here whatever the level,
  /// so raising it later reveals words where they have always been. Left null,
  /// it follows the age band the birthday falls in.
  Future<Profile> create({
    required String displayName,
    required GridChoice grid,
    DateTime? birthDate,
    bool? profanity,
    int? vocabLevel,
    bool usageTracking = ProfileSettings.usageTrackingForNewProfiles,
    bool crashReports = ProfileSettings.crashReportsForNewProfiles,
  }) async {
    if (!grid.isUsable) {
      throw ArgumentError(grid.refusal);
    }

    final band = AgeBand.forBirthDate(birthDate);
    final profileId = newId();
    final ts = nowMs();

    await _db
        .into(_db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: displayName,
            birthDate: Value(birthDate?.millisecondsSinceEpoch),
            vocabLevel: Value(vocabLevel ?? band.startingLevel),
            settingsJson: Value(
              jsonEncode({
                'orientation': grid.orientation.name,
                'iconSize': grid.iconSize.name,
                'profanity': profanity ?? band.swearsByDefault,
                // Written here rather than left to the getters. A default that
                // falls out of a getter reaches every profile that never chose
                // — including boards laid out before it existed, which these
                // two would shrink.
                'prediction': ProfileSettings.predictionForNewProfiles,
                'breadcrumbs': ProfileSettings.breadcrumbsForNewProfiles,
                // Whatever setup was told. Written even when the answer is
                // no, so the record says somebody was asked rather than
                // leaving it to a getter's default.
                'usageTracking': usageTracking,
                'crashReports': crashReports,
              }),
            ),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    await seedCoreBoardSet(
      _db,
      name: '$displayName’s words',
      rows: grid.rows,
      cols: grid.cols,
      profileId: profileId,
      ageBand: band,
      profanity: profanity,
      userName: displayName,
    );

    await remember(profileId);
    return (await byId(profileId))!;
  }

  /// Marks a profile deleted without destroying it.
  ///
  /// A hard delete would take a person's whole board set and every hour of
  /// practice behind it, on one tap, with no way back. Their usage history is
  /// also the evidence a funder or a school asked for.
  Future<void> archive(String profileId) async {
    await (_db.update(
      _db.profiles,
    )..where((p) => p.id.equals(profileId))).write(
      ProfilesCompanion(deletedAt: Value(nowMs()), updatedAt: Value(nowMs())),
    );

    if (await _appState(_lastProfileKey) == profileId) {
      final remaining = await list();
      if (remaining.isEmpty) {
        await (_db.delete(
          _db.appState,
        )..where((a) => a.key.equals(_lastProfileKey))).go();
      } else {
        await remember(remaining.first.id);
      }
    }
  }

  Future<String?> _appState(String key) async {
    final row = await (_db.select(
      _db.appState,
    )..where((a) => a.key.equals(key))).getSingleOrNull();
    return row?.value;
  }
}
