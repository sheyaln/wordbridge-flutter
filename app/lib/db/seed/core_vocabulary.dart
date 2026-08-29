/// The shipped vocabulary, as bands rather than coordinates.
///
/// Independently designed. Word selection comes from Project Core's Universal
/// Core 36 (Center for Literacy and Disability Studies, UNC-Chapel Hill);
/// ordering follows the Fitzgerald Key's left-to-right sentence arrangement,
/// published in 1926 and long out of copyright. No commercial vocabulary
/// layout was consulted or reproduced. See docs/starter-vocabulary.md.
///
/// Nothing here names a row or a column. Bands declare what belongs together
/// and in what order; [layOutBands] turns that into coordinates for whatever
/// grid the caregiver chose. The 7x12 result is identical to the layout this
/// file replaced, which `core_board_set_test.dart` asserts word by word.
library;

import '../tables.dart';
import 'band_layout.dart';

/// Everything a button needs, carried through the layout engine untouched.
typedef SeedWord = ({
  String label,
  String message,
  ButtonAction action,
  MorphemeKind? morphemeKind,
  PartOfSpeech? pos,
});

BandItem<SeedWord> w(
  String label,
  PartOfSpeech pos, {
  int level = 1,
  bool essential = false,
}) => BandItem(
  (
    label: label,
    message: label,
    action: ButtonAction.speak,
    morphemeKind: null,
    pos: pos,
  ),
  level: level,
  essential: essential,
);

List<BandItem<SeedWord>> _all(
  List<String> labels,
  PartOfSpeech pos, {
  int level = 2,
}) => [for (final l in labels) w(l, pos, level: level)];

List<BandItem<SeedWord>> nouns(List<String> l, {int level = 2}) =>
    _all(l, PartOfSpeech.noun, level: level);
List<BandItem<SeedWord>> verbs(List<String> l, {int level = 2}) =>
    _all(l, PartOfSpeech.verb, level: level);
List<BandItem<SeedWord>> adjectives(List<String> l, {int level = 2}) =>
    _all(l, PartOfSpeech.adjective, level: level);

List<BandItem<SeedWord>> pronouns(List<String> l, {int level = 2}) =>
    _all(l, PartOfSpeech.pronoun, level: level);

List<BandItem<SeedWord>> adverbs(List<String> l, {int level = 2}) =>
    _all(l, PartOfSpeech.adverb, level: level);

/// Whole utterances. One tap produces a complete thing to say, so they take no
/// endings and no copula — coding them as nouns is what let the board build
/// "I need a break's".
List<BandItem<SeedWord>> phrases(List<String> l, {int level = 2}) =>
    _all(l, PartOfSpeech.social, level: level);

