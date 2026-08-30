// voicebench — the dev bench for wordbridge's optional neural voice.
//
// Type anything, pick a voice and a preset, hear it synthesised from scratch,
// and see what that cost. Separate app, separate bundle id: it never touches
// org.wordbridge.wordbridge.
//
// Kokoro-82M v0.19 through sherpa-onnx. A Kokoro voice is a 256-float style
// vector; dims 0:128 carry timbre and 128:256 carry prosody, which is why
// "borrow delivery from" below is a real control and not a relabelled slider.
import 'dart:ffi';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const voices = [
  'af — American',
  'af_bella — American',
  'af_nicole — American, softer',
  'af_sarah — American',
  'af_sky — American',
  'am_adam — American, male',
  'am_michael — American, male',
  'bf_emma — British',
  'bf_isabella — British',
  'bm_george — British, male',
  'bm_lewis — British, male',
];

const nVoices = 11;
const nTokens = 511;
const styleDim = 256;

/// What the engine can actually be asked for today: speed and gain. Named for
/// what they do, because a preset that does not do what its name says is worse
/// than a missing one.
class Preset {
  const Preset(this.name, this.speed, this.gain, this.note);
  final String name;
  final double speed;
  final double gain;
  final String note;
}

const presets = [
  Preset('Normal', 1.0, 1.0, 'the voice as chosen'),
  Preset('Calm', 0.82, 0.95, 'slower'),
  Preset('Urgent', 1.25, 1.4, 'faster and louder'),
  Preset('Quiet', 0.95, 0.35, 'turned down — not a whisper'),
  Preset('Loud', 1.0, 2.5, 'past what the iPad alone can do'),
];

/// One synthesis, off the main isolate.
///
/// `generate()` blocks until it is finished, so run on the main isolate it
/// freezes the UI and — the part that matters for the product — leaves no
/// thread able to notice a timeout. The native engine is shared by address
/// rather than rebuilt, because a second copy of a 330 MB model does not fit
/// beside the first on a 3 GB tablet.
class _Synth {
  const _Synth(this.samples, this.sampleRate, this.ms);
  final Float32List samples;
  final int sampleRate;
  final int ms;
}

