import '../../db/database.dart';

/// A way of asking for caregiver mode.
///
/// Not a security boundary — the PIN behind it is that, as far as it goes.
/// This is the part that has to be impossible to produce by accident, on a
/// screen whose user explores it with their hands and cannot report a control
/// they triggered without meaning to.
enum CaregiverGesture {
  cornerHold(
    'One corner, held',
    'Press and hold the top-left corner of the sentence bar. Nothing is drawn '
        'until the hold is already underway, so there is nothing inviting '
        'anyone to try it.',
  ),
  twoCorners(
    'Both bottom corners, held together',
    'Press and hold the bottom-left and bottom-right locations of the board at '
        'the same time — home and the “more words” key. A hand resting on the '
        'tablet cannot produce two contacts that far apart.',
  );

  const CaregiverGesture(this.label, this.description);

  final String label;
  final String description;
}

/// Which gesture opens caregiver mode on this device, and how long it is held.
///
/// A fact about who is holding the tablet rather than about the person
/// speaking on it, which is why it belongs to the device and not to a profile.
/// Four profiles with four different gestures would be four gestures nobody
/// can rely on.
class CaregiverEntry {
  const CaregiverEntry({required this.gesture, required this.hold});

  const CaregiverEntry.standard()
    : gesture = CaregiverGesture.cornerHold,
      hold = defaultCornerHold;

  /// Long enough to be deliberate on a target nothing advertises.
  static const defaultCornerHold = Duration(seconds: 2);

  /// Longer, because two hands are already committed to it and the cost of
  /// waiting is lower than the cost of a caregiver believing it failed.
  static const defaultPairHold = Duration(seconds: 5);

  /// The one-point hold when it is not the chosen gesture.
  ///
  /// Choosing the two-corner hold adds a second door; it never closes this
  /// one. Anyone with one hand, a stylus or a head pointer has to be able to
  /// reach caregiver mode on a device somebody else set up — and the PIN is no
  /// way back in, because it lives behind whatever gesture is chosen.
  ///
  /// Fifteen seconds is what separates the two cases this has to tell apart.
  /// Nobody exploring a grid, and no hand resting on a tablet, holds one point
  /// unbroken for that long; a caregiver who was told one sentence always can.
  /// It is meant to be worse than the gesture it backs up. That is the trade —
  /// the fast door is the one you choose, the slow one is the one that cannot
  /// be taken away.
  static const oneHandedFallback = Duration(seconds: 15);

  /// A hold of zero is a tap, and a tap is what this exists to not be.
  static const minimumHold = Duration(seconds: 1);

  final CaregiverGesture gesture;

  /// How long the chosen gesture is held for.
  final Duration hold;

  /// The one-point hold, which is always available.
  Duration get cornerHold =>
      gesture == CaregiverGesture.cornerHold ? hold : oneHandedFallback;

  /// The two-point hold, or null where it is not armed.
  Duration? get pairHold =>
      gesture == CaregiverGesture.twoCorners ? hold : null;

  CaregiverEntry withGesture(CaregiverGesture gesture) => CaregiverEntry(
    gesture: gesture,
    // The two gestures want different durations, and a caregiver who switches
    // between them is choosing a gesture, not carrying a number across.
    hold: gesture == CaregiverGesture.cornerHold
        ? defaultCornerHold
        : defaultPairHold,
  );

  CaregiverEntry withHold(Duration hold) => CaregiverEntry(
    gesture: gesture,
    hold: hold < minimumHold ? minimumHold : hold,
  );

  @override
  bool operator ==(Object other) =>
      other is CaregiverEntry && other.gesture == gesture && other.hold == hold;

  @override
  int get hashCode => Object.hash(gesture, hold);

  @override
  String toString() => 'CaregiverEntry(${gesture.name}, ${hold.inSeconds}s)';
}

/// Reads and writes the device's choice.
class CaregiverEntryStore {
  const CaregiverEntryStore(this._db);

  final WordbridgeDatabase _db;

  static const gestureKey = 'caregiverGesture';
  static const holdSecondsKey = 'caregiverGestureSeconds';

  Future<String?> _value(String key) async {
    final row = await (_db.select(
      _db.appState,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// The stored choice, or the standard one where nothing has been chosen.
  ///
  /// An unreadable value falls back rather than throwing: this sits on the
  /// path to the only door into settings, and a device that cannot open its
  /// own settings because of a bad row cannot be fixed from inside them.
  Future<CaregiverEntry> read() async {
    final name = await _value(gestureKey);
    if (name == null) return const CaregiverEntry.standard();

    final gesture = CaregiverGesture.values
        .where((g) => g.name == name)
        .firstOrNull;
    if (gesture == null) return const CaregiverEntry.standard();

    final seconds = int.tryParse(await _value(holdSecondsKey) ?? '');
    final base = const CaregiverEntry.standard().withGesture(gesture);
    return seconds == null ? base : base.withHold(Duration(seconds: seconds));
  }

  Future<void> write(CaregiverEntry entry) async {
    final held = entry.hold < CaregiverEntry.minimumHold
        ? CaregiverEntry.minimumHold
        : entry.hold;

    await _db.transaction(() async {
      await _db
          .into(_db.appState)
          .insertOnConflictUpdate(
            AppStateCompanion.insert(
              key: gestureKey,
              value: entry.gesture.name,
            ),
          );
      await _db
          .into(_db.appState)
          .insertOnConflictUpdate(
            AppStateCompanion.insert(
              key: holdSecondsKey,
              value: '${held.inSeconds}',
            ),
          );
    });
  }
}
