import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/features/speech/neural/audio_clip.dart';
import 'package:wordbridge/features/speech/neural/clip_player.dart';
import 'package:wordbridge/features/speech/neural/clip_store.dart';
import 'package:wordbridge/features/speech/neural/neural_engine.dart';
import 'package:wordbridge/features/speech/neural/synthesis_budget.dart';
import 'package:wordbridge/features/speech/neural/voice_model.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

/// Rung three: the product as it already ships.
class _PlatformVoice implements SpeechEngine {
  final spoken = <String>[];
  final utterances = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> speakUtterance(String text) async {
    spoken.add(text);
    utterances.add(text);
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<List<VoiceOption>> voices() async => const [];
  @override
  Future<void> useVoice(VoiceOption voice) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVolume(double volume) async {}
}

AudioClip clipOf(int bytes, {int fill = 7}) =>
    (pcm16: Uint8List(bytes)..fillRange(0, bytes, fill), sampleRate: 24000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late _PlatformVoice platform;
  late List<Uint8List> played;

  const channel = MethodChannel('org.wordbridge/clip_audio');

  setUp(() {
    documents = Directory.systemTemp.createTempSync('wordbridge-neural');
    platform = _PlatformVoice();
    played = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'play') {
            final arguments = call.arguments as Map<Object?, Object?>;
            played.add(arguments['pcm']! as Uint8List);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  Future<Directory> where() async => documents;

  NeuralSpeechEngine engineWith({
    Future<AudioClip?> Function(String text)? synthesise,
  }) => NeuralSpeechEngine(
    platform,
    documentsDirectory: where,
    player: ClipPlayer(channel: channel),
    models: VoiceModelStore(documentsDirectory: where),
    synthesise: synthesise,
  );

  Future<ClipStore> packFor(String voiceId, double speed) => ClipStore.open(
    root: ClipStore.directoryIn(
      Directory(p.join(documents.path, VoiceModelStore.folder)),
    ),
    packId: ClipStore.idFor(voiceId, speed),
  );

  group('rung 1 — the cache, and it never waits', () {
    test('a baked word plays from the pack', () async {
      final pack = await packFor('af_bella', 1.0);
      await pack.write('outside', clipOf(240, fill: 9));
      await pack.close();

      final engine = engineWith();
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.speak('outside');

      expect(played, hasLength(1));
      expect(played.single.lengthInBytes, 240);
      expect(platform.spoken, isEmpty, reason: 'the platform must not speak');
    });

    test('a lone capital I is normalised before it is looked up', () async {
      // The word every AAC user needs most. The cache is keyed on what the
      // engine would have been asked to say, so both halves have to agree.
      final pack = await packFor('af_bella', 1.0);
      await pack.write('i', clipOf(120));
      await pack.close();

      final engine = engineWith();
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.speak('I');

      expect(played, hasLength(1));
      expect(platform.spoken, isEmpty);
    });

    test('a two-word repair is joined rather than handed to another voice',
        () async {
      // A copula key that corrects the word before it speaks the pair — "are
      // you" — which is not a string anything baked. Both halves are, and this
      // app owns the samples.
      final pack = await packFor('af_bella', 1.0);
      await pack.write('are', clipOf(200));
      await pack.write('you', clipOf(160));
      await pack.close();

      final engine = engineWith();
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.speak('are you');

      expect(platform.spoken, isEmpty);
      expect(played, hasLength(1));
      // Both clips, plus the gap that keeps them from running together.
      expect(played.single.lengthInBytes, greaterThan(200 + 160));
    });

    test('a phrase with an unbaked word goes to the platform, now', () async {
      final pack = await packFor('af_bella', 1.0);
      await pack.write('are', clipOf(200));
      await pack.close();

      final engine = engineWith();
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.speak('are they');

      expect(played, isEmpty);
      expect(platform.spoken, ['are they']);
    });
  });

  group('rung 3 — the platform voice, and it is counted', () {
    test('an unbaked word speaks in the platform voice without waiting',
        () async {
      final engine = engineWith(
        synthesise: (_) async {
          fail('the tap path must never synthesise');
        },
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.speak('emergency');

      expect(platform.spoken, ['emergency']);
      expect(engine.fallbackCount, 1);
      expect(engine.fallbacks.single.text, 'emergency');
    });

    test('switching the voice off restores the platform exactly', () async {
      final pack = await packFor('af_bella', 1.0);
      await pack.write('outside', clipOf(240));
      await pack.close();

      final engine = engineWith();
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.useNeuralVoice(enabled: false);

      await engine.speak('outside');
      await engine.speakUtterance('I want to go outside');

      expect(played, isEmpty);
      expect(platform.spoken, ['outside', 'I want to go outside']);
      // Nothing is counted as a fallback, because nothing fell back.
      expect(engine.fallbackCount, 0);
    });

    test('the count is kept per sentence, with the reason', () async {
      final engine = engineWith(synthesise: (_) async => null);
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.speakUtterance('I want to go outside');

      expect(engine.fallbackCount, 1);
      expect(engine.fallbacks.single.reason, contains('could not be loaded'));
      expect(platform.utterances, ['I want to go outside']);
    });
  });

  group('rung 2 — live synthesis, under the budget', () {
    test('a sentence inside the budget speaks in the chosen voice', () async {
      final engine = engineWith(
        synthesise: (text) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return clipOf(300);
        },
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      engine.budget = const SynthesisBudget(
        base: Duration(milliseconds: 500),
        perWord: Duration(milliseconds: 100),
      );

      await engine.speakUtterance('I want to go outside');

      expect(played, hasLength(1));
      expect(platform.spoken, isEmpty);
      expect(engine.fallbackCount, 0);
    });

    test('what was synthesised is kept, so the next press is instant',
        () async {
      var calls = 0;
      final engine = engineWith(
        synthesise: (_) async {
          calls++;
          return clipOf(300);
        },
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      await engine.speakUtterance('I want to go outside');
      await engine.speakUtterance('I want to go outside');

      expect(calls, 1);
      expect(played, hasLength(2));
    });

    test('a sentence past the budget falls back rather than hanging',
        () async {
      final engine = engineWith(
        synthesise: (_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return clipOf(300);
        },
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      engine.budget = const SynthesisBudget(
        base: Duration(milliseconds: 40),
        perWord: Duration(milliseconds: 10),
      );

      await engine.speakUtterance('I want to go outside');

      expect(platform.utterances, ['I want to go outside']);
      expect(engine.fallbacks.single.reason, contains('took longer than'));
    });

    test('the late result is dropped, so nothing is said twice', () async {
      // If the fallback has already spoken, neural audio arriving afterwards
      // would say the sentence a second time in a different voice — and the
      // user cannot easily take back either of them.
      final completer = Completer<AudioClip?>();
      final engine = engineWith(synthesise: (_) => completer.future);
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      engine.budget = const SynthesisBudget(
        base: Duration(milliseconds: 30),
        perWord: Duration.zero,
      );

      await engine.speakUtterance('I want to go outside');
      expect(platform.utterances, hasLength(1));

      completer.complete(clipOf(300));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(played, isEmpty, reason: 'the late clip must never play');
    });

    test('a newer press wins, and the older one goes quiet', () async {
      final first = Completer<AudioClip?>();
      final engine = engineWith(
        synthesise: (text) async => text == 'the first sentence'
            ? first.future
            : clipOf(120),
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      final slow = engine.speakUtterance('the first sentence');
      // Long enough for the first press to be inside synthesis rather than
      // still reading the cache, which is the case the next test covers.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await engine.speakUtterance('the second sentence');
      expect(played, hasLength(1), reason: 'the newest press speaks');

      first.complete(clipOf(999));
      await slow;

      expect(
        played,
        hasLength(1),
        reason: 'the superseded sentence must not arrive behind the new one',
      );
      expect(played.single.lengthInBytes, 120);
    });

    test('a press superseded before it synthesises says nothing at all',
        () async {
      // Two taps in the same event-loop turn. The older one is dropped where
      // it stands rather than being allowed to speak over the newer.
      final engine = engineWith(synthesise: (_) async => clipOf(120));
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      final first = engine.speakUtterance('the first sentence');
      final second = engine.speakUtterance('the second sentence');
      await Future.wait([first, second]);

      expect(played, hasLength(1));
      expect(platform.utterances, isEmpty);
    });

    test('a model released mid-press still speaks, in the platform voice',
        () async {
      // Backgrounding the app gives the model's 833 MB back, and a press can
      // be in flight when it does. What must never happen is silence: nobody
      // in the room can see a sentence that was not spoken by anything.
      final engine = engineWith(
        synthesise: (_) async =>
            throw StateError('The neural voice model is not loaded.'),
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      await engine.speakUtterance('I want to go outside');

      expect(platform.utterances, ['I want to go outside']);
      expect(engine.fallbacks.single.reason, contains('the voice failed'));
    });

    test('a string the model cannot make anything of still speaks', () async {
      final engine = engineWith(
        synthesise: (_) async => throw ArgumentError('no phonemes'),
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      await engine.speakUtterance('\u{1F600}\u{1F600}\u{1F600}');

      expect(platform.utterances, hasLength(1));
      expect(engine.fallbackCount, 1);
    });

    test('the budget grows with the sentence', () async {
      // A pure fixed budget picks one length and fails the rest: generous
      // enough for twenty words and a two-word answer hangs; tight enough for
      // two and the longest, most deliberate sentences never arrive.
      final engine = engineWith(
        synthesise: (text) async {
          await Future<void>.delayed(
            Duration(milliseconds: 30 * SynthesisBudget.wordsIn(text)),
          );
          return clipOf(120);
        },
      );
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      engine.budget = const SynthesisBudget(
        base: Duration(milliseconds: 40),
        perWord: Duration(milliseconds: 60),
      );

      await engine.speakUtterance('yes');
      await engine.speakUtterance('one two three four five six seven eight');

      expect(platform.utterances, isEmpty);
      expect(played, hasLength(2));
    });
  });

  group('changing the voice', () {
    test('the old voice clips are not read by the new one', () async {
      final bella = await packFor('af_bella', 1.0);
      await bella.write('outside', clipOf(240));
      await bella.close();

      final engine = engineWith();
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      await engine.useNeuralVoice(enabled: true, voiceId: 'bm_george');
      await engine.speak('outside');

      expect(played, isEmpty);
      expect(platform.spoken, ['outside']);
    });

    test('changing the speed is a different pack, because it is baked in',
        () async {
      final ordinary = await packFor('af_bella', 1.0);
      await ordinary.write('outside', clipOf(240));
      await ordinary.close();

      final engine = engineWith();
      await engine.useNeuralVoice(
        enabled: true,
        voiceId: 'af_bella',
        speed: 0.82,
      );
      await engine.speak('outside');

      expect(platform.spoken, ['outside']);
    });

    test('pruning keeps the pack in use', () async {
      for (final id in ['af_bella', 'bm_george', 'af_sky']) {
        final pack = await packFor(id, 1.0);
        await pack.write('outside', clipOf(2400));
        await pack.close();
      }

      final engine = engineWith();
      await engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');
      expect(await engine.pruneOtherVoices(), greaterThan(0));

      await engine.speak('outside');
      expect(played, hasLength(1));
    });
  });
}
