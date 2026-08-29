import 'package:flutter_tts/flutter_tts.dart';

/// Speech output, behind an interface.
///
/// The concrete engine is a single-maintainer package. Nothing outside this
/// file may talk to it directly, so replacing it — or adding a bundled neural
/// voice for locales the platform serves badly — stays a swap rather than a
/// refactor.
abstract interface class SpeechEngine {
  Future<void> init();
  Future<void> speak(String text);
  Future<void> stop();
  Future<List<VoiceOption>> voices();
  Future<void> useVoice(VoiceOption voice);

  /// Speaking speed, where **1.0 is this engine's ordinary speaking rate**,
  /// 0.5 is half that and 2.0 is twice.
  ///
  /// Stated in those terms rather than the engine's own numbers because every
  /// engine scales differently, and a caller that has to know which one it is
  /// talking to will eventually get it wrong in the direction of unusably
  /// fast. Translating is this file's job.
  Future<void> setRate(double rate);

  /// 1.0 is the voice's own pitch.
  Future<void> setPitch(double pitch);

  /// 0.0 to 1.0, as a share of the device's volume.
  Future<void> setVolume(double volume);
}

/// One voice the device can speak with.
///
/// [identifier] is the platform's own handle for it and is what selection is
/// keyed on where there is one: a device can carry two voices called "Daniel"
/// at different qualities, and a name alone picks whichever it finds first.
///
/// [isNovelty] marks the joke voices — robots, singing, cartoon characters.
/// They are real voices the platform offers, and for most people using this
/// app they are noise in a list they need to choose from carefully.
typedef VoiceOption = ({
  String name,
  String locale,
  String? identifier,
  String? gender,
  String? quality,
  bool isNovelty,
  bool requiresNetwork,
});

/// Works around synthesisers announcing a lone capital letter by name.
///
/// Both iOS and Android read a single uppercase character as its letter name
/// with a prefix — "I" becomes "capital I" — because in isolation it looks
/// like a letter rather than a word. Lowercasing yields the letter's plain
/// name, which for "I" is exactly the correct pronunciation of the word.
///
/// Only whole-utterance single letters are touched. Inside a sentence the
/// synthesiser already has enough context ("I want more" reads correctly),
/// and a spelling keyboard genuinely wants letter names, so it must not be
/// routed through here.
String normaliseForSpeech(String text) {
  final trimmed = text.trim();
  if (trimmed.length == 1 && RegExp(r'^[A-Z]$').hasMatch(trimmed)) {
    return trimmed.toLowerCase();
  }
  return trimmed;
}

class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine();

  final _tts = FlutterTts();

  @override
  Future<void> init() async {
    // Without this an iPad with the ringer switch off is silent, which for an
    // AAC device means a user who cannot speak. Not optional.
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
      IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      IosTextToSpeechAudioCategoryOptions.duckOthers,
    ], IosTextToSpeechAudioMode.defaultMode);

    await _tts.awaitSpeakCompletion(true);
    await _tts.setVolume(1.0);
  }

  @override
  Future<void> speak(String text) async {
    final spoken = normaliseForSpeech(text);
    if (spoken.isEmpty) return;
    // Newest selection wins. A user tapping quickly wants the current word,
    // not a queue draining words they have moved on from.
    await _tts.stop();
    await _tts.speak(spoken);
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<List<VoiceOption>> voices() async {
    final raw = await _tts.getVoices as List<dynamic>?;
    if (raw == null) return const [];

    return raw.whereType<Map>().map((v) {
      final features = (v['features'] as String?) ?? '';
      final identifier = v['identifier'] as String?;

      return (
        name: (v['name'] as String?) ?? 'unknown',
        locale: (v['locale'] as String?) ?? '',
        identifier: identifier,
        gender: v['gender'] as String?,
        quality: v['quality'] as String?,
        isNovelty: isNoveltyIdentifier(identifier),
        // Android reports networkTts in its feature string. A voice that needs
        // a connection is unusable on a device that must work anywhere.
        requiresNetwork: features.contains('networkTts'),
      );
    }).toList();
  }

  /// Whether this is one of the platform's joke voices.
  ///
  /// Apple files them under a different identifier prefix from the speaking
  /// voices — `com.apple.speech.synthesis.voice.Bells` against
  /// `com.apple.voice.compact.en-GB.Daniel` — which is a far steadier test
  /// than a list of names that changes with every OS release. Android has no
  /// such voices, and reports no identifier, so nothing is caught there.
  static bool isNoveltyIdentifier(String? identifier) =>
      identifier != null &&
      identifier.startsWith('com.apple.speech.synthesis.voice.');

  @override
  Future<void> useVoice(VoiceOption voice) => _tts.setVoice({
    'name': voice.name,
    'locale': voice.locale,
    // The plugin keys on the identifier when it is given one, which is the
    // only way to tell two voices of the same name apart.
    if (voice.identifier != null) 'identifier': voice.identifier!,
  });

  /// Turns "1.0 means normal" into the number the plugin wants.
  ///
  /// The plugin's own scale puts ordinary speech at **0.5** on both platforms:
  /// iOS passes the number straight to `AVSpeechUtterance.rate`, whose default
  /// is 0.5 and whose maximum is 1.0, and the Android side doubles it before
  /// handing it to a synthesiser whose normal is 1.0. Sending 1.0 for "normal
  /// speed" therefore asks both of them for double, which is too fast to make
  /// any of the words out.
  static double engineRate(double rate) => (rate * 0.5).clamp(0.0, 1.0);

  @override
  Future<void> setRate(double rate) => _tts.setSpeechRate(engineRate(rate));

  @override
  Future<void> setPitch(double pitch) => _tts.setPitch(pitch);

  @override
  Future<void> setVolume(double volume) => _tts.setVolume(volume);
}
