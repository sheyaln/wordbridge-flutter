/// Changing the grid a board was built on.
///
/// This is the most destructive thing wordbridge can do. Orientation and icon
/// size decide how many rows and columns there are, so changing either one
/// rebuilds every board and moves almost every word — the exact failure the
/// rest of the app exists to prevent. It is allowed because a person's motor
/// ability changes, and a board sized for who they were is worse than a
/// rebuild. It is never quiet.
///
/// Two properties make it survivable:
///
/// **It is measured first.** [preview] reports how many words move and how
/// much practice those locations have had, in the user's own tap counts, so a
/// caregiver decides with a number in front of them rather than a shrug.
///
/// **It is reversible.** [apply] builds a *new* vocabulary and points the
/// profile at it. The old board set is untouched — every location, every
/// customisation, every recorded tap — so [revert] is a single write.
library;

import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/seed/age_presets.dart';
import '../../db/seed/band_layout.dart';
import '../../db/seed/core_board_set.dart';
import '../../db/seed/core_vocabulary.dart';
import '../../db/tables.dart';
import '../usage/usage_queries.dart';

/// What changing the grid would cost, in the user's own history.
class MigrationImpact {
  const MigrationImpact({
    required this.fromRows,
    required this.fromCols,
    required this.toRows,
    required this.toCols,
    required this.moving,
    required this.staying,
    required this.leaving,
    required this.customWords,
    required this.totalTaps,
    required this.mostPractised,
    required this.trackingOff,
  });

  final int fromRows;
  final int fromCols;
  final int toRows;
  final int toCols;

  /// Words that end up somewhere other than where they are now.
  final int moving;

  /// Words that happen to land on the same location again.
  final int staying;

  /// Words the new grid has no room for on their board. They are not lost —
  /// they move to a later page — but they cost a navigation step they did not
  /// cost before.
  final int leaving;

  /// Words a caregiver added themselves. Carried across, and worth naming
  /// separately because they are the ones nobody can recreate from a default.
  final int customWords;

  /// Selections recorded at the locations that change.
  final int totalTaps;

  final List<({String label, int taps, String from, String to})> mostPractised;

  /// Usage tracking is off, so the tap counts are all zero and the warning
  /// cannot say what the change costs. Worth saying out loud rather than
  /// showing a confident "0 taps".
  final bool trackingOff;

  bool get isNoOp => fromRows == toRows && fromCols == toCols;

  /// Plain-language warning, in the user's own numbers.
  String warningFor(String? userName) {
    final who = userName ?? 'This user';
    final buffer = StringBuffer()
      ..write(
        'Rebuilding at ${toRows}x$toCols moves $moving of the '
        '${moving + staying} words on this board set. ',
      );

    if (trackingOff) {
      buffer.write(
        'Word usage is not being recorded, so there is no way to tell you how '
        'much practice these locations have had. If $who has been using this '
        'board for a while, assume it is a lot.',
      );
    } else if (totalTaps == 0) {
      buffer.write(
        'Nothing has been recorded at those locations yet, so this is about as '
        'cheap as a rebuild gets. Doing it now is much kinder than doing it in '
        'six months.',
      );
    } else {
      buffer.write(
        '$who has used those locations $totalTaps times. Anything learned '
        'there has to be learned again, which can take weeks.',
      );
    }

    if (leaving > 0) {
      buffer.write(
        ' $leaving words no longer fit on their board and move to a later '
        'page, costing an extra movement each.',
      );
    }

    if (customWords > 0) {
      buffer.write(
        ' $customWords words added by hand are carried across, and may not '
        'land where they are now.',
      );
    }

    return buffer.toString();
  }
}

