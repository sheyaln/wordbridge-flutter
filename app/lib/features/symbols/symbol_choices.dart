import 'dart:convert';

import '../../db/database.dart';

/// The key the symbol pack choices are kept under.
const symbolChoicesKey = 'symbolChoices';

/// Which picture sets a person has deliberately switched on or off.
///
/// Keyed by set slug, and by nothing else. Packs are not switched: a pack is
/// how pictures arrive and a set is whose drawings they are, and two packs can
/// serve one set — Stellar ships inside `core` and is also fetched — so an
/// answer stored against a pack would govern half a set.
///
/// Device-scoped rather than per profile, and stored in `app_state` beside the
/// caregiver gesture and the device id. Which picture sets this tablet may
/// fetch is a fact about the tablet and about who is answerable for it, not
/// about the person speaking on it, and two profiles on one device cannot
/// sensibly disagree about it.
///
/// **Only deliberate answers are written here.** A set nobody has decided
/// about is absent, and [SymbolRegistry.isSetEnabled] falls back to its
/// license. That is what lets a set added in a later release arrive with the
/// correct default instead of inheriting a saved map that predates it: a
/// noncommercial set shipped tomorrow is off tomorrow, and a CC BY-SA one
/// shipped beside it is on, without anybody having to migrate anything.
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
