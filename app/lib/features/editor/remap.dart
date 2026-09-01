import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';
import '../usage/usage_queries.dart';
import 'frame_keys.dart';
import 'placement_rules.dart';

/// Names, in an `edit_events` row's `after_json`, the event that row reverses.
///
/// It lives in the JSON rather than in a column of its own because a column is
/// a migration, and undo has to work on the database already sitting on
/// somebody's tablet. It has to live in the database either way: an undo stack
/// held in memory is empty every time the app is reopened, and a caregiver who
/// edited a board at bedtime still expects to be able to take it back at
/// breakfast.
///
/// An event named here is spent, and never reversed again. A row that names one
/// is a reversal rather than an edit, so pressing undo twice steps back two
/// edits instead of undoing the undo.
const _undoOfKey = 'undoOf';

/// The JSON an edit event recorded, or empty when it recorded none.
Map<String, Object?> _payload(String? json) {
  if (json == null) return const {};
  final decoded = jsonDecode(json);
  return decoded is Map<String, Object?> ? decoded : const {};
}

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

/// What came of an attempt to take the last edit back.
///
/// Three outcomes rather than two, because the two that change nothing are
/// different things to say to whoever pressed the button. One means the history
/// is spent; the other means the board has moved on and the location that edit
/// needs belongs to something else now.
enum UndoOutcome {
  /// The board is as it was before that edit.
  undone,

  /// Nothing left to take back.
  nothing,

