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
    SyncMeta,
  ],
)
class WordbridgeDatabase extends _$WordbridgeDatabase {
  WordbridgeDatabase() : super(driftDatabase(name: 'wordbridge'));

  /// In-memory instance for tests.
  WordbridgeDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

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
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
