/// English word forms, so a board does not need a cell per inflection.
///
/// Four buttons cover most of what a grid would otherwise spend dozens of
/// locations on: `want / wants / wanted / wanting` from one word plus one
/// suffix key. The cost is that the suffix has to be right — a board that
/// says "maked" teaches a mistake to someone who will repeat it, and who may
/// not be in a position to be corrected.
library;

import '../../db/tables.dart';

/// Past tenses that no rule produces.
///
/// Only verbs the shipped vocabulary can actually reach. Adding a verb to a
/// board means checking whether it belongs here too.
const _irregularPast = <String, String>{
  'go': 'went',
  'get': 'got',
  'do': 'did',
  'make': 'made',
  'put': 'put',
  'eat': 'ate',
  'drink': 'drank',
  'read': 'read',
  'draw': 'drew',
  'sing': 'sang',
  'run': 'ran',
  'can': 'could',
  'have': 'had',
  'is': 'was',
  'am': 'was',
  'are': 'were',
  'see': 'saw',
  'feel': 'felt',
  'hurt': 'hurt',
  'sleep': 'slept',
  'take': 'took',
  'come': 'came',
  'give': 'gave',
  'find': 'found',
  'buy': 'bought',
  'bring': 'brought',
  'think': 'thought',
  'say': 'said',
  'tell': 'told',
  'leave': 'left',
  'sit': 'sat',
  'stand': 'stood',
  'break': 'broke',
  'fall': 'fell',
  'hold': 'held',
  'hear': 'heard',
  'wear': 'wore',
  'win': 'won',
  'lose': 'lost',
  'cut': 'cut',
  'hit': 'hit',
  'let': 'let',
  'shut': 'shut',
};

/// Plurals and third-person singulars that no rule produces.
const _irregularPlural = <String, String>{
  'child': 'children',
  'person': 'people',
  'foot': 'feet',
  'tooth': 'teeth',
  'teeth': 'teeth',
  'man': 'men',
  'woman': 'women',
  'mouse': 'mice',
  'sheep': 'sheep',
  'fish': 'fish',
  'be': 'is',
  'have': 'has',
  'do': 'does',
  'go': 'goes',
};

const _vowels = 'aeiou';

/// Verbs and nouns whose final consonant doubles before a suffix.
///
/// The rule needs stress to be correct ("visit" does not double, "permit"
/// does), which is not recoverable from spelling. Restricted to
/// single-syllable words, where it is reliable.
bool _doublesFinalConsonant(String word) {
  if (word.length < 3) return false;

  final last = word[word.length - 1];
  final middle = word[word.length - 2];
  final first = word[word.length - 3];

  if (_vowels.contains(last) || last == 'y' || last == 'w' || last == 'x') {
    return false;
  }
  if (!_vowels.contains(middle)) return false;
  if (_vowels.contains(first)) return false;

  // One syllable only.
  return word.split('').where(_vowels.contains).length == 1;
}

String _addEd(String word) {
  final irregular = _irregularPast[word];
  if (irregular != null) return irregular;

  if (word.endsWith('e')) return '${word}d';
  if (word.endsWith('y') &&
      word.length > 1 &&
      !_vowels.contains(word[word.length - 2])) {
    return '${word.substring(0, word.length - 1)}ied';
  }
  if (_doublesFinalConsonant(word)) {
    return '$word${word[word.length - 1]}ed';
  }
  return '${word}ed';
}

String _addS(String word) {
  final irregular = _irregularPlural[word];
  if (irregular != null) return irregular;

  if (word.endsWith('s') ||
      word.endsWith('x') ||
      word.endsWith('z') ||
      word.endsWith('ch') ||
      word.endsWith('sh')) {
    return '${word}es';
  }
  if (word.endsWith('y') &&
      word.length > 1 &&
      !_vowels.contains(word[word.length - 2])) {
    return '${word.substring(0, word.length - 1)}ies';
  }
  return '${word}s';
}

String _addIng(String word) {
  if (word.endsWith('ie')) {
    return '${word.substring(0, word.length - 2)}ying';
  }
  // Keep the e in "see", "be", "agree" — it is part of the vowel sound.
  if (word.endsWith('e') && word.length > 2 && !word.endsWith('ee')) {
    return '${word.substring(0, word.length - 1)}ing';
  }
  if (_doublesFinalConsonant(word)) {
    return '$word${word[word.length - 1]}ing';
  }
  return '${word}ing';
}

String _addPossessive(String word) => word.endsWith('s') ? "$word'" : "$word's";