  /// The edit is still there, and still cannot be reversed: the location it
  /// needs is taken, or it is a kind that a rebuild undoes rather than a step.
  blocked,
}

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

  /// What a user has practiced at this location.
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

      // §4.43. The editor asks before it offers the move, so reaching here
      // means a path that did not — and the row this protects is the one where
      // a stray word costs the guard against a mis-reached "back".
      final vocabulary = await (_db.select(
        _db.vocabularies,
      )..where((v) => v.id.equals(button.vocabularyId))).getSingleOrNull();

      if (!button.isSystem &&
          vocabulary != null &&
          isSystemRow(vocabulary, target.row)) {
        throw StateError(
          'Row ${target.row} is the system row. A word cannot be moved onto '
          'it — see refusalToPlaceAt.',
        );
      }

      final fromCellId = button.cellId;
      final ts = nowMs();

      await _relocate(
        buttonId: buttonId,
        fromCellId: fromCellId,
        toCellId: toCellId,
        ts: ts,
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

  /// Moves a word between locations, or off the board when [toCellId] is null.
  ///
  /// Performed as a three-step swap through a null `cellId`, because the
  /// partial unique index permits at most one button per occupied location and
  /// SQLite checks it per statement rather than at commit.
  Future<void> _relocate({
    required String buttonId,
    required String? fromCellId,
    required String? toCellId,
    required int ts,
  }) async {
    await (_db.update(_db.buttons)..where((b) => b.id.equals(buttonId))).write(
      ButtonsCompanion(cellId: const Value(null), updatedAt: Value(ts)),
    );

    if (fromCellId != null) {
      await (_db.update(_db.cells)..where((c) => c.id.equals(fromCellId)))
          .write(const CellsCompanion(state: Value(CellState.emptyReserved)));
    }

    if (toCellId == null) return;

    await (_db.update(_db.buttons)..where((b) => b.id.equals(buttonId))).write(
      ButtonsCompanion(cellId: Value(toCellId), updatedAt: Value(ts)),
    );
    await (_db.update(_db.cells)..where((c) => c.id.equals(toCellId))).write(
      const CellsCompanion(state: Value(CellState.occupied)),
    );
  }

  /// Reverses the most recent edit that has not been reversed already.
  ///
  /// A caregiver who has just been told a move costs 341 taps of practice needs
  /// to be able to take it back in one tap, not reconstruct it by hand. Pressed
  /// again it steps back another edit, and another: a board is corrected in a
  /// handful of small changes and the wrong one is rarely the last one, so an
  /// undo that only reaches one step back is an undo that arrives too late.
  ///
  /// The two ways it can do nothing are different things to be told, which is
  /// why this reports which. A caregiver whose undo was refused because the
  /// board has moved on has not run out of history; they have hit a location
  /// somebody else now needs, and "nothing to undo" sends them looking for a
  /// history that is still there.
  Future<UndoOutcome> undoLast(String vocabularyId) {
    return _db.transaction(() async {
      // Ordered by the sequence the rows were written in rather than by the
      // clock alone. Two edits made inside the same millisecond are
      // indistinguishable by `changed_at`, and taking them back in the wrong
      // order lands a word at the location it held two edits ago.
      final events =
          await (_db.select(_db.editEvents)
                ..where((e) => e.vocabularyId.equals(vocabularyId))
                ..orderBy([
                  (e) => OrderingTerm.desc(e.changedAt),
                  (e) => OrderingTerm.desc(e.rowId),
                ]))
              .get();

      final trail = [
        for (final event in events) (event, _payload(event.afterJson)),
      ];
      final spent = {
        for (final (_, after) in trail)
          if (after[_undoOfKey] case final String id) id,
      };

      for (final (event, after) in trail) {
        if (after.containsKey(_undoOfKey)) continue;
        if (spent.contains(event.id)) continue;
        return await _reverse(event) ? UndoOutcome.undone : UndoOutcome.blocked;
      }
      return UndoOutcome.nothing;
    });
  }

  /// Records a word having been added, in the terms taking it back needs.
  ///
  /// Both the word and the location, because undo has to know which word to
  /// lift off which cell. A record naming only the location leaves it to work
  /// out which word filled it, and working out where something goes is the one
  /// move this board refuses.
  Future<void> recordCreate({
    required String vocabularyId,
    required String buttonId,
    required String cellId,
  }) => _db
      .into(_db.editEvents)
      .insert(
        EditEventsCompanion.insert(
          id: newId(),
          vocabularyId: vocabularyId,
          cellId: Value(cellId),
          buttonId: Value(buttonId),
          kind: EditKind.create,
          changedAt: nowMs(),
        ),
      );

  /// Applies the reverse of one recorded edit, or reports that it cannot.
  ///
  /// Every branch either completes the reversal and records it, or leaves the
  /// board exactly as it found it. A half-applied undo is the worst outcome
  /// available here: a change nobody asked for, to a board somebody navigates
  /// by muscle memory, made by the control they pressed to get back to where
  /// they were.
  ///
  /// The kinds with no reversal are the ones nothing recorded enough to
  /// reverse. A grid resize rebuilt every location at once, and is taken back
  /// by rebuilding rather than by stepping one edit backwards. Nothing writes
  /// relabel.
  Future<bool> _reverse(EditEvent event) {
    switch (event.kind) {
      case EditKind.remap:
        return _undoMove(event);
      case EditKind.hide:
      case EditKind.unhide:
        return _undoVisibility(event);
      case EditKind.delete:
        return _undoDelete(event);
      case EditKind.resymbol:
        return _undoSymbol(event);
      case EditKind.create:
        return _undoCreate(event);
      case EditKind.relabel:
      case EditKind.gridResize:
        return Future.value(false);
    }
  }

  /// Puts a moved word back at the location it came from.
  ///
  /// Refuses when something has taken that location since. Landing the word
  /// anywhere else would be a move nobody asked for, and overwriting would cost
  /// the newcomer the location it is already being reached for — the rule
  /// [restoreButton] keeps, for the reason it keeps it.
  ///
  /// A move recorded as coming from nowhere goes back to nowhere: a word lifted
  /// out of the unplaced tray returns to it, and the location it was dropped on
  /// is released.
  Future<bool> _undoMove(EditEvent event) async {
    final buttonId = event.buttonId;
    final before = _payload(event.beforeJson);
    if (buttonId == null || !before.containsKey('cellId')) return false;

    final button = await (_db.select(
      _db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingleOrNull();
    if (button == null) return false;

    final toCellId = before['cellId'] as String?;
    if (toCellId != null && !await _isFree(toCellId)) return false;

    final ts = nowMs();
    await _relocate(
      buttonId: buttonId,
      fromCellId: button.cellId,
      toCellId: toCellId,
      ts: ts,
    );
    await _recordUndo(
      event: event,
      kind: EditKind.remap,
      buttonId: buttonId,
      cellId: button.cellId,
      after: {'cellId': toCellId},
      ts: ts,
    );
    return true;
  }

  /// Puts a word back on or off the board.
  ///
  /// Nothing here touches the location. Hiding never released it, so revealing
  /// has nothing to reclaim and re-hiding has nothing to give up. The asymmetry
  /// with [_undoDelete] is the product rather than an implementation detail.
  ///
  /// Re-hiding one of the keys every board carries is refused for the reason
  /// [setHidden] refuses it, and the fact that the undo button is what asked
  /// makes no difference to somebody left on a board with no way off.
  Future<bool> _undoVisibility(EditEvent event) async {
    final buttonId = event.buttonId;
    if (buttonId == null) return false;

    final button = await (_db.select(
      _db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingleOrNull();
    if (button == null) return false;

    final hidden = event.kind == EditKind.unhide;
    if (hidden && button.isSystem) return false;

    final ts = nowMs();
    await (_db.update(_db.buttons)..where((b) => b.id.equals(buttonId))).write(
      ButtonsCompanion(hidden: Value(hidden), updatedAt: Value(ts)),
    );
    await _recordUndo(
      event: event,
      kind: hidden ? EditKind.hide : EditKind.unhide,
      buttonId: buttonId,
      cellId: button.cellId,
      after: {'hidden': hidden},
      ts: ts,
    );
    return true;
  }

  /// Puts a deleted word back at the exact location it gave up.
  ///
  /// Reclaiming the cell is what makes this the reverse of a delete rather than
  /// the reverse of a hide, and it is why the location has to be free: deleting
  /// handed it to whatever came next, and taking it away again would cost that
  /// word the movement it is already being reached for.
  ///
  /// A removed board is recorded as a delete too, and is refused here because
  /// it names a board rather than one word at one location. A board's worth of
  /// words coming back is not one word going back to one cell, and reading it
  /// as one would put a single word back and call the board restored.
  Future<bool> _undoDelete(EditEvent event) async {
    final buttonId = event.buttonId;
    final cellId = _payload(event.beforeJson)['cellId'] as String?;
    if (buttonId == null || cellId == null) return false;

    final button = await (_db.select(
      _db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingleOrNull();
    if (button == null || button.deletedAt == null) return false;
    if (!await _isFree(cellId)) return false;

    final ts = nowMs();
    await (_db.update(_db.buttons)..where((b) => b.id.equals(buttonId))).write(
      ButtonsCompanion(
        cellId: Value(cellId),
        deletedAt: const Value(null),
        updatedAt: Value(ts),
      ),
    );
    await (_db.update(_db.cells)..where((c) => c.id.equals(cellId))).write(
      const CellsCompanion(state: Value(CellState.occupied)),
    );
    await _recordUndo(
      event: event,
      kind: EditKind.create,
      buttonId: buttonId,
      cellId: cellId,
      after: {'cellId': cellId},
      ts: ts,
    );
    return true;
  }

  /// Takes back a word that was added, and gives its location up again.
  ///
  /// The reverse of adding is removing, not hiding: the location was free
  /// before the word arrived and has to be free again, or the next word a
  /// caregiver adds finds it held by something nobody meant to keep.
  ///
  /// Refused for a word that has moved since. The recorded location is no
  /// longer where it lives, and freeing that cell would release one somebody
  /// else is already being taught to reach for.
  Future<bool> _undoCreate(EditEvent event) async {
    final buttonId = event.buttonId;
    final cellId = event.cellId;
    if (buttonId == null || cellId == null) return false;

    final button = await (_db.select(
      _db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingleOrNull();

    if (button == null || button.deletedAt != null) return false;
    if (button.isSystem || button.cellId != cellId) return false;

    final ts = nowMs();
    await (_db.update(_db.buttons)..where((b) => b.id.equals(buttonId))).write(
      ButtonsCompanion(
        cellId: const Value(null),
        deletedAt: Value(ts),
        updatedAt: Value(ts),
      ),
    );
    await (_db.update(_db.cells)..where((c) => c.id.equals(cellId))).write(
      const CellsCompanion(state: Value(CellState.emptyReserved)),
    );
    await _recordUndo(
      event: event,
      kind: EditKind.delete,
      buttonId: buttonId,
      cellId: cellId,
      after: const {},
      ts: ts,
    );
    return true;
  }

  /// Puts back the picture a word had, on every copy of the key it is on.
  ///
  /// A picture chosen for one of the keys every board carries was written to
  /// every copy of it as one edit, so taking it off has to reach every copy as
  /// well — a key that looks like two different keys depending on which board
  /// it is seen from is exactly the confusion the fixed frame prevents.
  ///
  /// Refused when the record does not say what the picture replaced. A key an
  /// AAC user finds by its picture is one they can be given the wrong picture
  /// for, silently, by an undo that guessed.
  Future<bool> _undoSymbol(EditEvent event) async {
    final buttonId = event.buttonId;
    final before = _payload(event.beforeJson);
    if (buttonId == null || !before.containsKey('symbolId')) return false;

    final button = await (_db.select(
      _db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingleOrNull();
    if (button == null) return false;

    final symbolId = before['symbolId'] as String?;
    final siblings = await frameSiblings(_db, button);
    final ids = [button.id, for (final b in siblings) b.id];

    final ts = nowMs();
    await (_db.update(_db.buttons)..where((b) => b.id.isIn(ids))).write(
      ButtonsCompanion(symbolId: Value(symbolId), updatedAt: Value(ts)),
    );
    await _recordUndo(
      event: event,
      kind: EditKind.resymbol,
      buttonId: buttonId,
      cellId: button.cellId,
      after: {'symbolId': symbolId},
      ts: ts,
    );
    return true;
  }

  /// Whether a location is there and nothing is standing in it.
  Future<bool> _isFree(String cellId) async {
    final cell = await (_db.select(
      _db.cells,
    )..where((c) => c.id.equals(cellId))).getSingleOrNull();
    return cell != null && cell.state != CellState.occupied;
  }

  /// Adds the reversal to the trail, naming what it reversed.
  ///
  /// Appended rather than subtracted. The edit and the second thought are both
  /// things the board has been through, and the school SLP asked what changed
  /// on Tuesday, not what survived until Friday.
  Future<void> _recordUndo({
    required EditEvent event,
    required EditKind kind,
    required String buttonId,
    required String? cellId,
    required Map<String, Object?> after,
    required int ts,
  }) {
    return _db
        .into(_db.editEvents)
        .insert(
          EditEventsCompanion.insert(
            id: newId(),
            profileId: Value(event.profileId),
            vocabularyId: event.vocabularyId,
            cellId: Value(cellId),
            buttonId: Value(buttonId),
            kind: kind,
            afterJson: Value(jsonEncode({...after, _undoOfKey: event.id})),
            changedAt: ts,
          ),
        );
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

  /// Puts one deleted word back where it was, named directly.
  ///
  /// The same reversal [undoLast] performs, reached without walking the trail,
  /// because the prompt offering it names the word: it is the toast that
  /// appeared when the word went, and it means that word rather than whatever
  /// was changed last.
  ///
  /// Refuses rather than guesses when something has taken the location since.
  /// Putting the word somewhere else would be a move nobody asked for, and the
  /// caregiver undoing a delete is trying to get back to what they had.
  Future<bool> restoreButton(String buttonId) {
    return _db.transaction(() async {
      final event =
          await (_db.select(_db.editEvents)
                ..where(
                  (e) =>
                      e.buttonId.equals(buttonId) &
                      e.kind.equalsValue(EditKind.delete),
                )
                ..orderBy([
                  (e) => OrderingTerm.desc(e.changedAt),
                  (e) => OrderingTerm.desc(e.rowId),
                ])
                ..limit(1))
              .getSingleOrNull();

      if (event == null) return false;
      return _undoDelete(event);
    });
  }
}
