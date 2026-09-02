// neuralbench — times wordbridge's neural voice on the tablet it is for.
//
// Separate app, separate bundle id: org.wordbridge.neuralbench. It never
// touches com.sheyaln.aac, whose data container is a board somebody
// speaks with — and which a reinstall under the wrong build flavour empties.
//
// Everything timed here is imported from the app rather than copied, so what
// is measured is what ships.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wordbridge/features/speech/neural/audio_clip.dart';
import 'package:wordbridge/features/speech/neural/clip_player.dart';
import 'package:wordbridge/features/speech/neural/clip_store.dart';
import 'package:wordbridge/features/speech/neural/kokoro.dart';
import 'package:wordbridge/features/speech/neural/synthesis_budget.dart';
import 'package:wordbridge/features/speech/neural/voice_model.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

import 'pitch.dart';

/// The stored samples back as floats, so the pitch estimate reads what the
/// cache actually holds rather than a separate copy of it.
Float32List _floatsOf(AudioClip clip) {
  final view = ByteData.sublistView(clip.pcm16);
  final out = Float32List(clip.pcm16.lengthInBytes ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: const Bench()),
  );
}

class Bench extends StatefulWidget {
  const Bench({super.key});
  @override
  State<Bench> createState() => _BenchState();
}

class _BenchState extends State<Bench> {
  final _lines = <String>[];
  bool _running = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Runs on its own. Nobody is holding the tablet when this is launched from
    // a script, and a bench that needs a tap reports nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _note(String line) {
    setState(() => _lines.add(line));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _done = false;
      _lines.clear();
    });

    // The last run's results go before this one starts, so pulling the file
    // can never hand back an answer to a question that was already changed.
    final previous = File(
      p.join((await getApplicationDocumentsDirectory()).path,
          'neural-bench.txt'),
    );
    if (previous.existsSync()) previous.deleteSync();
    try {
      await _bench();
      _note('DONE');
    } catch (e, stack) {
      _note('FAILED $e');
      _note('$stack');
    }
    final documents = await getApplicationDocumentsDirectory();
    await File(
      p.join(documents.path, 'neural-bench.txt'),
    ).writeAsString(_lines.join('\n'));
    setState(() {
      _running = false;
      _done = true;
    });
  }

  /// Which sections to run this time.
  ///
  /// Read from `Documents/bench-sections.txt`, pushed beside the model. The
  /// sweep alone is four minutes and the model load is three more, so a bench
  /// that always starts from the top makes every fix to the last section cost
  /// the whole run. Empty or missing means all of them.
  Future<Set<String>> _sections(Directory documents) async {
    final file = File(p.join(documents.path, 'bench-sections.txt'));
    if (!file.existsSync()) return const {};
    final asked = (await file.readAsString())
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return asked;
  }

  Future<void> _bench() async {
    final documents = await getApplicationDocumentsDirectory();
    final only = await _sections(documents);
    bool wants(String section) => only.isEmpty || only.contains(section);
    if (only.isNotEmpty) _note('running only: ${only.join(', ')}');

    final root = Directory(p.join(documents.path, VoiceModelStore.folder));
    final files = VoiceModelFiles(Directory(p.join(root.path, 'model')));

    if (!files.arePresent) {
      _note('no model at ${files.root.path}');
      return;
    }
    _note('model ${(files.model.lengthSync() / 1000000).round()} MB');

    final needsModel =
        wants('sweep') || wants('question') || wants('tap');

    var started = DateTime.now();
    final synthesizer = KokoroSynthesizer(files);
    if (needsModel) {
      // Loading. A blocking FFI call over 330 MB of weights, so it runs off
      // the main isolate — this is how long the board would otherwise have
      // frozen.
      await synthesizer.load();
      _note(
        'model load + warm-up: '
        '${DateTime.now().difference(started).inMilliseconds} ms',
      );
    }

    if (wants('question')) await _questionMark(synthesizer);

    // Live synthesis by utterance length, median of three, so one scheduling
    // accident does not become the shipped budget.
    const unit = 'the cat sat on the mat and then it went outside again today';
    final words = unit.split(' ');
    final measured = <int, int>{};
    for (final n in wants('sweep') ? [1, 2, 3, 5, 8, 12, 16, 24] : <int>[]) {
      final text = [for (var i = 0; i < n; i++) words[i % words.length]].join(' ');
      final runs = <int>[];
      for (var run = 0; run < 3; run++) {
        started = DateTime.now();
        await synthesizer.generate(text: text, sid: 1, speed: 1.0);
        runs.add(DateTime.now().difference(started).inMilliseconds);
      }
      runs.sort();
      measured[n] = runs[1];
      _note('synthesis $n words: ${runs[1]} ms  (${runs.join(' / ')})');
    }

    if (measured.isNotEmpty) {
      final fitted = SynthesisBudget.fit(
        shortWords: 2,
        shortTook: Duration(milliseconds: measured[2]!),
        longWords: 16,
        longTook: Duration(milliseconds: measured[16]!),
      );
      _note('budget fitted here (doubled): $fitted');
      _note('budget shipped as default:    ${SynthesisBudget.shipped}');
    }

    if (wants('tap')) {
      // Real-time factor, and what trimming the padding is worth.
      started = DateTime.now();
      final raw = await synthesizer.generate(
        text: 'I want to go outside please',
        sid: 1,
        speed: 1.0,
        trim: false,
      );
      final synthesized = DateTime.now().difference(started);
      final clip = await synthesizer.generate(
        text: 'I want to go outside please',
        sid: 1,
        speed: 1.0,
      );
      final audio = clipDuration(clip);
      _note(
        'sentence: ${synthesized.inMilliseconds} ms for '
        '${audio.inMilliseconds} ms of audio — RTF '
        '${(synthesized.inMilliseconds / audio.inMilliseconds).toStringAsFixed(2)}',
      );
      _note(
        'padding trimmed: ${clipDuration(raw).inMilliseconds} ms -> '
        '${audio.inMilliseconds} ms '
        '(${(100 - clip.pcm16.lengthInBytes / raw.pcm16.lengthInBytes * 100).round()}% off)',
      );

      final short = await synthesizer.generate(text: 'I', sid: 1, trim: false);
      _note('the word "I" synthesizes to ${clipDuration(short).inMilliseconds} ms');

      // The tap path, which is the one that must not have got slower.
      final store = await ClipStore.open(
        root: ClipStore.directoryIn(root),
        packId: 'bench-r100',
      );
      await store.write('outside', clip);

      started = DateTime.now();
      for (var i = 0; i < 50; i++) {
        await store.read('outside');
      }
      _note(
        'cache lookup: '
        '${(DateTime.now().difference(started).inMicroseconds / 50).round()} us '
        'per word (${(clip.pcm16.lengthInBytes / 1024).round()} KB each)',
      );

      // What playing a buffer costs before any sound comes out, measured against
      // a clip of near-nothing so what is left is the channel, the wav wrapper
      // and the player starting.
      final player = ClipPlayer();
      final tiny = (pcm16: Uint8List(480), sampleRate: 24000);
      await player.play(tiny);
      started = DateTime.now();
      for (var i = 0; i < 20; i++) {
        await player.play(tiny);
      }
      final perPlay = DateTime.now().difference(started).inMicroseconds / 20;
      _note(
        'play a 10 ms clip, call to silence: '
        '${(perPlay / 1000).toStringAsFixed(1)} ms — so about '
        '${(perPlay / 1000 - 10).toStringAsFixed(1)} ms of it is not the audio',
      );

      // A whole tap, the way the board does it, against the same tap as it
      // works today. The audio differs — different voices say a word over
      // different lengths — so what is comparable is the gap between the call
      // and the sound, which is the part a person feels as lag.
      final word = await synthesizer.generate(text: 'outside', sid: 1);
      await store.write('word', word);
      final wordAudio = clipDuration(word).inMilliseconds;

      final platform = FlutterTtsEngine();
      await platform.init();
      await platform.speak('outside');

      var neural = 0;
      var today = 0;
      for (var i = 0; i < 5; i++) {
        started = DateTime.now();
        await platform.speak('outside');
        today += DateTime.now().difference(started).inMilliseconds;

        started = DateTime.now();
        final cached = await store.read('word');
        await player.play(cached!);
        neural += DateTime.now().difference(started).inMilliseconds;
      }
      _note(
        'one word "outside", call to silence, mean of 5 — '
        'today ${(today / 5).round()} ms, '
        'cached neural ${(neural / 5).round()} ms '
        '($wordAudio ms of the neural one is the audio, so '
        '${(neural / 5 - wordAudio).round()} ms is the app)',
      );

      _note('a whole 1231-word bake at these rates: '
          '${(1231 * measured[1]! / 60000).round()} minutes');

      await store.delete();
      await store.close();
    }

    synthesizer.dispose();

    if (wants('install')) await _install(root);
  }

  /// Does the question mark do anything, or only claim to?
  ///
  /// §4.42 sells the punctuation key on the grounds that a mark "buys a
  /// genuine rising intonation rather than an imitation of one", and that
  /// claim was made about platform engines. The neural voice is a different
  /// engine, and a control that does not do what its name says is exactly what
  /// §5 non-negotiable 9 forbids — so it gets measured rather than inherited.
  ///
  /// The same words, on the same voice, with and without the mark. Systematic
  /// error in the pitch estimate cancels; what is left is the difference.
  Future<void> _questionMark(KokoroSynthesizer synthesizer) async {
    _note('--- does the mark carry tone? (loaded: ${synthesizer.isLoaded}) ---');
    _note('rise = mean f0 of the last 200 ms, minus the mean over the whole');

    const pairs = [
      'are you ok',
      'you want more',
      'it is my turn',
      'that is mine',
      'we are going home',
      'you are cross with me',
      'is it time',
      'I can have one',
    ];

    var rose = 0;
    var fell = 0;
    for (final sentence in pairs) {
      final flat = await synthesizer.generate(text: sentence, sid: 1);
      final asked = await synthesizer.generate(text: '$sentence?', sid: 1);

      final flatRise = _rise(flat);
      final askedRise = _rise(asked);
      if (flatRise == null || askedRise == null) {
        _note('"$sentence": no pitch to measure');
        continue;
      }

      final change = askedRise - flatRise;
      if (change > 5) {
        rose++;
      } else if (change < -5) {
        fell++;
      }
      _note(
        '"$sentence"  rise ${flatRise.round()} Hz  ->  with "?" '
        '${askedRise.round()} Hz   (${change >= 0 ? '+' : ''}${change.round()})',
      );
    }
    _note(
      'of ${pairs.length}: $rose rose by more than 5 Hz, $fell fell by more '
      'than 5 Hz, ${pairs.length - rose - fell} did neither',
    );
  }

  /// How much the end lifts above the utterance's own average.
  ///
  /// A question contour is a rise on the final syllable, so the last 200 ms is
  /// what carries it and the whole-utterance mean is what it has to be judged
  /// against — two voices at different pitches would otherwise not be
  /// comparable at all.
  double? _rise(AudioClip clip) {
    final samples = _floatsOf(clip);
    final whole = Pitch.meanF0(samples, clip.sampleRate);
    final tailFrom = samples.length - (clip.sampleRate * 0.2).round();
    if (whole == null || tailFrom <= 0) return null;
    final tail = Pitch.meanF0(
      Float32List.sublistView(samples, tailFrom),
      clip.sampleRate,
    );
    if (tail == null) return null;
    return tail - whole;
  }

  /// The other half of the feature: getting the model here in the first place.
  ///
  /// Timed on the device because the risk is not the download, it is the
  /// unpacking — bzip2 in Dart over 346 MB of output, on an A12, is the one
  /// step nobody can estimate from a desk.
  Future<void> _install(Directory root) async {
    final store = VoiceModelStore();
    _note('--- install, from nothing ---');
    await store.deleteModel();

    final started = DateTime.now();
    var phase = ModelPhase.downloading;
    var phaseStarted = started;

    await for (final progress in store.install()) {
      if (progress.phase != phase) {
        _note(
          '${phase.name}: '
          '${DateTime.now().difference(phaseStarted).inSeconds} s',
        );
        phase = progress.phase;
        phaseStarted = DateTime.now();
      }
      if (progress.phase == ModelPhase.failed) {
        _note('install FAILED ${progress.detail}');
        return;
      }
    }

    _note('${phase.name}: ${DateTime.now().difference(phaseStarted).inSeconds} s');
    _note(
      'install end to end: '
      '${DateTime.now().difference(started).inSeconds} s',
    );
    _note('on disk after: ${(await store.bytesOnDisk() / 1000000).round()} MB');
    _note('files all present: ${await store.isInstalled()}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('neuralbench')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _running ? null : _run,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _running ? 'running…' : (_done ? 'run again' : 'Run the bench'),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final line in _lines)
                Text(
                  line,
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 13,
                    color: line.startsWith('FAILED')
                        ? Colors.redAccent
                        : Colors.greenAccent,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
