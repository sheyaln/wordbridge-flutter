import 'package:drift/drift.dart';

import '../../../db/database.dart';
import '../../../db/tables.dart';
import '../../utterance/morphology.dart';
import '../speech_engine.dart';

/// Everything a board can say, in the order it is worth having.
///
/// **The count is 1231, not 377.** The locations are 377, but a location is
/// not an utterance: measured over the shipped vocabulary it comes out as 444
/// distinct bare words across the three age presets, **782 inflected forms**,
/// and 5 forms of "to be". The endings are the majority and they are the easy
/// half to forget — a morpheme key speaks the form it just produced, so
/// `wanted`, `eating` and `leg's` each need audio of their own.
///
/// Derived from the board rather than from the seed on purpose. The seed is
/// what a profile *started* with; the board is what it says now, and a word a
/// caregiver added is exactly as much a word as one that shipped.
///
/// Ordered by vocabulary level, then bare words before their endings. A bake
/// is twenty-seven minutes and the board is in use throughout it, so the order
/// decides what a person can say in the first five: everything drawn at level
/// one, before anything that is not drawn at all yet.
Future<List<String>> bakeVocabulary(
  WordbridgeDatabase db,
  String vocabularyId,
) async {
  final buttons =
      await (db.select(db.buttons)..where(
            (b) =>
                b.vocabularyId.equals(vocabularyId) & b.deletedAt.isNull(),
          ))
          .get();

  final bare = <_Word>[];
  final seen = <String>{};

  void take(String? text, int level) {
    final spoken = normaliseForSpeech(text ?? '');
    if (spoken.isEmpty) return;
    if (!seen.add(spoken)) return;
    bare.add((text: spoken, level: level));
  }

  for (final button in buttons) {
    switch (button.action) {
      case ButtonAction.speak:
        take(button.speakText ?? button.message, button.vocabLevel);

      case ButtonAction.morpheme:
        // Articles append a word of their own and speak its label. Suffix keys
        // speak the form they produced, which is handled below, and the copula
        // keys speak a form of "to be", which is a fixed ring.
        if (button.morphemeKind == null && button.message == 'article') {
          take(button.label, button.vocabLevel);
        }

      case _:
        break;
    }
  }

  // Both rings in full. Five strings, and every one of them is reachable from
  // the first press of a copula key on some subject or other.
  for (final form in [...presentCopulaRing, ...pastCopulaRing]) {
    take(form, 1);
  }

  final inflected = <_Word>[];
  for (final button in buttons) {
    if (button.action != ButtonAction.speak) continue;
    final word = normaliseForSpeech(button.speakText ?? button.message);
    if (word.isEmpty) continue;

    for (final kind in MorphemeKind.values) {
      // The same test the board itself applies before it will offer the key.
      // Anything it would not offer is a form the user cannot reach, and audio
      // for it is twenty seconds of bake nobody hears.
      final offered = grammarHelperApplies(
        kind: kind,
        tense: '',
        previousText: word,
        previousPos: button.partOfSpeech,
        previousInflected: false,
        atStart: false,
        copulaCycles: true,
      );
      if (!offered) continue;

      final form = applyMorpheme(word, kind);
      if (form == word) continue;
      if (!seen.add(form)) continue;
      inflected.add((text: form, level: button.vocabLevel));
    }
  }

  int byLevel(_Word a, _Word b) {
    final level = a.level.compareTo(b.level);
    return level != 0 ? level : a.text.compareTo(b.text);
  }

  bare.sort(byLevel);
  inflected.sort(byLevel);

  return [
    for (final word in bare) word.text,
    for (final word in inflected) word.text,
  ];
}

typedef _Word = ({String text, int level});
