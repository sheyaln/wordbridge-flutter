import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';

/// Upgrading a device that someone already relies on.
///
/// A board set is user data. An upgrade may add a column or a table; it may
/// never move a cell, drop a customisation, or take a word off a board that
/// has been learned. These build a database at each shipped schema version and
/// open it with the current code to prove that holds.
void main() {
  /// The schema as it stood at version 1, written out rather than generated,
  /// so a later change to the table definitions cannot quietly rewrite the
  /// past and make the upgrade look correct when it is not.
  void buildV1(Database raw) {
    raw.execute('''
      CREATE TABLE profiles (
        id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        avatar_uri TEXT NULL,
        active_vocabulary_id TEXT NULL,
        vocab_level INTEGER NOT NULL DEFAULT 1,
        settings_json TEXT NOT NULL DEFAULT '{}',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL,
        PRIMARY KEY (id)
      )''');

    raw.execute('''
      CREATE TABLE vocabularies (
        id TEXT NOT NULL,
        profile_id TEXT NULL REFERENCES profiles (id),
        name TEXT NOT NULL,
        locale TEXT NOT NULL DEFAULT 'en-US',
        grid_rows INTEGER NOT NULL,
        grid_cols INTEGER NOT NULL,
        root_board_id TEXT NULL,
        system_cell_map TEXT NOT NULL DEFAULT '{}',
        colour_scheme TEXT NOT NULL DEFAULT 'modifiedFitzgerald',
        is_template INTEGER NOT NULL DEFAULT 0,
        source_license TEXT NULL,
        motor_plan_locked INTEGER NOT NULL DEFAULT 1,
        schema_version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL,
        PRIMARY KEY (id)
      )''');

    raw.execute('''
      CREATE TABLE boards (
        id TEXT NOT NULL,
        vocabulary_id TEXT NOT NULL REFERENCES vocabularies (id),
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL,
        PRIMARY KEY (id)
      )''');

    raw.execute('''
      CREATE TABLE cells (
        id TEXT NOT NULL,
        board_id TEXT NOT NULL REFERENCES boards (id),
        row INTEGER NOT NULL,
        col INTEGER NOT NULL,
        span_rows INTEGER NOT NULL DEFAULT 1,
        span_cols INTEGER NOT NULL DEFAULT 1,
        state TEXT NOT NULL DEFAULT 'emptyReserved',
        created_at INTEGER NOT NULL,
        PRIMARY KEY (id),
        UNIQUE (board_id, row, col)
      )''');

    raw.execute('''
      CREATE TABLE symbols (
        id TEXT NOT NULL,
        pack_id TEXT NULL,
        source TEXT NOT NULL,
        external_id TEXT NULL,
        local_uri TEXT NULL,
        label TEXT NOT NULL,
        license TEXT NOT NULL,
        attribution TEXT NOT NULL,
        content_hash TEXT NULL,
        width INTEGER NULL,
        height INTEGER NULL,
        last_used_at INTEGER NULL,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER NULL,
        PRIMARY KEY (id)
      )''');

    raw.execute('''
      CREATE TABLE buttons (
        id TEXT NOT NULL,
        cell_id TEXT NULL REFERENCES cells (id),
        vocabulary_id TEXT NOT NULL REFERENCES vocabularies (id),
        label TEXT NOT NULL,
        message TEXT NOT NULL,
        speak_text TEXT NULL,
        action TEXT NOT NULL,
        target_board_id TEXT NULL REFERENCES boards (id),
        morpheme_kind TEXT NULL,
        symbol_id TEXT NULL REFERENCES symbols (id),
        part_of_speech TEXT NULL,
        background_color TEXT NULL,
        border_color TEXT NULL,
        text_color TEXT NULL,
        hidden INTEGER NOT NULL DEFAULT 0,
        vocab_level INTEGER NOT NULL DEFAULT 1,
        is_system INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL,
        PRIMARY KEY (id)
      )''');

    raw.execute('''
      CREATE TABLE usage_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        profile_id TEXT NOT NULL,
        vocabulary_id TEXT NOT NULL,
        board_id TEXT NOT NULL,
        cell_id TEXT NOT NULL,
        button_id TEXT NULL,
        label_snapshot TEXT NOT NULL,
        action TEXT NOT NULL,
        source TEXT NOT NULL,
        session_id TEXT NOT NULL,
        utterance_id TEXT NULL,
        occurred_at INTEGER NOT NULL
      )''');

    raw.execute('''
      CREATE TABLE edit_events (
        id TEXT NOT NULL,
        profile_id TEXT NULL,
        vocabulary_id TEXT NOT NULL,
        cell_id TEXT NULL,
        button_id TEXT NULL,
        kind TEXT NOT NULL,
        before_json TEXT NULL,
        after_json TEXT NULL,
        motor_impact_taps INTEGER NULL,
        changed_at INTEGER NOT NULL,
        PRIMARY KEY (id)
      )''');

    raw.execute('''
      CREATE TABLE caregiver_auth (
        id TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        pin_algo TEXT NOT NULL DEFAULT 'sha256-salted',
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until INTEGER NULL,
        biometric_enabled INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (id)
      )''');

    raw.execute('''
      CREATE TABLE sync_meta (
        entity TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        local_rev INTEGER NOT NULL DEFAULT 0,
        server_rev INTEGER NULL,
        dirty INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity, entity_id)
      )''');

    raw.execute(
      'CREATE UNIQUE INDEX buttons_cell_uq '
      'ON buttons (cell_id) WHERE cell_id IS NOT NULL',
    );

    raw.userVersion = 1;
  }

  /// One profile, one board, one word at a location, one recorded tap — the
  /// smallest thing that is recognisably somebody's board.
  void seedV1(Database raw) {
    raw.execute(
      "INSERT INTO profiles (id, display_name, active_vocabulary_id, "
      "vocab_level, settings_json, created_at, updated_at) "
      "VALUES ('default', 'default', 'v1', 1, "
      "'{\"filterVerbs\":true}', 1, 1)",
    );
    raw.execute(
      "INSERT INTO vocabularies (id, name, grid_rows, grid_cols, "
      "root_board_id, created_at, updated_at) "
      "VALUES ('v1', 'core', 7, 12, 'b1', 1, 1)",
    );
    raw.execute(
      "INSERT INTO boards (id, vocabulary_id, name, kind, created_at, "
      "updated_at) VALUES ('b1', 'v1', 'home', 'root', 1, 1)",
    );
    raw.execute(
      "INSERT INTO cells (id, board_id, row, col, state, created_at) "
      "VALUES ('c1', 'b1', 3, 4, 'occupied', 1)",
    );
    raw.execute(
      "INSERT INTO buttons (id, cell_id, vocabulary_id, label, message, "
      "action, vocab_level, created_at, updated_at) "
      "VALUES ('btn1', 'c1', 'v1', 'eat', 'eat', 'speak', 2, 1, 1)",
    );
    raw.execute(
      "INSERT INTO usage_events (device_id, profile_id, vocabulary_id, "
      "board_id, cell_id, button_id, label_snapshot, action, source, "
      "session_id, occurred_at) VALUES ('d', 'default', 'v1', 'b1', 'c1', "
      "'btn1', 'eat', 'speak', 'touch', 's', 1)",
    );
  }

  WordbridgeDatabase openUpgraded() {
    final raw = sqlite3.openInMemory();
    buildV1(raw);
    seedV1(raw);
    return WordbridgeDatabase.forTesting(NativeDatabase.opened(raw));
  }

  test('a version 1 database opens at the current version', () async {
    final db = openUpgraded();
    addTearDown(db.close);

    // Forces the upgrade to run.
    await db.select(db.profiles).get();

    expect(db.schemaVersion, 5);
  });

  test('the board survives the upgrade untouched', () async {
    // The whole point. A device someone speaks with must come back from an
    // update with every word exactly where it was.
    final db = openUpgraded();
    addTearDown(db.close);

    final cells = await db.select(db.cells).get();
    expect(cells, hasLength(1));
    expect((cells.single.row, cells.single.col), (3, 4));
    expect(cells.single.state, isNotNull);

    final buttons = await db.select(db.buttons).get();
    expect(buttons.single.label, 'eat');
    expect(buttons.single.cellId, 'c1');
  });

  test('customisations survive the upgrade', () async {
    final db = openUpgraded();
    addTearDown(db.close);

    final profile = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals('default'))).getSingle();

    expect(profile.settingsJson, contains('filterVerbs'));
    expect(profile.activeVocabularyId, 'v1');
  });

  test('recorded history survives the upgrade', () async {
    // Tap counts are what the editor uses to tell a caregiver what moving a
    // word will cost. Losing them on an update loses that warning.
    final db = openUpgraded();
    addTearDown(db.close);

    final events = await db.select(db.usageEvents).get();
    expect(events, hasLength(1));
    expect(events.single.cellId, 'c1');
    expect(events.single.labelSnapshot, 'eat');
  });

  test('the new columns and tables arrive', () async {
    final db = openUpgraded();
    addTearDown(db.close);

    final profile = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals('default'))).getSingle();
    expect(profile.birthDate, isNull);

    expect(await db.select(db.appState).get(), isEmpty);

    // Prediction arrives switched off and knowing nothing, which is the only
    // state it may arrive in: an upgrade must not start keeping a record of
    // somebody's speech that they did not ask for.
    expect(await db.select(db.predictionPairs).get(), isEmpty);
  });

  test(
    'an upgraded board does not gain a strip that would shrink it',
    () async {
      // Both strips take their height from the grid, so arriving at a default
      // would shorten every button on a board somebody has already learned. The
      // upgrade writes the current behaviour down instead, which is what lets
      // the getters default to on for everyone who comes after.
      final db = openUpgraded();
      addTearDown(db.close);

      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals('default'))).getSingle();

      final settings = jsonDecode(profile.settingsJson) as Map<String, dynamic>;

      expect(settings['prediction'], isFalse);
      expect(settings['breadcrumbs'], isFalse);

      final live = ProfileSettings(db, 'default');
      await live.load();
      expect(live.prediction, isFalse);
      expect(live.breadcrumbs, isFalse);
    },
  );

  test('no word is taken off the board by the upgrade', () async {
    // The stored level decides what is drawn from version 3 onward, and no
    // earlier value expressed a decision anybody made. Levelling up reveals
    // words; carrying the old value forward would hide "eat" from someone who
    // had learned where it was.
    final db = openUpgraded();
    addTearDown(db.close);

    final profile = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals('default'))).getSingle();

    final word = await (db.select(
      db.buttons,
    )..where((b) => b.id.equals('btn1'))).getSingle();

    expect(
      profile.vocabLevel,
      greaterThanOrEqualTo(word.vocabLevel),
      reason: '"eat" would no longer be drawn after the upgrade',
    );
  });

  test('a fresh install does not run the upgrade steps', () async {
    // onCreate builds the current schema directly. If it also ran the upgrade
    // path, a new profile would have its chosen starting level overwritten.
    final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.select(db.profiles).get();
    expect(await db.select(db.appState).get(), isEmpty);
  });
}
