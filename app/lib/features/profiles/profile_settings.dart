import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import 'grid_choice.dart';

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

  /// Hide other verbs once a verb has been chosen, until something licenses
  /// another one.
  ///
  /// Off by default. It removes clutter mid-sentence at the cost of a board
  /// that changes shape while you use it.
  bool get filterVerbs => _values['filterVerbs'] as bool? ?? false;

  /// Return to the root board after speaking, so every word costs the same
  /// number of movements every time.
  ///
  /// On by default, because it is what makes a word's motor path fixed rather
  /// than dependent on where the user happened to be. Off suits someone
  /// building longer utterances out of one category, who would otherwise pay
  /// the navigation cost again for every word.
  bool get autoReturn => _values['autoReturn'] as bool? ?? true;

  /// How long the board ignores taps after it changes.
  ///
  /// A user moving at speed through a learned sequence has their finger coming
  /// down before the new board has finished arriving, and lands on whatever
  /// now occupies that location — a word they did not mean, in a sentence they
  /// cannot easily repair.
  ///
  /// This is the one place something deliberately stands between a user and
  /// speech, so it is short, adjustable, and can be switched off entirely by
  /// setting it to zero.
  Duration get settleDelay =>
      Duration(milliseconds: _values['settleDelayMs'] as int? ?? 500);

  /// The two answers the grid was derived from.
  ///
  /// Stored so the settings screen can show what was chosen rather than only
  /// its consequence, and so changing one can be recognised as the deliberate,
  /// expensive act it is. Nothing reads these to lay a board out — the board
  /// was laid out once, when the profile was made.
  BoardOrientation get orientation =>
      _enum('orientation', BoardOrientation.values, BoardOrientation.landscape);

  IconSize get iconSize => _enum('iconSize', IconSize.values, IconSize.medium);

  /// Whether strong language is revealed on the boards that carry it.
  ///
  /// The words are already placed either way; this only draws them. Turning it
  /// off hides them in place, so turning it back on puts them exactly where
  /// they were.
  bool get profanity => _values['profanity'] as bool? ?? false;

  T _enum<T extends Enum>(String key, List<T> values, T fallback) {
    final stored = _values[key];
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }

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

    // An update, never an upsert. Writing a setting must not be able to
    // overwrite a profile's name or unpick which vocabulary it points at.
    final written =
        await (_db.update(
          _db.profiles,
        )..where((p) => p.id.equals(profileId))).write(
          ProfilesCompanion(
            settingsJson: Value(jsonEncode(_values)),
            updatedAt: Value(nowMs()),
          ),
        );

    // An update against a profile that is not there writes nothing and reports
    // success. Silently losing a caregiver's setting is the single most
    // reported failure of the app this one exists to replace, so it fails
    // loudly rather than pretending to have saved.
    if (written == 0) {
      throw StateError(
        'No profile "$profileId" to save settings to. "$key" was not stored.',
      );
    }
  }
}
