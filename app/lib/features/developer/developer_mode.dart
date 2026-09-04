import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../db/database.dart';

/// The key the developer switches are kept under.
const developerModeKey = 'developerMode';

/// Whether this tablet is a development tablet, and what that draws.
///
/// **Device scoped, in `app_state` beside the caregiver gesture.** Which
/// tablet is on somebody's desk with a debugger attached is a fact about the
/// tablet, not about the person speaking on it, and two profiles on one device
/// cannot sensibly disagree about it. Put in a profile's settings it would
/// also mean that switching profile to reproduce a fault lost the mode at the
/// moment it was wanted.
///
/// **Persisted, unlike caregiver mode.** Caregiver mode is a door held open
/// for as long as somebody is standing in it, so a crash landing locked is the
/// correct outcome. This is not a door: it is a property of the device, and
/// the session it most needs to survive is the one that just ended in the
/// crash being investigated. A mode that switched itself off every time the
/// app died would be off exactly when it is wanted.
///
/// What makes that safe is the same thing that makes view-all safe: the board
/// says so while it is on, in a strip that cannot be missed, and the one
/// control on that strip turns it off. So the only visible button this adds to
/// the talk screen — the one an AAC user will certainly find — is the button
/// that puts the board back.
class DeveloperMode extends ChangeNotifier {
  DeveloperMode(this._db);

  final WordbridgeDatabase _db;

  Map<String, dynamic> _values = const {};

  /// How long a location is held before it opens.
  ///
  /// Longer than a platform long press. This sits over a board somebody
  /// speaks on, and a hold short enough to be produced by a slow or an
  /// imprecise press would put a sheet in front of a word they were saying.
  static const hold = Duration(milliseconds: 1200);

  bool get enabled => _values['on'] as bool? ?? false;

  /// Row and column on every location, as the database numbers them.
  ///
  /// On by default among the overlays, because it is the one that answers the
  /// question this app is about: where a word is.
  bool get coordinates => _values['coordinates'] as bool? ?? true;

  /// Why a location is drawing nothing.
  bool get cellState => _values['cellState'] as bool? ?? false;

  /// Whether a picture was chosen for this button or matched from its word.
  bool get pictureSource => _values['pictureSource'] as bool? ?? false;

  /// Whether holding a location opens what is behind it.
  bool get holdToInspect => _values['holdToInspect'] as bool? ?? true;

  /// What the board should draw, or null where it should draw nothing extra.
  ///
  /// Null rather than a view with every field false, so a board with developer
  /// mode off is handed nothing at all and cannot be one wrong condition away
  /// from drawing debug chrome in front of somebody who is talking.
  DeveloperView? get view => enabled
      ? DeveloperView(
          coordinates: coordinates,
          cellState: cellState,
          pictureSource: pictureSource,
          hold: holdToInspect ? hold : null,
        )
      : null;

  /// Reads the stored switches.
  ///
  /// Never throws and never refuses. This is on the path to the talk screen,
  /// and a device that will not open its board because a settings row will not
  /// parse is a device that has stopped talking. An unreadable value is read
  /// as "developer mode has never been switched on", which is the safe answer
  /// and the true one on every tablet but a handful.
  Future<void> load() async {
    try {
      final row = await (_db.select(
        _db.appState,
      )..where((s) => s.key.equals(developerModeKey))).getSingleOrNull();

      final decoded = row == null ? null : jsonDecode(row.value);
      _values = decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      _values = const {};
    }
    notifyListeners();
  }

  Future<void> set(String key, bool value) async {
    _values = {..._values, key: value};
    notifyListeners();

    await _db
        .into(_db.appState)
        .insertOnConflictUpdate(
          AppStateCompanion.insert(
            key: developerModeKey,
            value: jsonEncode(_values),
          ),
        );
  }

  Future<void> setEnabled(bool on) => set('on', on);
}

/// What the board draws over itself, and what a held location offers.
///
/// A value rather than a live object, so nothing on the board holds a listener
/// on the switches or reads them while it is painting.
class DeveloperView {
  const DeveloperView({
    this.coordinates = false,
    this.cellState = false,
    this.pictureSource = false,
    this.hold,
  });

  final bool coordinates;
  final bool cellState;
  final bool pictureSource;

  /// How long a location is held to open it, or null where holding does
  /// nothing.
  final Duration? hold;

  /// Whether anything is drawn over the grid at all.
  bool get drawsNothing => !coordinates && !cellState && !pictureSource;

  @override
  bool operator ==(Object other) =>
      other is DeveloperView &&
      other.coordinates == coordinates &&
      other.cellState == cellState &&
      other.pictureSource == pictureSource &&
      other.hold == hold;

  @override
  int get hashCode => Object.hash(coordinates, cellState, pictureSource, hold);
}
