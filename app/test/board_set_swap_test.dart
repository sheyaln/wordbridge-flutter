import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/editor/rebuild_from_seed.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/usage/logger.dart';
import 'package:wordbridge/main.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

class _SilentSpeech implements SpeechEngine {
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

/// A board set replaced under a session that is already open.
///
/// Three things point a profile at a *different* vocabulary: rebuilding from
/// the shipped words, migrating to another grid, and importing a board file.
/// All three write one column, and the session read that column once, at
/// launch, and believed it for the rest of the run — so the caregiver was
/// returned to the board they had just replaced, with nothing on screen saying
/// why, and the only way through was to close the app and open it again.
///
/// Being told to relaunch is the failure this whole app exists to avoid
/// elsewhere; it should not be the price of a supported edit.
void main() {
  late WordbridgeDatabase db;

  late Directory temp;

  Widget session(Profile profile) {
    final registry = SymbolRegistry(packs: const []);
    // Nothing is drawn from a pack here — the registry is empty — so the one
    // this needs is the one that never answers.
    final fetcher = GlobalSymbolsPack(
      documentsDirectory: () async => temp,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    addTearDown(fetcher.dispose);

    return MaterialApp(
      home: Session(
        db: db,
        profile: profile,
        speech: _SilentSpeech(),
        logger: UsageLogger(db, deviceId: 'test'),
        auth: PinAuth(db, storage: _FakeSecretStore()),
        resolver: SymbolResolver(registry: registry, db: db),
        registry: registry,
        fetcher: fetcher,
        onSwitchProfile: (_) {},
      ),
    );
  }

  /// The board arrives over several turns: the settings load, the vocabulary
  /// read, then the first cells off the query stream.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    temp = Directory.systemTemp.createTempSync('wb-swap');

    // Opening a session locks the tablet to the aspect its board was built
    // for, and that goes out over a platform channel. Unanswered, the whole
    // session future never completes and the screen holds its spinner
    // forever — which is a correct thing for it to do and a useless thing to
    // test against.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    temp.deleteSync(recursive: true);
  });

  // Deliberately not closed. Closing inside a widget test waits on work the
  // fake clock never runs; each test gets its own in-memory instance.

  testWidgets('a rebuilt board set reaches the open board', (tester) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final profile = await ProfileRepository(db).create(
      displayName: 'Maya',
      grid: GridChoice.derive(
        screen: const Size(744, 1133),
        orientation: BoardOrientation.landscape,
        iconSize: IconSize.medium,
      ),
    );
    final before = profile.activeVocabularyId!;

    await tester.pumpWidget(session(profile));
    await settle(tester);

    expect(
      tester.widget<TalkScreen>(find.byType(TalkScreen)).vocabularyId,
      before,
    );

    final after = await rebuildFromSeed(
      db,
      profileId: profile.id,
      vocabularyId: before,
    );
    expect(after, isNot(before));

    await settle(tester);

    expect(
      tester.widget<TalkScreen>(find.byType(TalkScreen)).vocabularyId,
      after,
      reason:
          'the session is still holding the board set the caregiver replaced, '
          'so the rebuild looks like it did nothing until the app is closed '
          'and opened again',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    // Drift schedules a zero-duration timer when a query stream is dropped.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a new board set is a new screen, not a redressed one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final profile = await ProfileRepository(db).create(
      displayName: 'Maya',
      grid: GridChoice.derive(
        screen: const Size(744, 1133),
        orientation: BoardOrientation.landscape,
        iconSize: IconSize.medium,
      ),
    );
    final before = profile.activeVocabularyId!;

    await tester.pumpWidget(session(profile));
    await settle(tester);

    final was = tester.state<TalkScreenState>(find.byType(TalkScreen));

    await rebuildFromSeed(db, profileId: profile.id, vocabularyId: before);
    await settle(tester);

    expect(
      tester.state<TalkScreenState>(find.byType(TalkScreen)),
      isNot(same(was)),
      reason:
          'a screen reads its vocabulary once, when it is created, so keeping '
          'the old state leaves it drawing the old boards from a new id',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });

  group('what the session follows', () {
    test('an unrelated write to the row does not rebuild it', () async {
      // Every setting a profile has lives in the same row, and each one
      // written touches it. A board that rebuilds on all of them pays for the
      // row being watched at all.
      final seen = <String?>[];
      final profile = await ProfileRepository(db).create(
        displayName: 'Maya',
        grid: GridChoice.derive(
          screen: const Size(744, 1133),
          orientation: BoardOrientation.landscape,
          iconSize: IconSize.medium,
        ),
      );

      final subscription = watchProfile(
        db,
        profile.id,
      ).listen((p) => seen.add(p.activeVocabularyId));
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(seen, [profile.activeVocabularyId]);

      final settings = ProfileSettings(db, profile.id);
      await settings.load();
      await settings.set('autoReturn', false);
      await pumpEventQueue();

      expect(seen, hasLength(1));
    });
  });
}
