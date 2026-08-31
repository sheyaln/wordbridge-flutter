/// Joining a word to the "not" behind it — "can" and "not" become "can't".
///
/// Asked for as *"can't (maybe auto-abbreviate when 'can' is followed by
/// 'not')"* and settled in §4.42 as a setting rather than a rule: contraction
/// is a house style, not a correctness fix, and a team that wants the board to
/// say exactly what was pressed is not wrong.
///
/// It is the same shape as the "a" → "an" repair, and for the same reason. The
/// user cannot know how the sentence will continue when they press the first
/// word, so the sentence is corrected behind them once it does.
library;

/// The contraction of [word] with a following "not", or null where English
/// has none.
///
/// A table rather than a rule, because the rule has as many exceptions as
/// members: "will not" is "won't", and nothing about the spelling of "will"
/// predicts that.
///
/// **"am" is deliberately absent.** English contracts "I am not" by moving the
/// apostrophe to the subject — "I'm not" — and "amn't" is not a word anybody
/// says. Contracting the subject is a different rule that reaches back past the
/// word behind, and it is not this one.
String? contractionFor(String word) => switch (word.trim().toLowerCase()) {
  'can' => "can't",
  'will' => "won't",
  'shall' => "shan't",

  'is' => "isn't",
  'are' => "aren't",
  'was' => "wasn't",
  'were' => "weren't",

  'do' => "don't",
  'does' => "doesn't",
  'did' => "didn't",

  'have' => "haven't",
  'has' => "hasn't",
  'had' => "hadn't",

  'could' => "couldn't",
  'would' => "wouldn't",
  'should' => "shouldn't",
  'must' => "mustn't",
  'might' => "mightn't",

  _ => null,
};

/// Whether [word] is the "not" a contraction joins to.
bool isNegation(String word) => word.trim().toLowerCase() == 'not';
