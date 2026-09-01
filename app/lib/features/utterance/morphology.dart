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
/// It used to hold only the verbs the shipped vocabulary could reach, which
/// meant a caregiver who added `swim` to a board got `swimmed` from the "+ed"
/// key — a wrong word, said out loud, by a key that looked like it worked.
/// The table is developer-maintained and the editor does not prompt for a
/// form, so the answer is to maintain it: it now covers the ordinary irregular
/// verbs of English whether or not this app ships them, and a caregiver's own
/// verb is as likely to be right as a seeded one.
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

  // Not in the shipped vocabulary, and reachable the moment somebody adds one.
  'swim': 'swam',
  'fly': 'flew',
  'drive': 'drove',
  'ride': 'rode',
  'write': 'wrote',
  'speak': 'spoke',
  'choose': 'chose',
  'forget': 'forgot',
  'begin': 'began',
  'blow': 'blew',
  'grow': 'grew',
  'know': 'knew',
  'throw': 'threw',
  'build': 'built',
  'send': 'sent',
  'spend': 'spent',
  'lend': 'lent',
  'feed': 'fed',
  'meet': 'met',
  'keep': 'kept',
  'sweep': 'swept',
  'creep': 'crept',
  'teach': 'taught',
  'catch': 'caught',
  'fight': 'fought',
  'seek': 'sought',
  'sell': 'sold',
  'bite': 'bit',
  'hide': 'hid',
  'shake': 'shook',
  'wake': 'woke',
  'freeze': 'froze',
  'steal': 'stole',
  'swing': 'swung',
  'ring': 'rang',
  'stick': 'stuck',
  'dig': 'dug',
  'lead': 'led',
  'bleed': 'bled',
  'shoot': 'shot',
  'mean': 'meant',
  'deal': 'dealt',
  'burn': 'burnt',
  'learn': 'learned',
  'smell': 'smelt',
  'spell': 'spelled',
  'spill': 'spilt',
  'spoil': 'spoilt',
  'cost': 'cost',
  'quit': 'quit',
  'set': 'set',
  'spread': 'spread',
  'burst': 'burst',
  'become': 'became',
  'lie': 'lay',
  'lay': 'laid',
  'pay': 'paid',
  'wind': 'wound',
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
///
/// A null subject means the copula opens the sentence and the subject has yet
/// to be tapped. The default it takes is settled by [copulaAgreeingWith].
String copulaFor(String? subject, {required bool past}) {
  final s = subject?.trim().toLowerCase();

  // "people" is the only plural noun here. The -body pronouns take the
  // singular: "everybody is here", "nobody is listening".
  const plural = {'you', 'we', 'they', 'people'};
  const firstPerson = {'i'};

  if (past) {
    return plural.contains(s) ? 'were' : 'was';
  }
  if (firstPerson.contains(s)) return 'am';
  if (plural.contains(s)) return 'are';
  return 'is';
}

/// The forms of "to be", in the order the copula keys cycle them.
///
/// A fixed ring rather than one reordered by what fits: the number of presses
/// between any two forms is then the same every time, which is the same
/// promise the rest of the board makes. "are" sits second because a sentence
/// that opens with the copula is far more often "are you...?" than "am I...?",
/// so the second press is the one worth making cheap.
const presentCopulaRing = <String>['is', 'are', 'am'];

const pastCopulaRing = <String>['was', 'were'];

/// Whether [word] is a form of "to be".
bool isCopula(String word) {
  final form = word.trim().toLowerCase();
  return presentCopulaRing.contains(form) || pastCopulaRing.contains(form);
}

/// The ring [word] belongs to, or null if it is not a form of "to be".
List<String>? copulaRingFor(String word) {
  final form = word.trim().toLowerCase();
  if (presentCopulaRing.contains(form)) return presentCopulaRing;
  if (pastCopulaRing.contains(form)) return pastCopulaRing;
  return null;
}

