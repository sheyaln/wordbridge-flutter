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
import 'package:wordbridge/features/speech/neural/neural_engine.dart';
import 'package:wordbridge/features/speech/neural/synthesis_budget.dart';
import 'package:wordbridge/features/speech/neural/voice_model.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

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

/// An engine that answers for itself without 833 MB of weights.
///
/// Measuring is the one step on the §4.62 chain that genuinely loads the
/// model, and a widget test cannot have one. Overridden rather than stepped
/// around, because whether the measurement is taken *before* the bake is part
/// of what is under test: unmeasured, the bake runs on the floor device's
/// budget and every word waits three times longer than it needs to.
class _TestNeural extends NeuralSpeechEngine {
  _TestNeural(
    super.platform, {
    super.documentsDirectory,
    super.player,
    super.models,
    super.synthesize,
  });

  int measured = 0;

  @override
  Future<SynthesisBudget?> measureBudget() async {
    measured++;
    return SynthesisBudget.fitted;
  }
}

/// §4.45 again, from the other end. The two voices went onto one screen, and
/// the choice between them ended up under two screens of dials — so a
/// caregiver configured a voice at length before being told which one was
/// doing the talking.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WordbridgeDatabase db;
  late Directory documents;
  late String vocabularyId;
  late ProfileSettings settings;
  late _TestNeural engine;

  Future<Directory> where() async => documents;

  void useEngine({ClipPlayer? player}) {
    engine = _TestNeural(
      _PlatformVoice(),
      documentsDirectory: where,
      player:
          player ??
          ClipPlayer(channel: const MethodChannel('org.wordbridge/clip_audio')),
      models: VoiceModelStore(documentsDirectory: where),
      synthesize: (text) async => (pcm16: Uint8List(20), sampleRate: 24000),
    );
  }

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    documents = Directory.systemTemp.createTempSync('wordbridge-chooser');

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

    useEngine();
  });

  tearDown(() async {
    // The bake parks on a file write a widget test's clock never delivers, so
    // it is stopped rather than waited for.
    engine.bake?.dispose();
    await db.close();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  /// The four things `VoiceModelFiles.arePresent` insists on, with bytes in
  /// them. Enough to count as installed, nowhere near enough to be a voice.
  void installModel() {
    final model = Directory(
      p.join(documents.path, VoiceModelStore.folder, 'model'),
    )..createSync(recursive: true);
    File(p.join(model.path, 'model.onnx')).writeAsBytesSync(Uint8List(64));
    File(p.join(model.path, 'voices.bin')).writeAsBytesSync(Uint8List(64));
    File(p.join(model.path, 'tokens.txt')).writeAsStringSync('a 1\n');
    final espeak = Directory(p.join(model.path, 'espeak-ng-data'))
      ..createSync();
    File(p.join(espeak.path, 'en_dict')).writeAsBytesSync(Uint8List(64));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Renders the whole screen at once. Both voices' settings run well past a
  /// tablet's fold, and a lazy list would not build the half being asserted
  /// about.
  Future<void> open(WidgetTester tester, {SpeechEngine? speech}) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceScreen(
          speech: speech ?? engine,
          settings: settings,
          db: db,
          vocabularyId: vocabularyId,
        ),
      ),
    );
    await settle(tester);
  }

  Finder header(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(VoiceHeader));

  Finder option(String name) => find.widgetWithText(RadioListTile<bool>, name);

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  group('the choice of voice comes before the settings that answer to it', () {
    testWidgets('nothing on the screen is above it', (tester) async {
      installModel();
      await open(tester);

      final choice = top(tester, header('Which voice speaks'));

      expect(choice, lessThan(top(tester, header('Device voice'))));
      expect(choice, lessThan(top(tester, header('Neural voice'))));
      expect(choice, lessThan(top(tester, header('Tone'))));
      expect(choice, lessThan(top(tester, find.text('Speed'))));
      expect(
        choice,
        lessThan(top(tester, find.text('Which voice'))),
        reason: 'the list of device voices is above the question it answers',
      );
    });

    testWidgets('and it is two voices by name, not one of them switched on', (
      tester,
    ) async {
      // Off, "use the neural voice" names one of the two and leaves the other
      // unnamed — and the unnamed one is the one that is speaking.
      installModel();
      await open(tester);

      expect(option('Device voice'), findsOneWidget);
      expect(option('Neural voice'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, 'Neural voice'), findsNothing);
      expect(find.text('Use the neural voice'), findsNothing);
    });

    testWidgets('the voice that was chosen is the one configured first', (
      tester,
    ) async {
      installModel();
      await open(tester);

      expect(
        top(tester, header('Device voice')),
        lessThan(top(tester, header('Neural voice'))),
      );

      await tester.tap(option('Neural voice'));
      await settle(tester);

      expect(
        top(tester, header('Neural voice')),
        lessThan(top(tester, header('Device voice'))),
        reason: 'the voice just chosen was left below the one that was not',
      );
    });

    testWidgets('the other voice is still there, named as the fallback', (
      tester,
    ) async {
      // §4.5. The device voice is not the alternative to the neural one, it is
      // what the neural one falls back to for every word not yet made — so it
      // is never hidden, whichever is chosen.
      installModel();
      await open(tester);
      await tester.tap(option('Neural voice'));
      await settle(tester);

      expect(header('Device voice'), findsOneWidget);
      expect(
        find.textContaining('has not made yet'),
        findsOneWidget,
        reason: 'the device voice reads as switched off rather than as next',
      );
      for (final control in ['Which voice', 'Tone', 'Speed', 'Pitch']) {
        expect(find.text(control), findsWidgets);
      }
    });
  });

  group('which voice each dial moves', () {
    testWidgets('is not said while only one voice can hear them', (
      tester,
    ) async {
      installModel();
      await open(tester);

      expect(find.textContaining('the neural voice is given'), findsNothing);
      expect(find.textContaining('applies to both'), findsNothing);
    });

    testWidgets('and is said on every dial once the other one is speaking', (
      tester,
    ) async {
      // Speed is handed to `useNeuralVoice`; pitch, volume and tone never
      // leave the platform engine. A caregiver who drags pitch, hears no
      // change in the voice that is speaking and concludes the dial is broken
      // is right about what they heard and wrong about why.
      installModel();
      await open(tester);
      await tester.tap(option('Neural voice'));
      await settle(tester);

      expect(
        find.textContaining('Speed is set with the device voice below'),
        findsOneWidget,
      );
      expect(
        find.textContaining('speed is the only one the neural voice is given'),
        findsOneWidget,
      );
      expect(
        find.textContaining('The neural voice is not given it'),
        findsOneWidget,
        reason: 'tone reads as though it shaped both voices',
      );
    });
  });

  group('what choosing the neural voice still sets off', () {
    testWidgets('the measurement, then the bake, without being asked', (
      tester,
    ) async {
      // §4.62. Both of these were buttons, and a caregiver who switched the
      // voice on and walked away got a board that fell back to the device
      // voice on every word indefinitely, with nothing on screen to say why.
      // Moving the chooser must not put that back.
      installModel();
      await open(tester);

      await tester.tap(option('Neural voice'));
      await settle(tester);

      expect(settings.neuralVoice, isTrue, reason: 'nothing was written down');
      expect(engine.isOn, isTrue, reason: 'useNeuralVoice was never called');
      expect(
        engine.measured,
        1,
        reason: 'the bake would run on the floor device\'s budget',
      );
      expect(settings.synthesisBudgetMeasured, isTrue);
      expect(
        engine.bake,
        isNotNull,
        reason: 'nothing else on this screen starts one',
      );
      expect(engine.bake!.total, greaterThan(0));
    });

    testWidgets('and choosing the device voice back gives it up', (
      tester,
    ) async {
      installModel();
      await open(tester);
      await tester.tap(option('Neural voice'));
      await settle(tester);

      await tester.tap(option('Device voice'));
      await settle(tester);

      expect(settings.neuralVoice, isFalse);
      expect(engine.isOn, isFalse);
    });
  });

  group('what the top says when there is no neural voice to choose', () {
    testWidgets('a build without the engine names its one voice and asks '
        'nothing', (tester) async {
      // A chooser with a single row is not a choice, it is a claim that
      // something was decided. What it is for — that no voice speaks unnamed —
      // the header does on its own.
      await open(tester, speech: _PlatformVoice());

      expect(header('Which voice speaks'), findsNothing);
      expect(find.byType(RadioListTile<bool>), findsNothing);
      expect(header('Device voice'), findsOneWidget);

      for (final control in ['Which voice', 'Tone', 'Speed', 'Pitch']) {
        expect(find.text(control), findsOneWidget);
      }
    });

    testWidgets('a model that is not downloaded is still a voice with a name', (
      tester,
    ) async {
      await open(tester);

      expect(header('Which voice speaks'), findsOneWidget);
      expect(
        tester.widget<RadioListTile<bool>>(option('Neural voice')).enabled,
        isFalse,
      );
      expect(find.textContaining('Not downloaded yet'), findsOneWidget);
      expect(
        find.text('Download the voice'),
        findsOneWidget,
        reason: 'the row says what is missing and nothing offers to fetch it',
      );
    });

    testWidgets('a device that cannot play one says so on the row itself', (
      tester,
    ) async {
      // `ClipPlayer` only learns it has no platform under it by asking once,
      // so the refusal has to be provoked before the screen is built.
      const channel = MethodChannel('org.wordbridge/clip_audio');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(code: 'unavailable'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final dead = ClipPlayer(channel: channel);
      await dead.play((pcm16: Uint8List(0), sampleRate: 24000));
      expect(dead.isAvailable, isFalse, reason: 'the player still works');

      useEngine(player: dead);
      installModel();
      await open(tester);

      expect(
        tester.widget<RadioListTile<bool>>(option('Neural voice')).enabled,
        isFalse,
      );
      expect(
        find.textContaining('This device cannot play one'),
        findsOneWidget,
      );
    });

    testWidgets('a profile carrying the voice onto a tablet without it is '
        'told what is speaking', (tester) async {
      // The setting outlives the model: a restore, or a profile moved between
      // devices. The row it is set on has to admit that the device voice is
      // doing the talking, and stay live enough to say so.
      await settings.set('neuralVoice', true);
      await open(tester);

      expect(
        find.textContaining('the board is speaking with the device voice'),
        findsOneWidget,
      );

      await tester.tap(option('Device voice'));
      await settle(tester);

      expect(
        settings.neuralVoice,
        isFalse,
        reason: 'there was no way off a voice that cannot speak',
      );
    });
  });
}