class GridMigration {
  /// Works out what a rebuild would do, without doing any of it.
  static Future<MigrationImpact> preview(
    WordbridgeDatabase db, {
    required String vocabularyId,
    required int rows,
    required int cols,
    AgeBand ageBand = AgeBand.child,
    bool trackingEnabled = true,
  }) async {
    SystemRowPlan.validate(rows: rows, cols: cols);

    final vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();

    final current = await _positionsByBoard(db, vocabularyId);
    final proposed = _proposedPositions(rows: rows, cols: cols, band: ageBand);
    final shipped = _shippedLabels(ageBand);

    var moving = 0;
    var staying = 0;
    var leaving = 0;
    var customWords = 0;
    var totalTaps = 0;

    final practised = <({String label, int taps, String from, String to})>[];

    for (final board in current.entries) {
      final base = _baseName(board.key);
      final onThisPage = proposed[board.key];

      for (final word in board.value.entries) {
        if (!shipped.contains(word.key)) customWords++;

        final now = word.value;
        final next = onThisPage?[word.key];
        final anywhere = _findAcross(proposed, base, word.key);

        if (next != null && next.row == now.row && next.col == now.col) {
          staying++;
          continue;
        }

        moving++;
        // Not on this page any more. It is still reachable, on a later one,
        // which is a movement it did not cost before.
        if (next == null && anywhere != board.key) leaving++;

        final taps = await _tapsAt(db, now.cellId);
        totalTaps += taps;

        if (taps > 0) {
          practised.add((
            label: word.key,
            taps: taps,
            from: 'row ${now.row + 1}, column ${now.col + 1}',
            to: next == null
                ? 'a later page'
                : 'row ${next.row + 1}, column ${next.col + 1}',
          ));
        }
      }
    }

    practised.sort((a, b) => b.taps.compareTo(a.taps));

    return MigrationImpact(
      fromRows: vocab.gridRows,
      fromCols: vocab.gridCols,
      toRows: rows,
      toCols: cols,
      moving: moving,
      staying: staying,
      leaving: leaving,
      customWords: customWords,
      totalTaps: totalTaps,
      mostPractised: practised.take(8).toList(),
      trackingOff: !trackingEnabled,
    );
  }

  /// Builds the board set again at the new grid and points the profile at it.
  ///
  /// The previous vocabulary is left exactly as it was, which is what makes
  /// this reversible. Storage is cheap; a board set somebody spent a year
  /// learning is not.
  static Future<String> apply(
    WordbridgeDatabase db, {
    required String profileId,
    required String vocabularyId,
    required int rows,
    required int cols,
    AgeBand ageBand = AgeBand.child,
    bool profanity = false,
  }) async {
    SystemRowPlan.validate(rows: rows, cols: cols);

    final previous = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();

    final impact = await preview(
      db,
      vocabularyId: vocabularyId,
      rows: rows,
      cols: cols,
      ageBand: ageBand,
    );

    final rebuilt = await seedCoreBoardSet(
      db,
      name: previous.name,
      locale: previous.locale,
      rows: rows,
      cols: cols,
      profileId: profileId,
      attachToProfile: false,
      ageBand: ageBand,
      profanity: profanity,
    );

    await _carryOver(db, from: vocabularyId, to: rebuilt, ageBand: ageBand);

    await (db.update(db.profiles)..where((p) => p.id.equals(profileId))).write(
      ProfilesCompanion(
        activeVocabularyId: Value(rebuilt),
        updatedAt: Value(nowMs()),
      ),
    );

    // The audit trail carries the number the caregiver was shown, so the answer
    // to "what happened in March" is not a guess.
    await db
        .into(db.editEvents)
        .insert(
          EditEventsCompanion.insert(
            id: newId(),
            profileId: Value(profileId),
            vocabularyId: rebuilt,
            kind: EditKind.gridResize,
            beforeJson: Value(
              '{"vocabulary":"$vocabularyId",'
              '"rows":${previous.gridRows},"cols":${previous.gridCols}}',
            ),
            afterJson: Value('{"rows":$rows,"cols":$cols}'),
            motorImpactTaps: Value(impact.totalTaps),
            changedAt: nowMs(),
          ),
        );

    return rebuilt;
  }

