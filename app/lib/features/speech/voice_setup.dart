import 'speech_engine.dart';
import 'tone.dart';

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
      final quality = _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
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
}
