import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/neural/bake_vocabulary.dart';
import 'package:wordbridge/features/speech/neural/clip_player.dart';
import 'package:wordbridge/features/speech/neural/clip_store.dart';
import 'package:wordbridge/features/speech/neural/neural_engine.dart';
import 'package:wordbridge/features/speech/neural/voice_model.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/main.dart';

/// The voice that speaks when the neural one has not been made yet.
class _PlatformVoice implements SpeechEngine {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> speakUtterance(String text) => speak(text);
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

/// Starting the bake without anybody pressing a button (§4.62).
///
/// The half that already worked is the interruption: `BakeJob` stands aside for
/// every utterance and picks up six seconds after the last word. What did not
/// work is beginning — nothing started a bake but a button on a settings
/// screen, so a caregiver who switched the voice on and closed the app came
/// back to a board that fell back on every word, with nothing on screen to
/// suggest why.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WordbridgeDatabase db;
  late Directory documents;
  late String vocabularyId;
  late String profileId;

  const channel = MethodChannel('org.wordbridge/clip_audio');

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    documents = Directory.systemTemp.createTempSync('wordbridge-autostart');

    final ts = nowMs();
    profileId = newId();
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: 'Maya',
            vocabLevel: const Value(3),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    vocabularyId = await seedCoreBoardSet(db, profileId: profileId);
  });

  tearDown(() async {
    await db.close();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  Future<Directory> where() async => documents;

  /// Counts what it was asked to make, so "did a bake start" is answerable
  /// without 345 MB of weights.
  ({NeuralSpeechEngine engine, List<String> made}) engineThatRecords() {
    final made = <String>[];
    return (
      engine: NeuralSpeechEngine(
        _PlatformVoice(),
        documentsDirectory: where,
        player: ClipPlayer(channel: channel),
        models: VoiceModelStore(documentsDirectory: where),
        synthesize: (text) async {
          made.add(text);
          return (pcm16: Uint8List(20), sampleRate: 24000);
        },
      ),
      made: made,
    );
  }

  Future<ClipStore> packFor(String voiceId, double speed) => ClipStore.open(
    root: ClipStore.directoryIn(
      Directory(p.join(documents.path, VoiceModelStore.folder)),
    ),
    packId: ClipStore.idFor(voiceId, speed),
  );

  Future<ProfileSettings> settingsWith(Map<String, Object?> values) async {
    final settings = ProfileSettings(db, profileId);
    await settings.load();
    for (final entry in values.entries) {
      await settings.set(entry.key, entry.value);
    }
    return settings;
  }

  /// The cheap question, asked before the expensive one.
  ///
  /// A session opening onto a fully baked board must not load 833 MB of
  /// weights to discover there is nothing to do, so this is answered from the
  /// pack's index and nothing else.
  group('whether there is anything left to make', () {
    test('is no when the voice is off, whatever the pack holds', () async {
      final e = engineThatRecords();
      await e.engine.useNeuralVoice(enabled: false, voiceId: 'af_bella');

      expect(e.engine.needsBaking(const ['want', 'more']), isFalse);
    });

    test('is yes when a word is missing', () async {
      final e = engineThatRecords();
      await e.engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      expect(e.engine.needsBaking(const ['want']), isTrue);
    });

    test('is no when every word is already in the pack', () async {
      final pack = await packFor('af_bella', 1.0);
      await pack.write('want', (pcm16: Uint8List(8), sampleRate: 24000));
      await pack.write('more', (pcm16: Uint8List(8), sampleRate: 24000));
      await pack.close();

      final e = engineThatRecords();
      await e.engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      expect(e.engine.needsBaking(const ['want', 'more']), isFalse);
    });

    test('is yes when one of many is missing', () async {
      // The ordinary state of a bake that was interrupted, and the reason this
      // is `any` rather than a count.
      final pack = await packFor('af_bella', 1.0);
      await pack.write('want', (pcm16: Uint8List(8), sampleRate: 24000));
      await pack.close();

      final e = engineThatRecords();
      await e.engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      expect(e.engine.needsBaking(const ['want', 'more']), isTrue);
    });
  });

  group('opening a session', () {
    test('picks the bake up where the last one stopped', () async {
      final e = engineThatRecords();
      final settings = await settingsWith({
        'neuralVoice': true,
        'neuralVoiceId': 'af_bella',
      });
      await e.engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      await resumeBaking(e.engine, settings, db, vocabularyId);
      final job = e.engine.bake;
      expect(job, isNotNull, reason: 'nothing else in the app starts one');
      await job!.settle();

      expect(e.made, isNotEmpty);
      expect(
        e.made,
        containsAll(await bakeVocabulary(db, vocabularyId)),
        reason: 'the whole board, filtered against what the pack already has',
      );
    });

    test('makes only what is missing', () async {
      // The pack is the progress: nothing records where a bake got to, so a
      // resumed one that re-made finished words would spend the twenty-seven
      // minutes again on every launch.
      final words = await bakeVocabulary(db, vocabularyId);
      final pack = await packFor('af_bella', 1.0);
      for (final word in words.take(words.length - 1)) {
        await pack.write(word, (pcm16: Uint8List(8), sampleRate: 24000));
      }
      await pack.close();

      final e = engineThatRecords();
      final settings = await settingsWith({
        'neuralVoice': true,
        'neuralVoiceId': 'af_bella',
      });
      await e.engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      await resumeBaking(e.engine, settings, db, vocabularyId);
      await e.engine.bake?.settle();

      expect(e.made, [words.last]);
    });

    test('starts nothing for a profile using the device voice', () async {
      final e = engineThatRecords();
      final settings = await settingsWith({'neuralVoice': false});

      await resumeBaking(e.engine, settings, db, vocabularyId);

      expect(e.engine.bake, isNull);
      expect(e.made, isEmpty);
    });

    test('starts nothing where the board is already made', () async {
      // And this is the case that has to stay cheap: the answer comes from the
      // pack's index, so no model is loaded to reach it.
      final words = await bakeVocabulary(db, vocabularyId);
      final pack = await packFor('af_bella', 1.0);
      for (final word in words) {
        await pack.write(word, (pcm16: Uint8List(8), sampleRate: 24000));
      }
      await pack.close();

      final e = engineThatRecords();
      final settings = await settingsWith({
        'neuralVoice': true,
        'neuralVoiceId': 'af_bella',
      });
      await e.engine.useNeuralVoice(enabled: true, voiceId: 'af_bella');

      await resumeBaking(e.engine, settings, db, vocabularyId);

      expect(e.engine.bake, isNull, reason: 'no job, so no model was loaded');
      expect(e.made, isEmpty);
    });

    test('does not take the session down when it cannot start', () async {
      // This runs on the path to the board. Whatever it hits, the person can
      // still talk — in the device voice, which is §4.4 and is a product.
      final e = engineThatRecords();
      final settings = await settingsWith({'neuralVoice': true});
      // Never given a pack, so there is nothing to bake into.

      await expectLater(
        resumeBaking(e.engine, settings, db, vocabularyId),
        completes,
      );
    });
  });
}
