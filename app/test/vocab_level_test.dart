import 'package:drift/drift.dart' hide Column, Table;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
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

/// Raising the vocabulary level has to reach the board that is open.
///
/// It is the app's growth mechanism, and the only one that reveals words
/// without moving any: the words are already placed, and the level decides how
/// many of them are drawn. It is also the one profile setting held in a column
/// rather than in `settingsJson`, so it does not travel on [ProfileSettings]
/// like every other live setting and needs its own way through.
///
/// A caregiver who moves the slider and sees the board behind it stay the same
/// has been told the setting does nothing.
void main() {
  late WordbridgeDatabase db;
  late Profile profile;

  Future<void> setLevel(int level) =>
      (db.update(db.profiles)..where((p) => p.id.equals(profile.id))).write(
        ProfilesCompanion(vocabLevel: Value(level)),
      );

  Future<void> makeProfile() async {
    profile = await ProfileRepository(db).create(
      displayName: 'Maya',
      grid: GridChoice.derive(
        screen: const Size(744, 1133),
        orientation: BoardOrientation.landscape,
        iconSize: IconSize.medium,
      ),
    );
    await setLevel(1);
  }

  group('the level reaches a session that is already open', () {
    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      await makeProfile();
    });

    tearDown(() async => db.close());

    test('a change to the column is delivered', () async {
      final seen = <int>[];
      final subscription = watchVocabLevel(db, profile.id).listen(seen.add);
      await pumpEventQueue();

      expect(seen, [1]);

      await setLevel(3);
      await pumpEventQueue();

      expect(
        seen,
        [1, 3],
        reason:
            'the board is holding the level the session opened with, so the '
            'words the caregiver just revealed stay invisible until the app '
            'is relaunched',
      );

      await subscription.cancel();
    });

    test('an unrelated write to the profile is not a change', () async {
      // Every other setting lives in the same row, and each one written
      // touches it. A board that rebuilds on all of them pays for the level
      // being watched at all.
      final seen = <int>[];
      final subscription = watchVocabLevel(db, profile.id).listen(seen.add);
      await pumpEventQueue();

      final settings = ProfileSettings(db, profile.id);
      await settings.load();
      await settings.set('autoReturn', false);
      await pumpEventQueue();

      expect(seen, [1]);

      await subscription.cancel();
    });
  });

  group('the board draws the new level', () {
    late String vocabularyId;

    /// A word the seeded board holds back at level 1 and shows at level 3.
    ///
    /// Read from the database rather than named, so this measures the level
    /// and not which words the shipped vocabulary happens to carry.
    Future<Button> withheldWord() async {
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabularyId))).getSingle();

      final rows =
          await (db.select(db.buttons).join([
                  innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
                ])
                ..where(
                  db.cells.boardId.equals(vocab.rootBoardId!) &
                      db.buttons.vocabLevel.isBiggerThanValue(1) &
                      db.buttons.hidden.equals(false) &
                      db.buttons.action.equalsValue(ButtonAction.speak),
                )
                ..orderBy([OrderingTerm.asc(db.buttons.id)]))
              .get();

      expect(
        rows,
        isNotEmpty,
        reason: 'the home board holds nothing back, so nothing can be revealed',
      );
      return rows.first.readTable(db.buttons);
    }

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      await makeProfile();
      vocabularyId = profile.activeVocabularyId!;
    });

    // The database is deliberately not closed. Closing it inside a widget test
    // waits on work the fake clock never runs; each test gets its own
    // in-memory instance and the process ends with the file.

    testWidgets('raising the level draws the words it reveals', (tester) async {
      tester.view.physicalSize = const Size(2048, 1536);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final word = await withheldWord();

      Widget board(int level) => MaterialApp(
        home: TalkScreen(
          db: db,
          speech: _SilentSpeech(),
          vocabularyId: vocabularyId,
          logger: UsageLogger(db, deviceId: 'test'),
          auth: PinAuth(db, storage: _FakeSecretStore()),
          profileId: profile.id,
          vocabLevel: level,
        ),
      );

      await tester.pumpWidget(board(1));
      // The board arrives over several turns: the vocabulary read, then the
      // first cells off the query stream. Each pump drains one.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(find.text(word.label), findsNothing);
      final state = tester.state<TalkScreenState>(find.byType(TalkScreen));
      expect(state.predictionLevel, 1);

      await tester.pumpWidget(board(3));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(
        find.text(word.label),
        findsOneWidget,
        reason:
            '"${word.label}" is placed and now within the level, and the '
            'board is still drawing it as an empty square',
      );
      expect(
        state.predictionLevel,
        3,
        reason:
            'the strip is still filtering on the old ceiling, so it withholds '
            'words the grid is drawing',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      // Drift schedules a zero-duration timer when a query stream is dropped.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
