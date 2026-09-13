/// The shipped vocabulary, as bands rather than coordinates.
///
/// Every word comes from one of two places: the Universal Core 36 published by
/// the Center for Literacy and Disability Studies at UNC Chapel Hill, or the
/// editorial judgment recorded in docs/starter-vocabulary.md, which says which
/// is which word by word. Ordering follows the Fitzgerald Key's left to right
/// sentence arrangement, first published in 1926 and in the public domain.
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
/// published core lists under-emphasize the word types that dominate early
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

/// Where the comparatives sit in that same order (§4.68).
///
/// The one grammar key that does not earn [grammarKeyPageRank]. Behind the
/// conjunctions at 20 and behind the verb tail at 30, because linking words
/// are what turn a run of words into a sentence and a comparative is not that.
/// Of everything on the root board these are the least costly to reach for on
/// a second page.
const comparativePageRank = 35;

/// The two endings that are drawn late as well as paged off late (§4.68).
///
/// Named because two rules have to make an exception of exactly this pair and
/// a rule that makes its exception by matching a label is a rule that breaks
/// when somebody renames a key.
const comparativeMorphemes = {
  MorphemeKind.comparativeEr,
  MorphemeKind.superlativeEst,
};

List<BandItem<SeedWord>> _all(
  List<String> labels,
  PartOfSpeech pos, {
  int level = 2,
  int? pageRank,
}) => [for (final l in labels) w(l, pos, level: level, pageRank: pageRank)];

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
List<BandItem<SeedWord>> phrases(
  List<String> l, {
  int level = 2,
  int? pageRank,
}) => _all(l, PartOfSpeech.social, level: level, pageRank: pageRank);

/// A digit to read and a word to say.
///
/// The numeral is quicker to recognize and the word is what a listener needs
/// to hear, so these are the first ordinary vocabulary where the label and the
/// spoken text are deliberately different. Colored as determiners because
/// that is the work they do — `three` quantifies exactly as `some` and `more`
/// do, and sharing their color is what says so.
/// The key that opens the number pad (§4.77).
///
/// Labelled with digits rather than with a word, because that is what it makes
/// and because there is no word for it a person would look for: nobody scans a
/// board for "keypad".
///
/// Tagged as a determiner like the numerals beside it. It is not a word and it
/// speaks nothing, but Fitzgerald colors by class and a band owns a row — one
/// grey key on the end of a row of orange ones would read as the board having
/// made a mistake, and what this key produces is a number.
BandItem<SeedWord> _keypad({int level = 2}) => BandItem((
  label: '123',
  message: '',
  action: ButtonAction.keypad,
  morphemeKind: null,
  pos: PartOfSpeech.determiner,
), level: level);

