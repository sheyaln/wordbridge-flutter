import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import '../utterance/utterance.dart';

/// Discards everything prediction has learned about a profile.
///
/// Turning prediction off calls this, and so does the button that offers it on
/// its own. A setting that stops using what it gathered but keeps it is not
/// off, and a user who asks to be forgotten is owed more than a flag.
///
/// Free of the rest of the class on purpose: forgetting somebody should not
/// require knowing which vocabulary or level they are on.
Future<void> forgetPredictions(WordbridgeDatabase db, String profileId) =>
    (db.delete(
      db.predictionPairs,
    )..where((p) => p.profileId.equals(profileId))).go();

/// What this user is likely to say next, learned from what they have said.
///
/// Three things constrain what may be offered, and all three are about not
/// undoing the rest of the app:
///
/// **Only words already on this user's boards.** A suggestion is a shortcut to
/// a word, never a source of new ones. Offering something a caregiver has
/// hidden or held back by level would route around a decision they made, and
/// offering a word with no home would teach a sequence that leads nowhere.
///
/// **Deterministic order.** Two identical states produce the same strip in the
/// same order. A list that reshuffles between rebuilds is an unstable target,
/// which is the whole thing this app exists to avoid.
///
/// **Counts, never a transcript.** [learn] stores pairs of words and how often
/// one followed the other. It cannot reconstruct a sentence.
class WordPrediction {
  WordPrediction(
    this._db, {
    required this.profileId,
    required this.vocabularyId,
    required this.vocabLevel,
  });

  final WordbridgeDatabase _db;
  final String profileId;
  final String vocabularyId;

  /// The same ceiling the grid draws at. Without it the strip would surface
  /// vocabulary a caregiver is deliberately holding back, and the level would
  /// stop meaning anything.
  final int vocabLevel;

  /// Marks the start of a sentence in the pair table.
  ///
  /// An empty string rather than NULL because it is half of a primary key, and
  /// NULLs in a key compare as distinct from each other in SQLite.
  static const sentenceStart = '';

  /// Words that carry no information about what follows them, so nothing is
  /// keyed on them and they are never offered.
  static bool _isSkippable(String word) =>
      word.trim().isEmpty || UtteranceBar.isPunctuation(word);

  static String _key(String word) => word.trim().toLowerCase();

  /// The next words worth offering, best first.
  ///
  /// Returns the buttons themselves rather than their labels, so that pressing
  /// a suggestion needs no database read: the part of speech and the spoken
  /// text are already in hand, and speech can start on the same turn as the
  /// tap. Nothing may stand between a user and a word, a lookup included.
  ///
  /// Falls back in three steps, so the strip is useful on day one and gets
  /// sharper rather than appearing from nothing: what has followed this word,
  /// then what this user says most at all, then the simplest words on their
  /// board. Each step only tops up what the one before it left short.
  Future<List<Button>> suggest({String? previous, int limit = 5}) async {
    if (limit <= 0) return const [];

    final offerable = await _offerableWords();
    if (offerable.isEmpty) return const [];

    final chosen = <Button>[];
    final taken = <String>{};

    void take(Iterable<String> words) {
      for (final word in words) {
        if (chosen.length >= limit) return;
        final button = offerable[_key(word)];
        if (button == null || !taken.add(_key(word))) continue;
        chosen.add(button);
      }
    }

    final last = previous == null || _isSkippable(previous)
        ? sentenceStart
        : _key(previous);

    take(await _rankedAfter(last));
    if (chosen.length < limit && last != sentenceStart) {
      take(await _rankedAfter(sentenceStart));
    }
    if (chosen.length < limit) {
      take(await _simplestWords());
    }

    return chosen;
  }

