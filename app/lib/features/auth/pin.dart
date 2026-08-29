import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../db/database.dart';
import '../../db/ids.dart';

/// Somewhere to keep a secret that is not the database.
///
/// Exists so the PIN salt can be stored in the platform keystore in
/// production and in memory under test, without tests having to subclass a
/// package whose method signatures change between versions.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Hardware-backed storage: Keychain on Apple platforms, Keystore on Android.
class KeychainSecretStore implements SecretStore {
  const KeychainSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Caregiver PIN.
///
/// The salt lives in the platform keystore rather than the database, so
/// someone who copies `wordbridge.db` off the device still cannot brute-force
/// the PIN offline.
///
/// The threat model is deliberately modest: this keeps an AAC user — and
/// their curious sibling — out of the editor, where a careless drag can undo
/// months of learned positions. It is not protection against a determined
/// adult with the unlocked device.
class PinAuth {
  PinAuth(this._db, {SecretStore? storage})
    : _storage = storage ?? const KeychainSecretStore();

  final WordbridgeDatabase _db;
  final SecretStore _storage;

  static const _saltKey = 'wordbridge.pin.salt';
  static const _row = 'caregiver';

  /// Device-wide rather than a row in `edit_events`: that log answers "what
  /// changed on the board", and every row of it is anchored to a vocabulary
  /// and read back by the editor's undo. A credential belongs to the device,
  /// touches no cell, and must not sit at the head of that queue.
  static const _resetAtKey = 'caregiverPinResetAt';

  static const maxAttempts = 5;
  static const _lockout = Duration(minutes: 5);

  Future<bool> isConfigured() async {
    final row = await _row_();
    return row != null;
  }

  Future<CaregiverAuthData?> _row_() => (_db.select(
    _db.caregiverAuth,
  )..where((r) => r.id.equals(_row))).getSingleOrNull();

  Future<String> _salt() async {
    final existing = await _storage.read(_saltKey);
    if (existing != null) return existing;

    final rng = Random.secure();
    final salt = base64Url.encode(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    await _storage.write(_saltKey, salt);
    return salt;
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt|$pin')).toString();

  Future<void> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) {
      throw ArgumentError('PIN must be 4-6 digits');
    }

    final hash = _hash(pin, await _salt());
    final ts = nowMs();

    await _db
        .into(_db.caregiverAuth)
        .insertOnConflictUpdate(
          CaregiverAuthCompanion.insert(
            id: _row,
            pinHash: hash,
            failedAttempts: const Value(0),
            lockedUntil: const Value(null),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
  }

  /// Clears the caregiver credential, and nothing else.
  ///
  /// A forgotten PIN costs the PIN. The board, the vocabulary, the profiles
  /// and the usage log are none of this credential's business, and recovering
  /// it never touches them: a recovery path that costs the motor plan is worse
  /// than the lockout it fixes.
  ///
  /// Dropping the row takes the failure count and any lockout with it. That
  /// gives nobody a shortcut — there is no longer a PIN to guess, and
  /// caregiver mode stays shut until a new one is set. The salt stays where it
  /// is; rotating it would reach into the keystore for no gain against a
  /// threat model that already assumes whoever holds the device can read it.
  Future<void> reset() async {
    final ts = nowMs();

    await _db.transaction(() async {
      await (_db.delete(
        _db.caregiverAuth,
      )..where((r) => r.id.equals(_row))).go();

      await _db
          .into(_db.appState)
          .insertOnConflictUpdate(
            AppStateCompanion.insert(key: _resetAtKey, value: '$ts'),
          );
    });
  }

  /// When the PIN was last cleared through recovery, or null if it never was.
  ///
  /// Recorded because the person who resets the PIN is often not the only
  /// person who uses it. A second parent or a school SLP learns that it
  /// happened at their next unlock rather than by finding the PIN changed.
  Future<DateTime?> lastResetAt() async {
    final row = await (_db.select(
      _db.appState,
    )..where((s) => s.key.equals(_resetAtKey))).getSingleOrNull();

    final ms = int.tryParse(row?.value ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Remaining lockout, or null if unlocked.
  Future<Duration?> lockoutRemaining() async {
    final row = await _row_();
    final until = row?.lockedUntil;
    if (until == null) return null;

    final remaining = until - nowMs();
    return remaining > 0 ? Duration(milliseconds: remaining) : null;
  }

  Future<bool> verify(String pin) async {
    final row = await _row_();
    if (row == null) return false;

    if (await lockoutRemaining() != null) return false;

    if (_hash(pin, await _salt()) == row.pinHash) {
      await (_db.update(
        _db.caregiverAuth,
      )..where((r) => r.id.equals(_row))).write(
        CaregiverAuthCompanion(
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
          updatedAt: Value(nowMs()),
        ),
      );
      return true;
    }

    // Exponential-ish backoff: a fixed lockout after a handful of misses is
    // enough friction for the actual threat without stranding a caregiver who
    // fat-fingered it.
    final attempts = row.failedAttempts + 1;
    await (_db.update(
      _db.caregiverAuth,
    )..where((r) => r.id.equals(_row))).write(
      CaregiverAuthCompanion(
        failedAttempts: Value(attempts),
        lockedUntil: Value(
          attempts >= maxAttempts ? nowMs() + _lockout.inMilliseconds : null,
        ),
        updatedAt: Value(nowMs()),
      ),
    );
    return false;
  }
}
