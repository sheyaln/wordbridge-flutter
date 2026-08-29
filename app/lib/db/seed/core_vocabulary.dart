/// The shipped vocabulary, as bands rather than coordinates.
///
/// Independently designed. Word selection comes from Project Core's Universal
/// Core 36 (Center for Literacy and Disability Studies, UNC-Chapel Hill);
/// ordering follows the Fitzgerald Key's left-to-right sentence arrangement,
/// first published in 1926 and in the public domain. No commercial vocabulary
/// layout was consulted or reproduced. See docs/starter-vocabulary.md.
///
/// Nothing here names a row or a column. Bands declare what belongs together
/// and in what order; [layOutBands] turns that into coordinates for whatever
/// grid the caregiver chose. `core_board_set_test.dart` pins the 7x12 result
/// cell by cell, because that is the grid most boards are built on and every
/// one of those cells is a movement somebody has learned.
///
/// Changing a band's order or its [BandFill] moves words. A board already in
/// use is unaffected — it lives in the database, and only an explicit,
/// measured rebuild recomputes it — but a change here is a different board for
/// everyone set up after it.
///
/// Three levels, and each has to be a different board.
///
/// The unit is **words drawn on one page**, not words in the vocabulary. What
/// a person faces is a board, and the same total spread over seven boards is
/// not the same thing twice.
///
/// **Level 1 draws exactly the Universal Core 36 on the root board.** Thirty
/// one of those words sit in the content area and five are question words in
/// the pinned column; six more content locations go to `yes`, `no`, `don't`,
/// `wait`, `me` and `maybe`, which is what the Universal Core has no answer
/// for — it carries `not`, which negates inside a sentence but cannot answer
/// one or make an imperative, its possessive key fires after `I` to give
/// "I's", and it offers no way to hedge, so every answer it can give is a
/// commitment. `how` joins them in the pinned column: it is the one English
/// question word the core omits, and a column offering five of the six reads
/// as a hole. Thirty six content locations is Project Core's own density for a
/// beginning communicator's whole-day board (CLDS, UNC-Chapel Hill); the root
/// board draws that and one more, which is the ceiling for any page at level
/// 1. The category boards are far below it.
///
/// **Level 2** adds the grammar engine — endings, articles, the copula, `will`
/// — and the fringe of an ordinary day. It lands near 250 words, which is
/// where roughly 80% of everyday speech is covered (Hattingh & Tönsing 2020,
/// reporting the English and European figure of 200-250). **Level 3** is
/// everything.
///
/// What earns a word an earlier level is how often it is needed and what it
/// costs to be without it, never how simple it looks: `toilet` and `emergency`
/// are level 1 and `biscuit` is not. Level 1 is deliberately heavier on
/// concrete nouns and social words than a core list alone would make it —
/// published core lists under-emphasise the word types that dominate early
/// expressive vocabulary (Laubscher & Light 2020).
///
/// Level 1 is one vocabulary, not one board: a grid too small to draw all
/// thirty six at once pages the rest rather than dropping them, which is the
/// same trade Project Core makes when it publishes the same 36 words four,
/// six and nine to a page.
///
/// `vocab_level_calibration_test.dart` holds the three apart, because a level
/// assigned word by word as vocabulary accumulates converges on one board
/// wearing three names.
///
/// What a grid too small to hold everything sheds first is [BandItem.pageRank],
/// which follows level by default and can be set apart from it where the two
/// questions have different answers. The tail of the verb band is drawn at
/// level 2 and paged off like level 3; the grammar keys are drawn at level 2
/// and page off like level 1. Both would otherwise have to be answered by
/// moving a word's level, which decides who sees it.
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
  int? pageRank,
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
  pageRankOverride: pageRank,
);

