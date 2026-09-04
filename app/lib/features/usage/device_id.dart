import '../../db/database.dart';
import '../../db/ids.dart';

/// The key the device's id is kept under.
const deviceIdKey = 'deviceId';

/// The id this tablet logs under, made once and kept.
///
/// It used to be a fresh `newId()` at every launch, which is the same as having
/// none. `usage_events.device_id` exists so that a profile carried between a
/// tablet at home and one at school can be told apart afterwards (§7), and a
/// column with a new value every morning answers that question with the number
/// of times the app has been opened.
///
/// Device-scoped rather than per profile, and stored in `app_state` beside the
/// caregiver gesture for the same reason: which tablet this is is not a fact
/// about the person speaking on it.
///
/// It is an opaque id and nothing else. It is not derived from anything the
/// platform knows about the hardware or its owner, which matters because it
/// travels: a backup carries the usage log, and a backup is copied to the
/// family's own iCloud or Google account where they have asked for that. What
/// identifies the tablet has to be as uninteresting as possible wherever the
/// file ends up.
Future<String> deviceIdFor(WordbridgeDatabase db) async {
  final stored = await _stored(db);
  if (stored != null) return stored;

  final made = newId();
  await db
      .into(db.appState)
      .insertOnConflictUpdate(
        AppStateCompanion.insert(key: deviceIdKey, value: made),
      );
  return made;
}

Future<String?> _stored(WordbridgeDatabase db) async {
  final row = await (db.select(
    db.appState,
  )..where((s) => s.key.equals(deviceIdKey))).getSingleOrNull();
  return row?.value;
}
