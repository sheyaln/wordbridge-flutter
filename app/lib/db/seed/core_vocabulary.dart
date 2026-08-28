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
    reserveCols: 1,
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
  Band(name: 'articles', shedRank: 7, items: [_article('a'), _article('the')]),

  // Held open, and empty on purpose. This is where the nouns a particular
  // person uses constantly get promoted to the root board, so their most
  // frequent words cost one movement instead of three.
  Band(
    name: 'nouns',
    shedRank: 8,
    minCols: 1,
    reserveCols: 1,
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
    ],
  ),

  // Refusal is the most urgent thing a user can need to say. It keeps a
  // location on the root board at every grid size; a board that can only agree
  // is not a communication device.
  Band(
    name: 'describing',
    shedRank: 2,
    items: [
      w('good', PartOfSpeech.adjective),
      w('not', PartOfSpeech.negation, essential: true),
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
];

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

/// Fringe vocabulary, grouped the way it is used rather than by frequency.
///
/// Words that do not fit the chosen grid are not dropped: they go to a second
/// page, reached by a key in a fixed location. Paging rather than scrolling,
/// because a page is a grid and a scroll position is not a position at all.
final categoryBands = <String, List<Band<SeedWord>>>{
  'people': [
    Band(
      name: 'family',
      shedRank: 0,
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
    // The blank columns are where a family's actual names belong.
    Band(
      name: 'names',
      shedRank: 9,
      minCols: 2,
      reserveCols: 1,
      reserveRank: 0,
      items: const [],
    ),
    Band(
      name: 'community',
      shedRank: 1,
      items: nouns([
        'friend',
        'teacher',
        'doctor',
        'nurse',
        'helper',
      ], level: 1),
    ),
    Band(
      name: 'everyone',
      shedRank: 2,
      items: nouns(['everybody', 'nobody', 'somebody', 'name']),
    ),
    Band(
      name: 'referring',
      shedRank: 3,
      items: nouns(['me', 'him', 'her', 'them', 'us']),
    ),
    Band(
      name: 'groups',
      shedRank: 4,
      items: nouns([
        'boy',
        'girl',
        'man',
        'woman',
        'family',
        'class',
        'neighbour',
        'driver',
        'stranger',
      ]),
    ),
  ],

  'food': [
    Band(name: 'eating', shedRank: 0, items: verbs(['eat', 'drink'], level: 1)),
    Band(
      name: 'drinks',
      shedRank: 1,
      items: nouns([
        'water',
        'milk',
        'juice',
        'squash',
        'tea',
        'coffee',
        'fizzy',
      ], level: 1),
    ),
    Band(
      name: 'staples',
      shedRank: 2,
      items: nouns([
        'bread',
        'toast',
        'cereal',
        'rice',
        'pasta',
        'egg',
        'cheese',
        'butter',
      ], level: 1),
    ),
    Band(
      name: 'meals',
      shedRank: 3,
      items: nouns(['pizza', 'chicken', 'soup', 'salad'], level: 1),
    ),
    Band(
      name: 'fruit',
      shedRank: 5,
      items: nouns([
        'apple',
        'banana',
        'orange',
        'grapes',
        'berries',
        'melon',
        'lemon',
      ], level: 1),
    ),
    Band(
      name: 'vegetables',
      shedRank: 6,
      items: nouns(['potato', 'carrot', 'peas', 'beans', 'tomato']),
    ),
    Band(
      name: 'sweet',
      shedRank: 7,
      items: nouns(['cake', 'biscuit', 'yoghurt', 'honey', 'jam', 'crisps']),
    ),
    Band(
      name: 'mealtimes',
      shedRank: 4,
      items: nouns(['breakfast', 'lunch', 'dinner', 'snack'], level: 1),
    ),
    // A user who cannot say "yucky" cannot decline a meal, only endure it.
    Band(
      name: 'describing',
      shedRank: 1,
      items: adjectives([
        'hungry',
        'thirsty',
        'hot',
        'cold',
        'yummy',
        'yucky',
      ], level: 1),
    ),
    Band(name: 'table', shedRank: 8, items: nouns(['plate', 'straw'])),
    Band(
      name: 'ours',
      shedRank: 9,
      minCols: 1,
      reserveCols: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  'play': [
    Band(
      name: 'doing',
      shedRank: 0,
      items: verbs(['play', 'read', 'draw', 'sing', 'dance', 'run'], level: 1),
    ),
    Band(
      name: 'moving',
      shedRank: 3,
      items: verbs([
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
    ),
    Band(
      name: 'things',
      shedRank: 1,
      items: nouns([
        'ball',
        'book',
        'toy',
        'game',
        'puzzle',
        'blocks',
      ], level: 1),
    ),
    Band(
      name: 'screens',
      shedRank: 2,
      items: nouns([
        'music',
        'video',
        'tablet',
        'film',
        'cartoon',
        'song',
        'story',
      ], level: 1),
    ),
    Band(
      name: 'outdoors',
      shedRank: 4,
      items: nouns([
        'bubbles',
        'swing',
        'slide',
        'bike',
        'scooter',
        'trampoline',
        'sand',
        'paint',
      ]),
    ),
    // Turn-taking is the whole of early play, and a user who cannot claim a
    // turn is watching rather than playing.
    Band(
      name: 'turns',
      shedRank: 0,
      items: nouns(['my turn', 'your turn', 'again', 'outside'], level: 1),
    ),
    Band(
      name: 'ours',
      shedRank: 9,
      minCols: 1,
      reserveCols: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  // Deliberately includes the difficult ones. A board that can only say
  // "happy" and "sad" cannot report pain, fear, or being overwhelmed, which
  // are the feelings that most need saying.
  'feelings': [
    Band(
      name: 'core',
      shedRank: 0,
      items: adjectives([
        'happy',
        'sad',
        'angry',
        'scared',
        'tired',
        'excited',
      ], level: 1),
    ),
    Band(
      name: 'unwell',
      shedRank: 0,
      items: adjectives([
        'hurt',
        'sick',
        'worried',
        'lonely',
        'bored',
        'silly',
      ], level: 1),
    ),
    Band(
      name: 'liking',
      shedRank: 1,
      items: verbs(['love', 'like', 'hate', 'miss'], level: 1),
    ),
    // The sentences a user needs most and can least afford to spell out one
    // word at a time.
    Band(
      name: 'too much',
      shedRank: 0,
      items: nouns([
        'too loud',
        'too bright',
        'too much',
        'leave me alone',
        'I need a break',
      ], level: 1),
    ),
    Band(
      name: 'shades',
      shedRank: 3,
      items: adjectives([
        'calm',
        'proud',
        'shy',
        'jealous',
        'confused',
        'surprised',
        'funny',
        'kind',
        'mean',
      ]),
    ),
    Band(
      name: 'judging',
      shedRank: 4,
      items: adjectives([
        'fair',
        'unfair',
        'safe',
        'better',
        'worse',
        'enough',
        'ready',
      ]),
    ),
    Band(
      name: 'pace',
      shedRank: 2,
      items: nouns(['too fast', 'too slow', 'I do not know'], level: 1),
    ),
    Band(
      name: 'ours',
      shedRank: 9,
      minCols: 1,
      reserveCols: 1,
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
      name: 'rooms',
      shedRank: 1,
      items: nouns([
        'bathroom',
        'bedroom',
        'kitchen',
        'garden',
        'outside',
        'inside',
      ], level: 1),
    ),
    Band(
      name: 'further',
      shedRank: 2,
      items: nouns(['hospital', 'work', 'holiday', 'away'], level: 1),
    ),
    Band(
      name: 'around',
      shedRank: 3,
      items: nouns([
        'upstairs',
        'downstairs',
        'room',
        'door',
        'window',
        'stairs',
      ]),
    ),
    Band(
      name: 'out',
      shedRank: 4,
      items: nouns(['street', 'beach', 'pool', 'library', 'church', 'cafe']),
    ),
    Band(
      name: 'getting there',
      shedRank: 5,
      items: [
        ...nouns(['train', 'plane', 'bike']),
        ...verbs(['walk']),
        ...adjectives(['far', 'near']),
      ],
    ),
    Band(
      name: 'ours',
      shedRank: 9,
      minCols: 1,
      reserveCols: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  'body': [
    Band(
      name: 'head',
      shedRank: 1,
      items: nouns(['head', 'face', 'eyes', 'ears', 'nose', 'mouth'], level: 1),
    ),
    Band(
      name: 'limbs',
      shedRank: 1,
      items: nouns(['hand', 'arm', 'leg', 'foot', 'tummy', 'back'], level: 1),
    ),
    // Being able to name a symptom is the difference between a doctor's visit
    // that finds the problem and one that guesses.
    Band(
      name: 'symptoms',
      shedRank: 0,
      items: [
        ...nouns(['it hurts'], level: 1),
        ...adjectives([
          'itchy',
          'sore',
          'dizzy',
          'thirsty',
          'sleepy',
          'poorly',
        ], level: 1),
      ],
    ),
    Band(
      name: 'detail',
      shedRank: 3,
      items: nouns([
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
    ),
    Band(
      name: 'care',
      shedRank: 2,
      items: nouns([
        'medicine',
        'plaster',
        'doctor',
        'nurse',
        'bandage',
        'cough',
        'temperature',
      ], level: 1),
    ),
    Band(
      name: 'ours',
      shedRank: 9,
      minCols: 1,
      reserveCols: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],
};
