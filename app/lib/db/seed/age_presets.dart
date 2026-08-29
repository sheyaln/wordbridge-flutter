/// Which starting vocabulary a profile gets, from the birthday it was given.
///
/// The core board does not change with age — "I", "want" and "not" are as
/// useful at thirty as at three, and re-teaching a motor plan at a birthday
/// would be absurd. What changes is the fringe: the categories gain the words
/// that particular life actually needs.
///
/// Older presets include vocabulary that child presets do not, including
/// profanity. That is not novelty. Autistic adults consistently report that
/// commercial AAC feels infantilising, and censoring an adult's vocabulary
/// removes agency from someone who cannot easily route around the omission —
/// a speaking adult can swear whenever they like, and nobody vets their word
/// list. Every one of these words is disable-able, and disabling one hides it
/// in place rather than freeing its location, so turning it back on later puts
/// it exactly where it was.
library;

import 'band_layout.dart';
import 'core_vocabulary.dart';

enum AgeBand {
  earlyYears('Under 6', 'Core words first, with the rest ready to reveal.'),
  child('6 to 12', 'The full starter vocabulary.'),
  teen('13 to 17', 'Adds the words a teenager needs and adults forget.'),
  adult('18 and over', 'Adds adult vocabulary, appointments and self-care.');

  const AgeBand(this.label, this.description);

  final String label;
  final String description;

  /// Whether this preset receives strong language at all. Below it, the toggle
  /// does not appear; at or above it, it does — defaulted per band.
  bool get canSwear => this == teen || this == adult;

  /// On for adults, off for teenagers, absent for children. A caregiver can
  /// change it either way; this is only where it starts.
  bool get swearsByDefault => this == adult;

  /// Which vocabulary levels start visible.
  ///
  /// Everything above is seeded and hidden, occupying its location from day
  /// one. Raising this later reveals words exactly where they have always
  /// been, which is the whole point of the levels.
  int get startingLevel => this == earlyYears ? 1 : 2;

  /// Bands appended to a category board for this preset.
  ///
  /// Appended, never inserted: the shipped words keep their order, so two
  /// profiles on the same grid put "happy" in the same place whatever their
  /// ages.
  ///
  /// These carry levels on the same rule as the shipped bands, so a teenager
  /// or an adult whose board has been simplified back to level 1 keeps the
  /// words their age needs most rather than losing the lot.
  List<Band<SeedWord>> extrasFor(String category) => [
    ...?_extras[this]?[category],
  ];

  /// Works out the band from a birthday. A profile with no birthday recorded
  /// gets [child], the preset that assumes least.
  static AgeBand forBirthDate(DateTime? birthDate, {DateTime? now}) {
    if (birthDate == null) return AgeBand.child;

    final today = now ?? DateTime.now();
    var years = today.year - birthDate.year;
    final hadBirthday =
        today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!hadBirthday) years -= 1;

    if (years < 0) return AgeBand.child;
    if (years < 6) return AgeBand.earlyYears;
    if (years < 13) return AgeBand.child;
    if (years < 18) return AgeBand.teen;
    return AgeBand.adult;
  }
}

/// Strong language, kept in one band so it can be hidden and revealed as a
/// unit. Seeded for the presets that receive it whether or not it is switched
/// on, because hiding holds the locations and switching it on later must not
/// move anything else.
///
/// Level 2, matching the level every preset that receives this band starts on,
/// so the profanity toggle is the only gate anybody meets. Level 1 would put it
/// ahead of the whole level-2 fringe on a small grid, and a board that pages
/// "right" and "wrong" off to keep "bloody" is not the trade anyone asked for.
final swearingBand = Band<SeedWord>(
  name: 'strong words',
  shedRank: 8,
  // Interjections, not adjectives. Coded as whole utterances, the board stops
  // offering "shit's" and "damn is".
  items: phrases([
    'damn',
    'crap',
    'bloody',
    'piss off',
    'shit',
    'bastard',
    'fuck',
  ], level: 2),
);

