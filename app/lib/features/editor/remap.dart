import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';
import '../usage/usage_queries.dart';

/// What moving a word would cost, in the user's own recorded practice.
///
/// [windowDays] is how far back the counts look, and travels with them so
/// anything displaying them can say so.
typedef RemapImpact = ({
  String label,
  int taps,
  int days,
  DateTime? firstUsed,
  bool isLearned,
  int windowDays,
});

/// Moving and placing words, with the cost of moving stated before it happens.
///
/// The distinction this class exists to enforce:
///
/// - **Additive** — attaching a word to a location nothing has ever occupied.
///   Free, silent, no ceremony.
/// - **Displacing** — moving a word that already has a home. Possible, because
///   sometimes it is genuinely the right call, but never quiet.
class RemapService {
  RemapService(this._db) : _usage = UsageQueries(_db);

  final WordbridgeDatabase _db;
  final UsageQueries _usage;

  /// Above this many recorded selections, treat the position as learned.
  ///
  /// Arbitrary, and deliberately low. The cost of over-warning is a caregiver
  /// reading one extra sentence; the cost of under-warning is a user reaching
  /// for a word that is no longer there.
  static const learnedThreshold = 20;

  /// How far back a single word's move looks.
  ///
  /// Recent practice, not everything ever recorded, because the question here
  /// is whether *this* position is live. A spot drilled two years ago and
  /// untouched since is not a motor plan a move destroys, and counting it would
  /// talk a caregiver out of a correction the user needs. Roughly a school
  /// term.
  ///
  /// A grid rebuild asks a different question and uses a different window; see
  /// `GridMigration`.
  static const practiceWindow = UsageWindow.rollingDays(90);