/// The root board.
///
/// Band order is the order the words come out in: who, then what they do, then
/// how it is modified, then what and where, then whether it is good or refused.
/// Reading the board left to right builds a sentence.
///
/// `shedRank` says what gives way when the chosen grid is small: pronouns and
/// verbs hold on longest because a board without them cannot make a sentence,
/// and articles go first because a sentence without one is still understood.
final homeBands = <Band<SeedWord>>[
  // Column 1 exists for the people in a particular person's life — the
  // most-requested personal vocabulary in every account of AAC use, and the
  // thing a shipped board can never guess. "we" and "they" take its first two
  // locations because they are core vocabulary and the pronoun column is full.
  Band(
    name: 'pronouns',
    shedRank: 0,
    reserveLines: 1,
    reserveRank: 1,
    items: [
      w('I', PartOfSpeech.pronoun, essential: true),
      w('you', PartOfSpeech.pronoun, essential: true),
      w('he', PartOfSpeech.pronoun),
      w('she', PartOfSpeech.pronoun),
      w('it', PartOfSpeech.pronoun),
      w('that', PartOfSpeech.pronoun),
      w('we', PartOfSpeech.pronoun),
      w('they', PartOfSpeech.pronoun),
      // "my" and "me" are toddler core and neither has a substitute here:
      // "+'s" fires after "I" and produces "I's", and the object pronoun on
      // the people board is two movements away from "help me".
      w('my', PartOfSpeech.pronoun),
      w('me', PartOfSpeech.pronoun),
    ],
  ),

  Band(
    name: 'determiners',
    shedRank: 5,
    items: [
      w('all', PartOfSpeech.determiner),
      w('some', PartOfSpeech.determiner),
      w('same', PartOfSpeech.determiner, level: 2),
      w('different', PartOfSpeech.determiner, level: 2),
      w('more', PartOfSpeech.determiner, essential: true),
      w('this', PartOfSpeech.determiner),
    ],
  ),

  // Opposites and near-relations sit next to each other: want above need above
  // like, open above close, go above stop, get above take. Neighbouring
  // locations are learned as a pair; two positions that happen to be far apart
  // are learned twice.
  Band(
    name: 'verbs',
    shedRank: 1,
    items: [
      w('want', PartOfSpeech.verb, essential: true),
      w('need', PartOfSpeech.verb),
      w('like', PartOfSpeech.verb),
      w('go', PartOfSpeech.verb),
      w('stop', PartOfSpeech.verb, essential: true),
      w('can', PartOfSpeech.verb, level: 2),
      w('get', PartOfSpeech.verb),
      w('take', PartOfSpeech.verb),
      w('do', PartOfSpeech.verb),
      w('make', PartOfSpeech.verb, level: 2),
      w('put', PartOfSpeech.verb, level: 2),
      w('will', PartOfSpeech.verb),
      w('open', PartOfSpeech.verb, level: 2),
      w('close', PartOfSpeech.verb),
      w('help', PartOfSpeech.verb, essential: true),
      w('look', PartOfSpeech.verb),
      w('turn', PartOfSpeech.verb, level: 2),
      w('finished', PartOfSpeech.verb, essential: true),
      // Cognition and communication: top-20 verbs in every published adult
      // core list, and "tell" is the word a user needs to disclose something.
      // Level 3 because the 7x12 board has no room for them — they shed to a
      // later page there, and appear on the root board at smaller icon sizes
      // where the grid is wider.
      w('know', PartOfSpeech.verb, level: 3),
      w('think', PartOfSpeech.verb, level: 3),
      w('say', PartOfSpeech.verb, level: 3),
      w('tell', PartOfSpeech.verb, level: 3),
      w('see', PartOfSpeech.verb, level: 3),
      w('come', PartOfSpeech.verb, level: 3),
      w('give', PartOfSpeech.verb, level: 3),
      w('feel', PartOfSpeech.verb, level: 3),
    ],
  ),

  // Six locations buy every inflected form of every verb on the board. A cell
  // each for want, wants, wanted, wanting would consume the grid several times
  // over and still miss combinations nobody predicted.
  //
  // Immediately right of the verbs, because the movement reads left to right —
  // verb, then ending — matching the order the words come out in.
  Band(
    name: 'endings',
    shedRank: 6,
    items: [
      _morpheme('+s', MorphemeKind.pluralS),
      _morpheme('+ed', MorphemeKind.pastEd),
      _morpheme('+ing', MorphemeKind.ing),
      _morpheme("+'s", MorphemeKind.possessive),
      // The copula agrees with whatever subject is already in the bar, so one
      // location covers am / is / are and another covers was / were.
      _copula('am/is/are', 'present'),
      _copula('was/were', 'past'),
    ],
  ),

  // "a" is inserted and repaired to "an" once the following word is known. The
  // choice has to be made before the noun exists, and asking a user to know
  // how their next word starts is not a reasonable thing to ask.
  // Articles and conjunctions share a line. Both are the small grammatical
  // words that turn a run of content words into a sentence, and neither
  // deserves a line of its own.
  //
  // "because" is the word that turns a refusal into a reason. A user who can
  // say "no" but not "because" gets overridden.
  Band(
    name: 'articles',
    shedRank: 7,
    items: [
      _article('a'),
      _article('the'),
      w('and', PartOfSpeech.conjunction, level: 2),
      w('but', PartOfSpeech.conjunction, level: 2),
      w('because', PartOfSpeech.conjunction, level: 2),
      w('so', PartOfSpeech.conjunction, level: 2),
    ],
  ),

  // Held open, and empty on purpose. This is where the nouns a particular
  // person uses constantly get promoted to the root board, so their most
  // frequent words cost one movement instead of three.
  Band(
    name: 'nouns',
    shedRank: 8,
    minLines: 1,
    reserveLines: 1,
    reserveRank: 0,
    items: const [],
  ),

  Band(
    name: 'places',
    shedRank: 4,
    items: [
      w('here', PartOfSpeech.preposition),
      w('in', PartOfSpeech.preposition, level: 2),
      w('on', PartOfSpeech.preposition, level: 2),
      w('up', PartOfSpeech.preposition, level: 2),
      // "to" is what lets a second verb follow a first — "I want to go" — and
      // what re-enables the other verbs when the optional verb filter is on.
      w('to', PartOfSpeech.preposition, level: 2),
      w('out', PartOfSpeech.preposition),
    ],
  ),

  // Answering and refusing. These keep their locations at every grid size; a
  // board that can only agree is not a communication device, and one that
  // cannot answer a direct question makes its user look absent from their own
  // conversation.
  //
  // "not" negates inside a sentence, "no" answers one — different words doing
  // different jobs, both of which a user needs.
  Band(
    name: 'describing',
    shedRank: 2,
    items: [
      w('good', PartOfSpeech.adjective),
      w('not', PartOfSpeech.negation, essential: true),
      w('yes', PartOfSpeech.social, essential: true),
      w('no', PartOfSpeech.negation, essential: true),
      // "not" negates inside a sentence and cannot make an imperative. Without
      // "don't" the board produces "I not go" where a user meant "don't go",
      // and the imperative is the one that stops something happening.
      w("don't", PartOfSpeech.negation, essential: true),
      // Floor-holding. An AAC user composes slower than a speaker talks, and
      // this is the one-tap way to stop being talked over mid-sentence.
      w('wait', PartOfSpeech.verb, essential: true),
    ],
  ),
];

