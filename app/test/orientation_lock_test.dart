import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/main.dart';

class _SilentSpeech implements SpeechEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text) async {}
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

/// The board is drawn into whatever box the window gives it.
///
/// Rotating the tablet does not re-derive the grid — it draws the same rows and
/// columns into a box of the opposite aspect, so every cell changes width,
/// height and position without a word moving in the database. The invariant
/// test cannot see it, and a person who has learned where "help" is under their
/// thumb finds it somewhere else.
///
/// So what is asserted here is the set of orientations, not that the call
/// happened. A lock that permits the other aspect is not a lock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WordbridgeDatabase db;
  late ProfileSettings settings;
  List<String>? locked;

  setUp(() async {
    locked = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            locked = (call.arguments as List).cast<String>();
          }
          return null;
        });

    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    final id = newId();
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: id,
            displayName: 'Maya',
            createdAt: nowMs(),
            updatedAt: nowMs(),
          ),
        );

    settings = ProfileSettings(db, id);
    await settings.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await db.close();
  });

  test('a landscape board holds the tablet on its side', () async {
    await settings.set('orientation', 'landscape');
    await applyProfileOrientation(settings);

    expect(locked, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
  });

  test('a portrait board holds it upright', () async {
    await settings.set('orientation', 'portrait');
    await applyProfileOrientation(settings);

    expect(locked, [
      'DeviceOrientation.portraitUp',
      'DeviceOrientation.portraitDown',
    ]);
  });

  test('both ways up on the chosen axis are allowed', () async {
    // A tablet mounted for a left-handed reach and one mounted for a
    // right-handed reach are both landscape. What must not change is the
    // aspect, not which way up — and refusing one of the two would leave a
    // mounted device showing the board upside down.
    await settings.set('orientation', 'landscape');
    await applyProfileOrientation(settings);

    expect(locked, hasLength(2));
  });

  group('opening a session', () {
    test('locks before the board is drawn', () async {
      // The board is built for one aspect and drawn into whatever the window
      // gives it. A session that opens without locking hands a person a grid
      // that changes shape the first time the tablet moves.
      await settings.set('orientation', 'portrait');
      locked = null;

      final close = await openSession(_SilentSpeech(), settings);
      addTearDown(close);

      expect(locked, [
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ]);
    });

    test('re-locks when a caregiver changes the orientation', () async {
      // Changing it rebuilds the board for the other aspect without ending the
      // session, so a lock set once and left is a device held to an aspect its
      // board no longer has.
      await settings.set('orientation', 'landscape');
      final close = await openSession(_SilentSpeech(), settings);
      addTearDown(close);

      locked = null;
      await settings.set('orientation', 'portrait');

      expect(locked, [
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ]);
    });

    test('stops re-locking once the session is over', () async {
      final close = await openSession(_SilentSpeech(), settings);
      close();

      locked = null;
      await settings.set('orientation', 'portrait');

      expect(
        locked,
        isNull,
        reason: 'a closed session was still holding the device',
      );
    });
  });

  test('a profile with nothing recorded is still locked', () async {
    // Not "unlocked until somebody chooses". Every grid was derived from an
    // orientation, and the default is the one the derivation defaults to, so a
    // profile made before the setting existed is held to the aspect its board
    // was actually built for.
    await applyProfileOrientation(settings);

    expect(
      locked,
      isNotNull,
      reason: 'the device was left free to rotate under a board it would break',
    );
    expect(locked, everyElement(contains('landscape')));
  });
}