/// The form after [word] in its own ring, wrapping at the end.
///
/// Null for a word that is not a form of "to be".
String? nextCopulaForm(String word) {
  final ring = copulaRingFor(word);
  if (ring == null) return null;

  final at = ring.indexOf(word.trim().toLowerCase());
  return ring[(at + 1) % ring.length];
}

/// How the copula keys choose between the forms of "to be".
///
/// One key holds am/is/are and one holds was/were, so something has to decide
/// which form a press produces. The two answers differ only where the subject
/// has yet to be tapped, which is to say at the start of a question.
enum CopulaMode {
  /// Each further press replaces the form before it with the next in the ring
  /// and speaks it, so the choice is made by ear and nothing is corrected
  /// afterwards.
  ///
  /// The first press still agrees with a subject already in the bar, which is
  /// what keeps this cheap: mid-sentence it is right without a second press.
  toggle('Press again to change it'),

  /// A provisional form goes in and settles when the subject arrives, the way
  /// "a" becomes "an".
  agree('Correct it once the subject arrives');

  const CopulaMode(this.label);

  final String label;
}

/// The form of "to be" that agrees with a subject arriving after it.
///
/// A question inverts subject and verb — "are you ok?", "what is that?",
/// "was it my turn?" — so the copula is placed before there is anything to
/// agree with, and settles once the subject lands. Tense is read off the form
/// already placed, so the two copula keys stay one path.
///
/// Null for a word that is not a form of "to be", which is left as it is.
String? copulaAgreeingWith(String copula, String subject) {
  final form = copula.trim().toLowerCase();
  if (presentCopulaRing.contains(form)) return copulaFor(subject, past: false);
  if (pastCopulaRing.contains(form)) return copulaFor(subject, past: true);
  return null;
}

/// Determiners that stand for a thing, so a verb can follow one directly.
///
/// "this is mine" is a sentence. "a is", "the is", "some is" and "more is" are
/// not: those are placed for a noun that has yet to be tapped.
const _demonstratives = {'this', 'that', 'these', 'those'};

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
  required String? previousText,
  required PartOfSpeech? previousPos,
  required bool previousInflected,
  required bool atStart,
  required bool copulaCycles,
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

  // "to be" agrees with a subject, and a question puts that subject after it —
  // "are you ok?", "what is that?" — so it opens a sentence, and follows a
  // question word, as readily as it follows a subject. Where it does follow a
  // subject, that word has to be one: "want is" is not a sentence anyone means
  // to build.
  if (kind == null && (tense == 'present' || tense == 'past')) {
    if (atStart) return true;

    // A key that changes the word it just produced has to stay reachable while
    // that word is the last one, or the second press has nowhere to land.
    // Every other rule here withholds a key that would do nothing; this one is
    // the reverse, and it only opens where the press does something.
    if (copulaCycles && isCopula(previousText ?? '')) return true;

    return switch (previousPos) {
      PartOfSpeech.pronoun ||
      PartOfSpeech.noun ||
      PartOfSpeech.question => true,
      PartOfSpeech.determiner => _demonstratives.contains(
        previousText?.trim().toLowerCase(),
      ),
      _ => false,
    };
  }

  // An ending needs a word to attach to.
  if (atStart) return false;

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

/// Whether an ordinary word should be offered after what has been said.
///
/// Only ever restricts verbs, and only when the caregiver has asked for it.
/// English does not allow two bare verbs in a row — "I want go" is not a
/// sentence — so after a verb the other verbs are noise until something
/// licenses another one. "to" is what licenses it: "I want **to** go".
///
/// Off by default, because a board that changes shape as you build a sentence
/// is harder to learn than one that does not, and that trade is a judgment
/// about a particular person rather than a fact about English.
bool verbIsOfferable({
  required PartOfSpeech? pos,
  required String? previousText,
  required PartOfSpeech? previousPos,
}) {
  if (pos != PartOfSpeech.verb) return true;
  if (previousPos != PartOfSpeech.verb) return true;

  // An infinitive marker or a modal opens the door to a second verb.
  const licensors = {'to', 'will', 'can', 'need', 'want'};
  return licensors.contains(previousText?.toLowerCase());
}
