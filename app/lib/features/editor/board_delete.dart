/// Removing a board a caregiver made by mistake.
///
/// "New board" is two taps from the caregiver home, so a mistyped or duplicate
/// board is easy to make. Without this it is also permanent.
///
/// Three things make it survivable:
///
/// **It is a `deleted_at`, never a `DELETE`.** A board holds cells, cells hold
/// the usage rows the remap warning is built on, and those rows are what tell a
/// caregiver whether the board was ever used. Destroying them to tidy up a
/// mistake answers the question by deleting it.
///
/// **Nothing that is part of the frame can go.** The home board, the boards on
/// the category wheel and the later pages of both are reached by keys that sit
/// at the same coordinates on every board. Removing one of those boards is the
/// hazard the wheel's append-only rule exists to prevent, run backwards: the
/// key stays where it is and opens something else, or nothing.
///
/// **A board with words on it says what would go first.** In the count of words
/// and the recorded taps against those locations, in the same window and the
/// same voice a single word's move uses.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/seed/core_board_set.dart';
import '../../db/tables.dart';
import '../usage/usage_queries.dart';
import 'remap.dart';

/// Why a board cannot be removed.
///
/// Each of these is shown to the caregiver rather than expressed by leaving the
/// control out. A control that is simply absent reads as a bug, and the reason
/// is the part worth knowing — it is usually also the answer to what they
/// should do instead.
enum BoardDeleteRefusal {
  alreadyGone,
  homeBoard,
  onTheCategoryWheel,
  openedByAFixedKey,
  partOfTheFrame,
}

/// What removing a board would take with it.
class BoardDeleteImpact {
  const BoardDeleteImpact({
    required this.boardName,
    required this.words,
    required this.taps,
    required this.days,
    required this.keys,
    required this.windowDays,
    required this.refusal,
    required this.reason,
  });

  final String boardName;

  /// Words on the board, hidden ones included. A word held below the current
  /// vocabulary level is still vocabulary somebody placed.
  final int words;

  /// Selections recorded at the locations those words occupy, over
  /// [windowDays]. Counted the way a single word's move counts them, so the two
  /// numbers a caregiver sees in one session mean the same thing.
  final int taps;

  /// Distinct calendar days those locations were used on.
  final int days;

  /// Buttons elsewhere in the board set that open this board. They keep their
  /// locations and stop doing anything.
  final int keys;

  final int windowDays;

  /// Null when the board can be removed.
  final BoardDeleteRefusal? refusal;

  /// Plain-language refusal, non-null exactly when [refusal] is.
  final String? reason;

  bool get canDelete => refusal == null;

  /// The case this feature is actually for: a board created and never filled.
  /// One tap, no ceremony, nothing to warn about.
  bool get isEmpty => words == 0 && keys == 0;

  /// What it costs, in the user's own recorded practice, or null when there is
  /// genuinely nothing to say.
  String? warningFor(String? userName) {
    if (isEmpty) return null;

    final who = userName ?? 'This user';
    final buffer = StringBuffer();

    if (words > 0) {
      buffer.write(
        '"$boardName" holds $words ${words == 1 ? 'word' : 'words'}, and they '
        'go with it. ',
      );

      if (taps == 0) {
        buffer.write(
          'Nothing has been recorded at those locations in the last '
          '$windowDays days, so this is about as cheap as removing a board '
          'gets. ',
        );
      } else {
        buffer.write(
          '$who has tapped those locations $taps '
          '${taps == 1 ? 'time' : 'times'} across $days '
          '${days == 1 ? 'day' : 'days'} in the last $windowDays days. '
          'Anything learned there is learned about a board that will not be '
          'there. ',
        );
      }
    }

    if (keys > 0) {
      buffer.write(
        '$keys ${keys == 1 ? 'key opens' : 'keys open'} this board. '
        '${keys == 1 ? 'It stays' : 'They stay'} where '
        '${keys == 1 ? 'it is' : 'they are'} and '
        '${keys == 1 ? 'stops' : 'stop'} doing anything, because a location '
        'somebody has learned must never be handed to something else. ',
      );
    }

    buffer.write(
      'Nothing is destroyed. The board is marked deleted and every recorded '
      'tap stays, so what was done here is still answerable afterwards.',
    );

    return buffer.toString();
  }
}

