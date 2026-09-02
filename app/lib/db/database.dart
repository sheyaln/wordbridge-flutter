import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// The name the board's database is stored under.
///
/// One constant because two things need it: drift, which opens it, and
/// [boardDatabaseFile], which has to find the same file before drift does.
const databaseName = 'wordbridge';

/// Where the board actually sits on this device.
///
/// The file drift is about to open, worked out without opening it, so that
/// something can be done about it first — see `snapshotBeforeMigration`, which
/// is the whole reason this exists.
///
/// The path is `drift_flutter`'s own default written out: the application
/// documents directory, and `$name.sqlite` inside it. Reproduced rather than
/// asked for because there is nothing to ask — the executor is built lazily
/// and does not say where it went. Pointing drift at a path of our own instead
/// would move the database out from under every device already carrying one,
/// which is the loss this file exists to prevent.
Future<File> boardDatabaseFile() async => File(
  p.join(
    (await getApplicationDocumentsDirectory()).path,
    '$databaseName.sqlite',
  ),
);

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
  WordbridgeDatabase() : super(driftDatabase(name: databaseName));

  /// In-memory instance for tests.
  WordbridgeDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

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
      // No index on the word: there is no word (§4.71). What is asked of this
      // table is how often a location was selected, and the index below is
      // what answers it.
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
        // made. Leveling every existing profile up reveals words rather than
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

      if (from < 8) {
        // §4.71. The usage log stops being a transcript.
        //
        // Dropping the columns is the point, not a side effect: a device that
        // has been recording since version 1 is carrying the words somebody
        // said and the sentences they said them in, and a change that stopped
        // writing them while leaving months of them on disk would be a change
        // of policy rather than of fact. The counts survive; what was said
        // does not.
        //
        // `alterTable` recreates and copies, which is how SQLite drops a
        // column, so the rows land in the new shape with the old values gone.
        await customStatement('DROP INDEX IF EXISTS usage_profile_label');
        await m.alterTable(TableMigration(usageEvents));
      }

      if (from < 7) {
        // Nothing named until somebody names something. A board that predates
        // this keeps whatever the layout called its rows, which is what it
        // was already showing.
        await m.addColumn(boards, boards.lineNames);
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
/// on would reach every board already in use. Writing the current behavior
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