/// Where the grammar keys sit in the order a small grid gives things up.
///
/// Between the level-1 core and ordinary level-2 vocabulary. One ending key
/// multiplies every verb on the board, so it earns a page-one location ahead
/// of any single word — and it earns it most on exactly the grids that have
/// least room, because a grid is small when the buttons are large, and the
/// buttons are large for the people least able to afford the extra movements
/// a second page costs.
///
/// Not ahead of the level-1 core, which is the evidence-based floor and the
/// only vocabulary some boards ever draw.
const grammarKeyPageRank = 15;

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
  //
  // Filled down its columns: the first is the subject paradigm — I, you, he,
  // she, it, that — and filling the other way would interleave it with the
  // column beside it.
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
      w('we', PartOfSpeech.pronoun, level: 2),
      w('they', PartOfSpeech.pronoun, level: 2),
      // Neither has a substitute here: "+'s" fires after "I" and produces
      // "I's", and the object pronoun on the people board is two movements
      // away from "help me". "me" is the one level 1 keeps, because it is the
      // one that follows a verb.
      w('my', PartOfSpeech.pronoun, level: 2),
      w('me', PartOfSpeech.pronoun),
    ],
  ),

  Band(
    name: 'determiners',
    shedRank: 5,
    items: [
      w('all', PartOfSpeech.determiner),
      w('some', PartOfSpeech.determiner),
      w('same', PartOfSpeech.determiner),
      w('different', PartOfSpeech.determiner),
      w('more', PartOfSpeech.determiner, essential: true),
      // "that" is the Universal Core demonstrative and points at the same
      // things, so level 1 carries one of the pair rather than both.
      w('this', PartOfSpeech.determiner, level: 2),
    ],
  ),

  // Opposites and near-relations sit side by side: want, need, like along one
  // row, then go beside stop, get beside take, open beside close. Neighbouring
  // locations are learned as a pair; two positions that happen to be far apart
  // are learned twice.
  //
  // Filled across the band rather than down it, which is what puts those pairs
  // shoulder to shoulder. The band keeps the same columns either way — this is
  // the Fitzgerald "does" region and it does not move.
  Band(
    name: 'verbs',
    shedRank: 1,
    fill: BandFill.acrossBand,
    items: [
      w('want', PartOfSpeech.verb, essential: true),
      w('need', PartOfSpeech.verb, level: 2),
      w('like', PartOfSpeech.verb),
      w('go', PartOfSpeech.verb),
      w('stop', PartOfSpeech.verb, essential: true),
      // Beside "stop", because it is the same movement with the difference
      // that matters: stopping something and holding it. Floor-holding is its
      // own job — an AAC user composes slower than a speaker talks, and this
      // is the one tap that stops them being talked over mid-sentence.
      w('wait', PartOfSpeech.verb, essential: true),
      w('can', PartOfSpeech.verb),
      w('get', PartOfSpeech.verb),
      w('take', PartOfSpeech.verb, level: 2),
      w('do', PartOfSpeech.verb),
      w('make', PartOfSpeech.verb),
      w('put', PartOfSpeech.verb),
      w('open', PartOfSpeech.verb),
      w('close', PartOfSpeech.verb, level: 2),
      w('help', PartOfSpeech.verb, essential: true),
      w('look', PartOfSpeech.verb),
      w('turn', PartOfSpeech.verb),
      w('finished', PartOfSpeech.verb, essential: true),
      // Cognition and communication: top-20 verbs in every published adult
      // core list, and "tell" is the word a user needs to disclose something.
      //
      // Drawn at level 2, and paged off like level 3. The 7x12 board has no
      // room for them on page one, so they shed to a later page there and sit
      // on the root board at smaller icon sizes where the grid is wider —
      // but there is no reason a person ready for a 241-word board should be
      // unable to say "I think" until they are ready for all 372.
      w('know', PartOfSpeech.verb, level: 2, pageRank: 30),
      w('think', PartOfSpeech.verb, level: 2, pageRank: 30),
      w('say', PartOfSpeech.verb, level: 2, pageRank: 30),
      w('tell', PartOfSpeech.verb, level: 2, pageRank: 30),
      w('see', PartOfSpeech.verb, level: 2, pageRank: 30),
      w('come', PartOfSpeech.verb, level: 2, pageRank: 30),
      w('give', PartOfSpeech.verb, level: 2, pageRank: 30),
      w('feel', PartOfSpeech.verb, level: 2, pageRank: 30),
      // Tense arrives as a set: "will" waits for the endings and the past
      // copula rather than leaving level 1 with a future and no past.
      //
      // Last in the band, and paged off with the run above it. The band is
      // exactly full at 7x12, so one verb has to go, and this is the only
      // candidate that is not half of a pair the board keeps side by side —
      // open/close, go/stop, get/take, want/need/like. Declared here rather
      // than among the modals so that page two keeps those pairs too: the
      // overflow reads in declaration order, and a word inserted into the
      // middle of it moves every pair after it apart.
      w('will', PartOfSpeech.verb, level: 2, pageRank: 25),
    ],
  ),

  // Six locations buy every inflected form of every verb on the board. A cell
  // each for want, wants, wanted, wanting would consume the grid several times
  // over and still miss combinations nobody predicted.
  //
  // Immediately right of the verbs, because the movement reads left to right —
  // verb, then ending — matching the order the words come out in.
  //
  // The whole band is level 2, the copula included. It is the one call here
  // that costs a sentence: without "am/is/are" a level-1 board cannot build
  // "are you ok?" or "what is that?". The Universal Core 36 carries no copula
  // at all, and that list is the evidence-based floor this vocabulary is built
  // from, so level 1 follows it and the grammar engine arrives as one set at
  // level 2 — in the locations it has held since day one.
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
      w('in', PartOfSpeech.preposition),
      w('on', PartOfSpeech.preposition),
      w('up', PartOfSpeech.preposition),
      // "to" is what lets a second verb follow a first — "I want to go" — and
      // what re-enables the other verbs when the optional verb filter is on.
      // A level-1 board with that filter switched on cannot chain verbs; the
      // filter is off unless somebody asks for it.
      w('to', PartOfSpeech.preposition, level: 2),
      w('out', PartOfSpeech.preposition, level: 2),
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
      // The answer that is neither, beside the two that are. Without it every
      // answer a person gives is a commitment, and nobody in the room can tell
      // an overstated "yes" from a meant one.
      //
      // Level 1: hedging is not an advanced skill, and it is the answer a
      // beginner most often has. Not essential even so — a grid too narrow to
      // draw it should page it, and marking it would refuse that grid outright
      // over one word.
      w('maybe', PartOfSpeech.adverb),
    ],
  ),
];

