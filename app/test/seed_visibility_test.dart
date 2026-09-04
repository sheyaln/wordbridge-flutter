import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/fallback_board.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/usage/logger.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';

/// What a watcher sees while a board set is being written.
///
/// A profile's `active_vocabulary_id` is watched, and the open session follows
/// it: the board swaps the moment it changes. Seeding used to point the
/// profile at the new vocabulary *first* and set `root_board_id` last, so for
/// the whole of the build — every board, every cell, seconds of writes — the
/// profile named a board set with no home board in it.
///
/// Nothing noticed while a rebuild still required relaunching the app, because
/// by the time anyone looked the writes had finished. The moment the session
/// started following the column, rebuilding from the shipped vocabulary handed
/// the person a spinner that nothing would ever clear. A tablet that turns on
/// and then does nothing is worse than one that reports an error, because an
/// error can be told to somebody.
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

void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  // The race itself is not reproducible here: drift serializes this test's
  // reads behind the seed's writes, so a single process never observes the
  // window a device interleaves. What is testable is the end state, and the
  // guard that stops the window — if it ever comes back — reaching a person as
  // a spinner rather than as words on a screen.

  test('and the board set it lands on is the finished one', () async {
    final vocabularyId = await seedCoreBoardSet(
      db,
      profileId: 'p1',
      rows: 7,
      cols: 12,
    );

    final profile = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals('p1'))).getSingle();

    expect(profile.activeVocabularyId, vocabularyId);

    final vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();
    expect(vocab.rootBoardId, isNotNull);
  });

  testWidgets('a board set with no home board is refused, not spun on', (
    tester,
  ) async {
    // What the window used to produce, made directly: a vocabulary a profile
    // names before it has a home board. The screen has to say so, because the
    // alternative it used to do is draw a spinner nothing ever clears — and a
    // tablet that turns on and then does nothing cannot be reported by the
    // person holding it.
    final vocabularyId = await seedCoreBoardSet(
      db,
      profileId: 'p1',
      rows: 7,
      cols: 12,
    );
    await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabularyId)))
        .write(const VocabulariesCompanion(rootBoardId: Value(null)));

    await tester.pumpWidget(
      MaterialApp(
        home: TalkScreen(
          db: db,
          speech: _SilentSpeech(),
          vocabularyId: vocabularyId,
          logger: UsageLogger(db, deviceId: 'test'),
          auth: PinAuth(db, storage: _FakeSecretStore()),
          profileId: 'p1',
          vocabLevel: 3,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'the screen is still spinning on a board set it cannot draw',
    );
    expect(find.byType(FallbackBoard), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
