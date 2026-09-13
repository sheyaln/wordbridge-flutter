import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';

/// One word, one location — unless the two are different kinds of word.
///
/// The board's oldest rule. A word in two places is two things to learn about
/// one word: two pictures to recognize, two movements to remember, and no way
/// to tell which one somebody meant. It costs a location on a board that has
/// none spare, and it buys nothing, because either location already says it.
///
/// **The exception is a word that is genuinely two words.** `dress` is a
/// garment and an action, `light` is a lamp and a weight, `orange` is a fruit
/// and a color — different parts of speech, different pictures, and the board
/// somebody is standing on says which one they meant. Those are not
/// duplicates and this test works them out from the part of speech rather than
/// from a list anybody has to maintain.
///
/// **It is easy to break by accident and invisible when you do.** Every batch
/// of vocabulary is written against one board at a time, and the word that
/// collides is on a board nobody was looking at — `sand` went onto `nature`
/// while it was already the thing a child digs in on `play`. Nothing failed;
/// the board simply had it twice. So this walks the whole shipped set instead
/// of trusting anybody to remember.
void main() {
  /// Words the board carries twice on purpose (§4.15).
  ///
  /// A homograph is two words that share a spelling, and the board separates
  /// them the only way it can: by board and by region, so which one somebody
  /// meant is answered by where they were standing. Adding to this list is a
  /// decision, not a fix — if the two uses are the same word, one of them
  /// should go.
  /// Same word, same part of speech, two boards — kept on purpose.
  ///
  /// **The rule is the part of speech, not this list.** A word carried twice
  /// is fine when the two copies are different kinds of word: `dress` the
  /// garment and `dress` the action, `light` the lamp and `light` the weight,
  /// `orange` the fruit and `orange` the color. Those are two words that share
  /// a spelling, the board each is on says which, and the test below works
  /// that out for itself rather than being told.
  ///
  /// This list is only for the ones that share a part of speech as well, where
  /// the second copy has to be argued for rather than derived.
  const sameKindOnPurpose = {
    // The bird on `animals` and the dinner on `food`. Both nouns, and still
    // two things: one is alive in a field and the other is on a plate, and a
    // child asking for one is not asking for the other.
    'chicken',
    // The board's own name, on the board it names.
    'weather',
    'animal',
    'animals',
  };

  /// Same word, same part of speech, from before this test existed.
  ///
  /// **Empty, and that is the point.** It held six — `doctor`, `nurse`,
  /// `thirsty`, `bike`, `itchy` and `like` — and every one of them was one
  /// word in two places rather than two words that share a spelling. Each has
  /// been given a single home: the board somebody is standing on when they
  /// need the word. `doctor` and `nurse` to `health`, `thirsty` to `food`,
  /// `itchy` to `health`, `bike` to `play`, `like` to the root board.
  ///
  /// **Do not add to this list.** A new word that collides can simply go in
  /// one place.
  const alreadyDoubled = <String>{};

  final pinned = {for (final q in pinnedQuestions) q.value.label};

  test('no word is on two boards unless it is meant to be', () async {
    final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);

    final names = {
      for (final b in await (db.select(
        db.boards,
      )..where((b) => b.vocabularyId.equals(vocabId))).get())
        b.id: b.name,
    };

    final rows = await (db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.buttons.vocabularyId.equals(vocabId))).get();

    // System keys are on every board by design — that is what makes them
    // fixed — so they are not what this is about.
    final boardsFor = <String, Set<String>>{};
    // What kind of word each copy is. Two copies of different kinds are two
    // words that share a spelling, which is allowed; two of the same kind are
    // one word in two places, which has to be argued for.
    final kindsFor = <String, Set<String>>{};
    for (final r in rows) {
      final button = r.readTable(db.buttons);
      if (button.isSystem) continue;
      // The pinned question column is on every board on purpose and its
      // buttons are not system keys — they are ordinary vocabulary that
      // happens to be pinned, which is what keeps them the right colour and
      // editable. They are the one thing that is *supposed* to be everywhere.
      if (pinned.contains(button.label)) continue;
      boardsFor
          .putIfAbsent(button.label, () => <String>{})
          .add(names[r.readTable(db.cells).boardId]!);
      kindsFor
          .putIfAbsent(button.label, () => <String>{})
          .add(button.partOfSpeech?.name ?? 'none');
    }

    final doubled = {
      for (final entry in boardsFor.entries)
        if (entry.value.length > 1 &&
            (kindsFor[entry.key]?.length ?? 1) == 1 &&
            !sameKindOnPurpose.contains(entry.key) &&
            !alreadyDoubled.contains(entry.key))
          entry.key: entry.value.toList()..sort(),
    };

    expect(
      doubled,
      isEmpty,
      reason:
          'these words are on more than one board with the same part of '
          'speech, so they are one word in two places rather than two words '
          'that share a spelling. Either one copy should go, or — if they '
          'really are two things, as the bird and the dinner are — say so in '
          'sameKindOnPurpose above',
    );
  });
}
