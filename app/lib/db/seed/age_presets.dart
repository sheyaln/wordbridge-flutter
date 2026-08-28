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
final swearingBand = Band<SeedWord>(
  name: 'strong words',
  shedRank: 8,
  items: adjectives([
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
        items: nouns([
          'phone',
          'headphones',
          'games',
          'online',
          'video call',
          'playlist',
        ], level: 1),
      ),
    ],
    'feelings': [
      Band(
        name: 'teenage',
        shedRank: 1,
        items: [
          ...adjectives([
            'annoyed',
            'stressed',
            'embarrassed',
            'awkward',
          ], level: 1),
          // Being able to end a conversation is as much a part of speech as
          // starting one.
          ...nouns(['whatever', 'leave it', 'not now'], level: 1),
        ],
      ),
    ],
    'places': [
      Band(
        name: 'out',
        shedRank: 3,
        items: nouns(['college', 'town', 'party', 'gig', 'bus stop'], level: 1),
      ),
    ],
    'people': [
      Band(
        name: 'mine',
        shedRank: 3,
        items: nouns(['mate', 'group', 'crush', 'support worker'], level: 1),
      ),
    ],
  },

  AgeBand.adult: {
    'places': [
      Band(
        name: 'business',
        shedRank: 2,
        items: nouns([
          'work',
          'appointment',
          'bank',
          'pharmacy',
          'taxi',
          'meeting',
        ], level: 1),
      ),
    ],
    'body': [
      // An adult who cannot say "medication" or name a body part to a doctor
      // is dependent on someone else's guess about their own body.
      Band(
        name: 'self care',
        shedRank: 0,
        items: nouns([
          'pain',
          'medication',
          'toilet',
          'shower',
          'period',
          'dentist',
        ], level: 1),
      ),
    ],
    'people': [
      Band(
        name: 'mine',
        shedRank: 2,
        items: nouns([
          'partner',
          'colleague',
          'support worker',
          'landlord',
          'boss',
        ], level: 1),
      ),
    ],
    'feelings': [
      Band(
        name: 'adult',
        shedRank: 1,
        items: [
          // "patronised" earns its location: being talked down to is the most
          // frequently reported experience of adult AAC users, and having no
          // word for it means having to endure it silently.
          ...adjectives([
            'frustrated',
            'patronised',
            'exhausted',
            'fine',
          ], level: 1),
          ...nouns(['not now', 'I decide', 'ask me'], level: 1),
        ],
      ),
    ],
  },
};