class BoardDeletion {
  /// How far back the tap count looks.
  ///
  /// The same window a single word's move uses, because a caregiver reading
  /// both in one sitting is entitled to assume two numbers labelled the same
  /// way were measured the same way.
  static const practiceWindow = RemapService.practiceWindow;

  /// Works out what removing a board would do, without doing any of it.
  static Future<BoardDeleteImpact> preview(
    WordbridgeDatabase db, {
    required String boardId,
  }) async {
    final board = await (db.select(
      db.boards,
    )..where((b) => b.id.equals(boardId))).getSingle();

    final vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(board.vocabularyId))).getSingle();

    final cellIds = [
      for (final c in await (db.select(
        db.cells,
      )..where((c) => c.boardId.equals(boardId))).get())
        c.id,
    ];

    final placed =
        await (db.select(db.buttons)..where(
              (b) =>
                  b.cellId.isIn(cellIds) &
                  b.isSystem.equals(false) &
                  b.deletedAt.isNull(),
            ))
            .get();

    final inbound =
        await (db.select(db.buttons)..where(
              (b) => b.targetBoardId.equals(boardId) & b.deletedAt.isNull(),
            ))
            .get();

    final history = await _historyAcross(db, [
      for (final b in placed) ?b.cellId,
    ]);

    final refusal = _refuse(board: board, vocabulary: vocab, inbound: inbound);

    return BoardDeleteImpact(
      boardName: board.name,
      words: placed.length,
      taps: history.taps,
      days: history.days,
      keys: inbound.length,
      windowDays: practiceWindow.days,
      refusal: refusal?.$1,
      reason: refusal?.$2,
    );
  }

  /// Marks the board deleted, and deals with everything that pointed at it in
  /// the same transaction.
  ///
  /// One transaction is the whole safety argument: a board that is half gone is
  /// a key that opens a board the talk screen cannot load, which is a
  /// nonspeaking person holding a device that shows nothing.
  ///
  /// Throws rather than guessing if the board has become undeletable since
  /// [preview] ran. A caller that has shown the wrong warning should fail
  /// loudly, not remove the wrong board quietly.
  static Future<void> apply(
    WordbridgeDatabase db, {
    required String boardId,
    String? profileId,
  }) async {
    final impact = await preview(db, boardId: boardId);
    if (!impact.canDelete) throw StateError(impact.reason!);

    await db.transaction(() async {
      final board = await (db.select(
        db.boards,
      )..where((b) => b.id.equals(boardId))).getSingle();
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(board.vocabularyId))).getSingle();

      final cellIds = [
        for (final c in await (db.select(
          db.cells,
        )..where((c) => c.boardId.equals(boardId))).get())
          c.id,
      ];

      final inbound =
          await (db.select(db.buttons)..where(
                (b) => b.targetBoardId.equals(boardId) & b.deletedAt.isNull(),
              ))
              .get();

      final refusal = _refuse(
        board: board,
        vocabulary: vocab,
        inbound: inbound,
      );
      if (refusal != null) throw StateError(refusal.$2);

      final ts = nowMs();

      // The key keeps its cell and its label and stops navigating. Removing it
      // would free a location that has been reached for, and the next word
      // added would take it — which is the displacement this whole schema
      // exists to prevent. Masked rather than left visible because a navigate
      // key with nowhere to go strands the talk screen on a board that is not
      // there.
      for (final key in inbound) {
        await (db.update(db.buttons)..where((b) => b.id.equals(key.id))).write(
          ButtonsCompanion(
            hidden: const Value(true),
            action: const Value(ButtonAction.none),
            targetBoardId: const Value(null),
            updatedAt: Value(ts),
          ),
        );
      }

      // Both, and neither is redundant. `hidden` is what the grid and the
      // prediction strip read, so it is what stops these words being drawn or
      // offered. `deleted_at` is what makes that stick: `hidden` is a setting
      // other controls flip in bulk across a whole vocabulary — the
      // strong-language switch is one, and it matches on label rather than on
      // board — so a word on a removed board would come back the next time one
      // of them was turned on.
      if (cellIds.isNotEmpty) {
        await (db.update(
          db.buttons,
        )..where((b) => b.cellId.isIn(cellIds))).write(
          ButtonsCompanion(
            deletedAt: Value(ts),
            hidden: const Value(true),
            updatedAt: Value(ts),
          ),
        );
      }

      // Cells are left exactly as they are, occupied included. They are the
      // anchor every usage row resolves through, and freeing one would make
      // removing a board a way to make locations move.
      await (db.update(db.boards)..where((b) => b.id.equals(boardId))).write(
        BoardsCompanion(deletedAt: Value(ts), updatedAt: Value(ts)),
      );

      await db
          .into(db.editEvents)
          .insert(
            EditEventsCompanion.insert(
              id: newId(),
              profileId: Value(profileId),
              vocabularyId: board.vocabularyId,
              kind: EditKind.delete,
              beforeJson: Value(
                jsonEncode({
                  'boardId': boardId,
                  'name': board.name,
                  'words': impact.words,
                  'keys': [
                    for (final k in inbound)
                      {
                        'buttonId': k.id,
                        'action': k.action.name,
                        'targetBoardId': k.targetBoardId,
                        'hidden': k.hidden,
                      },
                  ],
                }),
              ),
              afterJson: Value(jsonEncode({'deletedAt': ts})),
              motorImpactTaps: Value(impact.taps),
              changedAt: ts,
            ),
          );
    });
  }

  /// The reason this board has to stay, or null.
  static (BoardDeleteRefusal, String)? _refuse({
    required Board board,
    required Vocabulary vocabulary,
    required List<Button> inbound,
  }) {
    if (board.deletedAt != null) {
      return (
        BoardDeleteRefusal.alreadyGone,
        '"${board.name}" has already been removed.',
      );
    }

    if (board.kind == BoardKind.root || vocabulary.rootBoardId == board.id) {
      return (
        BoardDeleteRefusal.homeBoard,
        '"${board.name}" is the home board. Every word starts from here and '
            'the home key returns to it from everywhere, so it cannot be removed.',
      );
    }

    if (board.kind == BoardKind.system) {
      return (
        BoardDeleteRefusal.partOfTheFrame,
        '"${board.name}" is part of the board set\'s frame rather than its '
            'vocabulary, so it cannot be removed.',
      );
    }

    final frame = SystemFrame.parse(vocabulary.systemCellMap);
    if (frame != null && frame.categories.any((c) => c.boardId == board.id)) {
      return (
        BoardDeleteRefusal.onTheCategoryWheel,
        '"${board.name}" has a place on the category wheel. The keys along the '
            'bottom row are a window onto a fixed list, so taking a name out of it '
            'changes which board every key after it opens, relocating what a '
            'learned key does, without a single button moving. Empty it instead: '
            'the board stays where the keys expect it and the words on it go.',
      );
    }

    final fixed = inbound.where((b) => b.isSystem).toList();
    if (fixed.isNotEmpty) {
      return (
        BoardDeleteRefusal.openedByAFixedKey,
        '"${board.name}" is opened by "${fixed.first.label}", which holds the '
            'same coordinates on every board. Removing it would leave that key in '
            'place with nothing behind it. Empty the board instead.',
      );
    }

    return null;
  }

  /// Recorded practice across a set of locations, counted the way a single
  /// location's history is counted.
  ///
  /// Days are the union rather than the sum: a caregiver told "used across 40
  /// days" about a board somebody has had for a fortnight would rightly stop
  /// believing the rest of the numbers.
  static Future<({int taps, int days})> _historyAcross(
    WordbridgeDatabase db,
    List<String> cellIds,
  ) async {
    if (cellIds.isEmpty) return (taps: 0, days: 0);

    final rows =
        await (db.select(db.usageEvents)..where(
              (e) =>
                  e.cellId.isIn(cellIds) &
                  e.occurredAt.isBiggerOrEqualValue(practiceWindow.cutoffMs()) &
                  e.source.isInValues(UsageQueries.practisedSources),
            ))
            .get();

    final days = rows
        .map((r) {
          final d = DateTime.fromMillisecondsSinceEpoch(r.occurredAt);
          return DateTime(d.year, d.month, d.day);
        })
        .toSet()
        .length;

    return (taps: rows.length, days: days);
  }
}
