/// Joining two pressed words into the one word English says — "can" and "not"
/// become "can't", "I" and "am" become "I'm".
///
/// Asked for as *"can't (maybe auto-abbreviate when 'can' is followed by
/// 'not')"* and settled in §4.42 as a setting rather than a rule: contraction
/// is a house style, not a correctness fix, and a team that wants the board to
/// say exactly what was pressed is not wrong.
///
/// It is the same shape as the "a" → "an" repair, and for the same reason. The
/// user cannot know how the sentence will continue when they press the first
/// word, so the sentence is corrected behind them once it does.
///
/// Originally this joined to "not" and nothing else, which covered the half of
/// English contraction a board reaches by pressing an auxiliary and then a
/// negation — and left the half a board reaches far more often. A user builds
/// "I am hungry" one key at a time and hears *I am hungry*, in a voice nobody
/// speaks in, because the pair that contracts there is subject and auxiliary.
library;

/// Every pair English joins, keyed by the first word.
///
/// A table rather than a rule, because the rule has as many exceptions as
/// members: "will not" is "won't", and nothing about the spelling of "will"
/// predicts that.
///
/// Lower case throughout; [contractionOf] restores the case of what was
/// pressed, so a board whose keys are capitalized does not start saying "i'm".
const _pairs = <String, Map<String, String>>{
  // Auxiliary + negation. "am" is deliberately absent: English contracts
  // "I am not" by moving the apostrophe to the subject — "I'm not" — and
  // "amn't" is not a word anybody says. That sentence is reached here as the
  // subject pair below, and then "not" stands alone, which is correct.
  'can': {'not': "can't"},
  'will': {'not': "won't"},
  'shall': {'not': "shan't"},
  'is': {'not': "isn't"},
  'are': {'not': "aren't"},
  'was': {'not': "wasn't"},
  'were': {'not': "weren't"},
  'do': {'not': "don't"},
  'does': {'not': "doesn't"},
  'did': {'not': "didn't"},
  'have': {'not': "haven't"},
  'has': {'not': "hasn't"},
  'had': {'not': "hadn't"},
  'could': {'not': "couldn't"},
  'would': {'not': "wouldn't"},
  'should': {'not': "shouldn't"},
  'must': {'not': "mustn't"},
  'might': {'not': "mightn't"},

  // Subject + auxiliary. "have" and "has" contract only as the perfect
  // auxiliary — "I've eaten" — and a board cannot tell that from possession
  // when the word is pressed, so "I have" is left alone and only "I've" via a
  // following verb would be right. Left out rather than guessed at: saying
  // "I've a drink" for a request is worse than saying "I have a drink".
  'i': {'am': "I'm", 'will': "I'll", 'would': "I'd"},
  'you': {'are': "you're", 'will': "you'll", 'would': "you'd"},
  'he': {'is': "he's", 'will': "he'll", 'would': "he'd"},
  'she': {'is': "she's", 'will': "she'll", 'would': "she'd"},
  'it': {'is': "it's", 'will': "it'll", 'would': "it'd"},
  'we': {'are': "we're", 'will': "we'll", 'would': "we'd"},
  'they': {'are': "they're", 'will': "they'll", 'would': "they'd"},

  // Demonstratives, existentials and question words, which a board presses in
  // exactly this order to ask something.
  'that': {'is': "that's", 'will': "that'll"},
  'there': {'is': "there's", 'will': "there'll"},
  'here': {'is': "here's"},
  'what': {'is': "what's", 'are': "what're"},
  'where': {'is': "where's", 'are': "where're"},
  'who': {'is': "who's", 'are': "who're"},
  'how': {'is': "how's"},
  'why': {'is': "why's"},
  'let': {'us': "let's"},
};

/// The contraction of [first] followed by [second], or null where English
/// joins nothing there.
///
/// The capitalization of [first] is carried onto the result, because the
/// pressed word is what the board shows and a sentence that starts "i'm"
/// reads as a typo the user did not make.
String? contractionOf(String first, String second) {
  final joined =
      _pairs[first.trim().toLowerCase()]?[second.trim().toLowerCase()];
  if (joined == null) return null;

  final head = first.trim();
  if (head.isEmpty) return joined;

  // "I'm" is already capitalized in the table — "i" is the one English word
  // that carries its case in the dictionary — so only a key that was
  // capitalized itself may change what is returned.
  final capitalized = head[0].toUpperCase() == head[0];
  if (!capitalized) return joined;
  return joined[0].toUpperCase() + joined.substring(1);
}

/// Whether pressing [word] can join it to something in front of it.
///
/// Cheap, and asked on every press before the sentence is looked at.
bool canFollowInContraction(String word) {
  final needle = word.trim().toLowerCase();
  for (final seconds in _pairs.values) {
    if (seconds.containsKey(needle)) return true;
  }
  return false;
}
