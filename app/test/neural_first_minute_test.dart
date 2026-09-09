import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/caregiver/voice_screen.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/neural/clip_player.dart';
import 'package:wordbridge/features/speech/neural/synthesis_budget.dart';
import 'package:wordbridge/features/speech/neural/neural_engine.dart';
import 'package:wordbridge/features/speech/neural/resume_bake.dart';
import 'package:wordbridge/features/speech/neural/voice_model.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

/// The first minute with the neural voice (§4.79).
///
/// What somebody actually does: they choose the neural voice, and they go
/// straight back to the board to hear it. They do not scroll the settings
/// page, because they believe they are finished with it.
///
/// Everything here follows from that. Choosing the voice has to start the
/// download, because a Download button four headings further down is a button
/// that never gets pressed. What is happening has to be on the row that was
/// just chosen. And the synthesis has to begin on its own when the model lands
/// — including when the screen that started the download has been closed,
/// which it will have been.
class _PlatformVoice implements SpeechEngine {
  @override
  Future<void> speak(String text) async {}
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

/// A download nothing has to reach the network for.
class _FakeModels extends VoiceModelStore {
  _FakeModels({required super.documentsDirectory});

  final _updates = StreamController<ModelProgress>.broadcast();

  /// How many times somebody asked for the model. The number under test in
  /// half of this file: once, from choosing the voice, and never twice.
  int asked = 0;

  bool present = false;
  bool _running = false;

  @override
  Future<bool> isInstalled() async => present;

  /// How much of the archive is on the disk. Set to the whole of it to stand
  /// for an app killed after the download and before the unpack.
  int downloaded = 0;

  @override
  Future<int> downloadedBytes() async => downloaded;

  @override
  Future<bool> get isUnpackingLeft async =>
      !present && downloaded >= published.downloadBytes;

  @override
  Future<int> bytesOnDisk() async => present ? 100 << 20 : 0;

  @override
  bool get isInstalling => _running;

  @override
  Stream<ModelProgress>? get runningInstall =>
      _running ? _updates.stream : null;

  @override
  Stream<ModelProgress> install() {
    asked++;
    _running = true;
    return _updates.stream;
  }

  /// Reports progress the way a real download does.
  void report(ModelProgress progress) => _updates.add(progress);

  /// Lands the model, the way a finished download does.
  void finish() {
    present = true;
    _updates.add((
      phase: ModelPhase.installed,
      bytes: 100 << 20,
      totalBytes: 100 << 20,
      detail: null,
    ));
  }

  Future<void> close() => _updates.close();
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
  late _FakeModels models;

  Future<Directory> where() async => documents;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    documents = Directory.systemTemp.createTempSync('wordbridge-first-minute');

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

