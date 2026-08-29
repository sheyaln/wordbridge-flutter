/// What ordinary English tends to put after a word, shipped with the app.
///
/// Prediction that has to be taught before it does anything is prediction that
/// never does anything: the strip would show the same five words after every
/// word until somebody had spoken enough whole sentences to move it, and long
/// before that they would have turned it off. So the app arrives already
/// knowing how sentences usually go, and what a person teaches it sits on top.
///
/// **Ranked below the user's own history, never above it.** These are what
/// people say in general; the pair table is what *this* person says. Where the
/// two disagree, this loses. A shipped guess must never displace something a
/// user actually did.
///
/// **Not a corpus and not a language model.** Ordinary collocations over the
/// vocabulary this app ships, written out by hand and readable in full. That
/// is a virtue rather than an apology — it works offline, it is the same for
/// everybody, it cannot leak, and anybody can read the whole of what the app
/// believes about English in one sitting and argue with it.
///
/// Keys are lowercase, and the empty key is the start of a sentence. Words
/// that are not on a given user's boards are skipped when the strip is built,
/// so an entry naming a word a profile does not have costs nothing.
library;

const starterPredictions = <String, List<String>>{
  // Opening a sentence. Pronouns first: most sentences begin with who.
  '': ['I', 'you', 'what', 'it', 'we', 'more', 'help', 'where', 'no', 'yes'],

  // Pronouns want a verb.
  'i': ['want', 'need', 'like', 'feel', 'think', 'know', 'see', 'can', 'go'],
  'you': ['want', 'can', 'like', 'go', 'help', 'see', 'know', 'do'],
  'he': ['can', 'go', 'want', 'like', 'see', 'help'],
  'she': ['can', 'go', 'want', 'like', 'see', 'help'],
  'we': ['can', 'go', 'want', 'like', 'need', 'see'],
  'they': ['can', 'go', 'want', 'like', 'see'],
  'it': ['good', 'not', 'here', 'more', 'all'],
  'that': ['good', 'not', 'more', 'here', 'one'],
  'my': ['turn', 'mum', 'dad', 'book', 'ball', 'drink'],
  'me': ['more', 'that', 'please', 'it'],

  // Verbs want an object, a direction, or another verb.
  'want': ['more', 'that', 'it', 'to', 'some', 'all', 'drink', 'food'],
  'need': ['help', 'more', 'to', 'that', 'it', 'toilet'],
  'like': ['it', 'that', 'more', 'this', 'you'],
  'go': ['to', 'out', 'in', 'home', 'up', 'play'],
  'stop': ['it', 'that', 'please'],
  'can': ['I', 'you', 'we', 'go', 'help'],
  'get': ['it', 'more', 'that', 'up', 'some', 'drink'],
  'take': ['it', 'that', 'me', 'some'],
  'do': ['it', 'that', 'more', 'you', 'not'],
  'make': ['it', 'that', 'more', 'some'],
  'put': ['it', 'that', 'in', 'on', 'up'],
  'will': ['you', 'I', 'we', 'go'],
  'open': ['it', 'that'],
  'close': ['it', 'that'],
  'help': ['me', 'you', 'please'],
  'look': ['here', 'that', 'it', 'up'],
  'turn': ['it', 'on', 'up'],
  'know': ['it', 'that', 'you', 'what'],
  'think': ['I', 'it', 'that', 'so', 'you'],
  'say': ['it', 'that', 'no', 'yes', 'please'],
  'tell': ['me', 'you'],
  'see': ['it', 'that', 'you', 'me', 'more'],
  'come': ['here', 'in', 'out', 'up'],
  'give': ['me', 'it', 'that', 'more'],
  'feel': ['good', 'not', 'more'],
  'eat': ['more', 'it', 'food'],
  'play': ['more', 'ball', 'with', 'it'],
  'finished': ['I', 'yes', 'no', 'more'],

  // Joining words hand back to a pronoun.
  'and': ['I', 'you', 'it', 'we', 'more'],
  'but': ['I', 'you', 'not', 'it', 'we'],
  'because': ['I', 'you', 'it', 'we', 'that'],
  'so': ['I', 'you', 'it', 'we', 'that'],

  // Where and how.
  'here': ['it', 'I', 'more', 'now'],
  'in': ['it', 'here', 'my'],
  'on': ['it', 'here', 'my'],
  'up': ['it', 'I', 'more'],
  'out': ['I', 'we', 'go', 'here'],
  'to': ['go', 'do', 'see', 'make', 'play', 'eat'],
  'home': ['I', 'we', 'go', 'now'],

  // Yes, no, and the words that carry feeling.
  'good': ['I', 'you', 'it', 'that', 'thank you'],
  'not': ['good', 'want', 'I', 'you', 'here'],
  'yes': ['I', 'please', 'more', 'thank you'],
  'no': ['I', 'not', 'more', 'stop', 'thank you'],
  'wait': ['I', 'please', 'stop'],
  "don't": ['want', 'like', 'know', 'go', 'stop'],
  'more': ['please', 'that', 'it', 'drink', 'food'],
  'some': ['more', 'that', 'it', 'food', 'drink'],
  'all': ['finished', 'more', 'good'],
  'this': ['good', 'not', 'more', 'it', 'one'],
  'same': ['good', 'more', 'it'],
  'different': ['good', 'more', 'it'],
  'please': ['I', 'more', 'help', 'thank you'],
  'hello': ['I', 'you', 'mum', 'dad'],
  'mum': ['I', 'help', 'look', 'want'],
  'dad': ['I', 'help', 'look', 'want'],

  // Questions.
  'what': ['that', 'you', 'I', 'do', 'is'],
  'where': ['you', 'my', 'I', 'that', 'is'],
  'who': ['you', 'that', 'I', 'is'],
  'when': ['we', 'you', 'I', 'can'],
  'why': ['not', 'you', 'I', 'can'],
};
