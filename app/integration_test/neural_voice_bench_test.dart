import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wordbridge/features/speech/neural/audio_clip.dart';
import 'package:wordbridge/features/speech/neural/clip_player.dart';
import 'package:wordbridge/features/speech/neural/clip_store.dart';
import 'package:wordbridge/features/speech/neural/kokoro.dart';
import 'package:wordbridge/features/speech/neural/synthesis_budget.dart';
import 'package:wordbridge/features/speech/neural/voice_model.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

/// What the neural voice costs on the tablet it is for.
///
/// Runs on the device, against the shipping code, because every published
/// number for this model comes from something faster: RTF 0.62 on an A12X and
/// 4–4.5x real time through Core ML on an A17, against an A12 with 3 GB and
/// the plain ONNX runtime. A simulator is worse than useless here — it runs on
/// the Mac's own CPU and would say the feature is fast.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final report = StringBuffer();
  void note(String line) {
    report.writeln(line);
    // ignore: avoid_print — this is the whole output of the run.
    print('BENCH $line');
  }

  testWidgets('what the neural voice costs on this tablet', (tester) async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(documents.path, VoiceModelStore.folder));
    final files = VoiceModelFiles(Directory(p.join(root.path, 'model')));

    expect(
      files.arePresent,
      isTrue,
      reason: 'the model has to be installed before this can measure it',
    );

    final synthesizer = KokoroSynthesizer(files);

    await tester.runAsync(() async {
      // 1. Loading. Blocking FFI over 330 MB of weights, so it runs off the
      //    main isolate — this is how long a board would have frozen for.
      var started = DateTime.now();
      await synthesizer.load();
      final loaded = DateTime.now().difference(started);
      note('model load + warm-up: ${loaded.inMilliseconds} ms');

      // 2. Live synthesis, by utterance length. The sweep the timeout is
      //    fitted from: median of three, so one slow scheduling accident does
      //    not become the shipped budget.
      const unit =
          'the cat sat on the mat and then it went outside again today';
      final words = unit.split(' ');
      final lengths = [1, 2, 3, 5, 8, 12, 16, 24];
      final measured = <int, int>{};

      for (final n in lengths) {
        final text = [for (var i = 0; i < n; i++) words[i % words.length]]
            .join(' ');
        final runs = <int>[];
        for (var run = 0; run < 3; run++) {
          started = DateTime.now();
          await synthesizer.generate(text: text, sid: 1, speed: 1.0);
          runs.add(DateTime.now().difference(started).inMilliseconds);
        }
        runs.sort();
        measured[n] = runs[1];
        note('synthesis $n words: ${runs[1]} ms (${runs.join('/')})');
      }

      // 3. The budget this device would ship, fitted from its own numbers.
      final fitted = SynthesisBudget.fit(
        shortWords: 2,
        shortTook: Duration(milliseconds: measured[2]!),
        longWords: 16,
        longTook: Duration(milliseconds: measured[16]!),
      );
      note('budget fitted here (already doubled): $fitted');
      note('budget shipped as default:            ${SynthesisBudget.shipped}');

      // 4. Real-time factor, and what the padding costs.
      started = DateTime.now();
      final clip = await synthesizer.generate(
        text: 'I want to go outside please',
        sid: 1,
        speed: 1.0,
      );
      final synthesized = DateTime.now().difference(started);
      final audio = clipDuration(clip);
      note(
        'sentence: ${synthesized.inMilliseconds} ms for '
        '${audio.inMilliseconds} ms of audio — '
        'RTF ${(synthesized.inMilliseconds / audio.inMilliseconds).toStringAsFixed(2)}',
      );

      // 5. The tap path, which is the one that must not have got slower.
      final store = await ClipStore.open(
        root: ClipStore.directoryIn(root),
        packId: 'bench-r100',
      );
      await store.write('outside', clip);

      var lookups = 0;
      started = DateTime.now();
      for (var i = 0; i < 50; i++) {
        final read = await store.read('outside');
        lookups += read!.pcm16.lengthInBytes;
      }
      final perLookup = DateTime.now().difference(started).inMicroseconds / 50;
      note(
        'cache lookup: ${perLookup.toStringAsFixed(0)} us per word '
        '(${(lookups / 50 / 1024).round()} KB each)',
      );

      // 6. What playing a buffer costs before any sound comes out. Measured
      //    against a clip of near-nothing, so what is left is the channel, the
      //    wav wrapper and the player starting.
      final player = ClipPlayer();
      final tiny = (pcm16: Uint8List(480), sampleRate: 24000);
      await player.play(tiny);
      started = DateTime.now();
      for (var i = 0; i < 20; i++) {
        await player.play(tiny);
      }
      final perPlay = DateTime.now().difference(started).inMicroseconds / 20;
      note(
        'play a 10 ms clip end to end: ${(perPlay / 1000).toStringAsFixed(1)} ms '
        '(playable: ${player.isAvailable})',
      );

      // 7. The same word through both engines, start of call to end of audio.
      //    Not like for like — the voices differ, so the audio does — but it
      //    is the number a person actually waits through.
      final platform = FlutterTtsEngine();
      await platform.init();
      await platform.speak('outside');

      started = DateTime.now();
      await platform.speak('outside');
      final platformSpoke = DateTime.now().difference(started);

      started = DateTime.now();
      final cached = await store.read('outside');
      await player.play(cached!);
      final neuralSpoke = DateTime.now().difference(started);

      note(
        'one word, call to silence — platform ${platformSpoke.inMilliseconds} ms, '
        'cached neural ${neuralSpoke.inMilliseconds} ms '
        '(${audio.inMilliseconds} ms of it is the audio)',
      );

      await store.delete();
      await store.close();
      synthesizer.dispose();

      await File(p.join(documents.path, 'neural-bench.txt'))
          .writeAsString(report.toString());
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
