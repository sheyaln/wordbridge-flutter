import 'speech_engine.dart';
import 'tone.dart';

/// A run of voices under one heading.
///
/// A null [heading] means the voices are shown plain, with no heading above
/// them at all.
typedef VoiceGroup = ({String? heading, List<VoiceOption> voices});

/// Puts a profile's voice settings onto the engine.
///
/// Applied when a session opens and again whenever a caregiver changes
/// something, so what is heard always matches what the settings screen shows.
///
/// Nothing here is allowed to throw. A device whose stored voice was removed
/// by an OS update, or whose engine refuses a rate, must still speak — with
/// the default voice if it comes to that. Silence is the one outcome that is
/// not survivable.
class VoiceSetup {
  const VoiceSetup(this.engine);

  final SpeechEngine engine;

  Future<void> apply({
    String? voiceName,
    String? voiceLocale,
    String? voiceIdentifier,
    required double rate,
    required double pitch,
    required double volume,
    required Tone tone,
  }) async {
    if (voiceName != null && voiceLocale != null) {
      try {
        await engine.useVoice((
          name: voiceName,
          locale: voiceLocale,
          identifier: voiceIdentifier,
          gender: null,
          quality: null,
          isNovelty: false,
          requiresNetwork: false,
        ));
      } catch (_) {
        // The stored voice is gone. The device default is still a voice.
      }
    }

    final p = applyTone(tone, rate: rate, pitch: pitch, volume: volume);

    try {
      await engine.setRate(p.rate);
      await engine.setPitch(p.pitch);
      await engine.setVolume(p.volume);
    } catch (_) {
      // Whatever the engine accepted, it keeps. A rejected dial is a voice
      // that sounds wrong, which is recoverable; an exception here would be a
      // screen that never finishes loading, which is not.
    }
  }

  /// The voices worth offering, best first.
  ///
  /// Three filters, each for its own reason:
  ///
  /// Voices that **need a connection** are excluded rather than shown and
  /// warned about. This device has to work in a car, a playground and a
  /// hospital corridor, and a voice that works at home and not in an ambulance
  /// is not a voice — it is a trap with a nice accent.
  ///
  /// Voices for **another language** are excluded, because a board in English
  /// read by a German voice is not a choice anybody wants.
  ///
  /// **Joke voices** are excluded unless asked for. A platform can list a
  /// couple of dozen of them, which on a screen where somebody is choosing how
  /// their child will sound for the next several years is mostly a way to make
  /// the real options hard to find. They stay available, behind a switch,
  /// because some people want one — and because it is not this app's place to
  /// decide that a person may not sound like a robot if they would like to.
  Future<List<VoiceOption>> usableVoices({
    String? locale,
    bool includeNovelty = false,
  }) async {
    List<VoiceOption> all;
    try {
      all = await engine.voices();
    } catch (_) {
      return const [];
    }

    final language = locale?.split(RegExp('[-_]')).first.toLowerCase();

    final usable = [
      for (final voice in all)
        if (!voice.requiresNetwork &&
            (includeNovelty || !voice.isNovelty) &&
            (language == null ||
                voice.locale.toLowerCase().startsWith(language)))
          voice,
    ];

    // Better-sounding voices first, then by name. A device carrying both a
    // compact and an enhanced "Daniel" should offer the good one at the top
    // rather than leaving them adjacent and indistinguishable.
    usable.sort((a, b) {
      final quality = _qualityRank(b.quality)
          .compareTo(_qualityRank(a.quality));
      if (quality != 0) return quality;
      final name = a.name.compareTo(b.name);
      return name != 0 ? name : a.locale.compareTo(b.locale);
    });

    return usable;
  }

  static int _qualityRank(String? quality) => switch (quality?.toLowerCase()) {
    'premium' => 3,
    'enhanced' => 2,
    'default' => 1,
    _ => 0,
  };