/// Rewrites [word] into the form [kind] asks for.
///
/// Case is preserved on the first letter so "I" does not come back lowercase.
String applyMorpheme(String word, MorphemeKind kind) {
  final trimmed = word.trim();
  if (trimmed.isEmpty) return trimmed;

  final lower = trimmed.toLowerCase();
  final inflected = switch (kind) {
    MorphemeKind.pluralS => _addS(lower),
    MorphemeKind.pastEd => _addEd(lower),
    MorphemeKind.ing => _addIng(lower),
    MorphemeKind.possessive => _addPossessive(lower),
    MorphemeKind.comparativeEr => _addComparative(lower, 'er'),
    MorphemeKind.superlativeEst => _addComparative(lower, 'est'),
  };

  if (trimmed[0] == trimmed[0].toUpperCase() &&
      trimmed[0] != trimmed[0].toLowerCase()) {
    return inflected[0].toUpperCase() + inflected.substring(1);
  }
  return inflected;
}

String _addComparative(String word, String suffix) {
  const irregular = {
    'good': 'better',
    'bad': 'worse',
    'far': 'further',
    'little': 'less',
    'much': 'more',
    'many': 'more',
  };
  if (suffix == 'er' && irregular.containsKey(word)) return irregular[word]!;
  if (suffix == 'est') {
    const superlatives = {'good': 'best', 'bad': 'worst', 'far': 'furthest'};
    if (superlatives.containsKey(word)) return superlatives[word]!;
  }

  if (word.endsWith('e')) return '$word$suffix';
  if (word.endsWith('y') &&
      word.length > 1 &&
      !_vowels.contains(word[word.length - 2])) {
    return '${word.substring(0, word.length - 1)}i$suffix';
  }
  if (_doublesFinalConsonant(word)) {
    return '$word${word[word.length - 1]}$suffix';
  }
  return '$word$suffix';
}

/// The form of "to be" that agrees with [subject].
///
/// One button covers am / is / are, and one more covers was / were, instead of
/// five separate cells. The agreement is what makes it worth doing: a user who
/// taps "I" then the copula gets "I am", which is the correct sentence rather
/// than a correct word next to a wrong one.
String copulaFor(String? subject, {required bool past}) {
  final s = subject?.trim().toLowerCase();

  const plural = {'you', 'we', 'they', 'people', 'everybody'};
  const firstPerson = {'i'};

  if (past) {
    return plural.contains(s) ? 'were' : 'was';
  }
  if (firstPerson.contains(s)) return 'am';
  if (plural.contains(s)) return 'are';
  return 'is';
}

/// Whether a grammar helper makes sense given what has been said so far.
///
/// Endings that cannot apply are hidden rather than moved: the cell stays
/// reserved and the button reappears in exactly the same place the moment it
/// becomes usable. This is the same rule the rest of the board follows —
/// nothing that has a location ever loses it — applied to a button whose
/// availability changes mid-sentence rather than over months.
///
/// The point is not tidiness. A grid that offers "+ed" with nothing to attach
/// it to invites a tap that produces nothing, and a button that sometimes
/// does nothing is one a user learns to distrust.
bool grammarHelperApplies({
  required MorphemeKind? kind,
  required String tense,
  required PartOfSpeech? previousPos,
  required bool previousInflected,
  required bool atStart,
}) {
  // Articles come before a noun phrase, so they belong at the start of a
  // sentence or after a verb or preposition — "want a drink", "in a car".
  if (tense == 'article') {
    if (atStart) return true;
    return switch (previousPos) {
      PartOfSpeech.verb ||
      PartOfSpeech.preposition ||
      PartOfSpeech.conjunction => true,
      _ => false,
    };
  }

  if (atStart) return false;

  // "to be" agrees with a subject, so it follows one. "want is" is not a
  // sentence anyone means to build.
  if (kind == null && (tense == 'present' || tense == 'past')) {
    return switch (previousPos) {
      PartOfSpeech.pronoun ||
      PartOfSpeech.noun ||
      PartOfSpeech.determiner => true,
      _ => false,
    };
  }

  // One suffix per word. Stacking them gives "wanteding".
  if (previousInflected) return false;

  return switch (kind) {
    MorphemeKind.pastEd || MorphemeKind.ing => previousPos == PartOfSpeech.verb,
    // Plural on a noun, third person on a verb — one key, two jobs.
    MorphemeKind.pluralS =>
      previousPos == PartOfSpeech.noun || previousPos == PartOfSpeech.verb,
    MorphemeKind.possessive =>
      previousPos == PartOfSpeech.noun || previousPos == PartOfSpeech.pronoun,
    MorphemeKind.comparativeEr ||
    MorphemeKind.superlativeEst => previousPos == PartOfSpeech.adjective,
    null => false,
  };
}
