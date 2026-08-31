import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/interop/board_files.dart';

/// §4.41 part 3. The readers and writers existed, were tested, and nothing in
/// `lib/` called any of them — so a caregiver could not get a board out of
/// wordbridge or into it. Being able to leave is the argument for supporting
/// the format at all.
///
/// What is under test here is the wiring, not the format: `interop_test.dart`
/// owns what an `.obz` contains.
void main() {
  late WordbridgeDatabase db;
  late Directory documents;
  late BoardFileStore store;
  late String vocabularyId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    documents = Directory.systemTemp.createTempSync('wordbridge-boards');
    store = BoardFileStore(db, documentsDirectory: () async => documents);
    vocabularyId = await seedCoreBoardSet(db, rows: 7, cols: 12);
  });

  tearDown(() async {
    await db.close();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  group('what a written-out board is called', () {
    test('the board set\'s own name and the day', () {
      expect(
        exportFileName('Maya’s words', DateTime(2026, 8, 30)),
        'Maya-s words 2026-08-30.obz',
      );
    });

    test('a month and a day are padded, so the names sort', () {
      expect(
        exportFileName('board', DateTime(2026, 1, 2)),
        'board 2026-01-02.obz',
      );
    });

    test('and a nameless board set still gets a name', () {
      expect(
        exportFileName('   ', DateTime(2026, 8, 30)),
        'board 2026-08-30.obz',
      );
    });
  });

  group('who an imported file belongs to', () {
    test('the file, before anybody renames them', () {
      expect(nameFromFile('Maya 2026-08-30.obz'), 'Maya 2026-08-30');
    });

    test('and something rather than nothing', () {
      // A person with no name is worse than a placeholder: the profile picker
      // would offer a blank row. Not reachable through the store, which only
      // lists files that have a stem, but `importBoardFile` takes a name from
      // anywhere.
      expect(nameFromFile(''), 'Imported board');
      expect(nameFromFile('   '), 'Imported board');
    });
  });

  group('writing a board set out', () {
    test('puts a file in the folder and reports it', () async {
      final written = await store.exportVocabulary(
        vocabularyId,
        at: DateTime(2026, 8, 30),
      );

      expect(written.name, endsWith('.obz'));
      expect(written.bytes, greaterThan(0));
      expect(File(written.path).existsSync(), isTrue);
      expect(written.path, contains(BoardFileStore.folder));
    });

    test('and the folder then lists it', () async {
      await store.exportVocabulary(vocabularyId);

      final files = await store.files();
      expect(files, hasLength(1));
      expect(files.single.name, endsWith('.obz'));
    });

    test('newest first, because that is the one just written', () async {
      final directory = Directory('${documents.path}/${BoardFileStore.folder}')
        ..createSync(recursive: true);
      final old = File('${directory.path}/old.obz')..writeAsBytesSync([1, 2]);
      old.setLastModifiedSync(DateTime(2020));

      await store.exportVocabulary(vocabularyId);

      final files = await store.files();
      expect(files.first.name, isNot('old.obz'));
      expect(files.last.name, 'old.obz');
    });

    test('anything that is not a board is left out of the list', () async {
      final directory = Directory('${documents.path}/${BoardFileStore.folder}')
        ..createSync(recursive: true);
      File('${directory.path}/notes.txt').writeAsStringSync('hello');
      File('${directory.path}/board.obf').writeAsStringSync('{}');

      // The folder is open to the outside — that is the point of it — so a
      // stray file is ignored rather than reported as a fault.
      final files = await store.files();
      expect(files.map((f) => f.name), ['board.obf']);
    });
  });

  group('bringing one in', () {
    /// Out and back, which is the round trip the format exists for.
    Future<ImportOutcome> roundTrip() async {
      final written = await store.exportVocabulary(vocabularyId);
      return store.import(written, displayName: 'Sam');
    }

    test('arrives as a new person rather than over the old one', () async {
      final before = await db.select(db.profiles).get();
      final outcome = await roundTrip();

      expect(outcome.problem, isNull);
      expect(outcome.profileId, isNotNull);

      final after = await db.select(db.profiles).get();
      expect(after, hasLength(before.length + 1));

      // Nothing that already existed moved, changed level, or changed board.
      for (final was in before) {
        final now = after.firstWhere((p) => p.id == was.id);
        expect(now.activeVocabularyId, was.activeVocabularyId);
        expect(now.vocabLevel, was.vocabLevel);
      }
    });

    test('and the new person is holding the imported board', () async {
      final outcome = await roundTrip();

      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals(outcome.profileId!))).getSingle();

      expect(profile.displayName, 'Sam');
      expect(profile.activeVocabularyId, isNotNull);
      expect(
        profile.activeVocabularyId,
        isNot(vocabularyId),
        reason: 'the import was hung off the board it came from',
      );

      final vocabulary = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(profile.activeVocabularyId!))).getSingle();
      expect(vocabulary.profileId, profile.id);
    });

    test('drawn at every level, because a file carries no notion of one', () async {
      // An imported board arrives with every button at level 1 and no idea how
      // much of itself to show. Anything below 3 would hide words the file
      // plainly contains.
      final outcome = await roundTrip();
      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals(outcome.profileId!))).getSingle();

      expect(profile.vocabLevel, 3);
    });

    test('and it is not recording anybody until somebody says so', () async {
      final outcome = await roundTrip();
      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals(outcome.profileId!))).getSingle();

      expect(profile.settingsJson, contains('"usageTracking":false'));
    });

    test('a file that is not a board says so instead of throwing', () async {
      final outcome = await importBoardFile(
        db,
        name: 'broken.obf',
        bytes: utf8.encode('this is not json'),
        displayName: 'Sam',
      );

      // A caregiver holding a file that will not open needs a sentence they
      // can act on, not a crash on the one screen that could have said why.
      expect(outcome.profileId, isNull);
      expect(outcome.problem, isNotNull);

      // And nobody was created for a file that could not be read. The seeded
      // board set brings one profile with it; a failed import must not add a
      // second, half-built one.
      expect(await db.select(db.profiles).get(), hasLength(1));
    });

    test('a file that has gone says so too', () async {
      final written = await store.exportVocabulary(vocabularyId);
      File(written.path).deleteSync();

      final outcome = await store.import(written);
      expect(outcome.problem, contains('no longer'));
      expect(outcome.profileId, isNull);
    });

    test('the extension decides which reader is used', () async {
      // A `.obf` is one board of JSON; handing its bytes to the zip reader
      // would report a corrupt archive for a file that is fine.
      final board = await (db.select(
        db.boards,
      )..where((b) => b.vocabularyId.equals(vocabularyId))).get();
      expect(board, isNotEmpty, reason: 'the premise');

      final outcome = await importBoardFile(
        db,
        name: 'one.obf',
        bytes: utf8.encode(
          jsonEncode({
            'format': 'open-board-0.1',
            'id': 'b1',
            'name': 'One',
            'buttons': [
              {'id': '1', 'label': 'hello'},
            ],
            'grid': {
              'rows': 1,
              'columns': 1,
              'order': [
                ['1'],
              ],
            },
          }),
        ),
        displayName: 'One',
      );

      expect(outcome.problem, isNull);
      expect(outcome.profileId, isNotNull);
    });
  });

  group('removing a file', () {
    test('takes the file and leaves anything imported from it', () async {
      final written = await store.exportVocabulary(vocabularyId);
      final outcome = await store.import(written, displayName: 'Sam');

      await store.remove(written);

      expect(await store.files(), isEmpty);
      final profile = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals(outcome.profileId!))).getSingleOrNull();
      expect(profile, isNotNull);
    });

    test('and does not object to one that has already gone', () async {
      final written = await store.exportVocabulary(vocabularyId);
      File(written.path).deleteSync();

      await expectLater(store.remove(written), completes);
    });
  });
}