/// The pinned column, repeated on every board.
///
/// Questions are not a category — they apply to whatever the user is already
/// looking at. Pinning them means "where" is one movement from anywhere rather
/// than a trip back to the root board and out again, which is the difference
/// between asking a question and giving up on asking it.
///
/// Six words and no punctuation, because the column is `rows - 1` long and a
/// seventh item costs far more than a cell. Bands own whole lines, so a board
/// this closely packed frees a line only by shedding every word that shares it
/// — about fifteen at 7x12, the articles among them. The question mark belongs
/// to the sentence rather than to the grid and lives on the utterance bar,
/// where it costs no location on any board.
final pinnedQuestions = <BandItem<SeedWord>>[
  w('what', PartOfSpeech.question, essential: true),
  w('where', PartOfSpeech.question, essential: true),
  w('who', PartOfSpeech.question),
  w('when', PartOfSpeech.question),
  w('why', PartOfSpeech.question),
  // The one English question word the Universal Core omits. A column offering
  // five of the six reads as having a hole in a group a user takes to be
  // whole, so it draws at level 1 with the rest of them.
  w('how', PartOfSpeech.question),
];

BandItem<SeedWord> _morpheme(String label, MorphemeKind kind) => BandItem(
  (
    label: label,
    message: '',
    action: ButtonAction.morpheme,
    morphemeKind: kind,
    pos: PartOfSpeech.other,
  ),
  level: 2,
  pageRankOverride: grammarKeyPageRank,
);

BandItem<SeedWord> _copula(String label, String tense) => BandItem(
  (
    label: label,
    // A copula carries its tense here; a suffix carries it in morphemeKind.
    message: tense,
    action: ButtonAction.morpheme,
    morphemeKind: null,
    pos: PartOfSpeech.other,
  ),
  level: 2,
  pageRankOverride: grammarKeyPageRank,
);

BandItem<SeedWord> _article(String label) => BandItem(
  (
    label: label,
    message: 'article',
    action: ButtonAction.morpheme,
    morphemeKind: null,
    pos: PartOfSpeech.determiner,
  ),
  level: 2,
  pageRankOverride: grammarKeyPageRank,
);

