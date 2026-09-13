import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/speech/tone.dart';
import 'package:wordbridge/features/talk/quick_settings.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/usage/logger.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

class _SilentSpeech implements SpeechEngine {
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

/// The quick settings key as somebody actually presses it (§4.81).
///
/// The point of the whole feature is that changing the volume does not cost
/// you your place: the board underneath must be the same board, showing the
/// same sentence, when the menu closes. That is what these press.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;

  const profileId = 'p1';

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());

    final ts = nowMs();
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

    vocabularyId = await seedCoreBoardSet(
      db,
      rows: 7,
      cols: 12,
      profileId: profileId,
    );
    settings = ProfileSettings(db, profileId);
    await settings.load();
  });

  // Deliberately not closed: closing inside a widget test waits on work the
  // fake clock never runs.

  Future<void> pumpBoard(WidgetTester tester, _SilentSpeech speech) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: TalkScreen(
          db: db,
          speech: speech,
          vocabularyId: vocabularyId,
          logger: UsageLogger(db, deviceId: 'test'),
          auth: PinAuth(db, storage: _FakeSecretStore()),
          profileId: profileId,
          vocabLevel: 3,
          settings: settings,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> teardownBoard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the key opens three rows, drawn as board cells', (tester) async {
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    final key = find.text(quickSettingsLabel);
    expect(key, findsOneWidget, reason: 'the key is not on this board');

    await tester.tap(key);
    await settle(tester);

    for (final row in ['Volume', 'Tone', 'Favorites']) {
      expect(find.text(row), findsOneWidget, reason: '"$row" is not drawn');
    }

    await teardownBoard(tester);
  });

  testWidgets('the board underneath is never left', (tester) async {
    // The whole promise of the feature. The menu is a layer: the board is
    // still there, still the same board, with the same sentence in the bar.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text('I').first);
    await settle(tester);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);

    expect(find.text('want'), findsWidgets, reason: 'the board went away');
    expect(find.text('I'), findsWidgets, reason: 'the sentence went away');

    await teardownBoard(tester);
  });

  testWidgets('tapping away closes it and changes nothing', (tester) async {
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    final before = settings.speechVolume;

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    // The dark, which is everywhere but the key and its rows — the recovery
    // from the mis-reach the column this key sits in used to guard against.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    expect(find.text('Volume'), findsNothing);
    expect(settings.speechVolume, before);
    expect(find.text(quickSettingsLabel), findsOneWidget);

    await teardownBoard(tester);
  });

  testWidgets('Volume opens a slider between a whisper and a yell', (
    tester,
  ) async {
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Volume'));
    await settle(tester);

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text(volumeQuietest.label), findsOneWidget);
    expect(find.text(volumeLoudest.label), findsOneWidget);

    await teardownBoard(tester);
  });

  testWidgets('and it is only as tall as what is in it', (tester) async {
    // It is a slider, two small labels and the pause switch. An earlier
    // version put the pictures in `Expanded`, which took whatever height the
    // dialog was willing to give and turned a one-line control into most of
    // the screen — that is the failure this number is watching for, and it was
    // 768px tall.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Volume'));
    await settle(tester);

    // The card it actually paints, not the AlertDialog element — that one
    // spans the whole screen and would report 768 however small the card is.
    final card = tester.getSize(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      card.height,
      lessThan(360),
      reason: 'the volume dialog card is ${card.height}px tall',
    );

    await teardownBoard(tester);
  });

  testWidgets('and its ends are pressable, and are heard', (tester) async {
    // Hearing it is the only way to judge a volume: a thumb on a track cannot
    // tell anybody whether they will be heard across a room.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Volume'));
    await settle(tester);
    await tester.tap(find.text(volumeQuietest.label));
    await settle(tester);

    expect(settings.speechVolume, volumeQuietest.value);
    expect(speech.spoken, contains(volumeSample));

    await teardownBoard(tester);
  });

  testWidgets('and the volume says the sentence, not a sample', (tester) async {
    // The question somebody is answering is "will I be heard saying *this*, in
    // *this* room". A fixed phrase is the wrong words and the wrong length.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text('I').first);
    await settle(tester);
    await tester.tap(find.text('want').first);
    await settle(tester);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Volume'));
    await settle(tester);
    await tester.tap(find.text(volumeQuietest.label));
    await settle(tester);

    expect(speech.spoken.last, 'I want');
    expect(
      speech.spoken,
      isNot(contains(volumeSample)),
      reason: 'it said the sample over the sentence somebody had built',
    );

    await teardownBoard(tester);
  });

  testWidgets('and falls back to a sample when the bar is empty', (
    tester,
  ) async {
    // Silence would read as a volume of zero.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Volume'));
    await settle(tester);
    await tester.tap(find.text(volumeLoudest.label));
    await settle(tester);

    expect(speech.spoken, contains(volumeSample));

    await teardownBoard(tester);
  });

  testWidgets('Tone offers ways of speaking, and "Quiet" is not one', (
    tester,
  ) async {
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    expect(settings.tone, Tone.normal);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Tone'));
    await settle(tester);

    expect(find.text('Quiet'), findsNothing, reason: '"Quiet" is back');
    expect(find.text('Urgent'), findsOneWidget);

    await tester.tap(find.text('Urgent'));
    await settle(tester);

    expect(settings.tone, Tone.urgent);

    await teardownBoard(tester);
  });

  testWidgets('Favorites opens the list, and says a word on it', (
    tester,
  ) async {
    await settings.addFavorite('juice', message: 'I want juice');

    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Favorites'));
    await settle(tester);

    expect(find.text('Add a word'), findsOneWidget);

    await tester.tap(find.text('juice'));
    await settle(tester);

    expect(speech.spoken, contains('I want juice'));
    expect(find.text('Add a word'), findsNothing);
    expect(find.text(quickSettingsLabel), findsOneWidget);

    await teardownBoard(tester);
  });

  testWidgets('an empty list still offers the way to add one', (tester) async {
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Favorites'));
    await settle(tester);

    expect(find.text('Add a word'), findsOneWidget);

    await teardownBoard(tester);
  });

  testWidgets('adding one browses the board, and offers typing above it', (
    tester,
  ) async {
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Favorites'));
    await settle(tester);
    await tester.tap(find.text('Add a word'));
    await settle(tester);

    expect(find.text('Pick a word'), findsOneWidget);
    expect(find.text('Type a word instead'), findsOneWidget);

    // The board itself, browsable: a root-board word is right there.
    await tester.tap(find.text('want').first);
    await settle(tester);

    expect(settings.favorites.map((f) => f.label), contains('want'));
    // Back on the favorites sheet, not dropped onto the board.
    expect(find.text('Add a word'), findsOneWidget);

    await teardownBoard(tester);
  });

  testWidgets('a system key is not something you can favorite', (tester) async {
    // "home" and "more words" are how you move, not things anybody says. A
    // favorites list with "back a page" on it has misunderstood the question.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Favorites'));
    await settle(tester);
    await tester.tap(find.text('Add a word'));
    await settle(tester);

    await tester.tap(find.text('home').first);
    await settle(tester);

    expect(settings.favorites, isEmpty);
    // Still browsing, because pressing home navigated rather than picked.
    expect(find.text('Pick a word'), findsOneWidget);

    await teardownBoard(tester);
  });

  testWidgets('holding a favorite offers to remove it, and keeps it on a no', (
    tester,
  ) async {
    await settings.addFavorite('juice');

    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Favorites'));
    await settle(tester);

    await tester.longPress(find.text('juice'));
    await settle(tester);

    expect(find.text('Keep'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await settle(tester);

    expect(settings.favorites, hasLength(1));

    await tester.longPress(find.text('juice'));
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);

    expect(settings.favorites, isEmpty);

    await teardownBoard(tester);
  });

  testWidgets('the tone badge on the bar opens the tone picker', (
    tester,
  ) async {
    // The badge is where somebody notices the tone is wrong, so it is where
    // they put it right.
    await settings.set('tone', Tone.urgent.name);

    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    final badge = find.text(Tone.urgent.label);
    expect(badge, findsOneWidget, reason: 'the badge is not on the bar');

    await tester.tap(badge);
    await settle(tester);

    expect(find.text('How should it sound?'), findsOneWidget);

    await teardownBoard(tester);
  });

  testWidgets('and no badge is drawn for the ordinary voice', (tester) async {
    // It would be furniture: this bar is the busiest strip on screen and the
    // ordinary voice is what "no badge" already means.
    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    expect(settings.tone, Tone.normal);
    expect(find.text(Tone.normal.label), findsNothing);

    await teardownBoard(tester);
  });

  testWidgets('a tap on a favorite never removes it', (tester) async {
    // The reason removal is a hold behind a confirmation: on this grid the
    // difference between the word somebody wanted and the one beside it is a
    // few millimetres.
    await settings.addFavorite('juice');

    final speech = _SilentSpeech();
    await pumpBoard(tester, speech);

    await tester.tap(find.text(quickSettingsLabel));
    await settle(tester);
    await tester.tap(find.text('Favorites'));
    await settle(tester);
    await tester.tap(find.text('juice'));
    await settle(tester);

    expect(settings.favorites, hasLength(1));

    await teardownBoard(tester);
  });
}
