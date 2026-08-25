import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../db/database.dart';
import '../../db/ids.dart';

/// Per-user preferences, held in the profile row.
///
/// Kept as JSON rather than columns because these are settings, not data: they
/// accumulate, they are read together, and adding one should not be a schema
/// migration on a device someone depends on.
class ProfileSettings extends ChangeNotifier {
  ProfileSettings(this._db, this.profileId);

  final WordbridgeDatabase _db;
  final String profileId;

  Map<String, dynamic> _values = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Show word endings only where they can actually be used.
  ///
  /// On by default. A key that does nothing when pressed is one a user learns
  /// to distrust, and there is no way for them to know why it failed. Some
  /// teams prefer every key visible at all times so the board never changes
  /// shape, which is why this is a setting and not a rule.
  bool get contextualGrammar => _values['contextualGrammar'] as bool? ?? true;

  /// Return to the root board after speaking, so every word costs the same
  /// number of movements every time.
  bool get autoReturn => _values['autoReturn'] as bool? ?? true;

  Future<void> load() async {
    final row = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(profileId))).getSingleOrNull();

    if (row != null) {
      try {
        _values = Map<String, dynamic>.from(
          jsonDecode(row.settingsJson) as Map,
        );
      } catch (_) {
        _values = {};
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> set(String key, Object? value) async {
    _values = {..._values, key: value};
    notifyListeners();

    final ts = nowMs();
    await _db
        .into(_db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: 'default',
            settingsJson: Value(jsonEncode(_values)),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
  }
}