/// The pinned column, repeated on every board.
///
/// Questions are not a category — they apply to whatever the user is already
/// looking at. Pinning them means "where" is one movement from anywhere rather
/// than a trip back to the root board and out again, which is the difference
/// between asking a question and giving up on asking it.
final pinnedQuestions = <BandItem<SeedWord>>[
  w('what', PartOfSpeech.question, essential: true),
  w('where', PartOfSpeech.question, essential: true),
  w('who', PartOfSpeech.question, level: 2),
  w('when', PartOfSpeech.question, level: 2),
  w('why', PartOfSpeech.question, level: 2),
  // Appended rather than slotted in beside the question words, because every
  // one of those already has a location somebody has learned.
  _punctuation('?'),
];

BandItem<SeedWord> _punctuation(String mark) => BandItem((
  label: mark,
  message: mark,
  action: ButtonAction.punctuate,
  morphemeKind: null,
  pos: PartOfSpeech.question,
));

BandItem<SeedWord> _morpheme(String label, MorphemeKind kind) => BandItem((
  label: label,
  message: '',
  action: ButtonAction.morpheme,
  morphemeKind: kind,
  pos: PartOfSpeech.other,
), level: 2);

BandItem<SeedWord> _copula(String label, String tense) => BandItem((
  label: label,
  // A copula carries its tense here; a suffix carries it in morphemeKind.
  message: tense,
  action: ButtonAction.morpheme,
  morphemeKind: null,
  pos: PartOfSpeech.other,
), level: 2);

