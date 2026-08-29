import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Profiles,
    Vocabularies,
    Boards,
    Cells,
    Buttons,
    Symbols,
    UsageEvents,
    EditEvents,
    CaregiverAuth,
    AppState,
    PredictionPairs,
    SyncMeta,
  ],
)
class WordbridgeDatabase extends _$WordbridgeDatabase {
  WordbridgeDatabase() : super(driftDatabase(name: 'wordbridge'));

  /// In-memory instance for tests.
  WordbridgeDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();

      // Drift's uniqueKeys cannot express a partial index, and a plain
      // UNIQUE would treat every unplaced button as colliding on NULL in
      // some engines. One button per occupied location; unplaced buttons
      // sit in the editor tray unconstrained.
      await customStatement(
        'CREATE UNIQUE INDEX buttons_cell_uq '
        'ON buttons (cell_id) WHERE cell_id IS NOT NULL',
      );

      await customStatement(
        'CREATE INDEX usage_profile_time '
        'ON usage_events (profile_id, occurred_at)',
      );
      await customStatement(
        'CREATE INDEX usage_profile_label '
        'ON usage_events (profile_id, label_snapshot)',
      );
      // Powers the remap impact warning.
      await customStatement(
        'CREATE INDEX usage_cell_time '
        'ON usage_events (cell_id, occurred_at)',
      );

      await customStatement('CREATE INDEX cells_board ON cells (board_id)');
      await customStatement(
        'CREATE INDEX buttons_vocab ON buttons (vocabulary_id)',
      );
    },
    onUpgrade: (m, from, to) async {
      // Board layout is user data. A migration may add somewhere to record a
      // birthday or which profile was last open; it may never move a cell, and
      // it may never take a word off a board someone has learned.
      //
      // Steps are cumulative and each one belongs to the version that
      // introduced it. A device that stopped at any version reaches the
      // current one by running the steps above it, in order.
      if (from < 2) {
        await m.addColumn(profiles, profiles.birthDate);
        await m.createTable(appState);
      }

      if (from < 3) {
        // Version 3 is the first in which the stored vocabulary level decides
        // what is drawn, so no earlier value expresses a decision anybody
        // made. Levelling every existing profile up reveals words rather than
        // removing them, which is the safe direction.
        await customStatement('UPDATE profiles SET vocab_level = 3');
      }

      if (from < 4) {
        // Empty on arrival. Prediction is off until somebody turns it on, and
        // it has nothing to say until it has watched a few sentences.
        await m.createTable(predictionPairs);
      }

      if (from < 6) {
        // Boards built before this hold no record of their bands, so the grid
        // has nothing to name their regions from and simply does not label
        // them. Rebuilding a board set fills it in.
        await m.addColumn(boards, boards.bandMap);
      }

      if (from < 5) {
        // The suggestion strip and the breadcrumb trail are given to new
        // profiles, and both take their height from the grid. A profile that
        // predates them is written down as not having them, so that arriving
        // at a default cannot shorten every button on a board somebody has
        // already learned.
        await _recordStripsAsOff(this);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Writes an explicit value for a setting a profile never chose.
///
/// Settings live as JSON on the profile row, so a new key is normally absent
/// and its getter decides. That is fine for a setting nothing can see, and
/// wrong for one that changes the size of every button: a getter defaulting to
/// on would reach every board already in use. Writing the current behaviour
/// down leaves those boards as they are, and leaves the choice with a
/// caregiver.
Future<void> _recordStripsAsOff(WordbridgeDatabase db) async {
  final profiles = await db.select(db.profiles).get();

  for (final profile in profiles) {
    Map<String, dynamic> settings;
    try {
      settings = Map<String, dynamic>.from(
        jsonDecode(profile.settingsJson) as Map,
      );
    } catch (_) {
      settings = {};
    }

    settings.putIfAbsent('prediction', () => false);
    settings.putIfAbsent('breadcrumbs', () => false);

    await (db.update(db.profiles)..where((p) => p.id.equals(profile.id))).write(
      ProfilesCompanion(settingsJson: Value(jsonEncode(settings))),
    );
  }
}
