/// Words the engine says wrong, and what to hand it instead (§4.86).
///
/// **The spelling on the board is not negotiable; what the engine is handed
/// is.** These are words a person reads, recognizes and has learned the
/// location of — changing the label to make the voice behave would fix the
/// sound by breaking the board. So the label stays, the utterance bar keeps
/// showing it, and only the string passed to the synthesizer is respelled.
///
/// **Interjections are where this bites.** They are the one part of the
/// vocabulary that is a sound rather than a word: `ow` is not an abbreviation
/// of anything, and a text-to-speech engine given three letters with no entry
/// in its dictionary falls back to letter rules that were built for words.
/// The result is close enough to be recognized as wrong and not close enough
/// to pass — which for a word whose entire job is to land in the moment is a
/// failure, because a listener who has to work out what they heard has already
/// missed it.
///
/// **Deliberately tiny, and only ever grown from something somebody heard.**
/// A respelling is a guess about one engine on one platform; guessing at a
/// word nobody has reported puts something nobody wrote into a person's mouth,
/// which is worse than a slightly odd vowel.
const _saidDifferently = <String, String>{
  // Reported as wrong on an iPad. The apostrophe is what stops the engine
  // running the two syllables together into something like "oo-oh".
  'uh oh': "u'h oh",
  // Three letters with no dictionary entry get letter rules, which give a
  // long o. This is the diphthong, spelled the way the engine reads it.
  'ow': 'ouw',
};

/// How [word] should be said, or null where it is said as written — which is
/// almost always.
String? spokenForm(String word) => _saidDifferently[word.trim().toLowerCase()];

/// [word] as it should reach the voice: the respelling where there is one, and
/// the word itself otherwise.
String asSpoken(String word) => spokenForm(word) ?? word;
