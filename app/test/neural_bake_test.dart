import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/speech/neural/bake.dart';
import 'package:wordbridge/features/speech/neural/bake_vocabulary.dart';
import 'package:wordbridge/features/speech/neural/clip_store.dart';

void main() {
  group('what has to be baked', () {
    late WordbridgeDatabase db;
    late String vocabularyId;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final ts = nowMs();
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'p1',
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
        profileId: 'p1',
        ageBand: AgeBand.child,
      );
    });

    tearDown(() async => db.close());

    test('it is far more than the number of words on the board', () async {
      // A word is not an utterance. The endings multiply it — `want`,
      // `wanted`, `wanting`, `wants` are four clips off one key — and they are
      // the easy half to leave out of an estimate.
      final words = await bakeVocabulary(db, vocabularyId);
      expect(words.length, greaterThan(700));

      final placed = await (db.select(
        db.buttons,
      )..where((b) => b.isSystem.equals(false))).get();
      expect(words.length, greaterThan(placed.length));
    });

    test('though it is no longer more than the number of locations', () async {
      // It used to be, and the comparison was written against locations for
      // that reason. It stopped being true when §4.42's two new bands gave two
      // category boards another page each: a page is 84 locations and almost
      // all of them are reserved and empty, while the bake list de-duplicates.
      //
      // Kept as a test rather than deleted, because the number that matters is
      // how long a bake takes, and reading it off the cell count would now be
      // an overestimate by a third.
      final words = await bakeVocabulary(db, vocabularyId);
      final locations = await (db.select(
        db.cells,
      )..where((c) => c.boardId.isNotNull())).get();

      expect(locations.length, greaterThan(words.length));
    });

    test('a morpheme key speaks the form it produced, so that is baked', () {
      // `wanted`, `eating`, `leg's` — each is its own clip, because each is a
      // thing the board says out loud on a press.
      return expectLater(
        bakeVocabulary(db, vocabularyId),
        completion(
          allOf(
            contains('wanted'),
            contains('eating'),
            contains('going'),
            contains("leg's"),
          ),
        ),
      );
    });

    test('every form of "to be" is there', () async {
      // One key holds am/is/are and one holds was/were, and each press speaks
      // whichever form it landed on.
      final words = await bakeVocabulary(db, vocabularyId);
      for (final form in ['is', 'are', 'am', 'was', 'were']) {
        expect(words, contains(form), reason: '"$form" is reachable');
      }
    });

    test('nothing is baked twice', () async {
      final words = await bakeVocabulary(db, vocabularyId);
      expect(words.toSet().length, words.length);
    });

    test('it covers what the board says', () async {
      // This used to record a defect rather than a rule: `finished` was seeded
      // as a verb already carrying its ending, nothing marked it as such, so
      // the board offered `+ed` after it and said "finisheded" — and the bake
      // had to cover that, because a cache that left the form out would be a
      // key speaking in a stranger's voice.
      //
      // The seed now carries the stem, so the pair produces the word somebody
      // actually wants. The rule it was testing is unchanged and still the
      // point: the bake covers what the board says.
      final words = await bakeVocabulary(db, vocabularyId);
      expect(words, contains('finish'));
      expect(words, contains('finished'));
      expect(
        words,
        isNot(contains('finisheded')),
        reason: 'the board can still build the form that was the bug',
      );
    });

    test('a form the board would never offer is not baked', () async {
      // `grammarHelperApplies` decides whether a key is even shown. Audio for
      // a form nobody can reach is bake time nobody hears.
      final words = await bakeVocabulary(db, vocabularyId);
      expect(words, isNot(contains('theing')));
      expect(words, isNot(contains('nots')));
    });

    test('the bare words come before their endings', () async {
      // A bake is half an hour and the board is in use throughout, so the
      // order decides what a person can say in the first five minutes.
      final words = await bakeVocabulary(db, vocabularyId);
      expect(words.indexOf('want'), lessThan(words.indexOf('wanted')));
      expect(words.indexOf('go'), lessThan(words.indexOf('going')));
    });

    test('a word a caregiver adds is baked like any other', () async {
      // The shipped vocabulary is closed. The board is not, and that is the
      // whole argument of this project.
      final ts = nowMs();
      await db
          .into(db.buttons)
          .insert(
            ButtonsCompanion.insert(
              id: 'b-custom',
              vocabularyId: vocabularyId,
              label: 'Nanna',
              message: 'Nanna',
              action: ButtonAction.speak,
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      expect(await bakeVocabulary(db, vocabularyId), contains('Nanna'));
    });

    test('a deleted word is not baked', () async {
      final words = await bakeVocabulary(db, vocabularyId);
      final first = words.first;
      await (db.update(db.buttons)..where((b) => b.message.equals(first)))
          .write(ButtonsCompanion(deletedAt: Value(nowMs())));
      expect(await bakeVocabulary(db, vocabularyId), isNot(contains(first)));
    });
  });

  group('the bake resumes', () {
    late Directory root;
    late ClipStore store;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('wordbridge-bake');
      store = await ClipStore.open(root: root, packId: 'af_bella-r100');
    });

    tearDown(() async {
      await store.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('it picks up from what the pack already holds', () async {
      // Resuming needs nothing stored: the pack is the progress.
      await store.write('one', (pcm16: Uint8List(20), sampleRate: 24000));
      await store.write('two', (pcm16: Uint8List(20), sampleRate: 24000));

      final bake = stubBake(store);
      await bake.job.start(['one', 'two', 'three', 'four']);
      await bake.job.settle();

      expect(bake.job.total, 4);
      expect(bake.job.done, 4);
      expect(bake.made, ['three', 'four'], reason: 'only what was missing');
      expect(bake.job.state, BakeState.done);
    });

    test('nothing to do is done, not running', () async {
      await store.write('one', (pcm16: Uint8List(20), sampleRate: 24000));
      final bake = stubBake(store);
      await bake.job.start(['one']);
      expect(bake.job.state, BakeState.done);
      expect(bake.made, isEmpty);
    });

    test('stopping keeps everything already made', () async {
      final bake = stubBake(store, pauseAfter: 2);
      unawaited(bake.job.start(['a', 'b', 'c', 'd', 'e']));
      await bake.job.settle();

      expect(bake.job.state, BakeState.paused);
      expect(store.count, 2);

      // A second run finishes the rest rather than starting again.
      final resumed = stubBake(store);
      await resumed.job.start(['a', 'b', 'c', 'd', 'e']);
      await resumed.job.settle();
      expect(store.count, 5);
      expect(resumed.made, hasLength(3));
    });

    test(
      'a word that will not synthesize stops the job, not the app',
      () async {
        final bake = stubBake(store, failOn: 'c');
        await bake.job.start(['a', 'b', 'c', 'd']);
        await bake.job.settle();

        expect(bake.job.state, BakeState.failed);
        expect(bake.job.failure, isNotNull);
        expect(store.count, 2, reason: 'what was made is kept');
      },
    );

    test('a person speaking pushes it out of the way', () async {
      final bake = stubBake(store);
      bake.job.standAside();
      unawaited(bake.job.start(['a', 'b']));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(bake.job.state, BakeState.waiting);
      expect(store.count, 0, reason: 'the engine is left alone');

      bake.job.pause();
      await bake.job.settle();
    });
  });
}

/// A bake with the model taken out, so what is exercised is the resuming, the
/// ordering and the standing aside rather than the synthesis.
({BakeJob job, List<String> made}) stubBake(
  ClipStore store, {
  String? failOn,
  int? pauseAfter,
  bool waiting = false,
}) {
  final made = <String>[];
  late BakeJob job;
  job = BakeJob(
    store,
    synthesize: (word) async {
      if (word == failOn) throw StateError('no phonemes for "$word"');
      made.add(word);
      if (pauseAfter != null && made.length >= pauseAfter) job.pause();
      return (pcm16: Uint8List(20), sampleRate: 24000);
    },
    someoneIsWaiting: () => waiting,
  );
  return (job: job, made: made);
}
