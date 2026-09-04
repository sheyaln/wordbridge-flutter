import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/caregiver/voice_screen.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/neural/clip_player.dart';
import 'package:wordbridge/features/speech/neural/clip_store.dart';
import 'package:wordbridge/features/speech/neural/neural_engine.dart';
import 'package:wordbridge/features/speech/neural/synthesis_budget.dart';
import 'package:wordbridge/features/speech/neural/voice_model.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

/// The Speed dial, under a neural voice.
///
/// Kokoro is *given* speed when it generates, so it is inside the audio rather
/// than applied to it on the way out. A pack is therefore one voice at one
/// speed, and moving this dial does not adjust the words already made — it
/// invalidates every one of them.
///
/// The dial used to write `speechRate` and stop. Nothing re-pointed the engine,
/// so for the rest of the session the board kept speaking out of the pack for
/// the *old* speed while the screen said, in as many words, that speed
/// "applies to both". The next launch asked for the pack at the new speed,
/// opened an empty one, and fell back to the device voice on every word; the
/// next voice change ran `pruneOtherVoices` and deleted the only copy of the
/// old pack. Up to an hour of synthesis, discarded by a slider, with nothing
/// on screen ever having said that was the trade.
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

class _TestNeural extends NeuralSpeechEngine {
  _TestNeural(
    super.platform, {
    super.documentsDirectory,
    super.player,
    super.models,
    super.synthesize,
  });

  @override
  Future<SynthesisBudget?> measureBudget() async => SynthesisBudget.fitted;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WordbridgeDatabase db;
  late Directory documents;
  late String vocabularyId;
  late ProfileSettings settings;
  late _TestNeural engine;

  Future<Directory> where() async => documents;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    documents = Directory.systemTemp.createTempSync('wordbridge-speed');

    final ts = nowMs();
    final profileId = newId();
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

    settings = ProfileSettings(db, profileId);
    await settings.load();

