import 'dart:async';

import 'audio_clip.dart';
import 'voice_model.dart';

/// Kokoro in a browser — the same model, not yet the same runtime.
///
/// `sherpa_onnx` publishes a WebAssembly build with a TTS entry point, so this
/// is a matter of loading the weights into the module's own filesystem rather
/// than a missing capability. Until that is wired, [load] refuses and the
/// board speaks on the rung below — which is `NeuralSpeechEngine`'s design
/// rather than a workaround: an engine that cannot produce a word immediately
/// says it in whatever voice it can produce immediately.
class KokoroSynthesizer {
  KokoroSynthesizer(this.files);

  final VoiceModelFiles files;

  static const nominalSampleRate = 24000;

  bool get isLoaded => false;

  bool get liveWaiting => false;

  Future<void> load() async {
    throw UnsupportedError('The neural voice is not running in browsers yet.');
  }

  void dispose() {}

  Future<AudioClip> generate({
    required String text,
    required int sid,
    double speed = 1.0,
    double gain = 1.0,
    bool live = false,
    bool trim = true,
  }) async {
    throw StateError('The neural voice model is not loaded.');
  }

  static String textForModel(String text) {
    final trimmed = text.trim().replaceFirst(RegExp(r'[,;:\s]+$'), '');
    if (trimmed.isEmpty) return trimmed;
    return RegExp(r'[.!?…]$').hasMatch(trimmed) ? trimmed : '$trimmed.';
  }
}
