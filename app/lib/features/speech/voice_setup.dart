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
  /// Voices that need a connection are excluded rather than shown and warned
  /// about. This device has to work in a car, a playground and a hospital
  /// corridor, and a voice that works at home and not in an ambulance is not
  /// a voice — it is a trap with a nice accent.
  Future<List<VoiceOption>> usableVoices({String? locale}) async {
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
            (language == null ||
                voice.locale.toLowerCase().startsWith(language)))
          voice,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return usable;
  }
}