  /// What a user has practised at this location.
  Future<RemapImpact> impactOfMoving(String buttonId) async {
    final button = await (_db.select(
      _db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingle();

    if (button.cellId == null) {
      return (
        label: button.label,
        taps: 0,
        days: 0,
        firstUsed: null,
        isLearned: false,
        windowDays: practiceWindow.days,
      );
    }

    final history = await _usage.historyForCell(
      button.cellId!,
      window: practiceWindow,
    );
    return (
      label: button.label,
      taps: history.taps,
      days: history.days,
      firstUsed: history.firstUsed,
      isLearned: history.taps >= learnedThreshold,
      windowDays: practiceWindow.days,
    );
  }

  /// Plain-language warning, or null when the move is genuinely harmless.
  ///
  /// Written to be read aloud to a parent who is not a clinician: what
  /// changes, what it may cost, in their child's own numbers.
  Future<String?> warningFor(String buttonId, {String? userName}) async {
    final impact = await impactOfMoving(buttonId);
    if (impact.taps == 0) return null;

    final who = userName ?? 'This user';
    final word = '"${impact.label}"';

    if (!impact.isLearned) {
      return '$who has used $word from this spot ${impact.taps} '
          '${impact.taps == 1 ? 'time' : 'times'} in the last '
          '${impact.windowDays} days. Moving it is probably low risk, but the '
          'pattern will change.';
    }

    return 'Moving $word will change its motor pattern. '
        '$who has tapped this location ${impact.taps} times across '
        '${impact.days} ${impact.days == 1 ? 'day' : 'days'} in the last '
        '${impact.windowDays} days. If they have learned this position, moving '
        'it may take weeks to relearn.';
  }

  /// Moves a word to a different location.
  ///
  /// Performed as a three-step swap through a null `cellId`, because the
  /// partial unique index permits at most one button per occupied location and
  /// SQLite checks it per statement rather than at commit.
  ///
  /// Callers are expected to have shown [warningFor] first. Nothing here
  /// enforces that — a service that silently refused would just be worked
  /// around — but every move is recorded in `edit_events` with the tap count
  /// it cost, so the decision is always attributable afterwards.
  Future<void> moveButton({
    required String buttonId,
    required String toCellId,
    String? profileId,
  }) async {
    final impact = await impactOfMoving(buttonId);

    await _db.transaction(() async {
      final button = await (_db.select(
        _db.buttons,
      )..where((b) => b.id.equals(buttonId))).getSingle();
      final target = await (_db.select(
        _db.cells,
      )..where((c) => c.id.equals(toCellId))).getSingle();

      if (target.state == CellState.occupied) {
        throw StateError(
          'Location ${target.row},${target.col} already holds a word. Move '
          'that one out first rather than overwriting it.',
        );
      }

      final fromCellId = button.cellId;
      final ts = nowMs();

      await (_db.update(
        _db.buttons,
      )..where((b) => b.id.equals(buttonId))).write(
        ButtonsCompanion(cellId: const Value(null), updatedAt: Value(ts)),
      );

      if (fromCellId != null) {
        await (_db.update(_db.cells)..where((c) => c.id.equals(fromCellId)))
            .write(const CellsCompanion(state: Value(CellState.emptyReserved)));
      }

      await (_db.update(
        _db.buttons,
      )..where((b) => b.id.equals(buttonId))).write(
        ButtonsCompanion(cellId: Value(toCellId), updatedAt: Value(ts)),
      );

      await (_db.update(_db.cells)..where((c) => c.id.equals(toCellId))).write(
        const CellsCompanion(state: Value(CellState.occupied)),
      );

      await _db
          .into(_db.editEvents)
          .insert(
            EditEventsCompanion.insert(
              id: newId(),
              profileId: Value(profileId),
              vocabularyId: button.vocabularyId,
              cellId: Value(fromCellId),
              buttonId: Value(buttonId),
              kind: EditKind.remap,
              beforeJson: Value(jsonEncode({'cellId': fromCellId})),
              afterJson: Value(jsonEncode({'cellId': toCellId})),
              motorImpactTaps: Value(impact.taps),
              changedAt: ts,
            ),
          );
    });
  }

  /// Reverses the most recent edit.
  ///
  /// A caregiver who has just been told a move costs 341 taps of practice
  /// needs to be able to take it back in one tap, not reconstruct it by hand.
  Future<bool> undoLast(String vocabularyId) async {
    final last =
        await (_db.select(_db.editEvents)
              ..where((e) => e.vocabularyId.equals(vocabularyId))
              ..orderBy([(e) => OrderingTerm.desc(e.changedAt)])
              ..limit(1))
            .getSingleOrNull();

    if (last == null || last.kind != EditKind.remap) return false;

    final before = jsonDecode(last.beforeJson ?? '{}') as Map<String, dynamic>;
    final originalCellId = before['cellId'] as String?;
    if (originalCellId == null || last.buttonId == null) return false;

    await moveButton(
      buttonId: last.buttonId!,
      toCellId: originalCellId,
      profileId: last.profileId,
    );

    await (_db.delete(_db.editEvents)..where((e) => e.id.equals(last.id))).go();
    return true;
  }

  /// Hides a word. The location stays occupied, so nothing takes its place.
  ///
  /// Refused for the keys every board carries. Hiding an ordinary word takes it
  /// off the board and holds its location; hiding `home` takes away the way off
  /// the board, from somebody who cannot report that it happened. Their
  /// pictures stay editable — what a key looks like costs nothing, and helping
  /// somebody find it is the whole point.
  Future<void> setHidden({
    required String buttonId,
    required bool hidden,
    String? profileId,
  }) async {
    final button = await (_db.select(
      _db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingle();

    if (button.isSystem && hidden) {
      throw StateError(
        '"${button.label}" is one of the keys every board carries. Hidden, it '
        'would leave a board nobody can get off.',
      );
    }

    final ts = nowMs();

    await _db.transaction(() async {
      await (_db.update(_db.buttons)..where((b) => b.id.equals(buttonId)))
          .write(ButtonsCompanion(hidden: Value(hidden), updatedAt: Value(ts)));

      await _db
          .into(_db.editEvents)
          .insert(
            EditEventsCompanion.insert(
              id: newId(),
              profileId: Value(profileId),
              vocabularyId: button.vocabularyId,
              cellId: Value(button.cellId),
              buttonId: Value(buttonId),
              kind: hidden ? EditKind.hide : EditKind.unhide,
              changedAt: ts,
            ),
          );
    });
  }

  /// Removes a word and gives its location back.
  ///
  /// This is what separates deleting from hiding, and it is the whole cost:
  /// hiding keeps the cell occupied so nothing can take it, and deleting
  /// releases it. Whatever is put there next is reached by the movement this
  /// word had, from a user who has no way to say the board answered with
  /// something they did not mean.
  ///
  /// The row is kept and dated rather than dropped. `usage_events` refers to
  /// the location rather than to the word, and `edit_events` refers to both, so
  /// a hard delete would leave a history nothing could resolve — and would take
  /// the undo with it.
  Future<void> deleteButton({
    required String buttonId,
    String? profileId,
  }) async {
    final impact = await impactOfMoving(buttonId);

    await _db.transaction(() async {
      final button = await (_db.select(
        _db.buttons,
      )..where((b) => b.id.equals(buttonId))).getSingle();

      if (button.isSystem) {
        throw StateError(
          '"${button.label}" is one of the keys every board carries. Removing '
          'it would leave a board that cannot be navigated.',
        );
      }

      final ts = nowMs();
      final fromCellId = button.cellId;

      await (_db.update(
        _db.buttons,
      )..where((b) => b.id.equals(buttonId))).write(
        ButtonsCompanion(
          cellId: const Value(null),
          deletedAt: Value(ts),
          updatedAt: Value(ts),
        ),
      );

      if (fromCellId != null) {
        await (_db.update(_db.cells)..where((c) => c.id.equals(fromCellId)))
            .write(const CellsCompanion(state: Value(CellState.emptyReserved)));
      }

      await _db
          .into(_db.editEvents)
          .insert(
            EditEventsCompanion.insert(
              id: newId(),
              profileId: Value(profileId),
              vocabularyId: button.vocabularyId,
              cellId: Value(fromCellId),
              buttonId: Value(buttonId),
              kind: EditKind.delete,
              beforeJson: Value(
                jsonEncode({'cellId': fromCellId, 'label': button.label}),
              ),
              motorImpactTaps: Value(impact.taps),
              changedAt: ts,
            ),
          );
    });
  }

  /// Puts a deleted word back where it was.
  ///
  /// Refuses rather than guesses when something has taken the location since.
  /// Putting the word somewhere else would be a move nobody asked for, and the
  /// caregiver undoing a delete is trying to get back to what they had.
  Future<bool> restoreButton(String buttonId) async {
    return _db.transaction(() async {
      final button = await (_db.select(
        _db.buttons,
      )..where((b) => b.id.equals(buttonId))).getSingleOrNull();
      if (button == null || button.deletedAt == null) return false;

      final event =
          await (_db.select(_db.editEvents)
                ..where(
                  (e) =>
                      e.buttonId.equals(buttonId) &
                      e.kind.equalsValue(EditKind.delete),
                )
                ..orderBy([(e) => OrderingTerm.desc(e.changedAt)])
                ..limit(1))
              .getSingleOrNull();

      final before =
          jsonDecode(event?.beforeJson ?? '{}') as Map<String, dynamic>;
      final cellId = before['cellId'] as String?;
      if (cellId == null) return false;

      final cell = await (_db.select(
        _db.cells,
      )..where((c) => c.id.equals(cellId))).getSingleOrNull();
      if (cell == null || cell.state == CellState.occupied) return false;

      final ts = nowMs();
      await (_db.update(
        _db.buttons,
      )..where((b) => b.id.equals(buttonId))).write(
        ButtonsCompanion(
          cellId: Value(cellId),
          deletedAt: const Value(null),
          updatedAt: Value(ts),
        ),
      );
      await (_db.update(_db.cells)..where((c) => c.id.equals(cellId))).write(
        const CellsCompanion(state: Value(CellState.occupied)),
      );

      if (event != null) {
        await (_db.delete(
          _db.editEvents,
        )..where((e) => e.id.equals(event.id))).go();
      }
      return true;
    });
  }
}