BandItem<SeedWord> _article(String label) => BandItem((
  label: label,
  message: 'article',
  action: ButtonAction.morpheme,
  morphemeKind: null,
  pos: PartOfSpeech.determiner,
), level: 2);

/// Category boards, in the order their keys appear on the system row.
const categoryNames = ['people', 'food', 'play', 'feelings', 'places', 'body'];

/// Fringe vocabulary, grouped by word class and ordered within it by meaning.
///
/// Each band is one horizontal strip. Strips run top to bottom in Fitzgerald
/// order — whole utterances, verbs, nouns, object pronouns, adjectives,
/// adverbs — so a class occupies a contiguous block of rows, and therefore a
/// contiguous block of colour. Inside a strip the words run left to right in
/// semantic clusters, wrapping at the row edge.
///
/// Word class is the primary grouping because that is what the evidence
/// measured: arranging by word class made children significantly faster at
/// building multi-symbol messages (Thistle & Wilkinson 2017), and using
/// position to cue grammatical category cut fixations on irrelevant symbols
/// (Wilkinson, Gilmore & Qian 2022). The semantic cluster survives as the
/// ordering inside a strip because that is how children group vocabulary
/// themselves — small event-based groups rather than taxonomies (Fallon,
/// Light & Achenbach 2003).
///
/// Rows rather than columns, because a row-column scan picks a row first: on a
/// row-grouped board that first press narrows to a word class, and on a
/// column-grouped one it narrows to nothing.
///
/// Band names must be unique within a board, including the bands an age preset
/// appends — the layout engine keys bands by name.
final categoryBands = <String, List<Band<SeedWord>>>{
  'people': [
    Band(
      name: 'greeting',
      shedRank: 0,
      items: phrases(['hello', 'bye', 'please', 'thank you'], level: 1),
    ),

    Band(
      name: 'family',
      shedRank: 1,
      items: nouns([
        'mum',
        'dad',
        'baby',
        'brother',
        'sister',
        'grandma',
        'grandpa',
      ], level: 1),
    ),

    // Held open, and empty on purpose: this is where a family's actual names
    // go. Asked for rather than guaranteed, because a reserved row costs a
    // whole row's width — on a small grid those cells go to shipped words and
    // a name still fits in the family strip's tail.
    Band(
      name: 'names',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),

    Band(
      name: 'community',
      shedRank: 2,
      items: nouns([
        'friend',
        'teacher',
        'helper',
        'doctor',
        'nurse',
      ], level: 1),
    ),

    Band(
      name: 'groups',
      shedRank: 4,
      items: [
        ...nouns(['boy', 'girl', 'family'], level: 1),
        ...nouns([
          'man',
          'woman',
          'class',
          'neighbour',
          'driver',
          'stranger',
          'name',
        ]),
      ],
    ),

    // Object pronouns, after the nouns rather than before them: the root
    // board's pronoun column holds subjects, which start a sentence, and
    // these follow a verb.
    Band(
      name: 'referring',
      shedRank: 3,
      items: [
        ...pronouns(['him', 'her'], level: 1),
        ...pronouns(['us', 'them', 'everybody', 'somebody', 'nobody']),
      ],
    ),
  ],

  'food': [
    // "food" is a word as well as the name of this board. Wanting food in
    // general is a different request from wanting toast, and it is the one a
    // person reaches for first. Appended rather than inserted, so every noun
    // already on this board keeps the cell it has.
    Band(
      name: 'eating',
      shedRank: 0,
      items: [
        ...verbs(['eat', 'drink'], level: 1),
        ...nouns(['food'], level: 1),
      ],
    ),

    // One strip for every noun on the board. Splitting the clusters into
    // strips of their own costs a row each, and eight clusters do not fit in
    // six rows — that split moves 22 words to a second page to buy tidier
    // edges. The clusters stay contiguous in reading order; they just wrap.
    Band(
      name: 'food',
      shedRank: 3,
      items: [
        ...nouns(['water', 'milk', 'juice', 'squash'], level: 1),
        ...nouns(['tea', 'coffee', 'fizzy']),
        ...nouns(['straw'], level: 1),
        ...nouns(['plate']),
        ...nouns([
          'bread',
          'toast',
          'cereal',
          'rice',
          'pasta',
          'egg',
        ], level: 1),
        ...nouns(['cheese', 'butter']),
        ...nouns(['pizza', 'chicken', 'soup'], level: 1),
        ...nouns(['salad']),
        ...nouns(['breakfast', 'lunch', 'dinner', 'snack'], level: 1),
        ...nouns(['apple', 'banana', 'orange', 'grapes'], level: 1),
        ...nouns(['berries', 'melon', 'lemon']),
        ...nouns(['potato', 'carrot', 'peas', 'beans', 'tomato']),
        ...nouns(['cake', 'biscuit', 'crisps'], level: 1),
        ...nouns(['yoghurt', 'honey', 'jam']),
      ],
    ),

    // A user who cannot say "yucky" cannot decline a meal, only endure it.
    // Opposites sit side by side, which on this axis means along a row.
    Band(
      name: 'describing',
      shedRank: 1,
      items: [
        ...adjectives(['hungry', 'thirsty', 'yummy', 'yucky'], level: 1),
        ...adjectives(['hot', 'cold']),
      ],
    ),

    Band(
      name: 'ours',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  'play': [
    // Turn-taking is the whole of early play, and a user who cannot claim a
    // turn is watching rather than playing. First row, first cells.
    Band(
      name: 'saying',
      shedRank: 0,
      items: phrases(['my turn', 'your turn'], level: 1),
    ),

    Band(
      name: 'doing',
      shedRank: 1,
      items: [
        ...verbs([
          'play',
          'read',
          'draw',
          'sing',
          'dance',
          'run',
          'walk',
        ], level: 1),
        ...verbs([
          'jump',
          'climb',
          'swim',
          'ride',
          'build',
          'throw',
          'catch',
          'hide',
          'chase',
          'push',
          'pull',
          'win',
        ]),
      ],
    ),

    // The same shed rank as the verbs on purpose: when the grid is small the
    // two give way together, so a tiny board keeps some of each rather than a
    // row of verbs and nothing to do them to.
    Band(
      name: 'things',
      shedRank: 1,
      items: [
        ...nouns(['ball', 'book', 'toy', 'game', 'puzzle', 'blocks'], level: 1),
        ...nouns([
          'music',
          'video',
          'tablet',
          'film',
          'cartoon',
          'song',
          'story',
        ], level: 1),
        ...nouns([
          'bubbles',
          'swing',
          'slide',
          'bike',
          'scooter',
          'trampoline',
          'sand',
          'paint',
        ]),
      ],
    ),

    Band(
      name: 'again',
      shedRank: 3,
      items: adverbs(['again', 'outside'], level: 1),
    ),

    Band(
      name: 'ours',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  // Deliberately includes the difficult ones. A board that can only say
  // "happy" and "sad" cannot report pain, fear, or being overwhelmed, which
  // are the feelings that most need saying.
  'feelings': [
    // The sentences a user needs most and can least afford to spell out one
    // word at a time. Coded as whole utterances, so nothing offers them an
    // ending.
    Band(
      name: 'saying',
      shedRank: 0,
      items: phrases([
        'too loud',
        'too bright',
        'too fast',
        'too slow',
        'too much',
        'leave me alone',
        'I need a break',
        "I don't know",
        "I don't understand",
      ], level: 1),
    ),

    Band(
      name: 'liking',
      shedRank: 2,
      items: verbs(['love', 'like', 'hate', 'miss'], level: 1),
    ),

    Band(
      name: 'feeling',
      shedRank: 1,
      items: adjectives([
        'happy',
        'sad',
        'angry',
        'scared',
        'tired',
        'excited',
        'hurt',
        'sick',
        'worried',
        'lonely',
        'bored',
      ], level: 1),
    ),

    Band(
      name: 'shades',
      shedRank: 4,
      items: [
        ...adjectives(['silly'], level: 1),
        // Correcting a listener who got it wrong. Without these the only way
        // to disagree is "no", which reads as refusal rather than correction.
        ...adjectives(['right', 'wrong'], level: 1),
        ...adjectives(['funny', 'kind', 'mean']),
        ...adjectives([
          'calm',
          'proud',
          'shy',
          'jealous',
          'confused',
          'surprised',
        ]),
        ...adjectives([
          'fair',
          'unfair',
          'safe',
          'better',
          'worse',
          'enough',
          'ready',
        ]),
      ],
    ),

    Band(
      name: 'ours',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  'places': [
    Band(
      name: 'everyday',
      shedRank: 0,
      items: nouns(['home', 'school', 'shop', 'park', 'car', 'bus'], level: 1),
    ),

    Band(
      name: 'places',
      shedRank: 3,
      items: [
        ...nouns(['bathroom', 'bedroom', 'kitchen', 'garden'], level: 1),
        ...nouns(['hospital', 'work', 'holiday'], level: 1),
        ...nouns(['room', 'door', 'window', 'stairs']),
        ...nouns(['street', 'beach', 'pool', 'library', 'church', 'cafe']),
        ...nouns(['train', 'plane', 'bike']),
      ],
    ),

    Band(name: 'far', shedRank: 4, items: adjectives(['far', 'near'])),

    // Adverbs, not nouns: "upstairs's" and "away is" are what coding them as
    // nouns produced. Adverb also keeps them clear of the preposition colour,
    // which the modified scheme shares with social.
    Band(
      name: 'where',
      shedRank: 2,
      items: [
        ...adverbs(['outside', 'inside', 'away'], level: 1),
        ...adverbs(['upstairs', 'downstairs']),
      ],
    ),

    Band(
      name: 'ours',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  'body': [
    // One phrase and the rest of the row held open. This is the fastest cell
    // on the board and the class of button a caregiver adds to most.
    Band(
      name: 'saying',
      shedRank: 0,
      items: phrases(['it hurts', "don't touch me"], level: 1),
    ),

    // Needing the toilet is the most frequent daily request a user has, and
    // the most common reason someone is kept out of a mainstream setting.
    // Every preset gets it, at level 1.
    Band(
      name: 'toileting',
      shedRank: 0,
      items: nouns(['toilet', 'wee', 'poo'], level: 1),
    ),

    Band(
      name: 'body',
      shedRank: 2,
      items: [
        ...nouns(['head', 'face', 'eyes', 'ears', 'nose', 'mouth'], level: 1),
        ...nouns(['hand', 'arm', 'leg', 'foot', 'tummy', 'back'], level: 1),
        ...nouns([
          'hair',
          'teeth',
          'throat',
          'skin',
          'finger',
          'thumb',
          'knee',
          'elbow',
          'shoulder',
          'neck',
          'chest',
          'heart',
          'toes',
          'nails',
          'lips',
        ]),
      ],
    ),

    Band(
      name: 'care',
      shedRank: 3,
      items: nouns([
        'medicine',
        'plaster',
        'bandage',
        'cough',
        'temperature',
        'doctor',
        'nurse',
        // No workaround exists for these two. Someone who cannot say they are
        // allergic depends on another person's record being right.
        'allergic',
        'emergency',
      ], level: 1),
    ),

    // Being able to name a symptom is the difference between a visit that
    // finds the problem and one that guesses, so this holds on longer than the
    // medicine cupboard does.
    Band(
      name: 'hurting',
      shedRank: 1,
      items: adjectives([
        'itchy',
        'sore',
        'dizzy',
        'thirsty',
        'sleepy',
        'poorly',
      ], level: 1),
    ),

    Band(
      name: 'ours',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],
};