Future<_Synth> _generateOffThread({
  required int ttsAddress,
  required sherpa.OfflineTtsConfig config,
  required String text,
  required int sid,
  required double speed,
}) => Isolate.run(() {
  sherpa.initBindings();
  final tts = sherpa.OfflineTts.fromPtr(
    ptr: Pointer.fromAddress(ttsAddress),
    config: config,
  );
  final t0 = DateTime.now();
  final a = tts.generate(text: text, sid: sid, speed: speed);
  return _Synth(
    a.samples,
    a.sampleRate,
    DateTime.now().difference(t0).inMilliseconds,
  );
});

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
  sherpa.OfflineTts? _tts;
  final _player = AudioPlayer();
  final _text = TextEditingController(text: 'I want to go outside please');

  String _status = 'loading…';
  String _sweep = '';
  String _last = '';
  int _voice = 0;
  int _prosody = -1; // -1 = the voice's own
  int _loadedTimbre = -2;
  sherpa.OfflineTtsConfig? _config;
  final _platform = FlutterTts();
  // base + perWord x words, fitted on this device: 1149ms + 197ms/word.
  // Shipped default sits at roughly twice the fit, so only a stall trips it.
  double _base = 2300;
  double _perWord = 400;
  int _preset = 0;
  double _speed = 1.0;
  double _gain = 1.0;
  String? _dir;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The model's own metadata says n_speakers=11 and sherpa checks the voices
  /// file against it, so the table cannot be widened. Instead its eleven slots
  /// are rewritten to hold one timbre wearing each of the eleven deliveries:
  /// slot j = timbre[selected] + prosody[j]. Changing delivery is then a
  /// speaker id; changing timbre needs this written again and the model
  /// reloaded, which is why the reload is timed on screen.
  Future<String> _voicesFor(int timbre) async {
    final src = p.join(_dir!, 'voices.bin');
    if (timbre < 0) return src;
    final dst = p.join(_dir!, 'voices_t$timbre.bin');
    if (File(dst).existsSync()) return dst;
    final base = await File(src).readAsBytes();
    final f = base.buffer.asFloat32List();
    final out = Float32List.fromList(f);
    for (var j = 0; j < nVoices; j++) {
      for (var tok = 0; tok < nTokens; tok++) {
        final o = (j * nTokens + tok) * styleDim;
        final ti = (timbre * nTokens + tok) * styleDim;
        for (var d = 0; d < 128; d++) {
          out[o + d] = f[ti + d];
        }
      }
    }
    await File(dst).writeAsBytes(out.buffer.asUint8List(), flush: true);
    return dst;
  }

  /// Rebuilds the engine against a voices file. Only needed when the timbre
  /// changes; delivery and every slider are free.
  Future<void> _engineFor(int timbre) async {
    if (_loadedTimbre == timbre && _tts != null) return;
    setState(() => _status = 'loading the model…');
    final voicesPath = await _voicesFor(timbre);
    final t0 = DateTime.now();
    _tts?.free();
    _config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: p.join(_dir!, 'model.onnx'),
          voices: voicesPath,
          tokens: p.join(_dir!, 'tokens.txt'),
          dataDir: p.join(_dir!, 'espeak-ng-data'),
        ),
        numThreads: 2,
      ),
    );
    _tts = sherpa.OfflineTts(_config!);
    final ms = DateTime.now().difference(t0).inMilliseconds;
    _loadedTimbre = timbre;
    _tts!.generate(text: 'hello', sid: 0, speed: 1.0);
    if (mounted) setState(() => _status = 'ready · model loaded in ${ms}ms');
  }

  Future<void> _load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _dir = docs.path;
      final model = File(p.join(docs.path, 'model.onnx'));
      if (!model.existsSync()) {
        setState(() => _status = 'model.onnx missing in ${docs.path}');
        return;
      }
      // Stale tables from an earlier build would be loaded in preference to
      // being rebuilt, and one of them is the shape that would not load.
      for (final f in Directory(docs.path).listSync()) {
        if (p.basename(f.path).startsWith('voices_')) f.deleteSync();
      }
      sherpa.initBindings();
      await _platform.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker],
        IosTextToSpeechAudioMode.defaultMode,
      );
      await _platform.awaitSpeakCompletion(true);
      await _engineFor(-1);
    } catch (e) {
      setState(() => _status = 'ERROR $e');
    }
  }

  Future<void> _speak() async {
    final text = _text.text.trim();
    if (_tts == null || text.isEmpty) return;

    // No borrow: the untouched table, picked by voice. Borrowing: the table
    // rewritten for this timbre, picked by delivery.
    await _engineFor(_prosody < 0 ? -1 : _voice);
    final sid = _prosody < 0 ? _voice : _prosody;

    final words = text.split(RegExp(r'\s+')).length;
    final budget = Duration(milliseconds: (_base + _perWord * words).round());
    setState(
      () => _status =
          'synthesising… budget ${budget.inMilliseconds}ms for $words words',
    );

    final _Synth a;
    try {
      a = await _generateOffThread(
        ttsAddress: _tts!.ptr.address,
        config: _config!,
        text: text,
        sid: sid,
        speed: _speed,
      ).timeout(budget);
    } on TimeoutException {
      // What the product does here: speak now, in the voice that is ready.
      // The tone is lost with it, which is the cost worth seeing.
      setState(
        () =>
            _last = 'TIMED OUT at ${budget.inMilliseconds}ms — platform voice',
      );
      setState(() => _status = 'falling back');
      await _platform.setVolume(1.0);
      await _platform.setSpeechRate(0.5 * _speed);
      await _platform.speak(text);
      if (mounted) setState(() => _status = 'ready');
      return;
    }
    final synth = a.ms;

    var s = a.samples;
    if (_gain != 1.0) {
      // The buffer is ours, so loudness is a multiply -- the gain stage
      // platform TTS has never offered. tanh-shaped, because a hard clip is
      // just fuzz.
      s = Float32List.fromList([
        for (final v in s) math.tan(math.atan(v * _gain)).clamp(-1.0, 1.0),
      ]);
    }
    final dur = a.samples.length / a.sampleRate;
    final f = p.join(_dir!, 'play.wav');
    sherpa.writeWave(filename: f, samples: s, sampleRate: a.sampleRate);

    setState(() {
      _last =
          'from scratch: ${synth}ms  ·  audio ${(dur * 1000).toStringAsFixed(0)}ms  ·  '
          'RTF ${(synth / 1000 / dur).toStringAsFixed(2)}';
      _status = 'playing';
    });
    await _player.play(DeviceFileSource(f), volume: 1.0);
    await _player.onPlayerComplete.first;
    if (mounted) setState(() => _status = 'ready');
  }

  /// Sweeps utterance length so the timeout budget can be fitted rather than
  /// guessed. The cost is a large fixed call overhead plus a smaller per-word
  /// term, which is why a purely per-word budget cannot work: a one-word
  /// utterance can never meet a budget proportional to one word.
  Future<void> _runSweep() async {
    await _engineFor(_prosody < 0 ? -1 : _voice);
    const unit = 'the cat sat on the mat and then it went outside again today ';
    final lens = [1, 2, 3, 5, 8, 12, 16, 24];
    final lines = <String>[];
    for (final n in lens) {
      final words = (unit * 4).trim().split(' ').take(n).join(' ');
      final runs = <int>[];
      for (var r = 0; r < 3; r++) {
        final s = await _generateOffThread(
          ttsAddress: _tts!.ptr.address,
          config: _config!,
          text: words,
          sid: 0,
          speed: 1.0,
        );
        runs.add(s.ms);
      }
      runs.sort();
      lines.add('$n,${runs[1]}');
      setState(() => _sweep = '${lines.join("  ")}  (words,ms median of 3)');
    }
    File(p.join(_dir!, 'sweep.csv'))
        .writeAsStringSync('words,ms\n${lines.join("\n")}\n');
    setState(() => _status = 'sweep done — sweep.csv written');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('voicebench · Kokoro-82M v0.19')),
    body: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(_status, style: const TextStyle(color: Colors.greenAccent)),
        if (_last.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _last,
              style: const TextStyle(color: Colors.amber, fontSize: 15),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(
            labelText: 'Say this',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _voice,
          decoration: const InputDecoration(
            labelText: 'Voice (timbre — who it sounds like)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (var i = 0; i < voices.length; i++)
              DropdownMenuItem(value: i, child: Text(voices[i])),
          ],
          onChanged: (v) => setState(() => _voice = v ?? 0),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _prosody,
          decoration: const InputDecoration(
            labelText: 'Borrow delivery from (prosody — how it is said)',
            border: OutlineInputBorder(),
            helperText:
                'Style dims 128:256. Keeps the timbre above. Changing this '
                'is free; changing the voice reloads the model.',
          ),
          items: [
            const DropdownMenuItem(value: -1, child: Text('its own')),
            for (var i = 0; i < voices.length; i++)
              DropdownMenuItem(value: i, child: Text(voices[i])),
          ],
          onChanged: (v) => setState(() => _prosody = v ?? -1),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _preset,
          decoration: const InputDecoration(
            labelText: 'Preset',
            border: OutlineInputBorder(),
          ),
          items: [
            for (var i = 0; i < presets.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text('${presets[i].name} — ${presets[i].note}'),
              ),
          ],
          onChanged: (v) => setState(() {
            _preset = v ?? 0;
            _speed = presets[_preset].speed;
            _gain = presets[_preset].gain;
          }),
        ),
        const SizedBox(height: 8),
        Text('Speed ${_speed.toStringAsFixed(2)}'),
        Slider(
          value: _speed,
          min: 0.5,
          max: 2.0,
          divisions: 30,
          onChanged: (v) => setState(() => _speed = v),
        ),
        Text('Gain ${_gain.toStringAsFixed(2)}  (1.0 = the iPad\'s maximum)'),
        Slider(
          value: _gain,
          min: 0.1,
          max: 4.0,
          divisions: 39,
          onChanged: (v) => setState(() => _gain = v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _tts == null ? null : _speak,
          icon: const Icon(Icons.volume_up),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Speak — synthesised fresh',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Timeout budget: ${_base.round()}ms + ${_perWord.round()}ms/word'),
        Slider(
          value: _base,
          min: 300,
          max: 6000,
          divisions: 57,
          label: '${_base.round()}ms base',
          onChanged: (v) => setState(() => _base = v),
        ),
        Slider(
          value: _perWord,
          min: 0,
          max: 1200,
          divisions: 24,
          label: '${_perWord.round()}ms/word',
          onChanged: (v) => setState(() => _perWord = v),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _tts == null ? null : _runSweep,
          child: const Text('Measure latency vs sentence length'),
        ),
        if (_sweep.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _sweep,
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'No emotion presets here on purpose. Measured: Kokoro\'s prosody '
          'space is one axis and that axis is pitch, so "sad" and "stern" '
          'would be the speed and pitch sliders wearing a name they do not '
          'earn. "Borrow delivery from" is the one genuinely new control — it '
          'is a real style transplant, and it is worth listening for what it '
          'can and cannot carry.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    ),
  );
}