final _extras = <AgeBand, Map<String, List<Band<SeedWord>>>>{
  AgeBand.teen: {
    'play': [
      Band(
        name: 'screen',
        shedRank: 2,
        startsLine: false,
        items: [
          ...nouns(['phone', 'headphones'], level: 1),
          ...nouns(['games', 'online', 'video call'], level: 2),
          ...nouns(['playlist'], level: 3),
          ...nouns(['text'], level: 2),
        ],
      ),
    ],
    'feelings': [
      // Being able to end a conversation is as much a part of speech as
      // starting one. "private" names a boundary a teenager has and a board
      // read by adults gives away.
      Band(
        name: 'teen saying',
        shedRank: 1,
        startsLine: false,
        items: [
          // Tone rather than need, and the one here a level-1 board can do
          // without.
          ...phrases(['whatever'], level: 2),
          ...phrases([
            'leave it',
            'not now',
            'private',
            'I decide',
            'ask me',
          ], level: 1),
        ],
      ),
      Band(
        name: 'teenage',
        shedRank: 1,
        startsLine: false,
        items: [
          ...adjectives(['annoyed', 'stressed', 'embarrassed'], level: 2),
          ...adjectives(['awkward'], level: 3),
        ],
      ),
    ],
    'places': [
      // Named apart from the shipped bands on this board. The layout engine
      // keys bands by name, so a collision merges two bands and the words of
      // one of them are never placed.
      Band(
        name: 'teen out',
        shedRank: 3,
        startsLine: false,
        items: [
          ...nouns(['college', 'town'], level: 2),
          ...nouns(['party', 'gig'], level: 3),
          ...nouns(['bus stop'], level: 2),
          // Being unable to say "money" is being unable to buy anything alone.
          ...nouns(['money'], level: 1),
        ],
      ),
    ],
    'people': [
      Band(
        name: 'teen mine',
        shedRank: 3,
        startsLine: false,
        items: [
          ...nouns(['mate'], level: 2),
          ...nouns(['group', 'crush'], level: 3),
          ...nouns(['support worker'], level: 1),
        ],
      ),
    ],
  },

  AgeBand.adult: {
    'places': [
      // "work" is not repeated here: it already has a permanent location in
      // the shipped places band, and one word on one board has one location.
      Band(
        name: 'business',
        shedRank: 2,
        startsLine: false,
        items: [
          ...nouns(['appointment', 'bank', 'pharmacy', 'taxi'], level: 2),
          ...nouns(['meeting'], level: 3),
          ...nouns(['money', 'how much'], level: 1),
          ...nouns(['pay'], level: 2),
        ],
      ),
    ],
    'body': [
      // An adult who cannot say "medication" or name a body part to a doctor
      // is dependent on someone else's guess about their own body.
      Band(
        name: 'self care',
        shedRank: 0,
        startsLine: false,
        items: [
          ...nouns(['pain', 'medication'], level: 1),
          ...nouns([
            'shower',
            'period',
            'dentist',
            'wheelchair',
            'glasses',
            'charger',
          ], level: 2),
        ],
      ),
    ],
    'people': [
      Band(
        name: 'adult mine',
        shedRank: 2,
        startsLine: false,
        items: [
          ...nouns(['partner', 'colleague'], level: 2),
          // The person an adult most often needs to name, and the one most
          // often talked to instead of them.
          ...nouns(['support worker'], level: 1),
          ...nouns(['landlord'], level: 3),
          ...nouns(['boss'], level: 2),
        ],
      ),
    ],
    'feelings': [
      // Being spoken about in the third person while present is the most
      // reported experience of adult AAC users, and a board that names the
      // feeling but cannot interrupt it is only half the vocabulary.
      Band(
        name: 'adult saying',
        shedRank: 1,
        startsLine: false,
        items: phrases([
          'not now',
          'I decide',
          'ask me',
          'talk to me',
          'I disagree',
          'I need time',
        ], level: 1),
      ),
      Band(
        name: 'adult',
        shedRank: 1,
        startsLine: false,
        items: [
          ...adjectives(['frustrated', 'patronised', 'exhausted'], level: 2),
          // Answers to a direct question, alongside yes and no.
          ...adjectives(['fine', 'maybe'], level: 1),
        ],
      ),
    ],
  },
};