/// Category boards, in the order their keys appear on the system row.
///
/// Append only. The keys are a window onto this list and the cycle key moves
/// the window, so inserting a name changes which board every key after it
/// opens — a relocation of what a learned key does, without a single button
/// moving.
const categoryNames = [
  'people',
  'food',
  'play',
  'feelings',
  'places',
  'body',
  'doing',
];

/// Fringe vocabulary in clusters: one cluster to a band, one band to a row.
///
/// Word class is the coarse grouping. Strips run top to bottom in Fitzgerald
/// order — whole utterances, verbs, nouns, object pronouns, adjectives,
/// adverbs — so a class occupies a contiguous block of rows and therefore a
/// contiguous block of colour, which is what the evidence measured: arranging
/// by word class made children significantly faster at building multi-symbol
/// messages (Thistle & Wilkinson 2017), and using position to cue grammatical
/// category cut fixations on irrelevant symbols (Wilkinson, Gilmore & Qian
/// 2022).
///
/// Within that order a band is a cluster somebody would name out loud —
/// drinks, meals, fruit, treats — because small event-based groups are how
/// children group vocabulary themselves (Fallon, Light & Achenbach 2003), and
/// because a row is what a person reads in one sweep. A row holding half of
/// one group and half of the next has to be learned word by word.
///
/// Rows rather than columns, because a row-column scan picks a row first: on a
/// row-grouped board that first press narrows to a cluster, and on a
/// column-grouped one it narrows to nothing.
///
/// A board that is one word class throughout has no class order left to
/// encode, so its strips group by meaning alone. The scan argument survives
/// unchanged: the first press still narrows to a handful of related words.
///
/// **What this costs.** A band owns whole rows, so a cluster of five on an
/// eleven-wide grid leaves six cells empty and the next cluster starts the row
/// below. Eight clusters do not fit in six rows, and the ones a small grid
/// cannot afford read on page two — ten words of the food board at 7x12, eight
/// of the play board. Page two is one key press and always the same key, while
/// a mixed row is learned word by word. The empty tail is not waste either: it
/// is where a caregiver's own words for that cluster go.
///
/// Which clusters pay is [Band.shedRank] against [BandItem.level]. Level
/// decides first — a cluster that is level 3 throughout leaves before one
/// holding a level-2 word — and `shedRank` decides between clusters the levels
/// tie.
///
/// Band names must be unique within a board, including the bands an age preset
/// appends — the layout engine keys bands by name. They are read by a
/// caregiver too: `region_labels.dart` writes a band's name over its row
/// unless a plainer one is on file for it.
final categoryBands = <String, List<Band<SeedWord>>>{
  'people': [
    Band(
      name: 'greeting',
      shedRank: 0,
      items: phrases(['hello', 'bye', 'please', 'thank you'], level: 1),
    ),

    // Only the two a shipped board can assume. Whether there is a sibling or a
    // living grandparent is exactly the kind of thing it cannot know, so the
    // rest of the strip waits for somebody who does. "family" closes the row
    // because the collective belongs with its members, not with the words for
    // people in general.
    Band(
      name: 'family',
      shedRank: 1,
      items: [
        ...nouns(['mum', 'dad'], level: 1),
        ...nouns([
          'baby',
          'brother',
          'sister',
          'grandma',
          'grandpa',
          'family',
        ], level: 2),
      ],
    ),

    // Held open, and empty on purpose: this is where a family's actual names
    // go. Asked for rather than guaranteed, because a reserved row costs a
    // whole row's width — on a small grid those cells go to shipped words and
    // a name still fits in the family strip's tail. Empty also means free: a
    // band with no words costs no line, so the row survives on the presets
    // that append a band of their own to this board.
    Band(
      name: 'names',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),

    // Everybody outside the house, in one row rather than spread over two.
    // "doctor" and "nurse" stay side by side; the rest are the people a day
    // actually contains.
    Band(
      name: 'community',
      shedRank: 2,
      items: [
        ...nouns(['friend', 'teacher'], level: 2),
        ...nouns(['class', 'helper'], level: 3),
        ...nouns(['doctor', 'nurse'], level: 2),
        ...nouns(['neighbour', 'driver', 'stranger'], level: 3),
      ],
    ),

    // Words for a person nobody has named yet — the ones a user reaches for
    // when pointing is not enough and a name is not known. "name" closes the
    // row for the same reason: it is the word that asks for one.
    Band(
      name: 'people',
      shedRank: 4,
      items: nouns(['boy', 'girl', 'man', 'woman', 'name'], level: 2),
    ),

    // Object pronouns, after the nouns rather than before them: the root
    // board's pronoun column holds subjects, which start a sentence, and
    // these follow a verb.
    Band(
      name: 'referring',
      shedRank: 3,
      items: [
        ...pronouns(['him', 'her', 'us', 'them'], level: 2),
        ...pronouns(['everybody', 'somebody', 'nobody'], level: 3),
      ],
    ),
  ],

  'food': [
    // "food" is a word as well as the name of this board. Wanting food in
    // general is a different request from wanting toast, and it is the one a
    // person reaches for first. "straw" and "plate" ride with it because the
    // act and the kit are one event — the grouping a child actually makes
    // (Fallon, Light & Achenbach 2003) — and because neither is a food.
    Band(
      name: 'eating',
      shedRank: 0,
      items: [
        ...verbs(['eat', 'drink'], level: 1),
        ...nouns(['food'], level: 1),
        ...nouns(['straw'], level: 2),
        ...nouns(['plate'], level: 3),
      ],
    ),

    // Three at level 1, because asking for a drink is a daily need and two
    // options is not a choice. Everything below names a particular food, which
    // "food" and a pointed finger already cover on day one.
    Band(
      name: 'drinks',
      shedRank: 2,
      items: [
        ...nouns(['water', 'milk', 'juice'], level: 1),
        ...nouns(['squash', 'tea', 'coffee', 'fizzy'], level: 3),
      ],
    ),

    // The names of the meals, then three things a meal turns out to be. A row
    // a person can read as "what is happening at the table".
    Band(
      name: 'meals',
      shedRank: 3,
      items: [
        ...nouns(['breakfast', 'lunch', 'dinner', 'snack'], level: 2),
        ...nouns(['soup', 'pizza', 'chicken'], level: 3),
      ],
    ),

    // Bread and what goes on it, then the rest of the everyday plate. The
    // longest row on the board and still one thing.
    Band(
      name: 'staples',
      shedRank: 4,
      items: [
        ...nouns([
          'bread',
          'toast',
          'cereal',
          'rice',
          'pasta',
          'egg',
          'cheese',
        ], level: 2),
        ...nouns(['butter', 'honey', 'jam'], level: 3),
      ],
    ),

    Band(
      name: 'fruit',
      shedRank: 5,
      items: [
        ...nouns(['apple', 'banana'], level: 2),
        ...nouns(['orange', 'grapes', 'berries', 'melon', 'lemon'], level: 3),
      ],
    ),

    // Level 3 throughout, so this is the row a six-row grid gives up first and
    // a level-1 or level-2 board never draws either way. "salad" belongs here
    // rather than among the cooked dishes: it is what the vegetables arrive as.
    Band(
      name: 'vegetables',
      shedRank: 6,
      items: nouns([
        'potato',
        'carrot',
        'peas',
        'beans',
        'tomato',
        'salad',
      ], level: 3),
    ),

    // Last of the food rows to hold a page-one location, and the one whose
    // absence costs least: a biscuit is the thing most often offered without
    // being asked for, and page two is one press of a key that never moves.
    Band(
      name: 'treats',
      shedRank: 7,
      items: [
        ...nouns(['cake', 'biscuit'], level: 2),
        ...nouns(['crisps', 'yoghurt'], level: 3),
      ],
    ),

    // A user who cannot say "yucky" cannot decline a meal, only endure it.
    // Opposites sit side by side, which on this axis means along a row.
    Band(
      name: 'how it is',
      shedRank: 1,
      items: [
        ...adjectives(['hungry', 'thirsty', 'yummy', 'yucky'], level: 1),
        ...adjectives(['hot', 'cold'], level: 2),
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

    // What a person does on their own, ending in the ways of getting about.
    Band(
      name: 'doing',
      shedRank: 1,
      items: [
        ...verbs(['play'], level: 1),
        ...verbs(['read', 'draw', 'sing', 'dance', 'run', 'walk'], level: 2),
        ...verbs(['jump'], level: 2),
        ...verbs(['climb', 'swim', 'ride'], level: 3),
      ],
    ),

    // What takes somebody else. Pairs stay side by side — throw with catch,
    // push with pull — because a pair learned as a pair is one location plus a
    // direction.
    Band(
      name: 'games',
      shedRank: 4,
      items: [
        ...verbs(['throw', 'catch'], level: 3),
        ...verbs(['push', 'pull'], level: 2),
        ...verbs(['build', 'hide', 'chase', 'win'], level: 3),
      ],
    ),

    // The same shed rank as the verbs on purpose: when the grid is small the
    // two give way together, so a tiny board keeps some of each rather than a
    // row of verbs and nothing to do them to.
    Band(
      name: 'toys',
      shedRank: 1,
      items: [
        ...nouns(['ball', 'book', 'toy'], level: 1),
        ...nouns(['game'], level: 2),
        ...nouns(['puzzle', 'blocks'], level: 3),
      ],
    ),

    // Everything that plays back at you, whether it is heard or watched.
    Band(
      name: 'films and music',
      shedRank: 5,
      items: [
        ...nouns(['music'], level: 1),
        ...nouns(['song', 'story', 'video', 'tablet'], level: 2),
        ...nouns(['film', 'cartoon'], level: 3),
      ],
    ),

    // Level 3 throughout, which is what makes this the row a six-row grid
    // gives up: a board set to level 1 or 2 draws exactly the same page one
    // with it on page two.
    Band(
      name: 'outdoor',
      shedRank: 6,
      items: nouns([
        'bubbles',
        'swing',
        'slide',
        'bike',
        'scooter',
        'trampoline',
        'sand',
        'paint',
      ], level: 3),
    ),

    // "outside" has a location on the places board too. Level 1 takes that one:
    // a second copy buys no payload, and one word in one place is what a person
    // learns.
    Band(
      name: 'again',
      shedRank: 3,
      items: [
        ...adverbs(['again'], level: 1),
        ...adverbs(['outside'], level: 2),
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
      // The board that spends most of its level-1 budget, and the right one to
      // spend it on: no combination of core words builds any of these, and the
      // cost of not having them is a person enduring something instead of
      // ending it.
      items: [
        ...phrases(['too loud'], level: 1),
        ...phrases(['too bright', 'too fast', 'too slow'], level: 2),
        ...phrases([
          'too much',
          'leave me alone',
          'I need a break',
          "I don't know",
          "I don't understand",
        ], level: 1),
      ],
    ),

    Band(
      name: 'liking',
      shedRank: 2,
      items: [
        ...verbs(['love'], level: 1),
        ...verbs(['like', 'hate'], level: 2),
        ...verbs(['miss'], level: 3),
      ],
    ),

    Band(
      name: 'feeling',
      shedRank: 1,
      items: [
        ...adjectives(['happy', 'sad', 'angry', 'scared', 'tired'], level: 1),
        ...adjectives(['excited'], level: 2),
        ...adjectives(['hurt', 'sick'], level: 1),
        ...adjectives(['worried', 'lonely', 'bored'], level: 2),
      ],
    ),

    // The second row of feelings, immediately under the first, so the two read
    // as one region of the board in one colour. "safe" and "ready" close it:
    // both answer "how are you", which is what this row is for.
    Band(
      name: 'more feelings',
      shedRank: 4,
      items: [
        ...adjectives([
          'silly',
          'funny',
          'calm',
          'proud',
          'shy',
          'jealous',
          'confused',
          'surprised',
        ], level: 3),
        ...adjectives(['safe', 'ready'], level: 2),
      ],
    ),

    // Judgements rather than feelings — what a user says about a situation
    // somebody else is describing. Correcting a listener who got it wrong is
    // the job here: without these the only way to disagree is "no", which
    // reads as refusal rather than correction. Opposites are neighbours.
    Band(
      name: 'right and wrong',
      shedRank: 3,
      items: [
        ...adjectives(['right', 'wrong'], level: 2),
        ...adjectives(['fair', 'unfair', 'kind', 'mean'], level: 3),
        ...adjectives(['better'], level: 2),
        ...adjectives(['worse'], level: 3),
        ...adjectives(['enough'], level: 2),
      ],
    ),

    // Degrees of not knowing, for the questions "yes" and "no" answer too
    // strongly. The root board carries "maybe" at level 1 and that word does
    // the job on its own, so nothing here is level 1 and this row gives way
    // before the shipped feelings rows when the grid is short: the cost of
    // reading it on page two is a key press, not a lost answer.
    //
    // Last of the rows that hold words, because the strips run in word-class
    // order and these are adverbs. "unsure" leads, an adjective among them: it
    // is the one that answers "how are you", so it sits against the adjectives
    // in the row above.
    Band(
      name: 'not sure',
      shedRank: 5,
      items: [
        ...adjectives(['unsure'], level: 2),
        ...adverbs(['probably'], level: 2),
        ...adverbs(['possibly', 'perhaps'], level: 3),
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
    // The four a week actually contains. Everything with wheels moved to the
    // row below, because "car" answers "how are we getting there" and the rest
    // of this row answers "where are we going".
    Band(
      name: 'everyday',
      shedRank: 0,
      items: [
        ...nouns(['home', 'school'], level: 1),
        ...nouns(['shop'], level: 2),
        ...nouns(['park'], level: 1),
      ],
    ),

    Band(
      name: 'travel',
      shedRank: 1,
      items: [
        ...nouns(['car'], level: 1),
        ...nouns(['bus'], level: 2),
        ...nouns(['train', 'plane', 'bike'], level: 3),
      ],
    ),

    // The rooms and the ways between them. "toilet" on the body board is what
    // level 1 uses for the need itself, so "bathroom" here is the place rather
    // than the request and can wait.
    Band(
      name: 'at home',
      shedRank: 3,
      items: [
        ...nouns(['bathroom', 'bedroom', 'kitchen'], level: 2),
        ...nouns(['garden', 'room'], level: 3),
        ...nouns(['door'], level: 2),
        ...nouns(['window', 'stairs'], level: 3),
      ],
    ),

    // Everywhere that is a trip out, from the appointment to the holiday.
    Band(
      name: 'out',
      shedRank: 4,
      items: [
        ...nouns(['hospital', 'work'], level: 2),
        ...nouns([
          'street',
          'beach',
          'pool',
          'library',
          'church',
          'cafe',
          'holiday',
        ], level: 3),
      ],
    ),

    // Answers to "where" that are not a place: adverbs, not nouns, because
    // "upstairs's" and "away is" are what coding them as nouns produced.
    // Adverb also keeps them clear of the preposition colour, which the
    // modified scheme shares with social. "far" and "near" close the row —
    // adjectives, but the same question, and a row of their own would cost the
    // caregiver reserve below it.
    Band(
      name: 'where',
      shedRank: 2,
      items: [
        ...adverbs(['outside'], level: 1),
        ...adverbs(['inside', 'away'], level: 2),
        ...adverbs(['upstairs', 'downstairs'], level: 3),
        ...adjectives(['far', 'near'], level: 3),
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

    // Twenty seven parts, and a row holds eleven. Three rows by region rather
    // than one run that wraps wherever it happens to reach the edge, so a
    // person pointing at where it hurts looks in one place for it.
    //
    // "head" and "tummy" are level 1, because "it hurts" needs somewhere to
    // point and these are the two places it usually is. The rest name a
    // location precisely enough for a doctor, which is a level-2 conversation.
    Band(
      name: 'head',
      shedRank: 1,
      items: [
        ...nouns(['head'], level: 1),
        ...nouns([
          'face',
          'eyes',
          'ears',
          'nose',
          'mouth',
          'teeth',
          'throat',
        ], level: 2),
        ...nouns(['hair', 'lips'], level: 3),
      ],
    ),

    Band(
      name: 'arms and legs',
      shedRank: 2,
      items: [
        ...nouns(['hand', 'arm', 'leg', 'foot'], level: 2),
        ...nouns([
          'finger',
          'thumb',
          'knee',
          'elbow',
          'shoulder',
          'toes',
          'nails',
        ], level: 3),
      ],
    ),

    Band(
      name: 'body',
      shedRank: 3,
      items: [
        ...nouns(['tummy'], level: 1),
        ...nouns(['back'], level: 2),
        ...nouns(['chest', 'neck', 'heart', 'skin'], level: 3),
      ],
    ),

    // "emergency" is the one word here nothing else replaces: it summons
    // somebody in one tap and no run of core words does. "allergic" only means
    // anything inside a sentence naming what, which is not a sentence a
    // level-1 board builds.
    Band(
      name: 'care',
      shedRank: 5,
      // The rest of the strip is level 2 entire: a cough, a temperature and a
      // plaster are ordinary-day vocabulary, and reporting one is how a person
      // gets seen about it.
      items: [
        ...nouns([
          'medicine',
          'plaster',
          'bandage',
          'cough',
          'temperature',
          'doctor',
          'nurse',
          'allergic',
        ], level: 2),
        ...nouns(['emergency'], level: 1),
      ],
    ),

    // Seven clusters and six rows, and this is the one that reads on page two
    // at 7x12. It loses to the medicine cupboard on level rather than on rank:
    // "emergency" is level 1 and nothing here is, and level decides first.
    //
    // The right one to move even so. Every word here needs a body part to
    // attach to, and the parts are three rows above it — a symptom named on
    // page two is still a symptom named, while a board with adjectives and
    // nowhere to point them is not the body board.
    Band(
      name: 'hurting',
      shedRank: 4,
      items: [
        ...adjectives(['itchy'], level: 3),
        ...adjectives(['sore'], level: 2),
        ...adjectives(['dizzy', 'thirsty'], level: 3),
        ...adjectives(['sleepy', 'poorly'], level: 2),
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

  // The verbs a person needs constantly and the root board has no room for.
  // "doing" rather than "verbs" or "actions" because it is the word a UK
  // classroom already uses for them, so a caregiver scanning the keys reads it
  // without being taught.
  //
  // Every strip is verbs, so the strips group by what a person is doing rather
  // than by word class. Within a strip the words run in pairs — sit beside
  // stand, remember beside forget, hold beside drop — because a pair learned
  // as a pair is one location plus a direction, not two locations.
  //
  // Nothing here repeats a label that already has a location on another board.
  // One word, one place.
  'doing': [
    // Self-care first. These are the daily needs a person can least route
    // around, and the ones a listener is least willing to guess at.
    Band(
      name: 'caring',
      shedRank: 0,
      items: [
        ...verbs(['wash', 'brush', 'dress'], level: 2),
        ...verbs(['wear'], level: 3),
        ...verbs(['sleep'], level: 1),
        ...verbs(['wake'], level: 3),
        ...verbs(['rest'], level: 2),
        ...verbs(['breathe'], level: 3),
      ],
    ),

    // Directing another person's movement as well as describing one's own:
    // "stay", "leave" and "follow" are instructions a user gives, which is the
    // half of movement vocabulary a board usually forgets.
    Band(
      name: 'moving',
      shedRank: 1,
      items: [
        ...verbs(['sit', 'stand'], level: 1),
        ...verbs(['move', 'stay', 'leave'], level: 2),
        ...verbs(['follow', 'carry', 'fall'], level: 3),
      ],
    ),

    // Talking about talking. Without these a user can answer a question but
    // cannot say that they are answering one, ask for a turn, or report that
    // somebody is not listening.
    Band(
      name: 'telling',
      shedRank: 2,
      items: [
        ...verbs(['ask', 'answer', 'talk'], level: 2),
        ...verbs(['listen'], level: 1),
        ...verbs(['call'], level: 3),
        ...verbs(['show'], level: 1),
        ...verbs(['spell', 'shout'], level: 3),
      ],
    ),

    Band(
      name: 'thinking',
      shedRank: 3,
      items: [
        ...verbs(['remember', 'forget'], level: 2),
        ...verbs(['learn', 'understand'], level: 3),
        ...verbs(['try', 'choose'], level: 2),
        ...verbs(['decide', 'wonder'], level: 3),
      ],
    ),

    Band(
      name: 'handling',
      shedRank: 4,
      items: [
        ...verbs(['hold'], level: 2),
        ...verbs(['drop'], level: 3),
        ...verbs(['find'], level: 2),
        ...verbs(['lose', 'fix', 'clean', 'cut', 'cook'], level: 3),
      ],
    ),

    Band(
      name: 'sharing',
      shedRank: 5,
      items: [
        ...verbs(['share'], level: 2),
        ...verbs(['swap', 'meet', 'visit'], level: 3),
        ...verbs(['hug'], level: 1),
        ...verbs(['kiss', 'laugh', 'cry'], level: 2),
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
};
