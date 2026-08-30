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
///
/// Category vocabulary earns its place here twice over. The grammatical
/// fallback that fills a short strip reads the root board only, so a food, body
/// or feelings word can reach the strip no other way until it has been taught —
/// and reaching it by hand costs a board change, which is exactly the tap this
/// is here to save.
library;

const starterPredictions = <String, List<String>>{
  // Opening a sentence. Pronouns first: most sentences begin with who.
  '': ['I', 'you', 'what', 'it', 'more', 'no', 'help', 'where'],

  // Pronouns want a verb.
  'i': ['want', 'need', 'like', 'feel', 'can', "don't", 'go', 'know'],
  'you': ['want', 'can', 'like', 'help', 'go', 'see', 'know', 'do'],
  'he': ['can', 'want', 'go', 'like', 'see', 'help'],
  'she': ['can', 'want', 'go', 'like', 'see', 'help'],
  'we': ['can', 'go', 'want', 'need', 'like', 'see'],
  'they': ['can', 'go', 'want', 'like', 'see'],
  'it': ['good', 'not', 'yucky', 'yummy', 'here', 'more', 'hurt'],
  'that': ['good', 'not', 'more', 'please', 'here', 'yucky'],
  // Body parts and people, because "my" is how both get claimed.
  'my': ['turn', 'tummy', 'head', 'mum', 'dad', 'friend', 'name', 'book'],
  'me': ['more', 'please', 'that', 'it', 'up'],

  // Verbs want an object, a direction, or another verb.
  'want': ['more', 'to', 'food', 'drink', 'that', 'it', 'snack', 'toilet'],
  'need': ['help', 'to', 'toilet', 'more', 'drink', 'medicine', 'that'],
  'like': ['it', 'that', 'this', 'more', 'you'],
  'go': ['to', 'home', 'out', 'outside', 'school', 'park', 'in', 'up'],
  'stop': ['it', 'that', 'please'],
  'can': ['I', 'you', 'we', 'go', 'help', 'he', 'she'],
  'get': ['it', 'more', 'that', 'up', 'drink', 'water', 'some'],
  'take': ['it', 'that', 'me', 'medicine', 'some'],
  'do': ['it', 'that', 'more', 'you', 'not'],
  'make': ['it', 'that', 'more', 'some'],
  'put': ['it', 'that', 'in', 'on', 'up'],
  'will': ['you', 'I', 'we', 'go', 'help'],
  'open': ['it', 'door', 'window', 'that'],
  'close': ['it', 'door', 'window', 'that'],
  'help': ['me', 'please', 'you', 'us', 'him', 'her'],
  'look': ['here', 'that', 'it', 'up', 'outside'],
  'turn': ['it', 'on', 'up', 'music', 'tablet'],
  'know': ['it', 'that', 'you', 'what', 'why'],
  'think': ['so', 'I', 'it', 'that', 'you'],
  'say': ['it', 'that', 'no', 'yes', 'please', 'hello'],
  'tell': ['me', 'you', 'mum', 'dad', 'him', 'her'],
  'see': ['it', 'that', 'you', 'me', 'more'],
  'come': ['here', 'in', 'out', 'up', 'outside'],
  'give': ['me', 'it', 'that', 'more', 'him', 'her'],
  // A feeling word, not "good": the whole reason to reach for "feel" is to say
  // something the strip cannot get to from the root board.
  'feel': ['sad', 'sick', 'tired', 'happy', 'angry', 'scared', 'poorly'],
  'love': ['you', 'it', 'that', 'mum', 'dad', 'music'],
  'hate': ['it', 'that', 'this', 'school', 'you'],
  'miss': ['you', 'mum', 'dad', 'home', 'him', 'her'],
  'wait': ['please', 'here', 'I', 'stop'],
  'finish': ['I', 'yes', 'no', 'more'],

  // Joining words hand back to a pronoun.
  'and': ['I', 'you', 'it', 'we', 'more'],
  'but': ['I', 'you', 'not', 'it', 'we'],
  'because': ['I', 'my', 'you', 'it', 'that'],
  'so': ['I', 'you', 'it', 'we', 'that'],

  // Where and how.
  'here': ['I', 'it', 'please', 'more'],
  'in': ['here', 'my', 'it', 'car', 'bedroom', 'kitchen'],
  'on': ['it', 'my', 'here', 'tablet'],
  'up': ['I', 'it', 'more', 'please'],
  'out': ['I', 'we', 'go', 'here', 'outside'],
  // Both jobs of "to" at once: the second verb of "I want to go", and the
  // destination of "go to school".
  'to': ['go', 'school', 'home', 'toilet', 'park', 'see', 'eat', 'play'],
  'home': ['I', 'we', 'go', 'please'],
  'outside': ['play', 'go', 'I', 'we', 'please'],
  'inside': ['go', 'play', 'I', 'we'],

  // Yes, no, and the words that carry feeling.
  'good': ['I', 'you', 'it', 'that', 'thank you'],
  'not': ['good', 'want', 'I', 'hungry', 'ready', 'here'],
  'yes': ['please', 'I', 'more', 'thank you'],
  'no': ['thank you', 'not', 'I', 'more', 'stop'],
  "don't": ['want', 'like', 'know', 'go', 'stop'],
  'more': ['please', 'food', 'drink', 'water', 'snack', 'that'],
  'some': ['more', 'water', 'juice', 'milk', 'that', 'it'],
  'all': ['finish', 'more', 'good'],
  'this': ['good', 'not', 'more', 'it', 'please'],
  'same': ['good', 'more', 'it', 'please'],
  'different': ['good', 'more', 'it', 'please'],
  'please': ['I', 'more', 'help', 'thank you'],
  'enough': ['stop', 'thank you', 'I', 'no'],
  'ready': ['I', 'yes', 'go', 'not'],
  'wrong': ['you', 'that', 'no', 'not', 'I'],

  // Greeting and naming a person, which on this board is a way of getting one.
  'hello': ['mum', 'dad', 'I', 'you', 'teacher', 'friend'],
  'bye': ['mum', 'dad', 'you', 'thank you'],
  'thank you': ['I', 'you', 'mum', 'dad', 'bye'],
  'mum': ['help', 'I', 'look', 'come', 'here', 'please'],
  'dad': ['help', 'I', 'look', 'come', 'here', 'please'],
  'brother': ['I', 'here', 'play', 'come', 'help'],
  'sister': ['I', 'here', 'play', 'come', 'help'],
  'friend': ['my', 'here', 'play', 'I', 'come', 'school'],
  'teacher': ['help', 'I', 'here', 'school', 'come'],
  'doctor': ['help', 'I', 'see', 'hospital', 'here'],
  'nurse': ['help', 'I', 'here', 'hospital'],

  // Food. A drink or a meal is nearly always a request, so "please" and "more"
  // sit near the front of every one of these.
  'eat': ['food', 'more', 'lunch', 'dinner', 'breakfast', 'snack', 'toast'],
  'drink': ['water', 'milk', 'juice', 'squash', 'more', 'please'],
  'hungry': ['food', 'please', 'snack', 'lunch', 'more', 'dinner'],
  'food': ['please', 'more', 'I', 'yummy', 'hungry'],
  'thirsty': ['please', 'water', 'drink', 'juice', 'squash', 'I'],
  'yummy': ['more', 'please', 'I', 'thank you'],
  'yucky': ['no', 'not', 'stop', 'different', 'I'],
  'water': ['please', 'more', 'I', 'cold', 'thank you'],
  'milk': ['please', 'more', 'I', 'cold'],
  'juice': ['please', 'more', 'I'],
  'bread': ['butter', 'jam', 'cheese', 'please', 'more'],
  'toast': ['butter', 'jam', 'honey', 'please', 'more'],
  'apple': ['please', 'more', 'I', 'yummy'],
  'snack': ['please', 'more', 'I', 'want'],
  'breakfast': ['please', 'ready', 'I', 'more', 'finish'],
  'lunch': ['please', 'ready', 'I', 'more', 'finish'],
  'dinner': ['please', 'ready', 'I', 'more', 'finish'],

  // Feelings. "because" first, because a feeling nobody is given a reason for
  // gets managed rather than answered.
  'happy': ['because', 'thank you', 'I', 'you', 'good'],
  'sad': ['because', 'help', 'I', 'mum', 'dad'],
  'angry': ['because', 'stop', 'I', 'leave me alone', 'you'],
  'scared': ['because', 'help', 'I', 'mum', 'stop'],
  'tired': ['I', 'because', 'home', 'bedroom', 'please'],
  'excited': ['because', 'I', 'yes', 'more'],
  'bored': ['because', 'I', 'play', 'different', 'more'],
  'sick': ['I', 'help', 'toilet', 'home', 'because'],
  'hurt': ['help', 'my', 'here', 'I', 'because'],

  // Places, which are mostly the object of "go" and the answer to "where".
  'school': ['go', 'I', 'finish', 'teacher', 'not'],
  'park': ['go', 'play', 'I', 'outside', 'please'],
  'shop': ['go', 'I', 'want', 'please'],
  'car': ['go', 'in', 'out', 'I', 'please'],
  'bus': ['go', 'school', 'home', 'I', 'in'],
  'bathroom': ['go', 'toilet', 'I', 'please'],
  'bedroom': ['go', 'I', 'sleepy', 'please'],
  'kitchen': ['go', 'drink', 'snack', 'I'],
  'hospital': ['go', 'doctor', 'I', 'not'],
  'beach': ['go', 'swim', 'sand', 'play', 'I'],
  'door': ['open', 'close', 'please'],
  'window': ['open', 'close', 'please'],

  // Body. A part gets named in order to report something about it, and the
  // report is the word the strip should already be holding.
  'head': ['hurt', 'sore', 'help', 'my'],
  'tummy': ['hurt', 'sore', 'sick', 'toilet', 'help'],
  'arm': ['hurt', 'sore', 'help', 'my'],
  'leg': ['hurt', 'sore', 'help', 'my'],
  'hand': ['hurt', 'sore', 'help', 'my'],
  'throat': ['sore', 'hurt', 'drink', 'help'],
  'teeth': ['hurt', 'sore', 'dentist', 'help'],
  'eyes': ['hurt', 'itchy', 'too bright', 'help'],
  'ears': ['hurt', 'too loud', 'help'],
  'it hurts': ['here', 'my', 'help', 'because'],
  'sore': ['throat', 'tummy', 'head', 'my', 'here'],
  'itchy': ['my', 'here', 'skin', 'help'],
  'poorly': ['I', 'home', 'doctor', 'medicine', 'help'],
  'sleepy': ['I', 'bedroom', 'home', 'please'],
  'dizzy': ['I', 'help', 'because'],
  'medicine': ['please', 'need', 'want', 'I'],
  'toilet': ['please', 'go', 'I', 'want', 'need'],
  'wee': ['please', 'toilet', 'need', 'I'],
  'poo': ['please', 'toilet', 'need', 'I'],

  // Play: the thing, and the doing of it.
  'play': ['outside', 'ball', 'game', 'again', 'more', 'music', 'tablet'],
  'read': ['book', 'story', 'more', 'again', 'please'],
  'sing': ['song', 'music', 'more', 'again'],
  'ride': ['bike', 'scooter', 'bus', 'train'],
  'throw': ['ball', 'it', 'that', 'me'],
  'walk': ['outside', 'home', 'school', 'park', 'away'],
  'swim': ['pool', 'beach', 'more', 'please'],
  'ball': ['play', 'throw', 'catch', 'more', 'my'],
  'book': ['read', 'more', 'please', 'my'],
  'toy': ['play', 'my', 'more', 'please'],
  'game': ['play', 'my turn', 'more', 'again'],
  'music': ['more', 'play', 'sing', 'dance', 'please'],
  'video': ['more', 'play', 'again', 'please'],
  'tablet': ['please', 'my', 'more', 'play'],
  'song': ['more', 'again', 'sing', 'play'],
  'story': ['more', 'again', 'read', 'please'],
  'bike': ['ride', 'go', 'outside', 'my'],
  'again': ['please', 'more', 'yes', 'I'],
  'my turn': ['please', 'I', 'yes', 'more'],
  'your turn': ['you', 'please', 'yes', 'go'],

  // Sensory overload. Whatever follows has to arrive fast, so these hold the
  // words that end it rather than the ones that describe it.
  'too loud': ['stop', 'please', 'help', 'I'],
  'too bright': ['stop', 'please', 'help', 'I'],
  'too much': ['stop', 'please', 'help', 'I'],
  'leave me alone': ['please', 'stop', 'I'],

  // Questions.
  'what': ['that', 'you', 'I', 'do', 'want'],
  'where': ['my', 'you', 'I', 'that', 'go'],
  'who': ['you', 'that', 'I', 'me'],
  'when': ['we', 'you', 'I', 'can', 'go'],
  'why': ['not', 'you', 'I', 'can'],
};