    engine = _TestNeural(
      _PlatformVoice(),
      documentsDirectory: where,
      player: ClipPlayer(
        channel: const MethodChannel('org.wordbridge/clip_audio'),
      ),
      models: VoiceModelStore(documentsDirectory: where),
      synthesize: (text) async => (pcm16: Uint8List(20), sampleRate: 24000),
    );
  });

  tearDown(() async {
    engine.bake?.dispose();
    await db.close();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  /// Deliberately no installed model in these tests.
  ///
  /// `_getGoing` stops at `_installed`, so leaving it out keeps the bake — and
  /// the file writes it leaves running after the last pump — out of a test
  /// about what the dial does. That the bake restarts afterwards is
  /// `neural_autostart_test`'s to say.

  /// Words already made, written the way a finished bake leaves them.
  ///
  /// Put on disk before the engine opens the pack, so `count` is what a
  /// caregiver who has waited out a bake would actually be shown. Going
  /// through the running engine would not do: it holds its index in memory and
  /// a second handle on the same file is invisible to it.
  void bakeInto(String packId, List<String> words) {
    final root = ClipStore.directoryIn(
      Directory(p.join(documents.path, VoiceModelStore.folder)),
    )..createSync(recursive: true);

    final pack = File(p.join(root.path, '$packId.pack'));
    final index = StringBuffer('#wordbridge-clips 1 24000\n');
    var offset = 0;
    for (final word in words) {
      const length = 20;
      pack.writeAsBytesSync(Uint8List(length), mode: FileMode.append);
      index.writeln('$offset,$length,${base64Encode(utf8.encode(word))}');
      offset += length;
    }
    File(p.join(root.path, '$packId.index')).writeAsStringSync('$index');
  }

  /// Lets the real work land as well as the fake clock.
  ///
  /// A pack is a pair of files, so opening one is real asynchronous I/O — and
  /// a widget test's clock does not deliver that. Pumping alone leaves the
  /// engine mid-move forever: the first version of this file hung for
  /// seventeen minutes on `await engine.useNeuralVoice`, because the read
  /// inside it can never complete in a zone where only timers are advanced.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceScreen(
          speech: engine,
          settings: settings,
          db: db,
          vocabularyId: vocabularyId,
        ),
      ),
    );
    await settle(tester);
  }

  /// Speed is the first of the three dials, and the only one that reaches the
  /// neural voice. Dragged past the end so it lands on the maximum rather than
  /// on wherever the slider's pixel arithmetic put it.
  Future<void> dragSpeedToMax(WidgetTester tester) async {
    await tester.drag(find.byType(Slider).first, const Offset(2000, 0));
    await settle(tester);
  }

  /// The neural voice on, on the pack for the speed the profile is set to.
  Future<void> turnOnAt(WidgetTester tester, double speed) async {
    await settings.set('speechRate', speed);
    await settings.set('neuralVoice', true);
    await tester.runAsync(
      () => engine.useNeuralVoice(enabled: true, speed: speed),
    );
  }

  testWidgets('moving Speed asks before it throws the pack away', (
    tester,
  ) async {
    bakeInto(engine.packIdAt(1.0), ['want', 'more', 'stop']);
    await turnOnAt(tester, 1.0);
    await open(tester);

    expect(engine.clips?.count, 3, reason: 'the premise: words already made');

    await dragSpeedToMax(tester);

    expect(
      find.text('Speak at the new speed?'),
      findsOneWidget,
      reason: 'the pack was invalidated without the question being asked',
    );
    expect(find.textContaining('3 words already made'), findsOneWidget);
  });

  testWidgets('keeping the old speed puts the dial back', (tester) async {
    bakeInto(engine.packIdAt(1.0), ['want', 'more', 'stop']);
    await turnOnAt(tester, 1.0);
    await open(tester);

    await dragSpeedToMax(tester);
    await tester.tap(find.text('Keep the old speed'));
    await settle(tester);

    expect(
      settings.speechRate,
      1.0,
      reason:
          'the device voice was left at the new speed while the neural voice '
          'stayed at the old one, and the screen says the dial sets both',
    );
    expect(engine.speed, 1.0);
    expect(engine.clips?.count, 3, reason: 'the words were thrown away anyway');
  });

  testWidgets('agreeing moves the engine onto the new pack, now', (
    tester,
  ) async {
    bakeInto(engine.packIdAt(1.0), ['want', 'more', 'stop']);
    await turnOnAt(tester, 1.0);
    await open(tester);

    final was = engine.clips?.packId;
    await dragSpeedToMax(tester);
    await tester.tap(find.text('Change'));
    await settle(tester);

    // Dragged, not assigned: a slider's far end arrives as
    // 1.7999999999999998, which is the maximum and is not equal to it.
    expect(settings.speechRate, closeTo(VoiceScreen.speedMax, 0.001));
    expect(
      engine.speed,
      closeTo(VoiceScreen.speedMax, 0.001),
      reason:
          'the engine was left on the old speed, so the board goes on speaking '
          'at it until the app is next opened',
    );
    expect(
      engine.clips?.packId,
      isNot(was),
      reason: 'still reading clips that were made at the speed just abandoned',
    );
    expect(engine.clips?.packId, engine.packIdAt(VoiceScreen.speedMax));
  });

  testWidgets('the pack it moved off is still on disk afterwards', (
    tester,
  ) async {
    // The question promises this in as many words: "the old ones are kept, so
    // going back to that speed brings them back". A prune here would make the
    // screen a liar and turn a nudge into an hour of work.
    final old = engine.packIdAt(1.0);
    bakeInto(old, ['want', 'more', 'stop']);
    await turnOnAt(tester, 1.0);
    await open(tester);

    await dragSpeedToMax(tester);
    await tester.tap(find.text('Change'));
    await settle(tester);

    final root = ClipStore.directoryIn(
      Directory(p.join(documents.path, VoiceModelStore.folder)),
    );
    expect(
      File(p.join(root.path, '$old.pack')).existsSync(),
      isTrue,
      reason: 'the words made at the old speed were deleted, not kept',
    );
    expect(File(p.join(root.path, '$old.index')).existsSync(), isTrue);
  });

  testWidgets('with nothing made yet there is nothing to ask about', (
    tester,
  ) async {
    await turnOnAt(tester, 1.0);
    await open(tester);

    await dragSpeedToMax(tester);

    expect(
      find.text('Speak at the new speed?'),
      findsNothing,
      reason: 'an empty pack has no work in it to warn about losing',
    );
    expect(
      engine.speed,
      closeTo(VoiceScreen.speedMax, 0.001),
      reason: 'the engine still has to follow the dial',
    );
  });

  test('two speeds that round to the same hundredth are one pack', () {
    // What stops the question above being asked over nothing. Speed goes into
    // the pack name rounded, so a thumb that moved a thousandth has changed
    // no clip and must not cost a caregiver an hour of re-synthesis. Asserted
    // here rather than through the dial, because a Slider takes its value from
    // where the finger lands rather than how far it travelled and so cannot
    // express a nudge this small.
    expect(engine.packIdAt(1.0), engine.packIdAt(1.0004));
    expect(engine.packIdAt(1.0), isNot(engine.packIdAt(1.01)));
  });
}
