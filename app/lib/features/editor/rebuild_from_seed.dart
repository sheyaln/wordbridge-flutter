/// Rebuilding a profile's boards from the vocabulary the app currently ships.
///
/// A board set is materialised once, at profile creation, and nothing re-runs
/// it. That is right for somebody who has learned a layout and wrong while the
/// layout is still being designed: a change to the seed reaches new profiles
/// and leaves the device it was tested on drawing the old board.
///
/// This discards rather than merges. Merging would mean deciding, per word,
/// whether a location belongs to the old layout or the new one, and getting it
/// wrong silently — which is the failure everything else here exists to
/// prevent. Discarding is at least legible.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show BooleanExpressionOperators;

import '../../db/database.dart';
import '../../db/seed/age_presets.dart';
import '../../db/seed/core_board_set.dart';
import '../../db/seed/core_vocabulary.dart';

/// Every label the shipped vocabulary places, at any level, on any board.
///
/// Read from the same declaration the seed builds from, so a word added to the
/// seed is counted as shipped the moment it exists rather than when somebody
/// remembers to update a list.
Set<String> shippedLabels(AgeBand band) => {
  for (final b in homeBands)
    for (final item in b.items) item.value.label,
  for (final item in pinnedQuestions) item.value.label,
  for (final name in categoryNames)
    for (final b in categoryBandsFor(name, band))
      for (final item in b.items) item.value.label,
};

/// What a rebuild would cost, worked out without doing any of it.
typedef RebuildImpact = ({
  /// Words on the current boards that the shipped vocabulary does not place.
  List<String> handAdded,

  /// Taps recorded against locations on the current boards.
  int recordedTaps,

  int rows,
  int cols,
});

/// Reads what the current board set holds that a fresh one would not.
Future<RebuildImpact> rebuildImpact(
  WordbridgeDatabase db, {
  required String profileId,
  required String vocabularyId,
}) async {
  final vocab = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingle();

  final profile = await (db.select(
    db.profiles,
  )..where((p) => p.id.equals(profileId))).getSingle();

  final band = AgeBand.forBirthDate(
    profile.birthDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(profile.birthDate!),
  );
  final shipped = shippedLabels(band);

  final placed =
      await (db.select(db.buttons)..where(
            (b) =>
                b.vocabularyId.equals(vocabularyId) &
                b.cellId.isNotNull() &
                b.deletedAt.isNull(),
          ))
          .get();

  final handAdded = <String>{
    for (final button in placed)
      if (!button.isSystem && !shipped.contains(button.label)) button.label,
  };

  final taps = await (db.select(
    db.usageEvents,
  )..where((e) => e.vocabularyId.equals(vocabularyId))).get();

  return (
    handAdded: handAdded.toList()..sort(),
    recordedTaps: taps.length,
    rows: vocab.gridRows,
    cols: vocab.gridCols,
  );
}

/// Builds a fresh board set at the same grid and points the profile at it.
///
/// The old vocabulary is left where it is rather than deleted. Usage rows name
/// its cells, and that history is what the remap warning is built from — a
/// rebuild that erased it would make the next edit less safe, not more.
Future<String> rebuildFromSeed(
  WordbridgeDatabase db, {
  required String profileId,
  required String vocabularyId,
}) async {
  final profile = await (db.select(
    db.profiles,
  )..where((p) => p.id.equals(profileId))).getSingle();

  final vocab = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingle();

  final band = AgeBand.forBirthDate(
    profile.birthDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(profile.birthDate!),
  );

  final rebuilt = await seedCoreBoardSet(
    db,
    name: vocab.name,
    locale: vocab.locale,
    rows: vocab.gridRows,
    cols: vocab.gridCols,
    profileId: profileId,
    ageBand: band,
    profanity: _profanityOf(profile),
    userName: profile.displayName,
  );

  return rebuilt;
}

/// The strong-language answer this profile gave, or null to follow its band.
bool? _profanityOf(Profile profile) {
  try {
    final settings = jsonDecode(profile.settingsJson) as Map<String, dynamic>;
    return settings['profanity'] as bool?;
  } catch (_) {
    return null;
  }
}
