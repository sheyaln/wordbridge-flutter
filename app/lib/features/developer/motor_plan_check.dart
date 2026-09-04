import 'dart:convert';

import 'package:drift/drift.dart' show innerJoin;

import '../../db/database.dart';
import '../../db/ids.dart';

/// A word's motor path: the board it lives on and the location within it.
///
/// Two paths compare equal only if the finger movement is identical, which is
/// what the whole product rests on.
typedef MotorPath = ({String boardId, int row, int col});

/// One word, and where it was against where it is.
typedef MotorPlanMove = ({String label, MotorPath was, MotorPath now});

/// Every word's location across a board set, keyed by button.
///
/// Keyed by button id rather than by label because a label is not unique —
/// home, back and the paging keys sit on every board — and because the id is
/// what survives the operations this exists to watch: a top-up, an import, a
/// hide, a pin, a row move. A rebuild replaces every button, so it reads as
/// every word leaving and a different set arriving, which is the honest
/// account of what a rebuild does.
///
/// Hidden words are included deliberately, for the reason the invariant test
/// includes them: a word masked today has to reappear at the same location
/// when it is revealed months later, so its position is part of the contract
/// while it is invisible.
Future<Map<String, ({MotorPath path, String label})>> motorPlanOf(
  WordbridgeDatabase db,
  String vocabularyId,
) async {
  final rows = await (db.select(db.buttons).join([
    innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
  ])..where(db.buttons.vocabularyId.equals(vocabularyId))).get();

  return {
    for (final row in rows)
      row.readTable(db.buttons).id: (
        path: (
          boardId: row.readTable(db.cells).boardId,
          row: row.readTable(db.cells).row,
          col: row.readTable(db.cells).col,
        ),
        label: row.readTable(db.buttons).label,
      ),
  };
}

/// What has happened to a board set since a fingerprint was taken.
///
/// [moved] is the one that matters and the only one that is a fault. Words
/// arriving and words being removed are things a caregiver does on purpose;
/// a word that is somewhere else is the invariant broken, and there is no
/// screen in the app that would otherwise say so.
class MotorPlanCheck {
  const MotorPlanCheck({
    required this.moved,
    required this.added,
    required this.removed,
    required this.unchanged,
  });

  final List<MotorPlanMove> moved;
  final List<String> added;
  final List<String> removed;
  final int unchanged;

  bool get holds => moved.isEmpty;
}

/// Compares a stored fingerprint against the board set as it stands.
///
/// Sorted by label so two runs over the same database report in the same
/// order, which is what makes a difference between two runs a difference in
/// the boards rather than in the iteration.
MotorPlanCheck compareMotorPlans(
  Map<String, ({MotorPath path, String label})> before,
  Map<String, ({MotorPath path, String label})> after,
) {
  final moved = <MotorPlanMove>[];
  final removed = <String>[];
  var unchanged = 0;

  for (final entry in before.entries) {
    final now = after[entry.key];
    if (now == null) {
      removed.add(entry.value.label);
      continue;
    }
    if (now.path == entry.value.path) {
      unchanged++;
      continue;
    }
    moved.add((label: now.label, was: entry.value.path, now: now.path));
  }

  final added = [
    for (final entry in after.entries)
      if (!before.containsKey(entry.key)) entry.value.label,
  ];

  int byLabel(MotorPlanMove a, MotorPlanMove b) => a.label.compareTo(b.label);

  return MotorPlanCheck(
    moved: moved..sort(byLabel),
    added: added..sort(),
    removed: removed..sort(),
    unchanged: unchanged,
  );
}

/// A fingerprint somebody took, and when.
typedef MotorPlanFingerprint = ({
  String vocabularyId,
  DateTime takenAt,
  Map<String, ({MotorPath path, String label})> plan,
});

/// Where a fingerprint is kept between runs.
///
/// Device scoped, in `app_state`, for the reason developer mode itself is:
/// this is a measurement of a tablet, taken on that tablet, and it has to
/// survive the launch that follows whatever it is being used to investigate.
/// One fingerprint at a time — a history of them would be a second thing to
/// choose between before the question can be asked.
class MotorPlanStore {
  const MotorPlanStore(this._db);

  final WordbridgeDatabase _db;

  static const key = 'developerMotorPlan';

  Future<void> write(
    String vocabularyId,
    Map<String, ({MotorPath path, String label})> plan,
  ) => _db
      .into(_db.appState)
      .insertOnConflictUpdate(
        AppStateCompanion.insert(
          key: key,
          value: jsonEncode({
            'vocabularyId': vocabularyId,
            'takenAt': nowMs(),
            'plan': {
              for (final entry in plan.entries)
                entry.key: [
                  entry.value.path.boardId,
                  entry.value.path.row,
                  entry.value.path.col,
                  entry.value.label,
                ],
            },
          }),
        ),
      );

  /// The stored fingerprint, or null where there is none to read.
  ///
  /// A value that will not parse reads as no fingerprint rather than throwing.
  /// The answer to "what does this half written row mean" is that nobody can
  /// know, and the recovery is to take another one, which is one tap.
  Future<MotorPlanFingerprint?> read() async {
    try {
      final row = await (_db.select(
        _db.appState,
      )..where((s) => s.key.equals(key))).getSingleOrNull();
      if (row == null) return null;

      final decoded = jsonDecode(row.value) as Map<String, dynamic>;
      final plan = decoded['plan'] as Map<String, dynamic>;

      return (
        vocabularyId: decoded['vocabularyId'] as String,
        takenAt: DateTime.fromMillisecondsSinceEpoch(decoded['takenAt'] as int),
        plan: {
          for (final entry in plan.entries)
            entry.key: (
              path: (
                boardId: (entry.value as List)[0] as String,
                row: (entry.value as List)[1] as int,
                col: (entry.value as List)[2] as int,
              ),
              label: (entry.value as List)[3] as String,
            ),
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() =>
      (_db.delete(_db.appState)..where((s) => s.key.equals(key))).go();
}
