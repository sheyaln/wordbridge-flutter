import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/speech/tone.dart';
import 'package:wordbridge/features/speech/voice_setup.dart';

/// Records what was asked of the engine, and can be told to refuse.
class _RecordingEngine implements SpeechEngine {
  _RecordingEngine({this.available = const [], this.rejects = false});

  final List<VoiceOption> available;
  final bool rejects;

  final applied = <String, Object>{};
  VoiceOption? chosenVoice;

  @override
  Future<void> useVoice(VoiceOption voice) async {
    if (rejects) throw StateError('no such voice');
    chosenVoice = voice;
  }

  @override
  Future<void> setRate(double rate) async {
    if (rejects) throw StateError('rate refused');
    applied['rate'] = rate;
  }

  @override
  Future<void> setPitch(double pitch) async => applied['pitch'] = pitch;

  @override
  Future<void> setVolume(double volume) async => applied['volume'] = volume;

  @override
  Future<List<VoiceOption>> voices() async {
    if (rejects) throw StateError('cannot enumerate');
    return available;
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
}

/// A voice as the platform would report it.
VoiceOption voice(
  String name, {
  String locale = 'en-GB',
  String? identifier,
  String? gender,
  String? quality,
  bool isNovelty = false,
  bool requiresNetwork = false,
}) => (
  name: name,
  locale: locale,
  identifier: identifier,
  gender: gender,
  quality: quality,
  isNovelty: isNovelty,
  requiresNetwork: requiresNetwork,
);

void main() {
  group('the tones that exist', () {
    test('only what rate, pitch and volume can honestly produce', () {
      // The list is short on purpose. Sarcasm needs a prosodic contour and a
      // whisper needs breathiness; neither is a dial any platform engine
      // exposes, so neither is offered under a name that promises it.
      expect(Tone.values.map((t) => t.name), [
        'normal',
        'calm',
        'urgent',
        'quiet',
      ]);
      expect(
        Tone.values.map((t) => t.label),
        isNot(contains('Whisper')),
        reason: 'a quiet voice is not a whisper, and must not claim to be',
      );
      expect(Tone.values.map((t) => t.label), isNot(contains('Sarcastic')));
    });

    test('normal changes nothing', () {
      final p = applyTone(Tone.normal, rate: 0.7, pitch: 1.1, volume: 0.8);
      expect(p.rate, closeTo(0.7, 0.001));
      expect(p.pitch, closeTo(1.1, 0.001));
      expect(p.volume, closeTo(0.8, 0.001));
    });

    test('urgent is faster, higher and at full volume', () {
      final p = applyTone(Tone.urgent, rate: 1.0, pitch: 1.0, volume: 1.0);
      expect(p.rate, greaterThan(1.0));
      expect(p.pitch, greaterThan(1.0));
      expect(p.volume, 1.0);
    });

    test('calm is slower and lower', () {
      final p = applyTone(Tone.calm, rate: 1.0, pitch: 1.0, volume: 1.0);
      expect(p.rate, lessThan(1.0));
      expect(p.pitch, lessThan(1.0));
    });

    test('quiet turns the volume down and leaves the voice alone', () {
      final p = applyTone(Tone.quiet, rate: 1.0, pitch: 1.0, volume: 1.0);
      expect(p.volume, lessThan(0.5));
      expect(p.pitch, 1.0);
    });
  });

  group('tone multiplies the profile rather than replacing it', () {
    test('a slow reader gets a slower urgent, not everybody\'s urgent', () {
      final standard = applyTone(
        Tone.urgent,
        rate: 1.0,
        pitch: 1.0,
        volume: 1.0,
      );
      final slow = applyTone(Tone.urgent, rate: 0.5, pitch: 1.0, volume: 1.0);

      expect(slow.rate, lessThan(standard.rate));
      expect(
        slow.rate,
        greaterThan(0.5),
        reason: 'urgent still has to be faster than this user\'s normal',
      );
    });

    test('nothing leaves the range the engine accepts', () {
      // A profile already at an extreme, pushed further by a tone.
      final p = applyTone(Tone.urgent, rate: 1.9, pitch: 1.9, volume: 1.0);
      expect(p.rate, lessThanOrEqualTo(2.0));
      expect(p.pitch, lessThanOrEqualTo(2.0));
      expect(p.volume, lessThanOrEqualTo(1.0));

      final quiet = applyTone(Tone.quiet, rate: 0.1, pitch: 0.5, volume: 0.0);
      expect(quiet.rate, greaterThanOrEqualTo(0.1));
      expect(quiet.pitch, greaterThanOrEqualTo(0.5));
      expect(quiet.volume, greaterThanOrEqualTo(0.0));
    });
  });

  group('choosing a voice', () {
    test('voices that need a connection are not offered', () async {
      // This device has to work in a car, a playground and a hospital
      // corridor. A voice that works at home and not in an ambulance is a
      // trap, not a choice.
      final engine = _RecordingEngine(
        available: [voice('Local'), voice('Cloud', requiresNetwork: true)],
      );

      final voices = await VoiceSetup(engine).usableVoices(locale: 'en');
      expect(voices.map((v) => v.name), ['Local']);
    });

    test('only voices for the board\'s language', () async {
      final engine = _RecordingEngine(
        available: [
          voice('English'),
          voice('Deutsch', locale: 'de-DE'),
        ],
      );

      final voices = await VoiceSetup(engine).usableVoices(locale: 'en-GB');
      expect(voices.map((v) => v.name), ['English']);
    });

    test('an engine that cannot list voices is not an error', () async {
      final engine = _RecordingEngine(rejects: true);
      expect(await VoiceSetup(engine).usableVoices(), isEmpty);
    });

    test('the joke voices are kept out unless asked for', () async {
      // A platform can list a couple of dozen of these. On a screen where
      // somebody is choosing how another person will sound for years, they
      // are mostly a way to make the real options hard to find.
      final engine = _RecordingEngine(
        available: [
          voice('Daniel'),
          voice('Bells', isNovelty: true),
          voice('Zarvox', isNovelty: true),
        ],
      );
      final setup = VoiceSetup(engine);

      expect((await setup.usableVoices()).map((v) => v.name), ['Daniel']);
      expect(await setup.noveltyCount(), 2);

      final all = await setup.usableVoices(includeNovelty: true);
      expect(all.map((v) => v.name), containsAll(['Bells', 'Zarvox']));
    });

    test('Apple files its joke voices under their own prefix', () {
      // A steadier test than a list of names that changes each OS release.
      expect(
        FlutterTtsEngine.isNoveltyIdentifier(
          'com.apple.speech.synthesis.voice.Bells',
        ),
        isTrue,
      );
      expect(
        FlutterTtsEngine.isNoveltyIdentifier(
          'com.apple.voice.compact.en-GB.Daniel',
        ),
        isFalse,
      );
      // Android reports no identifier and has no such voices.
      expect(FlutterTtsEngine.isNoveltyIdentifier(null), isFalse);
    });

    test('better-sounding voices come first', () async {
      final engine = _RecordingEngine(
        available: [
          voice('Alice', quality: 'default'),
          voice('Zoe', quality: 'enhanced'),
        ],
      );

      final voices = await VoiceSetup(engine).usableVoices();
      expect(voices.first.name, 'Zoe');
    });
  });

  group('grouping the voices by gender', () {
    test('male and female get their own headings', () {
      final groups = VoiceSetup.groupByGender([
        voice('Serena', gender: 'female'),
        voice('Daniel', gender: 'male'),
        voice('Kate', gender: 'female'),
      ]);

      expect(groups.map((g) => g.heading), ['Female', 'Male']);
      expect(groups.first.voices.map((v) => v.name), ['Serena', 'Kate']);
      expect(groups.last.voices.map((v) => v.name), ['Daniel']);
    });

    test('the casing the platform uses is not trusted', () {
      final groups = VoiceSetup.groupByGender([
        voice('Serena', gender: 'FEMALE'),
        voice('Daniel', gender: ' Male '),
      ]);

      expect(groups.map((g) => g.heading), ['Female', 'Male']);
    });

    test('the ones the device did not label go in their own group', () {
      final groups = VoiceSetup.groupByGender([
        voice('Serena', gender: 'female'),
        voice('Daniel', gender: 'male'),
        voice('Anonymous', gender: 'unspecified'),
        voice('Nameless'),
      ]);

      expect(groups.map((g) => g.heading), [
        'Female',
        'Male',
        'Gender not reported',
      ]);
      expect(groups.last.voices.map((v) => v.name), ['Anonymous', 'Nameless']);
    });

    test('a device that labels nothing gets a plain list, no headings', () {
      // Android voice maps carry no gender key at all. A lone "Gender not
      // reported" heading over every voice on the device is worse than none.
      final voices = [voice('Daniel'), voice('Serena', gender: 'unspecified')];

      final groups = VoiceSetup.groupByGender(voices);
      expect(groups, hasLength(1));
      expect(groups.single.heading, isNull);
      expect(groups.single.voices, voices);
      expect(VoiceSetup.reportsGender(voices), isFalse);
    });

    test('one gender throughout gets no lone heading either', () {
      final groups = VoiceSetup.groupByGender([
        voice('Serena', gender: 'female'),
        voice('Kate', gender: 'female'),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.heading, isNull);
      expect(groups.single.voices.map((v) => v.name), ['Serena', 'Kate']);
    });

    test('no voices at all is no groups', () {
      expect(VoiceSetup.groupByGender(const []), isEmpty);
    });

    test('grouping keeps the better-sounding voices at the top', () async {
      final engine = _RecordingEngine(
        available: [
          voice('Daniel', gender: 'male', quality: 'default'),
          voice('Serena', gender: 'female', quality: 'default'),
          voice('Serena', gender: 'female', quality: 'enhanced'),
        ],
      );

      final groups = VoiceSetup.groupByGender(
        await VoiceSetup(engine).usableVoices(),
      );

      expect(groups.first.heading, 'Female');
      expect(groups.first.voices.map((v) => v.quality), [
        'enhanced',
        'default',
      ]);
    });
  });

  group('telling two voices of the same name apart', () {
    final compact = voice(
      'Daniel',
      identifier: 'com.apple.voice.compact.en-GB.Daniel',
      quality: 'default',
    );
    final enhanced = voice(
      'Daniel',
      identifier: 'com.apple.voice.enhanced.en-GB.Daniel',
      quality: 'enhanced',
    );

    test('each is separately selectable', () {
      expect(
        VoiceSetup.voiceKey(compact),
        isNot(VoiceSetup.voiceKey(enhanced)),
      );

      expect(
        VoiceSetup.storedVoice(
          [compact, enhanced],
          name: 'Daniel',
          locale: 'en-GB',
          identifier: enhanced.identifier,
        ),
        enhanced,
      );
    });

    test('a device without identifiers still keys on something', () {
      expect(
        VoiceSetup.voiceKey(voice('Daniel')),
        isNot(VoiceSetup.voiceKey(voice('Daniel', locale: 'en-US'))),
      );
    });

    test('a stored identifier the device lost falls back to the name', () {
      // An OS update can renumber identifiers. Reading the old one as "no
      // voice chosen" would quietly move somebody back to the device default.
      expect(
        VoiceSetup.storedVoice(
          [compact],
          name: 'Daniel',
          locale: 'en-GB',
          identifier: 'com.apple.voice.gone.en-GB.Daniel',
        ),
        compact,
      );
    });

    test('nothing stored selects nothing', () {
      expect(VoiceSetup.storedVoice([compact, enhanced]), isNull);
      expect(
        VoiceSetup.storedVoice([compact], name: 'Karen', locale: 'en-AU'),
        isNull,
      );
    });

    test('the better grades are named on the row, the rest say nothing', () {
      expect(VoiceSetup.qualityLabel('enhanced'), 'Enhanced');
      expect(VoiceSetup.qualityLabel('Premium'), 'Premium');
      expect(VoiceSetup.qualityLabel('default'), isNull);
      expect(VoiceSetup.qualityLabel(null), isNull);
      expect(VoiceSetup.qualityLabel('compact'), isNull);
    });
  });

  group('how fast it speaks', () {
    test('1.0 asks the engine for its ordinary speaking rate', () {
      // The plugin's own scale puts normal speech at 0.5 on both platforms —
      // iOS passes the number to AVSpeechUtterance.rate, whose default is 0.5,
      // and Android doubles it before a synthesiser whose normal is 1.0.
      // Sending 1.0 for "normal" therefore asks both for double speed, which
      // is far too fast to make out.
      expect(FlutterTtsEngine.engineRate(1.0), 0.5);
    });

    test('slower and faster land either side of it', () {
      expect(FlutterTtsEngine.engineRate(0.5), lessThan(0.5));
      expect(FlutterTtsEngine.engineRate(1.5), greaterThan(0.5));
    });

    test('nothing can be asked for past the top of the scale', () {
      expect(FlutterTtsEngine.engineRate(9.0), 1.0);
      expect(FlutterTtsEngine.engineRate(-1.0), 0.0);
    });
  });

  group('applying settings to the engine', () {
    test('the stored voice and the tone-adjusted dials both land', () async {
      final engine = _RecordingEngine();

      await VoiceSetup(engine).apply(
        voiceName: 'Daniel',
        voiceLocale: 'en-GB',
        rate: 1.0,
        pitch: 1.0,
        volume: 1.0,
        tone: Tone.calm,
      );

      expect(engine.chosenVoice?.name, 'Daniel');
      expect(engine.applied['rate'], lessThan(1.0));
    });

    test('a voice the device no longer has does not stop the rest', () async {
      // An OS update can remove a voice. The board must still speak, in
      // whatever voice remains, rather than fail to open.
      final engine = _RecordingEngine(rejects: true);

      await expectLater(
        VoiceSetup(engine).apply(
          voiceName: 'Gone',
          voiceLocale: 'en-GB',
          rate: 1.0,
          pitch: 1.0,
          volume: 1.0,
          tone: Tone.normal,
        ),
        completes,
      );
    });
  });

  group('what is remembered', () {
    late WordbridgeDatabase db;
    late ProfileSettings settings;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      await seedCoreBoardSet(db);
      settings = ProfileSettings(db, 'default');
      await settings.load();
    });
    tearDown(() async => db.close());

    test('the device\'s own voice, until somebody chooses otherwise', () {
      expect(settings.voiceName, isNull);
      expect(settings.tone, Tone.normal);
      expect(settings.speechRate, 1.0);
      expect(settings.speechPitch, 1.0);
      expect(settings.speechVolume, 1.0);
    });

    test('a chosen voice survives a reload', () async {
      await settings.set('voiceName', 'Daniel');
      await settings.set('voiceLocale', 'en-GB');
      await settings.set('tone', Tone.calm.name);
      await settings.set('speechRate', 0.75);

      final reopened = ProfileSettings(db, 'default');
      await reopened.load();

      expect(reopened.voiceName, 'Daniel');
      expect(reopened.voiceLocale, 'en-GB');
      expect(reopened.tone, Tone.calm);
      expect(reopened.speechRate, 0.75);
    });

    test('a tone that no longer exists falls back rather than crashing', () {
      // A stored name from a build where the list was different. Reading it
      // has to produce a voice, because the alternative is a screen that
      // will not open on a device somebody speaks with.
      expect(Tone.byName('sarcastic'), Tone.normal);
      expect(Tone.byName(null), Tone.normal);
    });
  });
}