  /// How many joke voices are being kept out of the list.
  ///
  /// Shown next to the switch, so it says what turning it on would do rather
  /// than leaving somebody to toggle it and see.
  Future<int> noveltyCount({String? locale}) async {
    final withOut = await usableVoices(locale: locale);
    final withAll = await usableVoices(locale: locale, includeNovelty: true);
    return withAll.length - withOut.length;
  }

  static const femaleHeading = 'Female';
  static const maleHeading = 'Male';
  static const unknownGenderHeading = 'Gender not reported';

  /// Splits a list into female, male and unknown, keeping the order given.
  ///
  /// Only iOS reports a gender, and only for some voices; Android voice maps
  /// carry no gender key at all. Where fewer than two groups would result the
  /// list comes back as one unheaded run, because a screen listing every voice
  /// under a single "Male" heading tells a caregiver less than no heading does
  /// and implies the rest are hidden somewhere.
  static List<VoiceGroup> groupByGender(List<VoiceOption> voices) {
    if (voices.isEmpty) return const [];

    final female = <VoiceOption>[];
    final male = <VoiceOption>[];
    final unknown = <VoiceOption>[];

    for (final voice in voices) {
      switch (_gender(voice.gender)) {
        case femaleHeading:
          female.add(voice);
        case maleHeading:
          male.add(voice);
        case _:
          unknown.add(voice);
      }
    }

    final groups = [
      if (female.isNotEmpty) (heading: femaleHeading, voices: female),
      if (male.isNotEmpty) (heading: maleHeading, voices: male),
      if (unknown.isNotEmpty) (heading: unknownGenderHeading, voices: unknown),
    ];

    if (groups.length < 2) return [(heading: null, voices: voices)];
    return groups;
  }

  /// Whether the device labeled any of these voices male or female.
  ///
  /// False on Android, and on an iOS build that reports "unspecified"
  /// throughout. The screen says so rather than leaving a caregiver looking for
  /// a grouping that is not coming.
  static bool reportsGender(Iterable<VoiceOption> voices) =>
      voices.any((voice) => _gender(voice.gender) != null);

  /// iOS spells this from `AVSpeechSynthesisVoice.gender.stringValue` and the
  /// casing is not contractual; anything other than the two known words is
  /// treated as unsaid rather than shown raw.
  static String? _gender(String? gender) =>
      switch (gender?.trim().toLowerCase()) {
        'female' => femaleHeading,
        'male' => maleHeading,
        _ => null,
      };

  /// What selection is keyed on.
  ///
  /// The platform identifier where there is one: a device can carry two voices
  /// called "Daniel" at different qualities, and keying on the name alone makes
  /// them the same row.
  static String voiceKey(VoiceOption voice) =>
      voice.identifier ?? '${voice.name}|${voice.locale}';

  /// Finds the stored voice in a list, or null if it is no longer there.
  ///
  /// The identifier decides it where both sides have one. The name is tried
  /// after, so a selection stored before the device reported identifiers — or
  /// one whose identifier an OS update changed — still shows as chosen instead
  /// of silently reading as "whatever the device uses".
  static VoiceOption? storedVoice(
    List<VoiceOption> voices, {
    String? name,
    String? locale,
    String? identifier,
  }) {
    if (identifier != null) {
      for (final voice in voices) {
        if (voice.identifier == identifier) return voice;
      }
    }
    if (name == null) return null;
    for (final voice in voices) {
      if (voice.name == name && voice.locale == locale) return voice;
    }
    for (final voice in voices) {
      if (voice.name == name) return voice;
    }
    return null;
  }

  /// The word for a voice's quality, or null where there is nothing to say.
  ///
  /// Only the grades that mean "this one sounds better" are named. "default"
  /// and anything unrecognized get no marker, because a label nobody can act on
  /// is just noise on the row.
  static String? qualityLabel(String? quality) =>
      switch (quality?.trim().toLowerCase()) {
        'premium' => 'Premium',
        'enhanced' => 'Enhanced',
        _ => null,
      };
}
