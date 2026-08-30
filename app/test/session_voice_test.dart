import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/main.dart';

/// Records the voice it was handed, and nothing else.
class _RecordingSpeech implements SpeechEngine {
  VoiceOption? voice;

  @override
  Future<void> useVoice(VoiceOption voice) async => this.voice = voice;

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
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVolume(double volume) async {}
}

/// A session has to open in the voice the caregiver approved.
///
/// A device can carry a compact and an enhanced voice under one name. The
/// identifier is the only thing separating them, so a session that hands over
/// the name alone leaves the engine to pick by quality — and the person speaks
/// every day in a voice nobody chose for them.
void main() {
  // Opening a session also holds the device to the board's aspect, which is a
  // platform channel call and needs a binding to go nowhere.
  TestWidgetsFlutterBinding.ensureInitialized();

  late WordbridgeDatabase db;
  late ProfileSettings settings;

  setUp(() async {
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
    await settings.set('voiceName', 'Daniel');
    await settings.set('voiceLocale', 'en-GB');
    await settings.set('voiceIdentifier', 'com.apple.compact.en-GB.Daniel');
  });

  tearDown(() async => db.close());

  test('opening a session carries the identifier, not just the name', () async {
    final speech = _RecordingSpeech();

    // Through the function the app actually opens a session with, not through
    // the one it calls. A voice that is applied correctly by a step nobody
    // takes is a device speaking in whatever the OS chose.
    addTearDown(await openSession(speech, settings));

    expect(speech.voice?.name, 'Daniel');
    expect(
      speech.voice?.identifier,
      'com.apple.compact.en-GB.Daniel',
      reason:
          'the engine was given a name and a locale to choose from, so the '
          'device speaks in whichever of the two it prefers',
    );
  });
}
