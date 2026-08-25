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
  Future<void> setRate(double rate);
  Future<void> setPitch(double pitch);
  Future<void> setVolume(double volume);
}

typedef VoiceOption = ({String name, String locale, bool requiresNetwork});

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
      return (
        name: (v['name'] as String?) ?? 'unknown',
        locale: (v['locale'] as String?) ?? '',
        // Android reports networkTts in its feature string. A voice that needs
        // a connection is unusable on a device that must work anywhere.
        requiresNetwork: features.contains('networkTts'),
      );
    }).toList();
  }

  @override
  Future<void> useVoice(VoiceOption voice) =>
      _tts.setVoice({'name': voice.name, 'locale': voice.locale});

  @override
  Future<void> setRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<void> setPitch(double pitch) => _tts.setPitch(pitch);

  @override
  Future<void> setVolume(double volume) => _tts.setVolume(volume);
}