BandItem<SeedWord> _numeral(String digit, String spoken, {int level = 2}) =>
    BandItem((
      label: digit,
      message: spoken,
      action: ButtonAction.speak,
      morphemeKind: null,
      pos: PartOfSpeech.determiner,
    ), level: level);

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
      // With "that", not with the determiners. They are one pair of
      // demonstratives doing one job, and English does not sort them into
      // different word classes: both work as pronoun and as determiner, "I
      // want that" beside "that cup". Tagged apart they drew in different
      // colors, in different regions, so somebody who had learned one got no
      w('we', PartOfSpeech.pronoun, level: 2),
      w('they', PartOfSpeech.pronoun, level: 2),
      // Neither has a substitute here: "+'s" fires after "I" and produces
      // "I's", and the object pronoun on the people board is two movements
      // away from "help me". "me" is the one level 1 keeps, because it is the
      // one that follows a verb.
      w('my', PartOfSpeech.pronoun, level: 2),
      w('me', PartOfSpeech.pronoun),
      // With "that", not with the determiners. They are one pair of
      // demonstratives doing one job, and English does not sort them into
      // different word classes: both work as pronoun and as determiner, "I
      // want that" beside "that cup". Tagged apart they drew in different
      // colors, in different regions, so somebody who had learned one got no
      // help finding the other.
      //
      // Last in the band, which is what puts it beside "it" and one cell from
      // "that" rather than at the top of the next column. The band fills down
      // its columns and is exactly six deep, so any two consecutive words that
      // straddle that boundary end up diagonally apart — which is what putting
      // it next to "that" in this list would have done.
      //
      // Level 2, because "that" is the Universal Core demonstrative and points
      // at the same things: level 1 carries one of the pair rather than both.
      w('this', PartOfSpeech.pronoun, level: 2),
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
      // Directly under "more", which is the whole point of where it sits. The
      // band fills down its column, so the two are one cell apart and the pair
      // is learned as a pair rather than as two positions that happen to mean
      // opposite things.
      //
      // Level 2: "more" is in the Universal Core 36 and this is not, so a
      // level 1 board holds the location without drawing it, and raising the
      // level reveals it exactly where it has always been.
      w('less', PartOfSpeech.determiner, level: 2),
    ],
  ),

  // Opposites and near-relations sit side by side: want, need, like along one
  // row, then go beside stop, get beside take, open beside close. Neighboring
  // locations are learned as a pair; two positions that happen to be far apart
  // are learned twice.
  //
  // Filled across the band rather than down it, which is what puts those pairs
  // shoulder to shoulder. The band keeps the same columns either way — this is
  // the Fitzgerald "does" region and it does not move.
  Band(
    name: 'verbs',
    shedRank: 1,
    // Three, because the rows above are triples: want/need/like, go/stop/wait,
    // can/get/take. A fourth column re-wraps every one of them and the pairs
    // this band is arranged around end up in different rows.
    maxLines: 3,
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
      // The stem, not the past form. Seeded as `finished` it was a verb
      // already carrying its ending, and nothing marked it as such — so the
      // board offered `+ed` after it and said "finisheded". `finish` takes the
      // endings like every other verb, and the word a person actually wants
      // most of the time is still one key plus `+ed`.
      w('finish', PartOfSpeech.verb, essential: true),
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
      // In the location "feel" held, which is what makes the swap free: the
      // cell, the rank and the level are the same one, so nothing else on this
      // band moves by a column. "feel" went to `feelings`, where the words it
      // attaches to are — it is the one verb here that needs an adjective from
      // another board to finish it, and "I feel" then "sad" was two boards
      // either way round.
      //
      // "have" is the verb that was missing and could not be built: possession
      // ("I have a sister"), obligation ("I have to go"), and the perfect that
      // the endings on this board cannot make on their own. Beside "give",
      // which is the other half of what happens to a thing.
      w('have', PartOfSpeech.verb, level: 2, pageRank: 30),
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
      // The rest of the modals, which the board had no way to say. Without
      // them a person can state and request but cannot hedge, offer or ask
      // permission — "could I", "would you", "should we" — and those are the
      // forms most of asking politely is made of.
      //
      // Level 3 and behind "will" in the overflow, deliberately. They are one
      // step past the tense set: a board still learning that "will" makes a
      // future does not need three more auxiliaries competing with it, and
      // declaring them here keeps the paired verbs above untouched for the
      // reason the comment above gives.
      w('could', PartOfSpeech.verb, level: 3, pageRank: 26),
      w('would', PartOfSpeech.verb, level: 3, pageRank: 26),
      w('should', PartOfSpeech.verb, level: 3, pageRank: 26),
      // The verb a person needs for their own equipment and for everything
      // anybody hands them — a chair, a lift, a toilet, a talker. Without it
      // "can I use that" has to be built out of "can" and a noun and hope.
      //
      // "use" and "order" are not here, and the reason is arithmetic rather
      // than judgement. This band overflows onto page two at 7x12, where its
      // width is however many columns the surplus needs — twelve words is two
      // columns and the pairs read across them, know/think over say/tell over
      // see/come over give/feel. Fourteen words is three columns, and every
      // one of those pairs comes apart. Both verbs are on `doing`, with the
      // groups they belong to.
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
      // Comparatives, at level 3 rather than with the rest of the band (§4.68).
      //
      // `applyMorpheme` has always known how to make these, irregulars
      // included — good becomes better, bad becomes worse — and no board had a
      // key to ask with. What arrives here is the movement, not the grammar.
      //
      // Level 3 because nothing is unsayable without them: the copula earns
      // level 2 by being the difference between a board that can ask "are you
      // ok?" and one that cannot, and a comparative is not that. It also needs
      // an adjective already in the bar to attach to, which is a later skill
      // than the endings beside it.
      //
      // And the first thing off the root board when it will not all fit. Every
      // other ending ranks at `grammarKeyPageRank`, which is what kept them on
      // page one ahead of the conjunctions at 20 — so adding two more at that
      // rank pushed `and but because so` off instead. Linking words are what
      // turn a run of words into a sentence and they earn page one; a
      // comparative does not, on any grid too small for both.
      //
      // 35 puts them behind the conjunctions and behind the verb tail at 30,
      // which is the honest order: of everything on the root board these are
      // the least costly to reach for on a second page.
      _morpheme(
        '+er',
        MorphemeKind.comparativeEr,
        level: 3,
        pageRank: comparativePageRank,
      ),
      _morpheme(
        '+est',
        MorphemeKind.superlativeEst,
        level: 3,
        pageRank: comparativePageRank,
      ),
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
      // With the joining words, which is what it is: "for" is benefactive, not
      // locative — "help for me" answers who, not where — and under the
      // "where" heading it was mislabelled.
      //
      // This band is six deep, so it goes to the second page. Accepted rather
      // than worked around: at 7x11 it was already on the second page of
      // "where", so the move costs nothing it was not already costing and buys
      // a heading that describes it.
      //
      // Tagged a conjunction, which is what colors it. It was left a
      // preposition on the argument that Fitzgerald colors by word class and
      // the color should not follow the neighbors — but the neighbors are
      // what a person reads. One pink key in a row of white ones says the
      // board made a mistake, and the reader who most needs the color coding
      // is the one least able to be told it is fine. "for" is a coordinating
      // conjunction as well as a preposition — it is the F in "for, and, nor,
      // but, or, yet, so" — so this is the truth about the word, not a lie
      // told for the sake of the palette.
      w('for', PartOfSpeech.conjunction, level: 2),
      // Accompaniment, which none of the spatial prepositions cover: "go with
      // me", "I want to come with you". It belongs in the preposition band
      // above and there is no room for it there at any grid this board ships
      // on, so it is here with the other words whose job is to join two parts
      // of a sentence — which is what this one does.
      //
      // Seventh in a six-deep band, so at 7x12 it reads on page two behind
      // "for", exactly as "for" reads on page two there. Accepted for the same
      // reason: one movement further away costs less than the column.
      w('with', PartOfSpeech.preposition, level: 2),
      // What a sentence is *of*, which nothing on this board could say. Every
      // preposition in `places` answers where a thing is; none of them answers
      // what a thing concerns — "talk about it", "ask about him", "a story
      // about the dog" — and that is most of what anybody says out loud.
      //
      // Here rather than in `places`, for the reason "with" is here: that band
      // is exactly twelve deep, which is exactly two columns at 7x12, and a
      // thirteenth word costs it a whole column and takes `under`, `left`,
      // `right` and `off` off page one to pay for it. This band is the one for
      // words whose job is to join two parts of a sentence, and joining is
      // what this one does.
      //
      // Appended, so it takes a location nothing was in.
      w('about', PartOfSpeech.preposition, level: 2),
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
      // "for" is what turns a request into one made on somebody's behalf —
      // "help for me", "a drink for you" — and it is the preposition this band
      // was missing (§4.70).
      // The only one of the common spatial prepositions the band was missing:
      // in, on, up and out were all here and "under" was not, so a board could
      // say where a thing was in every direction but one.
      w('under', PartOfSpeech.preposition, level: 2),
      // Directions, which the band had none of: a person could say a thing was
      // in, on, up, out or under something and not which side of it.
      //
      // "right" is also on the right and wrong band, as the opposite of wrong.
      // Two buttons, one label, two meanings — which is what the word does in
      // English, and separating them by board and by region is how a board
      // carries a homograph. Nothing keys behavior off this label, so the two
      // do not interfere; anything added later that matches words by label has
      // to expect both.
      w('left', PartOfSpeech.preposition, level: 3),
      w('right', PartOfSpeech.preposition, level: 3),
      // "on" has been here since the first board and "off" never was, so the
      // board could put a thing somewhere and not take it back — and could
      // not say the one thing anybody says about a light, a tap or a
      // television. It draws at level 2 with "out" and "under", the other two
      // that answer where something went rather than where it is.
      w('off', PartOfSpeech.preposition, level: 2),
      // The other axis. Left and right are the only directions a board with
      // these could give, which is half of every instruction about a
      // wheelchair, a queue, a page or a walk.
      w('forward', PartOfSpeech.preposition, level: 3),
      w('backward', PartOfSpeech.preposition, level: 3),
      // "there" is not here, and "with" is not here. Both belong in this band
      // by word class and neither fits: the band is exactly twelve deep, which
      // is exactly two columns at 7x12, and a thirteenth word costs it a whole
      // column — which at that size took `under`, `left`, `right` and `off`
      // off page one and moved `yes`, `no` and `don't` a column sideways.
      // Two words are not worth four words and a displacement.
      //
      // "there" is on `places` / `where`, with the other adverbs that answer
      // the question. "with" is in `articles` below, with the joining words.
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
      // The rest of the scale "good" is one end of. Without them the only
      // verdict on this board is a positive one, and "not good" is what a
      // person is left saying when they mean "bad" — which is a hedge, not
      // the word.
      //
      // Paged at the comparative rank, beside "almost", and the dump is why:
      // at their own rank the band asks for a second column, and the column it
      // takes comes off `places` — `under`, `left`, `right`, `off`, `forward`
      // and `backward` all leave page one to pay for two words. Ranked here
      // they take themselves to page two on a grid with no room and sit in
      // "good"'s own column on a grid that has it.
      //
      // Level 2, not 1, and that is the paging rank's doing rather than a
      // judgement about the words: at level 1 they are the only thing on page
      // two of a level-1 board, which hands a beginner a paging key and a
      // second page where the board had been one page and done. "almost" sits
      // at this rank for the same reason and took level 2 with it.
      w('ok', PartOfSpeech.adjective, level: 2, pageRank: comparativePageRank),
      w('bad', PartOfSpeech.adjective, level: 2, pageRank: comparativePageRank),
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
      // Beside "maybe", which is the other answer a person needs when yes and
      // no are both wrong. "almost" is the one that answers "are you
      // finished?" honestly, and without it the truthful answer is "no".
      //
      // Paged at the comparative rank, which is the last thing off this board.
      // The band is exactly six deep and 7x12 gives it one column, so a
      // seventh word at the band's own rank made it ask for two — and the
      // column it would have taken came off `places`, which lost `under`,
      // `left`, `right` and `off` from page one to pay for it. Ranked here it
      // takes itself to page two instead and every other word stays put.
      w('almost', PartOfSpeech.adverb, level: 2, pageRank: comparativePageRank),
    ],
  ),

  // What to say to somebody who does not know what they are looking at: a
  // stranger reads a pause as absence, and starts talking to whoever is
  // standing next to the user. Saying the voice is a computer's answers both
  // halves of what they are working out — why the wait, and who is speaking —
  // and the sentence names no object, so it holds whatever anybody calls the
  // device and reads the same off a paper backup board.
  //
  // "computer voice" rather than the formal terms, and rather than
  // "computer generated". A sentence said aloud to a bus driver is not a
  // funding form: "speech generating device" sounds like a diagnosis being
  // read out, "synthetic voice" hands over a category instead of a reason, and
  // "generated" is a word a listener does not need. Length is not free either.
  // A label is set on one line and scaled down to its cell, so each extra word
  // is drawn at the cost of the ones already there.
  //
  // "please wait" is deliberately not part of it. `wait` is on this board at
  // level 1 and marked essential; a phrase that repeated it would buy a second
  // location for a word already one press away, and the two combine.
  //
  // Costs the board nothing at any grid size. The one spare column a 7x12
  // board has is the reserve `nouns` holds for the words a particular person
  // turns out to need on the root board, and a shipped phrase is not worth
  // spending it: this one takes a tail cell where the last row ends short and
  // pages where it does not.
  Band(
    name: 'introduction',
    startsLine: false,
    tailOnly: true,
    items: phrases(['I use a computer voice to talk'], pageRank: 40),
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

BandItem<SeedWord> _morpheme(
  String label,
  MorphemeKind kind, {
  int level = 2,
  int pageRank = grammarKeyPageRank,
}) => BandItem(
  (
    label: label,
    message: '',
    action: ButtonAction.morpheme,
    morphemeKind: kind,
    pos: PartOfSpeech.other,
  ),
  level: level,
  pageRankOverride: pageRank,
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
  // Renamed from `body`. The board was already more than the parts — the
  // toilet, the medicine cupboard, the emergency key — and naming it for the
  // parts sent people to it for a body part and nowhere else. Renaming a
  // category changes the word over a key, not the key: this name sits at the
  // same index it always did, so the wheel opens exactly what it opened.
  'health',
  'doing',
  // Appended, which is what makes it safe: the wheel is a window onto this
  // list in order, so a name added at the end leaves every key already learned
  // opening exactly what it always opened.
  'numbers',
  'time',
  'objects',
  // Appended for the same reason and with the same guarantee: the wheel is a
  // window onto this list in order, so every key already learned still opens
  // what it always opened.
  'weather',
  'clothing',
  'animals',
  // Appended, with the same guarantee as every name above it: the wheel is a
  // window onto this list in order, so a name at the end leaves every key
  // already learned opening what it always opened.
  'measurement',
  'colors',
  'nature',
  // Appended, with the same guarantee as every name above it: the wheel is a
  // window onto this list in order, so a name at the end leaves every key
  // already learned opening what it always opened.
  'shapes',
];

/// Categories that have been renamed, old name to new.
///
/// A rename changes the word over a key and nothing else: the name keeps its
/// index in [categoryNames], so the wheel opens exactly what it opened.
///
/// **A board set built before the rename does not know that.** It carries the
/// old name in its boards table and in the frame it recorded, and everything
/// that matches a category by name — the top-up above all — reads the new name
/// as a category it does not have. Left to itself it would build a second
/// board beside the one already there, take a system-row column to open it,
/// and leave the person with the body board they learned and a health board
/// holding the same words.
///
/// So a rename is two things: the entry above changes, and the old name is
/// recorded here so a board set carrying it can be brought forward.
///
/// Append only, and never a chain: the value is always a current entry of
/// [categoryNames], so one lookup is always enough.
/// Words whose label changed after boards had already been built with the old
/// one (§4.82).
///
/// **A label, not a location.** The button keeps its cell, its id, its picture
/// and its place in the motor plan; only the word written on it changes. That
/// is what makes this safe to apply without asking — the movement that reached
/// the old word reaches the new one, because it is the same button.
///
/// Only for a word that was *wrong*, never for one somebody might prefer
/// differently. A board that renamed words on taste would be changing what a
/// person had learned to say.
const renamedWords = <({String from, String to, String? onBoard})>[
  // "sweets" is British and this board is written in American English. A
  // person whose board says "sweets" sounds like somebody else's board.
  (from: 'sweets', to: 'candy', onBoard: null),
  // Same reason: "film" is what it is called somewhere else. Nobody in this
  // house asks to watch a film.
  (from: 'film', to: 'movie', onBoard: null),
  // Not a rename for the sake of a better word — a rename for a wider one.
  // "cartoon" names one kind of thing on the screen, and the thing a person
  // actually asks for is the screen: the news, a show, a game somebody else is
  // playing. A board that can only ask for cartoons cannot ask to watch
  // anything else.
  (from: 'cartoon', to: 'TV', onBoard: null),
  // **The place, not the verb — which is what `onBoard` is for.**
  //
  // "shop" is both a noun and a verb in English and the board needs both, so
  // the place takes the unambiguous word and the verb keeps "shop" on `doing`.
  // Renaming by label alone would have renamed the verb too, and left a board
  // with "store" where an action should be. Found by the test that says a
  // fresh seed has nothing to rename.
  (from: 'shop', to: 'store', onBoard: 'places'),
];

const renamedCategories = <String, String>{'body': 'health'};

/// Fringe vocabulary in clusters: one cluster to a band, one band to a row.
///
/// Word class is the coarse grouping. Strips run top to bottom in Fitzgerald
/// order — whole utterances, verbs, nouns, object pronouns, adjectives,
/// adverbs — so a class occupies a contiguous block of rows and therefore a
/// contiguous block of color, which is what the evidence measured: arranging
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
      // "sorry" is the fifth of the set and the one a person is asked for
      // most often. Level 1: a board that can greet and thank but not
      // apologize leaves somebody without the word for the situation they are
      // most likely to be put on the spot in.
      items: phrases([
        'hello',
        'bye',
        'please',
        'thank you',
        'sorry',
      ], level: 1),
    ),

    // Only the two a shipped board can assume. Whether there is a sibling or a
    // living grandparent is exactly the kind of thing it cannot know, so the
    // rest of the strip waits for somebody who does.
    //
    // The family somebody chose is on the end of the same row, appended into
    // the free cells it already had. Not a band of its own: they are the same
    // kind of word, somebody looking for "wife" looks where "mom" is, and a
    // seventh band on this board takes a seventh row the board does not have —
    // which at 7x12 would have paged the nine possessives to buy four words.
    //
    // **`maxLines: 1` is what stops that happening anyway.** A band with more
    // items than its line holds claims another line by default, and another
    // line here is the same eviction by a quieter route. Capped, the row keeps
    // the eleven it can draw and the twelfth reads on page two: at 7x12 that
    // is `girlfriend`, and on every wider grid all four fit. One word a press
    // further away, against nine.
    //
    // Level 2, not the level 3 the rest of the naming vocabulary sits at.
    // Adults and teenagers start at level 2, so level 3 would have meant
    // shipping these and drawing none of them — and a board that can say "mom"
    // and "brother" but not "wife" has decided which of somebody's
    // relationships count.
    //
    // "family" no longer closes the row. It did, on the argument that the
    // collective belongs with its members; it is still among them, one cell
    // further in.
    Band(
      name: 'family',
      shedRank: 1,
      maxLines: 1,
      items: [
        ...nouns(['mom', 'dad'], level: 1),
        ...nouns([
          'baby',
          'brother',
          'sister',
          'grandma',
          'grandpa',
          'family',
        ], level: 2),
        ...nouns(['husband', 'wife'], level: 2),
        ...nouns(['boyfriend', 'girlfriend'], level: 2),
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
        // "doctor" and "nurse" are not here: they are on `health`, which is
        // the board somebody is on when they need one. They were on both as
        // the same noun, which is one word in two places rather than two
        // words.

        ...nouns(['neighbor', 'driver', 'stranger'], level: 3),
      ],
    ),

    // Words for a person nobody has named yet — the ones a user reaches for
    // when pointing is not enough and a name is not known. "name" closes the
    // row for the same reason: it is the word that asks for one.
    Band(
      name: 'people',
      shedRank: 4,
      items: nouns([
        'boy',
        'girl',
        'man',
        'woman',
        'name',
        // The board's own name, and the word for one of whoever is on it.
        // Appended, so the five above keep the locations they were learned in
        // — and the person's own name is placed in the free cell after these,
        // which is what puts it beside the key that asks for one.
        'person',
        'people',
      ], level: 2),
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

    // Whose something is. Here rather than on the root board because the root
    // board's pronoun column is the subject paradigm, and a possessive is not
    // a subject — the same reason the object pronouns are in the row above.
    //
    // Both forms, because they are different words in a sentence: "your turn"
    // takes a noun after it, "it's yours" stands alone. The determiners come
    // first and a level earlier, because they are the ones that appear inside
    // a sentence somebody is building rather than as an answer on their own.
    //
    // "my" and "me" stay on the root board. They are the two a person reaches
    // for constantly and they have already been paid for there.
    // "her" is missing from this row on purpose: it is already in `referring`
    // above, as the object pronoun, and the two are spelled the same. One
    // label twice on one board is a defect — the person cannot tell the keys
    // apart, and the second one teaches that a word can be in two places.
    // The key that is there says "her", which is the word either way.
    Band(
      name: 'belonging',
      shedRank: 6,
      items: [
        ...pronouns(['your', 'his', 'our', 'their'], level: 2),
        ...pronouns(['mine', 'yours', 'hers', 'ours', 'theirs'], level: 3),
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
        // Moved here from `doing` / `handling`. It is a verb, but it is a verb
        // about the nouns on this board, and one movement to `cook` plus one
        // to what is being cooked beats two boards for one sentence.
        ...verbs(['cook'], level: 3),
        // The rest of what a person does with food (§4.42). `open` is not
        // here — it is a level-1 core word on the root board and one word has
        // one location.
        ...verbs(['taste', 'chew', 'swallow', 'pour', 'spill'], level: 3),
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
        ...nouns(['tea', 'coffee', 'soda'], level: 3),
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
        ...nouns(['cake', 'cookie'], level: 2),
        ...nouns(['chips', 'yogurt'], level: 3),
      ],
    ),

    // The half of "treats" that was missing, and the half a person is most
    // often offered a choice between (§4.42).
    // Above `treats` and below the reserve, so these two are what pages off
    // rather than what pushes `fruit` off. A band added to a full board takes
    // the back of the queue: nothing that was on page one goes to page two to
    // make room for something that has just arrived.
    Band(
      name: 'sweet things',
      shedRank: 8,
      items: [
        // "candy", not "sweets". Both are English and only one of them is the
        // English this board is written in — a board that says "sweets" to an
        // American child is a board that sounds like somebody else.
        ...nouns(['dessert', 'candy'], level: 2),
        ...nouns(['chocolate', 'ice cream', 'pudding'], level: 3),
      ],
    ),

    // The objects a meal happens with. Naming the thing you need is how you
    // ask for it without anybody having to guess which one.
    Band(
      name: 'at the table',
      shedRank: 8,
      items: [
        // `plate` is on the `eating` row already, and one word has one
        // location.
        // All level 3. The level-2 ceiling is a wall rather than a budget
        // (§4.28), and a row of tableware is not what a day becomes sayable
        // on — `hungry`, `drink` and `more` already are.
        ...nouns(['cup', 'bowl', 'spoon', 'fork', 'knife', 'napkin'], level: 3),
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
        // The four tastes, on the row that already answers "what is it like"
        // rather than at the end of `eating` above it. `eating` is verbs and
        // the things they are done to; these are what the answer to `taste` —
        // one row up and a few locations along — actually is. Kept with the
        // other adjectives so the row stays one color, which is the whole of
        // how somebody finds a describing word without reading it.
        ...adjectives(['sweet', 'sour', 'bitter', 'salty'], level: 3),
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
        // "break" against "build", which is the pair this row is built on —
        // throw with catch, push with pull, build with break.
        //
        // Slotted in rather than appended, which is the one place this file
        // does that: it moves `hide`, `chase`, `win` and `lose` a column along
        // in the shipped layout. Affordable only because nobody has learned
        // those positions yet — no board in anybody's hands is rebuilt by
        // this, because a top-up never moves a button that is already placed.
        // It would not be affordable after 1.0.
        ...verbs(['build', 'break'], level: 3),
        ...verbs(['hide', 'chase'], level: 3),
        // "lose" against "win", which is the pair and not two words. It was
        // on `doing` among the things somebody does to an object — fix, clean,
        // cut — where it meant mislaying a shoe. This is the other sense and
        // the one a game needs, and it belongs against its opposite: a pair
        // learned as a pair is one location plus a direction.
        ...verbs(['win', 'lose'], level: 3),
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
        // Appended, not slotted in beside "game" where it reads best. Putting
        // it there pushed "puzzle" and "blocks" a column along, and a word
        // added to a band has to take a location nothing was in — otherwise a
        // board built today and one built last week disagree about where two
        // words are, and the top-up can only report the new one as blocked.
        ...nouns(['video game'], level: 2),
      ],
    ),

    // Everything that plays back at you, whether it is heard or watched.
    Band(
      name: 'films and music',
      shedRank: 5,
      items: [
        ...nouns(['music'], level: 1),
        ...nouns(['song', 'story', 'video', 'tablet'], level: 2),
        ...nouns(['movie', 'TV'], level: 3),
        // The other half of a screen: the things it holds and the thing that
        // makes them. "picture" earns level 2 on its own — it is half of "take
        // a picture", which is a whole request, and it is what a person points
        // at when the word they want is not on the board.
        ...nouns(['picture'], level: 2),
        ...nouns(['camera'], level: 3),
      ],
    ),

    // Level 3 throughout, which is what makes this the row a six-row grid
    // gives up: a board set to level 1 or 2 draws exactly the same page one
    // with it on page two.
    Band(
      name: 'outdoor',
      shedRank: 6,
      items: [
        // The place the rest of this row happens in, first, because it is the
        // word that asks to go and the others are what you do once you are
        // there. "park" is not here: it has a level-1 location on `places`,
        // which is one movement away, and a second copy of a word is a second
        // thing to learn about it.
        ...nouns(['playground'], level: 2),
        ...nouns([
          'bubbles',
          'swing',
          'slide',
          'bike',
          'scooter',
          'trampoline',
          'sand',
          'paint',
        ], level: 3),
      ],
    ),

    // What a person is doing rather than what they are doing it with. "active"
    // is how somebody describes a day, a mood, or what they want more of, and
    // "activity" is the word every school timetable and support plan is
    // written in — which makes it the word said *to* this person all day, and
    // one they have no way to say back without it.
    Band(
      name: 'activity',
      shedRank: 7,
      items: [
        ...nouns(['activity'], level: 2),
        ...adjectives(['active'], level: 3),
        // Here rather than beside "story" in the row above, where it reads
        // best. That row is exactly nine words, which is exactly a line at
        // 6x10, so a tenth opens a line there and takes `activity`, `active`,
        // `lose` and the whole sports row down a page with it — twelve placed
        // words moved to pay for one. This row has room on every grid the app
        // builds, and it is not a bad home: a joke is a thing a person does,
        // which is what this row is for.
        //
        // The only repair this board has for a sentence that landed wrong.
        // Somebody who cannot say "joke" cannot take anything back, and is
        // answered seriously for the rest of the conversation — which is a
        // worse outcome than the joke not landing.
        //
        // Level 3, with "funny" and "silly" on `feelings`. Appended.
        ...nouns(['joke'], level: 3),
      ],
    ),

    // A row of its own rather than a scatter through the verbs, because these
    // are what a person watches, plays, supports and is taken to — and because
    // naming the category gives somebody a way to ask about one this board
    // does not carry.
    Band(
      name: 'sports',
      shedRank: 8,
      items: [
        ...nouns(['sports'], level: 2),
        ...nouns(['soccer', 'basketball'], level: 2),
        ...nouns([
          'baseball',
          'football',
          'tennis',
          'hockey',
          'golf',
          'running',
        ], level: 3),
      ],
    ),

    // "outside" has a location on the places board too. Level 1 takes that one:
    // a second copy buys no payload, and one word in one place is what a person
    // learns.
    // "outside" is not here any more: it and "inside" both live on `places`,
    // which is the board that answers where. A second copy bought no payload
    // and cost a person a second thing to learn about one word.
    Band(
      name: 'again',
      shedRank: 3,
      items: [
        ...adverbs(['again'], level: 1),
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
          // The sentence an AAC user needs most and is least often given time
          // to build. Composing one word at a time is slower than speech, so
          // the gap before the next word reads to a speaking listener as the
          // end of the turn — and they answer, or move on, or finish it
          // themselves. `wait` is on the root board at level 1 and holds the
          // floor before a sentence; this is the one that takes it back
          // halfway through, which is when it is actually lost.
          'let me finish',
        ], level: 1),
      ],
    ),

    // What a person makes rather than says (§4.85).
    //
    // **These are reactions, and the board had none.** Everything else here is
    // a sentence — "it hurts", "too loud", "I need a break" — and a sentence
    // arrives after the moment it was about. An interjection is the moment:
    // `ow` lands while the thing is happening, which is when somebody can
    // still stop it, and `uh oh` is how a person reports a spill or a mistake
    // before anybody has asked.
    //
    // Coded as whole utterances for the same reason the sentences above are:
    // one tap is the complete thing, and nothing should offer `ow` a plural.
    // That also puts them in the social color, which is where Modified
    // Fitzgerald keeps them — Goossens' gives interjections a group of their
    // own, and if this board ever ships that scheme these are the words it
    // would move.
    //
    // Level 1 for the four that report something happening to somebody, and
    // that is the argument for the whole row: a person who cannot say `ow` at
    // the moment it hurts is a person whose pain is found out later, from a
    // sentence, if at all.
    Band(
      name: 'reacting',
      shedRank: 1,
      items: [
        ...phrases(['ow', 'uh oh'], level: 1),
        ...phrases(['oops', 'yay'], level: 1),
        ...phrases(['wow', 'huh'], level: 2),
        // Here rather than on the sentence row above, which is where it was
        // asked for. That row is exactly ten phrases, which is exactly a line
        // at 6x11 and 7x11, so an eleventh opens a line there and walks the
        // whole board down — every feeling, every judgement, the unsure row
        // and the adverbs, on four of the seven grids this app builds.
        //
        // And this row is the honest home for it anyway. "excuse me" is not a
        // sentence about how somebody is, it is the noise a person makes to
        // get a turn — which is what everything on this row is, and the reason
        // the row exists.
        //
        // Level 1, with the four beside it that report something happening.
        // A person who cannot interrupt is a person who speaks only when they
        // are asked to.
        ...phrases(['excuse me'], level: 1),
      ],
    ),

    Band(
      name: 'liking',
      shedRank: 2,
      items: [
        ...verbs(['love'], level: 1),
        // "like" is not here: it is a level-1 verb on the root board, one
        // movement from everywhere, and it was the same verb twice.
        ...verbs(['hate'], level: 2),
        ...verbs(['miss'], level: 3),
        // Off the root board, onto the board its object is on. "feel" is the
        // one verb the root carried that needs a word from somewhere else to
        // finish it — "I feel" and then "sad", "tired", "worried", none of
        // which are on the root — so it was always two boards, and this way
        // the second board is the one it is already on.
        //
        // Level 2, which is what it drew at on the root: the move is a
        // location, not a demotion.
        ...verbs(['feel'], level: 2),
      ],
    ),

    // The nouns the board had none of, and the board's own name among them.
    // Rows run in Fitzgerald order — whole utterances, verbs, nouns, then the
    // adjectives that modify them — so this sits between the verbs above and
    // the feelings below and each class keeps a contiguous block of color.
    //
    // "feeling" is what a person needs to talk *about* how they are rather
    // than only to report it: "I have a feeling", "that is a bad feeling".
    Band(
      name: 'what it is',
      shedRank: 7,
      items: [
        ...nouns(['feeling'], level: 2),
        ...nouns(['feelings', 'mood'], level: 3),
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
    // as one region of the board in one color. "safe" and "ready" close it:
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
          // An ordinary evaluative adjective, in the band that already holds
          // them. It opens no row and widens none.
          'cute',
        ], level: 3),
        ...adjectives(['safe', 'ready'], level: 2),
        // Appended, so nothing on this row moves.
        //
        // "uncomfortable" is the one that earns its place: it is what somebody
        // says about a chair, a seam, a position they have been left in or a
        // room that is too warm — none of which is pain, and all of which get
        // reported as pain by a board that has no other word for them. "hurt"
        // is already here and it is a different thing; being taken to mean it
        // is how a person ends up examined for a problem they do not have.
        //
        // Level 2 for the same reason: it is what a day is negotiated in, not
        // what it is named with. Its opposite comes with it, because a person
        // who can only report the bad half is a person nobody can ask whether
        // a change helped.
        ...adjectives(['comfortable', 'uncomfortable'], level: 2),
      ],
    ),

    // Judgments rather than feelings — what a user says about a situation
    // somebody else is describing. Correcting a listener who got it wrong is
    // the job here: without these the only way to disagree is "no", which
    // reads as refusal rather than correction. Opposites are neighbors.
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
        // The one answer this row could not give: that something is not
        // likely. Without it "maybe" has to cover everything from probably to
        // almost certainly not.
        ...adjectives(['unlikely'], level: 3),
      ],
    ),

    // Degree words, which is a class this board had none of (§4.42). They
    // attach to an adjective, and three of the bands above are nothing but
    // adjectives — so this is the board they belong on and this is the row a
    // caregiver will reach for when they ask for another one.
    //
    // "too" was considered and left out. It means "also" as often as it means
    // "excessively", and a key with two meanings and one location is the
    // confusion this board exists to avoid.
    Band(
      name: 'how much',
      shedRank: 6,
      items: [
        ...adverbs(['very', 'really', 'a little'], level: 3),
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
        ...nouns(['store'], level: 2),
        ...nouns(['park'], level: 1),
        // The board's own name. Without it a person can name the places on
        // the board and cannot ask about one that is not.
        ...nouns(['place'], level: 2),
      ],
    ),

    Band(
      name: 'travel',
      shedRank: 1,
      items: [
        ...nouns(['car'], level: 1),
        ...nouns(['bus'], level: 2),
        // "bike" is not here: it is on `play`, where it is the thing a
        // person rides for the sake of it rather than to get somewhere.
        ...nouns(['train', 'plane'], level: 3),
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
    // Adverb also keeps them clear of the preposition color, which the
    // modified scheme shares with social.
    //
    // "far" and "near" used to close this row. They are on `measurement` now,
    // with the rest of the words that answer how big and how far — two
    // adjectives on the end of a row of adverbs were a color break as well as
    // the wrong home, and one word has one home (§4.42).
    Band(
      name: 'where',
      shedRank: 2,
      items: [
        ...adverbs(['outside'], level: 1),
        ...adverbs(['inside', 'away'], level: 2),
        ...adverbs(['upstairs', 'downstairs'], level: 3),
        // "here" is on the root board and "there" never was anywhere, so a
        // person could say where they are and not where anything else goes —
        // and "put it there" is the sentence that needs it. It is here rather
        // than beside "here" because the root board's preposition column is
        // exactly full at 7x12 and a thirteenth word costs it a column.
        ...adverbs(['there'], level: 2),
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

  // Called `body` until it was renamed. Naming a board of parts, toileting,
  // the medicine cupboard and the emergency key after the parts alone sent
  // people to it for a body part and for nothing else.
  'health': [
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
      items: nouns(['toilet', 'pee', 'poo'], level: 1),
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
        // "butt" sits with the other parts rather than behind the adult page
        // two: it is an ordinary body part, and a word a child needs to name
        // to whoever is helping them. Page two is for the genital and vulgar
        // vocabulary, which is a different question.
        ...nouns(['back', 'butt'], level: 2),
        ...nouns(['chest', 'neck', 'heart', 'skin'], level: 3),
        // The whole of what the parts around it belong to, and the board's
        // old name. "my body" is how a person says a thing is theirs to
        // decide about, which is a sentence none of the parts build.
        ...nouns(['body'], level: 2),
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

    // What a person is, in their own words, on the board they are asked about
    // themselves on. Somebody who cannot say "autism" is described in the
    // third person in front of them at every appointment they attend, with no
    // way to name what is being discussed and no way to disagree with it.
    //
    // Both words, because they are not the same word. "autism" is what is on
    // the form and what a stranger says; "autistic" is the identity-first
    // term most autistic adults ask to be described with. A board carrying
    // only the clinical one would be picking a side on the user's behalf.
    //
    // Tagged as nouns throughout, including the two that are adjectives.
    // Fitzgerald colors by word class and the band owns a row: coloring three
    // of six cells differently would read as the board having made a mistake,
    // and this row is a group rather than a sentence being built out of. The
    // `care` band above already does the same with "allergic".
    Band(
      name: 'about me',
      shedRank: 6,
      items: [
        ...nouns(['autism', 'autistic'], level: 2),
        ...nouns(['neurodivergent'], level: 2),
        ...nouns(['disability', 'disabled'], level: 3),
        ...nouns(['diagnosis', 'therapy'], level: 3),
        // The board's own name, and the word for the subject of every
        // appointment the words above are said at.
        ...nouns(['health'], level: 2),
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
        // "thirsty" is not here: it is level 1 on `food`, where a person is
        // when they want a drink, and that is two levels sooner than this.
        ...adjectives(['dizzy'], level: 3),
        ...adjectives(['sleepy', 'poorly'], level: 2),
      ],
    ),

    // The other half of what a person is, and the half nobody puts on an AAC
    // board. A nonspeaking adult has no way to come out, no way to correct
    // somebody who assumes, and no way to say who they are to a doctor asking
    // — and the usual answer to that is to build the word out of the ones
    // already here, which for these three does not work.
    //
    // A row of its own rather than an append to `about me`, which is where
    // they read best. That row is exactly eight words, which is exactly a line
    // at 5x9 and one short of one at 6x11, 7x11 and 6x10, so three more there
    // open a line on four of the seven grids and walk the symptoms down with
    // it. Last in the file and ranked to shed first, so it takes the line
    // nothing else wanted or reads on page two.
    //
    // Tagged as nouns for the reason `about me` is: Fitzgerald colors by word
    // class, the band owns a row, and a row that is half orange and half blue
    // reads as the board having made a mistake.
    //
    // Level 3. Not a judgement about the words — it is where a word goes when
    // it is not needed to build a sentence and is needed to say a true thing,
    // which is where "disability" and "diagnosis" sit.
    Band(
      // Not 'who I am': `about me` one board over already draws under that
      // heading, and two rows on one board with the same name over them is
      // two rows nobody can tell apart.
      name: 'who I love',
      shedRank: 8,
      items: [
        ...nouns(['gay', 'lesbian'], level: 3),
        ...nouns(['bisexual'], level: 3),
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
        // The chair, the talker, the phone. Equipment running flat is a
        // communication outage for the person it belongs to, and until this
        // there was no word that got somebody to do something about it
        // before it happened. The noun is on `objects`, with the other
        // things a person uses.
        ...verbs(['charge'], level: 2),
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
        // Asking somebody whose job it is to bring it: a meal, a drink, a
        // delivery. "want" on the root board is the wish and this is the act,
        // and at a counter they are not the same sentence.
        ...verbs(['order'], level: 3),
        // The noun the two verbs beside it take. "ask" and "answer" were both
        // here and the thing being asked and answered was not, so a person
        // could say they were asking without naming what — and "I have a
        // question" is how somebody gets a turn in a classroom.
        ...nouns(['question'], level: 2),
        ...verbs(['listen'], level: 1),
        ...verbs(['call'], level: 3),
        ...verbs(['show'], level: 1),
        ...verbs(['spell', 'shout'], level: 3),
        // Appended, like everything added to a band here: it takes a location
        // nothing was in.
        //
        // On the telling row rather than among the things done to objects,
        // because what it does is answer somebody — it is the other half of
        // "order". Level 2 and not 3: "let me" is how a person asks to be
        // allowed to do a thing themselves, which is the request this board
        // most needs to be able to make and the one nobody can build out of
        // the words around it.
        ...verbs(['let'], level: 2),
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

    // Money words, as a row of their own rather than scattered through the
    // verbs. They come as a set — you shop somewhere, you buy a thing, and
    // "sell" is what the other person is doing — and a person who has one of
    // them almost always wants the next.
    Band(
      name: 'buying',
      shedRank: 5,
      items: [
        // The verb. The place is "store" on `places`, which is what the
        // rename above is for: one label for two parts of speech means the
        // picture is wrong for one of them.
        ...verbs(['shop'], level: 2),
        ...verbs(['buy'], level: 2),
        ...verbs(['sell'], level: 3),
      ],
    ),

    Band(
      name: 'handling',
      shedRank: 4,
      items: [
        ...verbs(['hold'], level: 2),
        ...verbs(['drop'], level: 3),
        ...verbs(['find'], level: 2),
        // For a person's own equipment and for everything anybody hands them
        // — a chair, a lift, a toilet, a talker. Without it "can I use that"
        // has to be built out of "can" and a noun and hope. It belongs on the
        // root board with the other core verbs and there is no room for it
        // there: that band overflows at 7x12, and two more words re-wrap the
        // overflow and take its pairs apart.
        ...verbs(['use'], level: 2),
        // `cook` is not here. It moved to `food` / `eating`, beside the food
        // it acts on (§4.42) — displacing for anybody who had learned it on
        // this board, which is why it is a seed change reaching new profiles
        // and not an edit to a board in use.
        // "lose" left here for `play`, against "win" — see that board. What
        // stayed is the row's own sense: things done to an object.
        ...verbs(['fix', 'clean', 'cut'], level: 3),

        // "break" is not here: it went to `play`, against "build". It reads as
        // a thing done to an object, which is this row, but the word it is
        // actually used with is its opposite — and a pair learned as a pair is
        // one location plus a direction.
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

    // Adverbs of manner, designed once rather than answered again for every
    // one somebody asks for (§4.42). They modify verbs, and this is the verb
    // board; anywhere else and the word is a movement away from the word it
    // attaches to.
    Band(
      name: 'how',
      shedRank: 6,
      items: [
        ...adverbs([
          'quietly',
          'loudly',
          'slowly',
          'quickly',
          'carefully',
          'gently',
        ], level: 3),
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

  // Nothing here draws at level 1. `more` and `all` ship on the root board and
  // do the quantity work a beginner needs; a board of single words does not
  // need `seven`.
  //
  // A sequence rather than a set of choices, which is unlike every other
  // cluster here: nobody reads `1 2 3 4 5 6 7 8 9 10` in one sweep, they scan
  // along it. Kept to ten so that scan is one row and stays one movement wide
  // — a person who needs a bigger number has words for it on the row below.
  'numbers': [
    Band(
      name: 'counting',
      shedRank: 0,
      items: [
        _numeral('1', 'one'),
        _numeral('2', 'two'),
        _numeral('3', 'three'),
        _numeral('4', 'four'),
        _numeral('5', 'five'),
        // Six upward wait for level 3. Counting to five covers a young
        // child's age, a small quantity and a choice between a few things,
        // which is what the level that "most of a day is sayable" is
        // measured against — and the locations are already here, so these
        // appear where they have always been rather than arriving somewhere
        // new.
        _numeral('6', 'six', level: 3),
        _numeral('7', 'seven', level: 3),
        _numeral('8', 'eight', level: 3),
        _numeral('9', 'nine', level: 3),
        _numeral('10', 'ten', level: 3),
        // The end of the row, and the answer to what the row cannot hold. Ten
        // keys is one movement wide and that is worth keeping; a person's
        // numbers are not ten long. Appended, so every numeral above keeps the
        // location it was learned in.
        //
        // Level 2 with `1` to `5` rather than level 3 with the rest. A board
        // drawing five numbers is the one that most needs another way to a
        // sixth, and the pad is the way that does not cost a location.
        _keypad(),
      ],
    ),

    // What somebody says about a quantity when they do not have the numeral,
    // which is most of the time. "how many" is a question the pinned column
    // cannot ask: `how` is there, but `how many` is a different question and
    // one a person is asked constantly.
    Band(
      name: 'how many',
      shedRank: 1,
      items: [
        ...phrases(['how many'], level: 2),
        ...adjectives(['none'], level: 2),
        ...phrases(['a lot', 'a little'], level: 2),
        // "whole" beside "half", which is the pair a quantity is usually
        // described against: half the sandwich, the whole sandwich.
        ...adjectives(['both', 'half', 'whole'], level: 3),
        // The board's own name, and the word for the numbers this board is
        // not: a phone number, a house number, a bus number.
        ...nouns(['number'], level: 2),
      ],
    ),

    Band(
      name: 'in order',
      shedRank: 2,
      items: [
        ...adjectives(['first', 'next', 'last'], level: 2),
        ...adjectives(['before', 'after'], level: 3),
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

  // Nothing on the board said when. Asked for twice, which made it the oldest
  // unbuilt item in the file.
  //
  // The rows run in Fitzgerald order like every other category — whole
  // utterances, then nouns, then the words that modify them — so a class holds
  // a contiguous block of rows and therefore of color.
  //
  // "before" and "after" are deliberately absent: they are on `numbers`, in
  // `in order`, where they mean sequence. Putting them here as well would give
  // one word two homes and neither would be the obvious one.
  // A board set that could say `eat`, `hurt`, `outside` and `tomorrow` could
  // not name a chair. The root board's `THINGS` band is a reserve, not a
  // board, so until this there was no category for objects at all (§4.42).
  //
  // Banded by where a thing is rather than by word class, because that is how
  // somebody looks for an object — and almost all of it is level 3, since an
  // objects board is naming vocabulary and level 2 is where a day becomes
  // sayable.
  'objects': [
    Band(
      name: 'around the house',
      shedRank: 1,
      items: [
        ...nouns(['chair', 'bed'], level: 2),
        // `door` and `window` are not here. Both are on `places` / `at home`,
        // and one word with two homes and neither obvious is worse than one
        // movement further away (§4.42).
        ...nouns(['table', 'light', 'floor', 'wall'], level: 3),
      ],
    ),

    Band(
      name: 'things I use',
      shedRank: 2,
      items: [
        ...nouns([
          'phone',
          'keys',
          'bag',
          'money',
          'glasses',
          'watch',
        ], level: 3),
        // Moved off the adult preset's `self care` row, where it was the one
        // thing among the medication and the wheelchair that is not health
        // vocabulary — and where every profile that is not an adult had no
        // word for it at all. Level 2 here, because a person whose chair or
        // talker is running flat needs the noun as much as the verb.
        ...nouns(['charger'], level: 2),
        // The board's own name, more or less: nobody looks for a "thing" by
        // asking for an object. It is the word for whatever is not on the
        // board, which is what a naming board most needs.
        ...nouns(['thing'], level: 2),
      ],
    ),

    Band(
      name: 'at school',
      shedRank: 3,
      items: [
        // `book` is on `play` / `toys`, where reading for pleasure is what it
        // is for, and stays there.
        ...nouns([
          'pencil',
          'pen',
          'paper',
          'scissors',
          'glue',
          'computer',
        ], level: 3),
      ],
    ),

    // The `clothes` band that used to close this board is now the `clothing`
    // board, which is where somebody looks for a sock. Six words wedged
    // between the school things and the caregiver reserve were as far as an
    // objects board could go, and getting dressed is a daily negotiation
    // rather than a corner of the naming vocabulary.
    Band(
      name: 'ours',
      shedRank: 9,
      reserveLines: 1,
      reserveRank: 0,
      items: const [],
    ),
  ],

  'time': [
    // The answers to "when" that come before anybody can name a day, and the
    // reason this board earns level 1 rather than waiting for level 3. A
    // person who can say "later" can decline something without refusing it.
    Band(
      name: 'when',
      shedRank: 0,
      items: [
        ...adverbs(['now', 'later', 'soon'], level: 1),
        // "again" is not here: it is on `play` at level 1, where repetition is
        // what it is for. Two homes and neither obvious is worse than one
        // movement further away.
        ...adverbs(['never', 'always', 'sometimes'], level: 3),
      ],
    ),

    // The three-word frame the rest of the board hangs off, and the one a
    // school day is actually organized around.
    Band(
      name: 'today',
      shedRank: 1,
      items: [
        ...nouns(['today'], level: 1),
        ...nouns(['tomorrow', 'yesterday'], level: 2),
      ],
    ),

    // The parts of a day, in the order they happen. "bedtime" closes the row
    // because it is the event rather than the hour, and it is the one most
    // often negotiated.
    // Named for the strip that runs above it (§4.19), which is why it is not
    // just "day": there is a `day` key two rows down, and a label that reads
    // as one of the keys under it teaches the wrong thing.
    Band(
      name: 'parts of the day',
      shedRank: 2,
      items: [
        ...nouns(['morning', 'afternoon', 'night'], level: 2),
        // "evening" and "bedtime" name the same stretch as "night" for most
        // households, so they are the two this row can afford to hold back.
        ...nouns(['evening', 'bedtime'], level: 3),
      ],
    ),

    // Level 3 entire. The days are what a person needs last and what a
    // caregiver models first, and seven of them fill a row on their own.
    Band(
      name: 'days of the week',
      shedRank: 4,
      items: nouns([
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ], level: 3),
    ),

    // Duration rather than position: how long a thing takes, and whether it
    // happened at the right moment. "time" is the word for the board itself
    // as well as a word in its own right — "what time is it".
    Band(
      name: 'how long',
      shedRank: 3,
      items: [
        ...nouns(['time'], level: 2),
        ...adjectives(['early', 'late'], level: 2),
        // Units. A person names the unit only once they are negotiating with
        // it — "five more minutes" — which is a level-3 conversation.
        ...nouns(['minute', 'hour', 'day', 'week'], level: 3),
        // Appended, so nothing on this row moves. The longer spans and the
        // shortest one: a board that stops at "week" cannot say when a
        // birthday is or how long a wait is, and "second" is the word for
        // "wait a second" — which is a whole sentence on its own.
        ...nouns(['month', 'year'], level: 3),
        ...nouns(['second'], level: 3),
        // The object, not a span. It is what somebody points at to ask when
        // something is, and it is on the wall of most of the rooms this board
        // gets used in.
        ...nouns(['calendar'], level: 3),
        // What turns a number into a time. The numbers board can already say
        // "three"; this is the word that makes it three o'clock rather than
        // three of something, and without it a person can count and cannot
        // tell anybody when.
        ...nouns(["o'clock"], level: 3),
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

  // Nothing on the board said what it was like outside. Weather is the
  // small talk a person is asked for most and can least improvise — "is it
  // raining?" is a closed question somebody either answers or is answered
  // for — and it is what decides whether going out is being offered at all.
  //
  // Adjectives lead, because what a person says is "it's sunny" rather than
  // "sun". The nouns are below them for the times the thing itself is the
  // subject.
  'weather': [
    Band(
      name: 'what it is like',
      shedRank: 0,
      items: [
        ...adjectives(['sunny', 'rainy'], level: 2),
        ...adjectives(['windy', 'cloudy'], level: 3),
        ...adjectives(['snowy', 'foggy', 'icy', 'stormy'], level: 3),
      ],
    ),

    // Deliberately not "hot" and "cold". Both are on `food` / `how it is`,
    // where they describe a meal about to be eaten or refused, and that is
    // the sense a person needs first and most urgently. A second pair here
    // would give each word two homes and neither would be the obvious one
    // (§4.42). These four say the same thing about a day without taking the
    // meal's words away from it.
    Band(
      name: 'how it feels',
      shedRank: 1,
      items: [
        ...adjectives(['warm', 'cool'], level: 2),
        ...adjectives(['freezing', 'boiling'], level: 3),
        ...adjectives(['wet', 'dry'], level: 2),
      ],
    ),

    Band(
      name: 'in the sky',
      shedRank: 2,
      items: [
        ...nouns(['sun', 'rain'], level: 2),
        ...nouns(['snow', 'wind', 'cloud'], level: 3),
        ...nouns(['sky', 'storm'], level: 3),
        // The board's own name, and what all of it answers: "what is the
        // weather" is the question, and until this the board could answer it
        // without being able to ask it.
        ...nouns(['weather'], level: 2),
      ],
    ),

    // What the weather is usually being asked about: whether to go out, and
    // what has to be found before anybody can.
    Band(
      name: 'what to take',
      shedRank: 3,
      items: [
        ...nouns(['umbrella'], level: 2),
        ...nouns(['sunglasses', 'sunscreen'], level: 3),
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

  // Getting dressed, which is a daily negotiation and was six nouns in a
  // corner of `objects`. Those six are here unchanged and in the same order,
  // and the rest of the board is what they could not say: which garment,
  // whether it is going on or coming off, and what is wrong with it.
  //
  // Rows run in Fitzgerald order like every other mixed-class board — whole
  // utterances and verbs, then the nouns, then what modifies them — so a
  // class holds a contiguous block of rows and therefore of color. The first
  // draft led with the clothes, which put an orange row above the verbs and
  // two more below them; the golden of this board is what showed it.
  //
  // The verbs `dress` and `wear` are not here. Both are on `doing` /
  // `caring`, with the rest of self-care, and one word with two homes and
  // neither obvious is worse than one movement further away (§4.42).
  //
  // Where British and American English differ — sweater and jumper, pyjamas
  // and pajamas, what "pants" means — one had to be picked. These are near
  // the top of the list a caregiver renames, and renaming a label never moves
  // the key it is on.
  'clothing': [
    // On and off, as whole utterances rather than verbs. "put" and "on" are
    // two keys and two endings away from each other, and a verb key spelled
    // "put on" would take the board's suffixes and produce "put oning".
    Band(
      name: 'getting dressed',
      shedRank: 1,
      items: [
        ...phrases(['put it on', 'take it off'], level: 1),
        ...verbs(['change'], level: 2),
        ...verbs(['zip', 'button'], level: 3),
      ],
    ),

    Band(
      name: 'every day',
      shedRank: 0,
      items: [
        ...nouns(['shoes', 'coat'], level: 2),
        ...nouns(['shirt', 'pants', 'socks', 'hat'], level: 3),
        // The board's own name. A garment nobody has named yet is "clothes",
        // and so is the whole pile of them.
        ...nouns(['clothes'], level: 2),
      ],
    ),

    Band(
      name: 'more to wear',
      shedRank: 3,
      items: [
        ...nouns(['jacket', 'sweater'], level: 3),
        ...nouns(['dress', 'skirt', 'shorts'], level: 3),
        ...nouns(['boots', 'gloves', 'scarf'], level: 3),
      ],
    ),

    Band(
      name: 'underneath',
      shedRank: 4,
      items: [
        ...nouns(['underwear', 'pyjamas'], level: 2),
        ...nouns(['swimsuit'], level: 3),
      ],
    ),

    // What is wrong with it, which is the half of dressing a board usually
    // forgets and the half a person most needs. Without these the only thing
    // sayable about an unbearable seam is "no", and a refusal nobody can
    // explain gets treated as a mood.
    Band(
      name: 'how it feels on',
      shedRank: 2,
      items: [
        // "itchy" is not here: it is on `health`, with the other things a
        // body reports. It was the same adjective on both.
        ...adjectives(['tight'], level: 2),
        ...adjectives(['loose', 'scratchy'], level: 3),
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

  // Basics, which is what was asked for. An animals board is naming
  // vocabulary, so almost all of it is level 3 — with the exception of the
  // two a household actually contains and talks to, which are level 2.
  //
  // Banded by where the animal is met rather than by anything taxonomic: a
  // child looking for "cow" is thinking of a farm, not of hooves.
  'animals': [
    Band(
      name: 'pets',
      shedRank: 0,
      items: [
        ...nouns(['dog', 'cat'], level: 2),
        ...nouns(['fish', 'bird', 'rabbit'], level: 3),
        // The board's own name, and the word for the one at the window that
        // is not on the board.
        ...nouns(['animal'], level: 2),
      ],
    ),

    Band(
      name: 'on the farm',
      shedRank: 1,
      items: [
        ...nouns(['horse', 'cow', 'sheep'], level: 3),
        ...nouns(['pig', 'chicken', 'duck'], level: 3),
      ],
    ),

    Band(
      name: 'wild',
      shedRank: 2,
      items: [
        ...nouns(['lion', 'bear', 'elephant'], level: 3),
        ...nouns(['monkey', 'tiger', 'snake'], level: 3),
      ],
    ),

    Band(
      name: 'small ones',
      shedRank: 3,
      items: [
        ...nouns(['bug', 'spider', 'bee', 'butterfly'], level: 3),
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

  // How big, how far, how fast, how heavy. Nothing on the board answered any
  // of them: "big" and "small" are the two adjectives a child is asked for
  // most and neither had a location anywhere, and `far` and `near` were two
  // adjectives on the end of a row of adverbs on `places`.
  //
  // They are here rather than on the boards they describe because a
  // measurement is not about one subject — the same "big" is said about a
  // dog, a queue, a portion and a room, and a copy on each of those boards is
  // one word with four homes and no obvious one (§4.42).
  //
  // Opposites sit side by side and a band owns a row, so each row is one
  // question and its two answers: a pair learned as a pair rather than as two
  // positions that happen to mean opposite things.
  //
  // Nouns first and the adjectives after them, which is the Fitzgerald order
  // every other mixed board runs in, so a class holds a contiguous block of
  // rows and therefore of color.
  'measurement': [
    Band(
      name: 'measuring',
      shedRank: 4,
      items: [
        // What a person asks about before they have a word for the answer —
        // "what size", "the wrong size" — and the board's own name behind it.
        ...nouns(['size'], level: 2),
        ...nouns(['measurement'], level: 3),
      ],
    ),

    Band(
      name: 'how big',
      shedRank: 0,
      items: [
        // Level 1, and the only level-1 pair on this board. A child is asked
        // to choose between a big one and a small one before they are asked
        // anything else here.
        ...adjectives(['big', 'small'], level: 1),
        ...adjectives(['long', 'short'], level: 2),
        ...adjectives(['tall', 'wide', 'thin'], level: 3),
        // Not a second "big". It is the word on a label, a menu and a form —
        // small, medium, large — which is the one place a person is asked to
        // pick a size in words rather than by pointing, and the one "big" does
        // not answer.
        //
        // Appended, and free on every grid but the smallest. This row is
        // exactly seven words, which is exactly a line at 4x8, so there it
        // opens one and moves `size`, `measurement` and the heavy/light row
        // down a row on page two — six level-2 words, one row, on the
        // narrowest board the app builds. Taken rather than worked around:
        // the alternative is the row of nouns above, where an adjective would
        // draw in the wrong color.
        ...adjectives(['large'], level: 3),
      ],
    ),

    Band(
      name: 'how far',
      shedRank: 1,
      items: [
        // Moved here from `places` / `where`. Level 2 rather than the 3 they
        // drew at there: "too far" is a refusal a person needs long before
        // they need to name a library.
        ...adjectives(['far', 'near'], level: 2),
        ...adjectives(['close', 'deep'], level: 3),
        // The same axis at nought distance, and the pair this board was built
        // for: every row on it is two words that are opposites. "together" is
        // wanted far more often than it is described — "sit together", "play
        // together" — and the root board has no column left to give it, so it
        // is one movement away rather than none.
        ...adjectives(['together', 'separate'], level: 2),
      ],
    ),

    Band(
      name: 'how fast',
      shedRank: 2,
      items: [
        // "too fast" and "too slow" are whole utterances on `feelings`, where
        // they are complaints about what is being done to somebody. These are
        // the adjectives, which describe anything at all — and the pair a
        // person needs to ask for a change of pace rather than to protest one.
        ...adjectives(['fast', 'slow'], level: 2),
      ],
    ),

    Band(
      name: 'how heavy',
      shedRank: 3,
      items: [
        // "light" is also on `objects` / `around the house`, where it is the
        // one on the ceiling. Two buttons, one label, two meanings — which is
        // what the word does in English, and separating them by board and by
        // region is how a board carries a homograph, exactly as `right` is
        // carried on the root board and on `feelings`. Nothing keys behavior
        // off the label, so the two do not interfere.
        ...adjectives(['heavy', 'light'], level: 2),
        ...adjectives(['full', 'empty'], level: 2),
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

  // Naming a color is how a person chooses between two things that are
  // otherwise the same — which shirt, which cup, which crayon — and it is the
  // answer to the question a room asks a child more than almost any other.
  //
  // Adjectives throughout, which is what they are: they describe the noun
  // somebody is pointing at, and coding them as anything else would put them
  // in a different color block from every other describing word on the board.
  'colors': [
    Band(
      name: 'colors',
      shedRank: 4,
      items: [
        // The board's own name as a word, like every other category carries.
        // It is also the question — "what color?" — and the way to ask for one
        // when the particular color is not the point.
        ...nouns(['color'], level: 3),
        // A noun on a board of adjectives, and it belongs on this row for that
        // reason rather than among the hues: it is a thing somebody points at
        // and names, not a way of describing something else. It is also the
        // one word here a person is most likely to want and least likely to
        // be able to build out of the others.
        ...nouns(['rainbow'], level: 3),
      ],
    ),

    // The four a child is taught first and asked about most.
    Band(
      name: 'first colors',
      shedRank: 0,
      items: adjectives(['red', 'blue', 'yellow', 'green'], level: 1),
    ),

    Band(
      name: 'more colors',
      shedRank: 1,
      items: [
        ...adjectives(['orange', 'purple', 'pink'], level: 3),
        ...adjectives(['brown'], level: 3),
      ],
    ),

    // Kept apart from the hues rather than mixed in with them, because this is
    // the row somebody reaches for when they mean light or dark rather than
    // when they mean a color.
    Band(
      name: 'light and dark',
      shedRank: 2,
      items: [
        ...adjectives(['black', 'white'], level: 3),
        ...adjectives(['gray'], level: 3),
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

  // The outdoors as things you can name, which is what a walk, a window and
  // most of a school year are made of.
  //
  // Deliberately not the weather and not the animals: both have boards of
  // their own, and a word that appeared on two of them would be two things to
  // learn about one word. So there is no `sun`, `rain`, `cloud` or `sky` here
  // — they are on `weather`, one movement away — and no `bug` or `bird`, which
  // are on `animals`.
  'nature': [
    Band(
      name: 'nature',
      shedRank: 4,
      items: [
        // The board's own name as a word, like every other category carries.
        ...nouns(['nature'], level: 3),
      ],
    ),

    // What is growing, which is the half of this a person meets every day.
    Band(
      name: 'growing',
      shedRank: 0,
      items: [
        ...nouns(['tree', 'flower'], level: 1),
        ...nouns(['plant', 'grass'], level: 3),
        ...nouns(['leaf'], level: 3),
      ],
    ),

    // What is underfoot, and what it is made of.
    Band(
      name: 'ground',
      shedRank: 1,
      items: [
        ...nouns(['rock', 'dirt'], level: 3),
        // No "sand": it is on `play` / `outdoor`, where it is the thing a
        // child digs in. One word, one location.
        ...nouns(['mud'], level: 3),
      ],
    ),

    // Water, largest first, because the one a person is most likely to be
    // taken to is the one they are most likely to want a word for.
    Band(
      name: 'water',
      shedRank: 2,
      items: [
        ...nouns(['ocean', 'lake'], level: 3),
        ...nouns(['river'], level: 3),
      ],
    ),

    // What is too big or too far to touch. "sun" is not here and "moon" is:
    // the sun belongs to the weather, which is the board that answers what
    // today is like, and these two answer what is up there at night.
    Band(
      name: 'up there',
      shedRank: 3,
      items: [
        ...nouns(['moon', 'star'], level: 3),
        ...nouns(['mountain', 'forest'], level: 3),
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

  // The words a school day is full of and no board carried: every early
  // worksheet, every sorting task, every "find me the red circle" asks for one
  // of these, and a person who has the color and not the shape can answer half
  // of it.
  //
  // Laid out like `colors`, which is the board it is the pair to: the name of
  // the class first, the ones taught first next, then the rest, then the words
  // for describing a thing that is not one of the named shapes.
  //
  // No "star" and no "heart". Both are already words on other boards — `star`
  // on `nature` and `heart` on `health` — and a second copy is a second thing
  // to learn about one word.
  'shapes': [
    Band(
      name: 'shapes',
      shedRank: 4,
      items: [
        // The board's own name, and the question: "what shape?" — which is how
        // somebody asks when the particular shape is not the point.
        ...nouns(['shape'], level: 2),
      ],
    ),

    // The three a child is taught first and asked about most.
    Band(
      name: 'first shapes',
      shedRank: 0,
      items: nouns(['circle', 'square', 'triangle'], level: 2),
    ),

    Band(
      name: 'more shapes',
      shedRank: 1,
      items: nouns(['rectangle', 'oval', 'diamond'], level: 3),
    ),

    // Adjectives, and kept off the rows above for that reason: these describe
    // a thing that is not one of the named shapes, which is most things.
    //
    // Not named 'describing': that name is already spoken as "yes, no and how
    // it is" on the root board, and the map that does it is keyed by band name
    // for the whole app.
    Band(
      name: 'what it looks like',
      shedRank: 2,
      items: adjectives(['round', 'flat', 'straight', 'curved'], level: 3),
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