  /// Puts the profile back on the board set it had before a rebuild.
  ///
  /// Possible because nothing was destroyed. Every location and every recorded
  /// tap in the previous vocabulary is still there.
  static Future<void> revert(
    WordbridgeDatabase db, {
    required String profileId,
    required String toVocabularyId,
  }) async {
    await (db.update(db.profiles)..where((p) => p.id.equals(profileId))).write(
      ProfilesCompanion(
        activeVocabularyId: Value(toVocabularyId),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  /// Moves a caregiver's work onto the rebuilt boards.
  ///
  /// Two kinds of thing: words they added, which have no home in the shipped
  /// layout and go into the reserve; and edits to shipped words — a different
  /// picture, a different spoken form, a word switched off — which follow the
  /// word to wherever it now lives.
  static Future<void> _carryOver(
    WordbridgeDatabase db, {
    required String from,
    required String to,
    required AgeBand ageBand,
  }) async {
    final old = await _positionsByBoard(db, from);
    final rebuilt = await _boardsByName(db, to);
    final shipped = _shippedLabels(ageBand);

    // Where every word ended up, across the whole rebuilt set. A word shed to
    // a later page is still that word, and a caregiver's decision about it
    // has to follow it there.
    final placedNow = <String, Button>{};
    for (final b
        in await (db.select(db.buttons)..where(
              (b) => b.vocabularyId.equals(to) & b.isSystem.equals(false),
            ))
            .get()) {
      placedNow.putIfAbsent(b.label, () => b);
    }

    for (final board in old.entries) {
      final target = rebuilt[board.key] ?? rebuilt[_baseName(board.key)];
      if (target == null) continue;

      for (final word in board.value.entries) {
        final existing = placedNow[word.key];

        if (existing != null) {
          // A shipped word that already has its place. Carry the edits, not
          // the position.
          await (db.update(
            db.buttons,
          )..where((b) => b.id.equals(existing.id))).write(
            ButtonsCompanion(
              symbolId: Value(word.value.symbolId),
              speakText: Value(word.value.speakText),
              hidden: Value(word.value.hidden),
              updatedAt: Value(nowMs()),
            ),
          );
          continue;
        }

        if (shipped.contains(word.key)) continue;

        await _placeIntoReserve(
          db,
          vocabularyId: to,
          boardId: target,
          word: word.value,
        );
      }
    }
  }

  /// Puts a caregiver's own word on the first free location, reading order.
  static Future<void> _placeIntoReserve(
    WordbridgeDatabase db, {
    required String vocabularyId,
    required String boardId,
    required _Word word,
  }) async {
    final free =
        await (db.select(db.cells)
              ..where(
                (c) =>
                    c.boardId.equals(boardId) &
                    c.state.equalsValue(CellState.emptyReserved),
              )
              ..orderBy([
                (c) => OrderingTerm.asc(c.col),
                (c) => OrderingTerm.asc(c.row),
              ])
              ..limit(1))
            .getSingleOrNull();

    // Nowhere to put it. Better an unplaced word the editor can show in its
    // tray than one silently written over something else.
    if (free == null) return;

    await db
        .into(db.buttons)
        .insert(
          ButtonsCompanion.insert(
            id: newId(),
            cellId: Value(free.id),
            vocabularyId: vocabularyId,
            label: word.label,
            message: word.message,
            speakText: Value(word.speakText),
            action: word.action,
            symbolId: Value(word.symbolId),
            partOfSpeech: Value(word.partOfSpeech),
            hidden: Value(word.hidden),
            vocabLevel: Value(word.vocabLevel),
            createdAt: nowMs(),
            updatedAt: nowMs(),
          ),
        );

    await (db.update(db.cells)..where((c) => c.id.equals(free.id))).write(
      const CellsCompanion(state: Value(CellState.occupied)),
    );
  }

  static Future<Map<String, Map<String, _Word>>> _positionsByBoard(
    WordbridgeDatabase db,
    String vocabularyId,
  ) async {
    final query =
        db.select(db.buttons).join([
          innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
        ])..where(
          db.buttons.vocabularyId.equals(vocabularyId) &
              db.buttons.isSystem.equals(false),
        );

    final result = <String, Map<String, _Word>>{};
    for (final r in await query.get()) {
      final button = r.readTable(db.buttons);
      final cell = r.readTable(db.cells);
      final board = r.readTable(db.boards);

      (result[board.name] ??= {})[button.label] = (
        cellId: cell.id,
        row: cell.row,
        col: cell.col,
        label: button.label,
        message: button.message,
        speakText: button.speakText,
        action: button.action,
        symbolId: button.symbolId,
        partOfSpeech: button.partOfSpeech,
        hidden: button.hidden,
        vocabLevel: button.vocabLevel,
      );
    }
    return result;
  }

  static Future<Map<String, String>> _boardsByName(
    WordbridgeDatabase db,
    String vocabularyId,
  ) async {
    final boards = await (db.select(
      db.boards,
    )..where((b) => b.vocabularyId.equals(vocabularyId))).get();
    return {for (final b in boards) b.name: b.id};
  }

  /// Where the shipped vocabulary would land on a given grid, page by page.
  ///
  /// Mirrors the paging the seed does, because a word that ends up on page two
  /// has moved just as surely as one that changes row — more so, since it now
  /// costs a movement to reach.
  static Map<String, Map<String, ({int row, int col})>> _proposedPositions({
    required int rows,
    required int cols,
    required AgeBand band,
  }) {
    final questionRows = rows - 1;
    final spilledQuestions = pinnedQuestions.skip(questionRows).toList();

    final boards = {
      ..._pagedPositions(
        'home',
        [
          ...homeBands,
          if (spilledQuestions.isNotEmpty)
            Band(name: 'questions', items: spilledQuestions, shedRank: 3),
        ],
        rows,
        cols,
      ),
      for (final category in categoryNames)
        ..._pagedPositions(
          category,
          [
            ...categoryBands[category]!,
            ...band.extrasFor(category),
            if (band.canSwear && category == 'feelings') swearingBand,
          ],
          rows,
          cols,
          axis: BandAxis.rows,
        ),
    };

    // The pinned column repeats on every board, so it belongs in every board's
    // proposal. Leaving it out reports the questions as moving off each board
    // they are a permanent part of.
    final questionCol = cols - 1;
    for (final positions in boards.values) {
      for (var q = 0; q < pinnedQuestions.length && q < questionRows; q++) {
        positions[pinnedQuestions[q].value.label] = (row: q, col: questionCol);
      }
    }

    return boards;
  }

  static Map<String, Map<String, ({int row, int col})>> _pagedPositions(
    String name,
    List<Band<SeedWord>> bands,
    int rows,
    int cols, {
    BandAxis axis = BandAxis.columns,
  }) {
    final result = <String, Map<String, ({int row, int col})>>{};
    var remaining = bands;
    var page = 0;

    while (true) {
      final layout = layOutBands(
        rows: rows,
        cols: cols,
        bands: remaining,
        axis: axis,
      );
      result[page == 0 ? name : '$name ${page + 1}'] = {
        for (final p in layout.placed) p.value.label: (row: p.row, col: p.col),
      };

      if (layout.overflow.isEmpty || layout.placed.isEmpty) return result;

      remaining = [
        for (final bandName in layout.overflowBands)
          Band(
            name: bandName,
            items: [
              for (final o in layout.overflow.reversed)
                if (o.band == bandName) o.item,
            ],
          ),
      ];
      page++;
    }
  }

  static Set<String> _shippedLabels(AgeBand band) => {
    for (final b in homeBands)
      for (final i in b.items) i.value.label,
    for (final entry in categoryBands.entries)
      for (final b in [...entry.value, ...band.extrasFor(entry.key)])
        for (final i in b.items) i.value.label,
    if (band.canSwear)
      for (final i in swearingBand.items) i.value.label,
    for (final i in pinnedQuestions) i.value.label,
  };

  /// Which page of a board group a word lands on, or null if none.
  static String? _findAcross(
    Map<String, Map<String, ({int row, int col})>> proposed,
    String base,
    String label,
  ) {
    for (final entry in proposed.entries) {
      if (_baseName(entry.key) != base) continue;
      if (entry.value.containsKey(label)) return entry.key;
    }
    return null;
  }

  /// "food 2" and "food" are the same board at two sizes.
  static String _baseName(String name) =>
      name.replaceAll(RegExp(r'\s+\d+$'), '');

  /// How much practice a location has had.
  ///
  /// Counts only the ways of choosing a word that involved going to the
  /// location, so the number a caregiver is shown before a rebuild means what
  /// it says.
  static Future<int> _tapsAt(WordbridgeDatabase db, String cellId) async {
    final count = db.usageEvents.id.count();
    final query = db.selectOnly(db.usageEvents)
      ..addColumns([count])
      ..where(
        db.usageEvents.cellId.equals(cellId) &
            db.usageEvents.source.isInValues(UsageQueries.practisedSources),
      );

    return (await query.getSingle()).read(count) ?? 0;
  }
}

typedef _Word = ({
  String cellId,
  int row,
  int col,
  String label,
  String message,
  String? speakText,
  ButtonAction action,
  String? symbolId,
  PartOfSpeech? partOfSpeech,
  bool hidden,
  int vocabLevel,
});
