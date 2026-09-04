import 'dart:async';

import 'audio_clip.dart';
import 'kokoro_worker.dart';
import 'voice_model.dart';

/// The downloaded model, and the worker that is allowed to run it.
///
/// The same shape as the tablet's, and for the same reason: **`generate()` is
/// a blocking call**. There it blocks an isolate; here it would block the one
/// thread a page has, which stops the board drawing, stops it taking taps and
/// — the part that decides the architecture — leaves nothing able to notice a
/// deadline, so the timeout in [SynthesisBudget] cannot fire at all. A frozen
/// board that will not give up is worse than a slow one.
///
/// So everything goes through [KokoroWorker], which holds the WebAssembly
/// module, the weights and the synthesis in a thread of its own. What crosses
/// back is samples, transferred rather than copied.
class KokoroSynthesizer {
  KokoroSynthesizer(this.files);

  final VoiceModelFiles files;

  /// What Kokoro v0.19 produces. Read back from the model once a clip has been
  /// made, but needed before that to size a buffer.
  static const nominalSampleRate = 24000;

  final _worker = KokoroWorker.instance;

  bool get isLoaded => _worker.isLoaded;

  /// Whether something is waiting on the model to speak right now.
  ///
  /// The bake reads this between words and stands aside. A person pressing the
  /// bar outranks a background job every time.
  bool get liveWaiting => _liveWaiting > 0;
  int _liveWaiting = 0;

  /// Loads the model into the worker.
  ///
  /// No warm-up call afterwards, unlike the tablet's. Measured in a browser
  /// the first synthesis and the second are within a few percent of each
  /// other — whatever warm-up cost exists is paid inside the engine's own
  /// construction, which this is already waiting on.
  Future<void> load() async {
    if (!files.arePresent) {
      throw StateError('The neural voice model is not installed.');
    }
    await _worker.load();
  }

  /// Gives the model back its memory, and keeps the download.
  ///
  /// Not awaited by its caller, so nothing here may throw: the engine calls
  /// this when the voice is switched off and when the page goes to the
  /// background, and both are moments where a failure has nobody to tell.
  void dispose() {
    unawaited(_worker.unload());
  }

  /// What the model is actually handed.
  ///
  /// A bare word with nothing to end it comes back with a schwa stuck on the
  /// end — `look` as "look-uh", `wait` as "wait-uh" — and `like` comes back as
  /// two syllables. The phonemizer reads an unpunctuated string as a fragment
  /// that carries on, and voices the end of it accordingly. A full stop is how
  /// it is told the utterance is finished.
  ///
  /// The same string as the tablet builds, deliberately: a word baked on one
  /// and heard on the other has to be the same word in the same voice.
  static String textForModel(String text) {
    final trimmed = text.trim().replaceFirst(RegExp(r'[,;:\s]+$'), '');
    if (trimmed.isEmpty) return trimmed;
    return RegExp(r'[.!?…]$').hasMatch(trimmed) ? trimmed : '$trimmed.';
  }

  /// Synthesizes [text], trimmed and ready to store or play.
  ///
  /// [live] marks a person waiting, which is what [liveWaiting] reports to the
  /// bake. It changes nothing else: the worker answers in the order it was
  /// asked, and the caller's own budget decides how long it is prepared to
  /// stay in the queue.
  Future<AudioClip> generate({
    required String text,
    required int sid,
    double speed = 1.0,
    double gain = 1.0,
    bool live = false,
    bool trim = true,
  }) async {
    if (live) _liveWaiting++;
    try {
      final audio = await _worker.generate(
        text: textForModel(text),
        sid: sid,
        speed: speed,
      );
      // Untrimmed only to measure what the trimming is worth. Nothing that
      // reaches a person skips it: the padding is 30% of the bytes and it is
      // the pause a tap would otherwise start with.
      final samples = trim
          ? trimSilence(audio.samples, audio.sampleRate)
          : audio.samples;
      return (
        pcm16: toPcm16(samples, gain: gain),
        sampleRate: audio.sampleRate,
      );
    } finally {
      if (live) _liveWaiting--;
    }
  }
}
