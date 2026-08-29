import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import '../utterance/utterance.dart';
import 'starter_predictions.dart';

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
///
/// **Learning happens when a sentence is spoken**, not as each word arrives.
/// Until it has learned anything — and to fill the gaps afterwards — the strip
/// runs on [starterPredictions], which ships with the app.
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
  /// Four sources, each only topping up what the one above it left short:
  ///
  /// 1. what has followed this word **for this person**
  /// 2. what usually follows it in English ([starterPredictions])
  /// 3. what this person opens sentences with
  /// 4. anything whose part of speech can follow the last word's
  ///
  /// The user's own history outranks the shipped guesses, always. The shipped
  /// guesses are what make the strip work on the first tap of the first day,
  /// and 4 is what stops it ever repeating itself: a list that shows the same
  /// five words after every word is not a prediction, it is a decoration that
  /// costs grid height.
  Future<List<Button>> suggest({
    String? previous,
    PartOfSpeech? previousPos,
    int limit = 5,
  }) async {
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

    // What this person has said, first and always.
    take(await _rankedAfter(last));

    // Then what people say. Shipped, so the strip works on the first tap of
    // the first day rather than after enough sentences to teach it.
    if (chosen.length < limit) take(starterPredictions[last] ?? const []);

    if (chosen.length < limit && last != sentenceStart) {
      take(await _rankedAfter(sentenceStart));
    }

    // Then anything that can grammatically follow, so the strip is never
    // short and never the same list twice in a row.
    if (chosen.length < limit) {
      take(await _wordsThatCanFollow(previousPos));
    }

    return chosen;
  }

  /// Records a whole sentence at once.
  Future<void> learn(List<String> words) async {
    final pairs = <({String previous, String word})>[];
    var previous = sentenceStart;

    for (final word in words) {
      if (_isSkippable(word)) continue;
      final key = _key(word);
      pairs.add((previous: previous, word: key));
      previous = key;
    }

    return _record(pairs);
  }

  Future<void> _record(List<({String previous, String word})> pairs) async {
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

  /// What kind of word usually comes after each kind of word.
  ///
  /// Ordinary English word order, and nothing cleverer. It is not a grammar —
  /// it cannot tell you that "want" takes an object — but it is enough to stop
  /// the strip offering five pronouns after a pronoun, and it works from the
  /// very first tap on a profile that has taught it nothing.
  ///
  /// Earlier in a list means offered first.
  static const _follows = <PartOfSpeech?, List<PartOfSpeech>>{
    // Opening a sentence.
    null: [
      PartOfSpeech.pronoun,
      PartOfSpeech.question,
      PartOfSpeech.social,
      PartOfSpeech.verb,
    ],
    PartOfSpeech.pronoun: [
      PartOfSpeech.verb,
      PartOfSpeech.negation,
      PartOfSpeech.adverb,
    ],
    PartOfSpeech.verb: [
      PartOfSpeech.determiner,
      PartOfSpeech.noun,
      PartOfSpeech.pronoun,
      PartOfSpeech.preposition,
      PartOfSpeech.adjective,
    ],
    PartOfSpeech.determiner: [PartOfSpeech.noun, PartOfSpeech.adjective],
    PartOfSpeech.adjective: [PartOfSpeech.noun],
    PartOfSpeech.noun: [
      PartOfSpeech.verb,
      PartOfSpeech.conjunction,
      PartOfSpeech.preposition,
      PartOfSpeech.adjective,
    ],
    PartOfSpeech.preposition: [
      PartOfSpeech.determiner,
      PartOfSpeech.noun,
      PartOfSpeech.pronoun,
    ],
    PartOfSpeech.adverb: [PartOfSpeech.verb, PartOfSpeech.adjective],
    PartOfSpeech.negation: [PartOfSpeech.verb, PartOfSpeech.pronoun],
    PartOfSpeech.question: [
      PartOfSpeech.pronoun,
      PartOfSpeech.verb,
      PartOfSpeech.noun,
    ],
    PartOfSpeech.conjunction: [
      PartOfSpeech.pronoun,
      PartOfSpeech.verb,
      PartOfSpeech.noun,
    ],
    PartOfSpeech.social: [PartOfSpeech.pronoun, PartOfSpeech.noun],
  };

  /// The home board's words, with the ones that can follow [previousPos]
  /// first.
  ///
  /// Home board only. A learned pair may surface any word on any board — that
  /// is the shortcut worth having — but guessing from grammar alone across
  /// several hundred words means picking arbitrarily between two hundred
  /// nouns. The home board is the core vocabulary, and its own reading order
  /// is meaningful: columns run in sentence order, leftmost are the pronouns.
  Future<List<String>> _wordsThatCanFollow(PartOfSpeech? previousPos) async {
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
          ]);

    final wanted = _follows[previousPos] ?? const <PartOfSpeech>[];

    // A stable sort over board order, so words of an equally likely class stay
    // in the order the board puts them and the strip does not reshuffle.
    final ranked = <({int rank, String message})>[];
    for (final row in await query.get()) {
      final button = row.readTable(_db.buttons);
      final index = wanted.indexOf(button.partOfSpeech ?? PartOfSpeech.other);
      ranked.add((
        rank: index == -1 ? wanted.length : index,
        message: button.message,
      ));
    }

    final order = List.generate(ranked.length, (i) => i)
      ..sort((a, b) {
        final byRank = ranked[a].rank.compareTo(ranked[b].rank);
        return byRank != 0 ? byRank : a.compareTo(b);
      });

    return [for (final i in order.take(_candidatePool)) ranked[i].message];
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
