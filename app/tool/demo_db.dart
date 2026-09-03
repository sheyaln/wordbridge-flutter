// Builds a database for a screenshot: one profile, its board set materialized,
// nothing said on it yet.
//
// Run it, drop the file into a simulator's Documents directory as
// `wordbridge.sqlite`, and the app opens on a board rather than on setup. That
// is the whole point: the store listing and the website both need a picture of
// the board, and driving setup by hand each time is how two screenshots end up
// showing two different boards.
//
// It is a test file because it has to be. `GridChoice` reaches `dart:ui` for
// `Size`, which the plain Dart VM does not have, so `flutter test` is what can
// run this at all.
//
//   flutter test tool/demo_db.dart --dart-define=out=/tmp/wordbridge.sqlite
//
// Grid defaults to what an iPad mini works out for itself in landscape at the
// middle icon size, so the picture is of a real device's answer rather than of
// a number somebody typed.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';

const _out = String.fromEnvironment(
  'out',
  defaultValue: '/tmp/wordbridge-demo.sqlite',
);

const _name = String.fromEnvironment('name', defaultValue: 'Wordbridge');

/// The device's logical size. The short and long sides are what
/// [GridChoice.derive] reads, so either orientation of the pair works.
///
/// Defaults to an iPad mini. Pass the pair for another device to stage a
/// screenshot at the size a store asks for.
const _short = int.fromEnvironment('short', defaultValue: 744);
const _long = int.fromEnvironment('long', defaultValue: 1133);
final _screen = Size(_short.toDouble(), _long.toDouble());

void main() {
  test('writes a seeded database for a screenshot', () async {
    final file = File(_out);
    if (file.existsSync()) file.deleteSync();
    file.parent.createSync(recursive: true);

    final grid = GridChoice.derive(
      screen: _screen,
      orientation: BoardOrientation.landscape,
      iconSize: IconSize.medium,
    );

    expect(grid.isUsable, isTrue, reason: grid.refusal ?? '');

    final db = WordbridgeDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final repository = ProfileRepository(db);
    final profile = await repository.create(
      displayName: _name,
      grid: grid,
      vocabLevel: 3,
    );

    // The band headings are what the picture is of, so they are on. They are
    // off for a new profile because a person who knows their board does not
    // need them read to them, and a picture of the board is the opposite case.
    final settings = Map<String, dynamic>.from(
      jsonDecode(profile.settingsJson) as Map,
    )..['regionLabels'] = true;

    await (db.update(db.profiles)..where((p) => p.id.equals(profile.id))).write(
      ProfilesCompanion(settingsJson: Value(jsonEncode(settings))),
    );

    // Setup seeds the name onto the board, which is the right thing for a
    // person and the wrong thing for a screenshot: it puts whatever this
    // profile was called on a key. Taken back off, and its location left
    // reserved, which is what an unused location is.
    final named = await (db.select(
      db.buttons,
    )..where((b) => b.label.equals(_name) & b.isSystem.equals(false))).get();

    for (final button in named) {
      await (db.delete(db.buttons)..where((b) => b.id.equals(button.id))).go();
      final cellId = button.cellId;
      if (cellId == null) continue;
      await (db.update(db.cells)..where((c) => c.id.equals(cellId))).write(
        const CellsCompanion(state: Value(CellState.emptyReserved)),
      );
    }

    stdout.writeln(
      'wrote ${grid.rows}x${grid.cols} board to ${file.path}, '
      '${named.length} name key removed',
    );
  });
}
