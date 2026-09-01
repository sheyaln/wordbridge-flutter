import 'dart:convert';

import '../../db/database.dart';

/// The key the symbol pack choices are kept under.
const symbolChoicesKey = 'symbolChoices';

/// Which symbol packs a person has deliberately switched on or off.
///
/// Device-scoped rather than per profile, and stored in `app_state` beside the
/// caregiver gesture and the device id. Which picture sets this tablet may
/// fetch is a fact about the tablet and about who is answerable for it, not
/// about the person speaking on it, and two profiles on one device cannot
/// sensibly disagree about it.
///
/// **Only deliberate answers are written here.** A pack nobody has decided
/// about is absent, and [SymbolRegistry.isEnabled] falls back to its license.
/// That is what lets a pack added in a later release arrive with the correct
/// default instead of inheriting a saved set that predates it: a noncommercial
/// pack shipped tomorrow is off tomorrow, without anybody having to migrate a
/// stored map.
Future<Map<String, bool>> loadSymbolChoices(WordbridgeDatabase db) async {
  final row = await (db.select(
    db.appState,
  )..where((s) => s.key.equals(symbolChoicesKey))).getSingleOrNull();

  if (row == null) return const {};

  try {
    final decoded = jsonDecode(row.value);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is bool)
          entry.key as String: entry.value as bool,
    };
  } catch (_) {
    // A value that will not parse is a value nobody can act on, and guessing
    // at it could turn a noncommercial pack on. Fall back to the licenses.
    return const {};
  }
}

Future<void> saveSymbolChoices(
  WordbridgeDatabase db,
  Map<String, bool> choices,
) async {
  await db
      .into(db.appState)
      .insertOnConflictUpdate(
        AppStateCompanion.insert(
          key: symbolChoicesKey,
          value: jsonEncode(choices),
        ),
      );
}
