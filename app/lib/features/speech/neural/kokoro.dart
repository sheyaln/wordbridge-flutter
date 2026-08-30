import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'audio_clip.dart';
import 'voice_model.dart';

/// The downloaded model, and the one thread that is allowed to run it.
///
/// Everything here exists because **`generate()` is a blocking FFI call**. Run
/// on the main isolate it freezes the board for the length of the synthesis
/// and — the part that decides the architecture — leaves no thread able to
/// notice a deadline, so the timeout in [SynthesisBudget] cannot fire at all.
/// A frozen board that will not give up is worse than a slow one.
///
/// So every call into the model goes through [Isolate.run], and the engine is
/// shared **by address** rather than rebuilt inside it: a second copy of a
/// 330 MB model does not fit beside the first on a 3 GB tablet, which is the
/// device this is for. `OfflineTts.fromPtr` is public for exactly this.
class KokoroSynthesiser {
  KokoroSynthesiser(this.files);

  final VoiceModelFiles files;

  /// What Kokoro v0.19 produces. Read back from the model rather than assumed
  /// once a clip has been made, but needed before that to size a buffer.
  static const nominalSampleRate = 24000;

  /// Two, measured. More threads on an A12 buys nothing: the cores it would
  /// use are the efficiency cores, and the contention costs more than the
  /// parallelism returns.
  static const _threads = 2;

  sherpa.OfflineTts? _tts;
  sherpa.OfflineTtsConfig? _config;

  bool get isLoaded => _tts != null;

  /// Whether something is waiting on the model to speak right now.
  ///
  /// The bake reads this between words and stands aside. A person pressing the
  /// bar outranks a background job every time.
  bool get liveWaiting => _liveWaiting > 0;
  int _liveWaiting = 0;

  /// One at a time. The native engine is a single object behind a pointer and
  /// two concurrent `generate` calls on it are a data race, so requests queue.
  Future<void> _turn = Future.value();

  /// Loads the model, off the main isolate.
  ///
  /// Building the engine is itself a blocking call — 345 MB of ONNX has to be
  /// read and prepared — so it goes the same way as synthesis. The pointer it
  /// returns is a process address and stays valid on this side; that is the
  /// same property [Isolate.run] relies on below.
  ///
  /// Warms up before returning, because the first synthesis after a load is
  /// several times the cost of the second and nobody should pay it on a press.
  Future<void> load() async {
    if (_tts != null) return;
    if (!files.arePresent) {
      throw StateError('The neural voice model is not installed.');
    }

    sherpa.initBindings();

    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: files.model.path,
          voices: files.voices.path,
          tokens: files.tokens.path,
          dataDir: files.espeakData.path,
        ),
        numThreads: _threads,
      ),
    );

    final address = await Isolate.run(() {
      sherpa.initBindings();
      return sherpa.OfflineTts(config).ptr.address;
    });

    _config = config;
    _tts = sherpa.OfflineTts.fromPtr(
      ptr: Pointer.fromAddress(address),
      config: config,
    );

    await _generate(text: 'hello', sid: 0, speed: 1.0);
  }

  /// Gives the model back its memory.
  ///
  /// Called when the voice is switched off or the model deleted. 833 MB
  /// resident is most of what a 3 GB tablet has to spare, and holding it for a
  /// feature nobody is using is how a board becomes the thing that gets killed
  /// in the background.
  void dispose() {
    _tts?.free();
    _tts = null;
    _config = null;
  }

  /// What the model is actually handed.
  ///
  /// A bare word with nothing to end it comes back with a schwa stuck on the
  /// end — `look` as "look-uh", `wait` as "wait-uh" — and `like` comes back as
  /// two syllables. The phonemiser reads an unpunctuated string as a fragment
  /// that carries on, and voices the end of it accordingly. A full stop is how
  /// it is told the utterance is finished. Whole sentences already end in one,
  /// which is why they always sounded right and single words did not.
  ///
  /// A trailing comma or colon is replaced rather than added to: `look,.` is
  /// not a string to hand a phonemiser.
  ///
  /// Applied here rather than at either call site, because the bake and the
  /// live path must give the model the same string — a cached word and a
  /// freshly made one that did not match would be the same word in two voices.
  static String textForModel(String text) {
    final trimmed = text.trim().replaceFirst(RegExp(r'[,;:\s]+$'), '');
    if (trimmed.isEmpty) return trimmed;
    return RegExp(r'[.!?…]$').hasMatch(trimmed) ? trimmed : '$trimmed.';
  }

  /// Synthesises [text], trimmed and ready to store or play.
  ///
  /// [live] marks a person waiting, which is what [liveWaiting] reports to the
  /// bake. It changes nothing else: the queue is first come, first served, and
  /// the caller's own budget decides how long it is prepared to stay in it.
  Future<AudioClip> generate({
    required String text,
    required int sid,
    double speed = 1.0,
    double gain = 1.0,
    bool live = false,
    bool trim = true,
  }) {
    if (live) _liveWaiting++;

    final turn = _turn.then((_) async {
      final audio = await _generate(
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
    });

    // The queue must survive a failed turn, or one bad string stops the model
    // answering for the rest of the session.
    _turn = turn.then((_) {}, onError: (Object _) {});

    if (!live) return turn;
    return turn.whenComplete(() => _liveWaiting--);
  }

  /// One synthesis, on a thread that is not the one drawing the board.
  ///
  /// The engine is passed as an address and rebuilt around it inside the
  /// isolate. `initBindings()` has to run there too — bindings are per-isolate
  /// even though the engine behind them is not.
  Future<_Audio> _generate({
    required String text,
    required int sid,
    required double speed,
  }) {
    final tts = _tts;
    final config = _config;
    if (tts == null || config == null) {
      throw StateError('The neural voice model is not loaded.');
    }

    final address = tts.ptr.address;
    return Isolate.run(() {
      sherpa.initBindings();
      final engine = sherpa.OfflineTts.fromPtr(
        ptr: Pointer.fromAddress(address),
        config: config,
      );
      final audio = engine.generate(text: text, sid: sid, speed: speed);
      return _Audio(audio.samples, audio.sampleRate);
    });
  }
}

/// What comes back across the isolate boundary.
class _Audio {
  const _Audio(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}