  /// Records the sentence that was just spoken.
  ///
  /// Called when a sentence is spoken rather than as each word is added, so
  /// what is learned is what the user meant to say, not every combination they
  /// passed through while building it.
  Future<void> learn(List<String> words) async {
    final pairs = <({String previous, String word})>[];
    var previous = sentenceStart;

    for (final word in words) {
      if (_isSkippable(word)) continue;
      final key = _key(word);
      pairs.add((previous: previous, word: key));
      previous = key;
    }

    if (pairs.isEmpty) return;

    await _db.batch((batch) {
      for (final pair in pairs) {
        batch.insert(
          _db.predictionPairs,
          PredictionPairsCompanion.insert(
            profileId: profileId,
            previous: pair.previous,
            word: pair.word,
            count: const Value(1),
          ),
          onConflict: DoUpdate(
            ($PredictionPairsTable old) => PredictionPairsCompanion.custom(
              count: old.count + const Constant(1),
            ),
            target: [
              _db.predictionPairs.profileId,
              _db.predictionPairs.previous,
              _db.predictionPairs.word,
            ],
          ),
        );
      }
    });
  }

  Future<void> forget() => forgetPredictions(_db, profileId);

  Future<bool> hasLearnedAnything() async {
    final row =
        await (_db.select(_db.predictionPairs)
              ..where((p) => p.profileId.equals(profileId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Words that follow [previous], most frequent first.
  ///
  /// Ties break alphabetically. Two words seen the same number of times must
  /// come out in the same order every time or the strip moves under the user.
  Future<List<String>> _rankedAfter(String previous) async {
    final query = _db.select(_db.predictionPairs)
      ..where(
        (p) => p.profileId.equals(profileId) & p.previous.equals(previous),
      )
      ..orderBy([
        (p) => OrderingTerm.desc(p.count),
        (p) => OrderingTerm.asc(p.word),
      ])
      ..limit(_candidatePool);

    return [for (final row in await query.get()) row.word];
  }

  /// The board's own starting point, for a profile that has said nothing yet.
  ///
  /// Reading order on the home board, which is not an arbitrary order: columns
  /// there run in sentence order and the leftmost are the pronouns, so the
  /// first few cells are the words most sentences open with. Ranking by level
  /// and then alphabetically would offer whatever happened to start with "a".
  Future<List<String>> _simplestWords() async {
    final rootBoardId = await _rootBoardId();
    if (rootBoardId == null) return const [];

    final query =
        _db.select(_db.buttons).join([
            innerJoin(_db.cells, _db.cells.id.equalsExp(_db.buttons.cellId)),
          ])
          ..where(
            _speakable(_db.buttons) & _db.cells.boardId.equals(rootBoardId),
          )
          ..orderBy([
            OrderingTerm.asc(_db.cells.row),
            OrderingTerm.asc(_db.cells.col),
          ])
          ..limit(_candidatePool);

    return [
      for (final row in await query.get()) row.readTable(_db.buttons).message,
    ];
  }

  Future<String?> _rootBoardId() async {
    final vocab = await (_db.select(
      _db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingleOrNull();
    return vocab?.rootBoardId;
  }

  /// Every word currently on a board, keyed by its lowercase form.
  ///
  /// A word may hold two locations across two boards. The first one found wins
  /// and the strip offers it once: two identical suggestions side by side are
  /// two ways of saying the same thing and a wasted slot.
  Future<Map<String, Button>> _offerableWords() async {
    final query = _db.select(_db.buttons)
      ..where(_speakable)
      ..orderBy([(b) => OrderingTerm.asc(b.id)]);

    final words = <String, Button>{};
    for (final row in await query.get()) {
      words.putIfAbsent(_key(row.message), () => row);
    }
    return words;
  }

  /// Plain vocabulary only.
  ///
  /// System keys, word endings and punctuation are excluded: they act on the
  /// sentence rather than adding to it, and a prediction strip that offers
  /// "go back" is offering navigation, not a word.
  Expression<bool> _speakable($ButtonsTable b) =>
      b.vocabularyId.equals(vocabularyId) &
      b.action.equalsValue(ButtonAction.speak) &
      b.hidden.equals(false) &
      b.isSystem.equals(false) &
      b.vocabLevel.isSmallerOrEqualValue(vocabLevel) &
      b.deletedAt.isNull();

  /// Read more rows than the strip shows, because some will be words that are
  /// no longer on a board and get filtered out.
  static const _candidatePool = 40;
}
