import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/main.dart';

/// The wiring that decides whether a caregiver's chosen picture is ever drawn.
///
/// Everything downstream of this is well covered, and all of it is inert if the
/// resolver the app builds for itself has no symbol store: the picker writes
/// the choice, the board draws the pack picture for the word instead, and
/// nothing anywhere reports a problem. One omitted argument, no symptom — so
/// the app's own construction is pinned rather than left to inspection.
void main() {
  test('the app builds its resolver with the symbol store', () {
    final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final resolver = appSymbolResolver(
      db: db,
      registry: SymbolRegistry(packs: const []),
    );

    expect(
      resolver.db,
      same(db),
      reason:
          'without the store every board falls back to the picture for the '
          'word, and a chosen picture is written but never drawn',
    );
  });
}
