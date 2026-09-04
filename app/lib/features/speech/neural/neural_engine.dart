import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../speech_engine.dart';
import 'audio_clip.dart';
import 'bake.dart';
import 'clip_player.dart';
import 'clip_store.dart';
import 'kokoro.dart';
import 'neural_voice.dart';
import 'synthesis_budget.dart';
import 'voice_model.dart';

/// One time the platform voice had to speak instead.
typedef Fallback = ({DateTime at, String text, String reason});

/// The board's voice, when a profile has switched the downloaded one on.
///
/// Everything here is a ladder, and which rung a piece of speech lands on is
/// decided by which half of the board it came from:
///
/// 1. **Cached neural audio.** The ordinary case, and *faster* than the
///    platform engine because there is nothing to synthesize — a buffer that
///    already exists against a synthesizer that has to start.
/// 2. **Live neural synthesis**, under [SynthesisBudget], on both paths.
/// 3. **The platform voice**, when the budget runs out. *A different voice* —
///    a real cost rather than a graceful degradation. A word that comes out in
///    a stranger's voice is noticeable to everyone in the room except,
///    possibly, the person it happened to. It is counted, and the caregiver
///    screen shows how often it fired.
///
/// **Rung 2 is on the tap path, and that is a deliberate reversal.** It used
/// to be the bar's speak key only, on the §5 non-negotiable 1 reading that a
/// tap must never wait — and the result was that the first thing anybody heard
/// after switching the voice on was the device voice, because nothing is baked
/// for half an hour. They conclude the feature does not work, and they are not
/// wrong about what they heard.
///
/// What non-negotiable 1 forbids is a person left unable to speak. A wait
/// bounded by a number shown on the screen, which then speaks either way, is
/// not that. What it costs is real and worth naming: until the bake catches
/// up, a tapped word can take up to the budget before it is heard. It is
/// self-clearing — every synthesized clip is filed as it is made, so the same
/// word is a cache read next time.
class NeuralSpeechEngine implements SpeechEngine {
  NeuralSpeechEngine(
    this.platform, {
    VoiceModelStore? models,
    ClipPlayer? player,
    Future<Directory> Function()? documentsDirectory,
    Future<AudioClip?> Function(String text)? synthesize,
  }) : models = models ?? VoiceModelStore(),
       _player = player ?? ClipPlayer(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _synthesizeOverride = synthesize;

  /// §4.4 as it already ships, and what rung 3 is.
  ///
  /// Not a degraded mode invented for this: the neural voice is the addition,
  /// and what it falls back to is the product as it stands — the profile's
  /// rate, pitch and volume, on the voice a caregiver chose. Which is the
  /// strongest available answer to "what if it fails".
  final SpeechEngine platform;

  final VoiceModelStore models;
  final ClipPlayer _player;
  final Future<Directory> Function() _documentsDirectory;

  /// Stands in for the model, so the ladder and its timeout can be exercised
  /// without 345 MB of weights and a device to run them on.
  final Future<AudioClip?> Function(String text)? _synthesizeOverride;

  KokoroSynthesizer? _synthesizer;
  ClipStore? _clips;
  BakeJob? _bake;

  NeuralVoice _voice = neuralVoiceById(null);
  double _speed = 1.0;
  double _volume = 1.0;
  bool _on = false;

  SynthesisBudget budget = SynthesisBudget.shipped;

  /// Which utterance is the current one.
  ///
  /// **A late result must never speak.** If the fallback has already spoken,
  /// neural audio arriving afterwards would say the sentence a second time in
  /// a different voice — and the user cannot easily take back either of them.
  /// Every path checks this after every await and drops what it is holding if
  /// it is no longer the newest. `FlutterTtsEngine.speak` carries the same
  /// rule for the same reason.
  int _generation = 0;

  /// Whether this profile asked for the neural voice.
  bool get isOn => _on;

  /// Whether cached audio can actually be played back.
  ///
  /// Distinct from [isOn]: the cache can be full and the platform still have
  /// no way to play a buffer, and a switch that silently does nothing is what
  /// §5 non-negotiable 9 forbids.
  bool get canPlay => _player.isAvailable;

  NeuralVoice get voice => _voice;

  /// The speed the open pack was baked at.
  ///
  /// Deliberately not `ProfileSettings.speechRate`. The two part company the
  /// moment the dial moves, and that gap is the whole of what the voice screen
  /// has to reconcile: a pack made at 1.0 is a pack made at 1.0 until
  /// something re-points this engine at another one.
  double get speed => _speed;

  /// The pack this engine would be on at [speed], for a screen deciding
  /// whether a dial has changed anything.
  ///
  /// Speed is rounded into the name, so two positions of a slider can be one
  /// pack and a caregiver should not be asked to re-make 1231 words because a
  /// thumb moved a thousandth.
  String packIdAt(double speed) => ClipStore.idFor(_voice.id, speed);

  ClipStore? get clips => _clips;

  BakeJob? get bake => _bake;

  /// Whether the model is in memory. False is the ordinary state: 833 MB
  /// resident is most of what a 3 GB tablet has spare, and the cache — which
  /// is the whole tap path — needs none of it.
  bool get isModelLoaded => _synthesizer?.isLoaded ?? false;

  /// Every time this session had to use the platform voice.
  ///
  /// Held for the life of the app rather than stored, and the screen says so.
  /// The question a caregiver is answering is "is this happening often", and
  /// a session is the window in which that is answerable.
  List<Fallback> get fallbacks => List.unmodifiable(_fallbacks);
  final _fallbacks = <Fallback>[];
  static const _keepFallbacks = 20;

  int get fallbackCount => _fallbackCount;
  int _fallbackCount = 0;

  /// Switches the voice on or off for a profile, and puts it on the right pack.
  ///
  /// Cheap either way. Turning it on opens an index file; it does **not** load
  /// the model, which is deferred until something actually needs to synthesize.
  /// Turning it off gives the memory back and leaves the platform engine
  /// exactly as §4.4 configured it, which is what makes "turning it off
  /// restores today's behavior" true rather than approximately true.
  Future<void> useNeuralVoice({
    required bool enabled,
    String? voiceId,
    double speed = 1.0,
  }) async {
    _voice = neuralVoiceById(voiceId);
    _speed = speed;

    if (!enabled) {
      _on = false;
      await _release();
      return;
    }

    final packId = ClipStore.idFor(_voice.id, _speed);
    if (_clips?.packId != packId) {
      await _clips?.close();
      _clips = await ClipStore.open(root: await _clipRoot(), packId: packId);
      // A pack belongs to one voice at one speed, so the job that fills it
      // does too. Keeping the old one would report another pack's progress.
      _bake?.dispose();
      _bake = null;
    }
    _on = true;
  }

  Future<Directory> _clipRoot() async => ClipStore.directoryIn(
    Directory(
      p.join((await _documentsDirectory()).path, VoiceModelStore.folder),
    ),
  );

  /// Throws away every pack but the one in use.
  ///
  /// A tablet that has tried four voices carries four packs, three of which
  /// nothing will read again. Called from the caregiver screen, after a choice
  /// is committed, rather than on every settings write.
  Future<int> pruneOtherVoices() async {
    final keep = _clips?.packId;
    if (keep == null) return 0;
    return ClipStore.pruneTo(await _clipRoot(), keep);
  }

  /// Loads the model, once, when something needs it.
  ///
  /// Deliberately not at session open. Most sessions never synthesize a thing
  /// — the cache answers them — and a communication device should not be
  /// carrying most of a gigabyte for a feature it is not using.
  Future<KokoroSynthesizer?> loadModel() async {
    if (!_on) return null;
    final existing = _synthesizer;
    if (existing != null && existing.isLoaded) return existing;

    try {
      final synthesizer = KokoroSynthesizer(await models.files());
      await synthesizer.load();
      return _synthesizer = synthesizer;
    } catch (_) {
      // No model, or one that will not load. Every rung below this still
      // speaks, which is the point of having them.
      return null;
    }
  }

  /// Gives the model its memory back.
  ///
  /// Called when the bake finishes and when the app goes to the background.
  /// The cache is untouched: the board still speaks in the chosen voice with
  /// nothing loaded at all.
  Future<void> releaseModel() async {
    _synthesizer?.dispose();
    _synthesizer = null;
  }

  Future<void> _release() async {
    _bake?.dispose();
    _bake = null;
    await releaseModel();
    await _clips?.close();
    _clips = null;
  }

  /// Whether any of [words] is still missing from this voice's pack.
  ///
  /// Asked before [bakeJob], and the reason it exists: the pack is an open
  /// index and answering this costs nothing, where making the job loads 833 MB
  /// of weights. A session opening onto a board that is already fully baked
  /// must not pay that to discover there is nothing to do.
  bool needsBaking(Iterable<String> words) {
    final clips = _clips;
    if (!_on || clips == null) return false;
    return words.any((word) => !clips.contains(word));
  }

  /// The job that fills this profile's pack, made on demand.
  ///
  /// Null where the model will not load. A bake with nothing to bake with is
  /// a progress bar that never moves, which says less than an honest absence.
  Future<BakeJob?> bakeJob() async {
    final existing = _bake;
    if (existing != null) return existing;

    final clips = _clips;
    if (clips == null) return null;

    // The same stand-in the ladder uses, for the same reason: a bake is the
    // other thing worth exercising without 345 MB of weights and a device to
    // run them on. Nothing is waiting on an engine that is not there.
    final override = _synthesizeOverride;
    if (override != null) {
      return _bake = BakeJob(
        clips,
        synthesize: (word) async =>
            await override(word) ?? (pcm16: Uint8List(0), sampleRate: 24000),
        someoneIsWaiting: () => false,
      );
    }

    final synthesizer = await loadModel();
    if (synthesizer == null) return null;

    return _bake = BakeJob(
      clips,
      synthesize: (word) =>
          synthesizer.generate(text: word, sid: _voice.sid, speed: _speed),
      someoneIsWaiting: () => synthesizer.liveWaiting,
    );
  }

  @override
  Future<void> init() => platform.init();

  /// Says a word, now if it can and shortly if it cannot.
  ///
  /// Cached first, then composed — a copula key that corrects the word before
  /// it speaks the pair ("are you") is not a string anything baked, but both
  /// halves are, and this app owns the samples, so they are joined rather than
  /// handed to a different voice mid-sentence.
  ///
  /// **A word nothing has baked is made now, not handed to the platform.**
  /// This used to fall back the instant the cache missed, which was faster and
  /// was wrong in the case that actually happens: somebody switches the voice
  /// on, waits out the download, presses a word to hear it — and hears the
  /// device voice, because nothing is baked yet. They conclude it does not
  /// work. The bake takes half an hour and nobody watches it before forming
  /// that opinion.
  ///
  /// The wait is the same [budget] the utterance path uses and is shown on the
  /// caregiver screen, so it is bounded and it is a number somebody was told.
  /// It is also self-clearing: the clip is filed as it is made, so the second
  /// press of that word is a cache read, and the bake is closing the gap
  /// underneath.
  @override
  Future<void> speak(String text) async {
    final spoken = normalizeForSpeech(text);
    if (spoken.isEmpty) return;

    final mine = ++_generation;
    _bake?.standAside();

    final clips = _on ? _clips : null;
    if (clips == null) return platform.speak(spoken);

    final cached = await clips.read(spoken);
    if (mine != _generation) return;
    if (cached != null) return _play(cached);

    final composed = await _compose(spoken, clips);
    if (mine != _generation) return;
    if (composed != null) return _play(composed);

    await _makeItNow(spoken, mine, clips, platform.speak);
  }

  /// Says a whole sentence, and this is the one place a wait was agreed to.
  ///
  /// The exception in §4.5 is exact: one press, one wait, one sentence, for a
  /// profile that switched a realistic voice on knowing what it costs. It is
  /// bounded by [budget], because an opted-in wait is a trade somebody chose
  /// and an *unbounded* wait is not a trade at all — nobody agrees to a number
  /// they were never shown.
  ///
  /// Falling back here loses more than the voice. Tone lives in the contour
  /// across a whole utterance and the platform engine has none, so the
  /// sentence comes out meaning something slightly different — which is why
  /// the count is kept and shown rather than inferred.
  @override
  Future<void> speakUtterance(String text) async {
    final spoken = normalizeForSpeech(text);
    if (spoken.isEmpty) return;

    final mine = ++_generation;
    _bake?.standAside();

    final clips = _on ? _clips : null;
    if (clips == null) return platform.speakUtterance(spoken);

    final cached = await clips.read(spoken);
    if (mine != _generation) return;
    if (cached != null) return _play(cached);

    await _makeItNow(spoken, mine, clips, platform.speakUtterance);
  }

  /// Makes the sound now, and hands over to the platform only when the wait
  /// runs out.
  ///
  /// One ladder, used by both paths, so a word and a sentence cannot come to
  /// disagree about how long is too long or about what counts as a failure.
  /// [saySomehow] is the platform call that matches the path this was reached
  /// from — the tap path may not be given the utterance call, which is allowed
  /// to wait a second time.
  Future<void> _makeItNow(
    String spoken,
    int mine,
    ClipStore clips,
    Future<void> Function(String) saySomehow,
  ) async {
    final deadline = budget.forText(spoken);
    try {
      // The budget covers the wait for the engine as well as the synthesis.
      // A model busy with the word before this one is a person waiting just
      // the same, and the clock they are watching does not know the
      // difference.
      final clip = await _synthesize(spoken).timeout(deadline);
      if (mine != _generation) return;
      if (clip == null) {
        _recordFallback(spoken, 'the voice could not be loaded');
        await saySomehow(spoken);
        return;
      }
      await clips.write(spoken, clip);
      await _play(clip);
    } on TimeoutException {
      // The result may still arrive. It is dropped where it lands: the words
      // are about to be spoken, and hearing them twice — the second time in
      // another voice — is worse than not hearing them in this one.
      if (mine != _generation) return;
      _recordFallback(spoken, 'took longer than ${deadline.inMilliseconds} ms');
      await saySomehow(spoken);
    } catch (e) {
      // Anything else the model can do: a string it cannot phonemize, memory
      // it cannot have, or — the one that will actually happen — an engine
      // released out from under it, because backgrounding the app gives the
      // model's 833 MB back and a press can be in flight when it does.
      //
      // Every one of those has to come out as the platform voice. Words in the
      // wrong voice are a cost somebody can hear and work around; words spoken
      // by nothing at all are the failure this file exists to prevent, and the
      // one nobody in the room can see happening.
      if (mine != _generation) return;
      _recordFallback(spoken, 'the voice failed: $e');
      await saySomehow(spoken);
    }
  }

  /// Speaks [text] in [voice], whether or not it is the chosen one.
  ///
  /// Every control on the voice screen previews itself as a spoken sentence
  /// (§4.4), and a voice is the control that most needs it: a caregiver is
  /// choosing how somebody else will sound for the next several years, and the
  /// person it is for may not be able to say it is wrong.
  ///
  /// Synthesized live, and slow — this is the private half of Pullin & Hennig's
  /// split, where a wait costs nobody a conversation. Changing which voice is
  /// previewed is free: the model takes the speaker as a generation parameter,
  /// so nothing is reloaded between one voice and the next.
  ///
  /// False where there was no model to ask.
  Future<bool> previewVoice(NeuralVoice voice, String text) async {
    final synthesizer = await loadModel();
    if (synthesizer == null) return false;

    final mine = ++_generation;
    try {
      final clip = await synthesizer.generate(
        text: text,
        sid: voice.sid,
        speed: _speed,
        live: true,
      );
      if (mine != _generation) return true;
      await _play(clip);
      return true;
    } catch (_) {
      // Nothing to hear, and the screen says so. A caregiver screen that
      // throws is one somebody cannot get back out of.
      return false;
    }
  }

  /// Times two sentences and fits this tablet's own budget.
  ///
  /// Shipped as a constant it would be the floor device's number on every
  /// device, and the floor device is three times slower than an A12X and far
  /// more than that against a current iPad. Measuring is also the only honest
  /// way for a setting screen to say what *this* tablet does rather than what
  /// a file says.
  ///
  /// Two lengths, well separated, because what has to be resolved is the split
  /// between the fixed overhead and the per-word term — and a caregiver is
  /// waiting while it runs.
  Future<SynthesisBudget?> measureBudget() async {
    final synthesizer = await loadModel();
    if (synthesizer == null) return null;

    Future<Duration> time(String text) async {
      final started = DateTime.now();
      await synthesizer.generate(
        text: text,
        sid: _voice.sid,
        speed: _speed,
        live: true,
      );
      return DateTime.now().difference(started);
    }

    const short = 'yes';
    const long = 'I would like to go outside and see the garden this afternoon';

    try {
      return SynthesisBudget.fit(
        shortWords: SynthesisBudget.wordsIn(short),
        shortTook: await time(short),
        longWords: SynthesisBudget.wordsIn(long),
        longTook: await time(long),
      );
    } catch (_) {
      // A measurement that could not be taken is not a measurement, and the
      // shipped default already covers this device.
      return null;
    }
  }

  Future<AudioClip?> _synthesize(String text) async {
    final override = _synthesizeOverride;
    if (override != null) return override(text);

    final synthesizer = await loadModel();
    if (synthesizer == null) return null;
    return synthesizer.generate(
      text: text,
      sid: _voice.sid,
      speed: _speed,
      live: true,
    );
  }

  /// Joins cached words into a phrase, or null if any of them is missing.
  ///
  /// Only for the tap path. The bar synthesizes live precisely because a
  /// sentence assembled from separately cached words has no contour across it
  /// — every word arrives with the prosody it had standing alone. For a
  /// two-word repair that is a fair trade against changing voice; for a
  /// sentence somebody composed it is not, and it is not offered there.
  Future<AudioClip?> _compose(String text, ClipStore clips) async {
    final words = text.split(RegExp(r'\s+'));
    if (words.length < 2 || words.length > 4) return null;
    for (final word in words) {
      if (!clips.contains(word)) return null;
    }

    final parts = <Uint8List>[];
    for (final word in words) {
      final clip = await clips.read(word);
      if (clip == null) return null;
      parts.add(clip.pcm16);
    }

    // A short gap, so the words do not run together into something that
    // sounds like one longer word.
    final gap = Uint8List((clips.sampleRate * 2 * 0.06).round() & ~1);
    final total =
        parts.fold<int>(0, (sum, part) => sum + part.lengthInBytes) +
        gap.lengthInBytes * (parts.length - 1);

    final joined = Uint8List(total);
    var at = 0;
    for (var i = 0; i < parts.length; i++) {
      joined.setRange(at, at + parts[i].lengthInBytes, parts[i]);
      at += parts[i].lengthInBytes;
      if (i < parts.length - 1) {
        at += gap.lengthInBytes;
      }
    }
    return (pcm16: joined, sampleRate: clips.sampleRate);
  }

  Future<void> _play(AudioClip clip) => _player.play(clip, volume: _volume);

  void _recordFallback(String text, String reason) {
    _fallbackCount++;
    _fallbacks.add((at: DateTime.now(), text: text, reason: reason));
    if (_fallbacks.length > _keepFallbacks) _fallbacks.removeAt(0);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
    await platform.stop();
  }

  /// The platform's voices, unchanged.
  ///
  /// This is the fallback voice's list and it stays the caregiver's to choose
  /// from — rung 3 is what somebody hears when the cache misses, so it matters
  /// which voice it is. The neural voices are a separate list, on their own
  /// screen, because they are a separate choice.
  @override
  Future<List<VoiceOption>> voices() => platform.voices();

  @override
  Future<void> useVoice(VoiceOption voice) => platform.useVoice(voice);

  /// The speed both engines run at.
  ///
  /// Kokoro takes speed as a generation parameter, not a playback rate, so it
  /// is baked into every clip — which is why the pack is keyed on it and why
  /// changing it is a re-bake the caregiver has to be told about *before* it
  /// happens. Handled on the voice screen; nothing is re-baked from here.
  @override
  Future<void> setRate(double rate) => platform.setRate(rate);

  /// Platform only, and the voice screen says so.
  ///
  /// Kokoro has no pitch control: what it has is a 256-float style vector, and
  /// gate 3 measured that its prosody half moves pitch and nothing else. A
  /// pitch dial that silently did nothing under the neural voice would be a
  /// control that does not do what its name says.
  @override
  Future<void> setPitch(double pitch) => platform.setPitch(pitch);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await platform.setVolume(volume);
  }
}