    models = _FakeModels(documentsDirectory: where);
    engine = _TestNeural(
      _PlatformVoice(),
      documentsDirectory: where,
      player: ClipPlayer(
        channel: const MethodChannel('org.wordbridge/clip_audio'),
      ),
      models: models,
      synthesize: (text) async => (pcm16: Uint8List(20), sampleRate: 24000),
    );
  });

  tearDown(() async {
    // The bake parks on a file write a widget test's clock never delivers, so
    // it is stopped rather than waited for.
    engine.bake?.pause();
    engine.bake?.dispose();
    await models.close();
    await db.close();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
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

  Finder neuralOption() =>
      find.widgetWithText(RadioListTile<bool>, 'Neural voice');

  Future<void> chooseNeural(WidgetTester tester) async {
    await tester.tap(neuralOption());
    await settle(tester);
  }

  group('choosing the voice', () {
    testWidgets('can be done before it is downloaded', (tester) async {
      // The download is what choosing it starts, not what has to happen first.
      // A row that cannot be pressed until somebody has found a button further
      // down the page is a row nobody ever presses.
      await open(tester);

      final row = tester.widget<RadioListTile<bool>>(neuralOption());
      expect(row.enabled, isTrue);
    });

    testWidgets('starts the download, without being asked again', (
      tester,
    ) async {
      await open(tester);
      expect(models.asked, 0);

      await chooseNeural(tester);

      expect(settings.neuralVoice, isTrue);
      expect(
        models.asked,
        1,
        reason:
            'choosing the voice did not fetch it, so the board would have '
            'gone on speaking in the device voice with nothing to say why',
      );
    });

    testWidgets('and asks for it once, not once per rebuild', (tester) async {
      await open(tester);
      await chooseNeural(tester);
      await settle(tester);
      await settle(tester);

      expect(models.asked, 1);
    });

    testWidgets('choosing the device voice fetches nothing', (tester) async {
      await open(tester);

      await tester.tap(
        find.widgetWithText(RadioListTile<bool>, 'Device voice'),
      );
      await settle(tester);

      expect(models.asked, 0);
      expect(settings.neuralVoice, isFalse);
    });
  });

  group('what is happening is on the row that was chosen', () {
    /// The top of the device voice's own settings. Anything above this line is
    /// visible to somebody who has not scrolled.
    double deviceBlock(WidgetTester tester) => tester
        .getTopLeft(
          find.ancestor(
            of: find.text('Device voice'),
            matching: find.byType(VoiceHeader),
          ),
        )
        .dy;

    testWidgets('the download reports under the voice it belongs to', (
      tester,
    ) async {
      await open(tester);
      await chooseNeural(tester);

      // Round decimal megabytes, because that is how the screen prints them.
      models.report((
        phase: ModelPhase.downloading,
        bytes: 40000000,
        totalBytes: 100000000,
        detail: null,
      ));
      await settle(tester);

      expect(find.text('Downloading the voice'), findsOneWidget);
      expect(find.textContaining('40 MB of 100 MB'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Downloading the voice')).dy,
        lessThan(deviceBlock(tester)),
        reason: 'the progress is below the fold nobody scrolls past',
      );
    });

    testWidgets('and so does the synthesis once the model is here', (
      tester,
    ) async {
      models.present = true;
      await open(tester);
      await chooseNeural(tester);

      expect(find.text('Making words in advance'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Making words in advance')).dy,
        lessThan(deviceBlock(tester)),
      );
    });

    testWidgets('the send-info switch is up here too', (tester) async {
      // Put where it can be turned off without hunting for it: it sends
      // timings off the device, and somebody who wants it off wants it off
      // now rather than after four headings.
      models.present = true;
      await open(tester);
      await chooseNeural(tester);

      final label = find.textContaining('how the neural voice is performing');
      expect(label, findsOneWidget);
      expect(tester.getTopLeft(label).dy, lessThan(deviceBlock(tester)));
    });

    testWidgets('and none of it is there while the device voice speaks', (
      tester,
    ) async {
      // The row is not chosen, so there is nothing happening to report and a
      // progress bar under it would describe work nobody asked for.
      await open(tester);

      expect(find.text('Downloading the voice'), findsNothing);
      expect(find.text('Making words in advance'), findsNothing);
    });
  });

  group('the synthesis starts on its own', () {
    test('when a download that is already running lands', () async {
      // The case that was broken: the settings screen is where a download is
      // watched, and it is the screen somebody leaves the moment they have
      // chosen the voice.
      await settings.set('neuralVoice', true);
      await engine.useNeuralVoice(enabled: true);
      models.install();

      final watch = bakeWhenInstalled(engine, settings, db, vocabularyId);
      expect(
        watch,
        isNotNull,
        reason: 'nothing was left watching the download',
      );
      addTearDown(() => watch?.cancel());

      models.finish();

      // The bake reads the board out of the database before it starts, so this
      // waits on real work rather than on a fixed number of microtasks.
      for (var i = 0; i < 100 && engine.bake == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(engine.bake, isNotNull, reason: 'the synthesis never began');
      expect(engine.bake!.isRunning, isTrue);

      // Stopped and waited for, before the test ends. A loop still running
      // afterwards notifies a disposed listener and fails the test it already
      // passed.
      engine.bake!.pause();
      await engine.bake!.settle();
    });

    test('and it attaches rather than starting one', () async {
      // A session must not put hundreds of megabytes on a household's
      // connection because a setting says the voice is on.
      await settings.set('neuralVoice', true);

      final watch = bakeWhenInstalled(engine, settings, db, vocabularyId);

      expect(watch, isNull);
      expect(models.asked, 0);
    });

    test('and does nothing for a profile on the device voice', () async {
      models.install();

      expect(bakeWhenInstalled(engine, settings, db, vocabularyId), isNull);
    });
  });

  /// An install killed between the download and the unpack (§4.79).
  ///
  /// The bytes are paid for and on the disk. Nothing anywhere finished the
  /// second half, so the person was left with a voice that is downloaded, not
  /// installed, and a screen offering them a download they had already waited
  /// through.
  group('an install interrupted after the download', () {
    test('is finished on the next launch', () async {
      await settings.set('neuralVoice', true);
      await engine.useNeuralVoice(enabled: true);
      models.downloaded = models.published.downloadBytes;

      final watch = await finishInterruptedInstall(
        engine,
        settings,
        db,
        vocabularyId,
      );
      addTearDown(() => watch?.cancel());

      expect(watch, isNotNull, reason: 'the half-done install was left alone');
      expect(models.asked, 1);
    });

    test('and no download is started to do it', () async {
      // A session may finish local work somebody asked for. It may not put
      // hundreds of megabytes on a household's connection because a setting
      // says the voice is on.
      await settings.set('neuralVoice', true);
      models.downloaded = 0;

      final watch = await finishInterruptedInstall(
        engine,
        settings,
        db,
        vocabularyId,
      );

      expect(watch, isNull);
      expect(models.asked, 0);
    });

    test('and a finished install is not unpacked again', () async {
      await settings.set('neuralVoice', true);
      models.present = true;
      models.downloaded = models.published.downloadBytes;

      final watch = await finishInterruptedInstall(
        engine,
        settings,
        db,
        vocabularyId,
      );

      expect(watch, isNull);
      expect(models.asked, 0);
    });

    test('and one already running is left to whoever started it', () async {
      await settings.set('neuralVoice', true);
      models.downloaded = models.published.downloadBytes;
      models.install();
      expect(models.asked, 1);

      final watch = await finishInterruptedInstall(
        engine,
        settings,
        db,
        vocabularyId,
      );

      expect(watch, isNull);
      expect(models.asked, 1, reason: 'a second install onto the same file');
    });
  });
}
