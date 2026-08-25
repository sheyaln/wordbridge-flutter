import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../db/database.dart';
import '../../db/ids.dart';

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
  PinAuth(this._db, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final WordbridgeDatabase _db;
  final FlutterSecureStorage _storage;

  static const _saltKey = 'wordbridge.pin.salt';
  static const _row = 'caregiver';

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
    final existing = await _storage.read(key: _saltKey);
    if (existing != null) return existing;

    final rng = Random.secure();
    final salt = base64Url.encode(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    await _storage.write(key: _saltKey, value: salt);
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
