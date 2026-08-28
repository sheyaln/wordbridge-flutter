import 'dart:ui';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';

const iPadMini = Size(744, 1133);

void main() {
  late WordbridgeDatabase db;
  late ProfileRepository profiles;

  setUp(() {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    profiles = ProfileRepository(db);
  });

  tearDown(() async => db.close());

  GridChoice grid({
    IconSize iconSize = IconSize.medium,
    BoardOrientation orientation = BoardOrientation.landscape,
  }) => GridChoice.derive(
    screen: iPadMini,
    orientation: orientation,
    iconSize: iconSize,
  );

  Future<Profile> create({
    String name = 'Maya',
    IconSize iconSize = IconSize.medium,
    BoardOrientation orientation = BoardOrientation.landscape,
    DateTime? birthDate,
  }) => profiles.create(
    displayName: name,
    grid: grid(iconSize: iconSize, orientation: orientation),
    birthDate: birthDate,
  );

  group('creating a profile', () {
    test('builds a board set at the chosen grid', () async {
      final profile = await create(iconSize: IconSize.large);

      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(profile.activeVocabularyId!))).getSingle();

      final expected = grid(iconSize: IconSize.large);
      expect(vocab.gridRows, expected.rows);
      expect(vocab.gridCols, expected.cols);
    });

    test('records the two answers the grid came from', () async {
      // Stored so settings can show what was chosen, not only its consequence.
      // "9 by 5" means nothing to a caregiver; "large icons, landscape" does.
      final profile = await create(
        iconSize: IconSize.large,
        orientation: BoardOrientation.portrait,
      );

      final settings = ProfileSettings(db, profile.id);
      await settings.load();

      expect(settings.iconSize, IconSize.large);
      expect(settings.orientation, BoardOrientation.portrait);
    });

    test(
      'a grid that cannot work is refused before anything is built',
      () async {
        final impossible = grid(
          iconSize: IconSize.extraLarge,
          orientation: BoardOrientation.portrait,
        );
        expect(impossible.isUsable, isFalse);

        await expectLater(
          profiles.create(displayName: 'Sam', grid: impossible),
          throwsArgumentError,
        );

        expect(await profiles.list(), isEmpty);
        expect(await db.select(db.vocabularies).get(), isEmpty);
      },
    );
  });

  group('two people on one device', () {
    test('each gets their own board set', () async {
      final maya = await create(name: 'Maya');
      final sam = await create(name: 'Sam', iconSize: IconSize.large);

      expect(maya.activeVocabularyId, isNot(sam.activeVocabularyId));

      final vocabularies = await db.select(db.vocabularies).get();
      expect(vocabularies, hasLength(2));
    });

    test('one person’s board never appears on another’s', () async {
      final maya = await create(name: 'Maya');
      final sam = await create(name: 'Sam');

      final mayaButtons = await (db.select(
        db.buttons,
      )..where((b) => b.vocabularyId.equals(maya.activeVocabularyId!))).get();

      final sansBoards = await (db.select(
        db.boards,
      )..where((b) => b.vocabularyId.equals(sam.activeVocabularyId!))).get();
      final samBoardIds = sansBoards.map((b) => b.id).toSet();

      final cells = await db.select(db.cells).get();
      final cellBoard = {for (final c in cells) c.id: c.boardId};

      for (final button in mayaButtons) {
        expect(
          samBoardIds,
          isNot(contains(cellBoard[button.cellId])),
          reason: '"${button.label}" from Maya landed on Sam’s board',
        );
      }
    });

    test('settings do not leak between them', () async {
      final maya = await create(name: 'Maya');
      final sam = await create(name: 'Sam');

      final mayaSettings = ProfileSettings(db, maya.id);
      final samSettings = ProfileSettings(db, sam.id);
      await mayaSettings.load();
      await samSettings.load();

      await mayaSettings.set('filterVerbs', true);
      await samSettings.load();

      expect(mayaSettings.filterVerbs, isTrue);
      expect(samSettings.filterVerbs, isFalse);
    });

    test('writing a setting does not overwrite the name', () async {
      // The settings writer used to upsert a whole profile row, which would
      // have replaced a person's name with a placeholder on the next toggle.
      final maya = await create(name: 'Maya');

      final settings = ProfileSettings(db, maya.id);
      await settings.load();
      await settings.set('autoReturn', false);

      final after = await profiles.byId(maya.id);
      expect(after!.displayName, 'Maya');
      expect(after.activeVocabularyId, maya.activeVocabularyId);
    });
  });

  group('resuming', () {
    test('launch goes back to whoever was last using the device', () async {
      await create(name: 'Maya');
      final sam = await create(name: 'Sam');

      expect((await profiles.resume())!.id, sam.id);

      await profiles.remember((await profiles.list()).first.id);
      expect((await profiles.resume())!.displayName, 'Maya');
    });

    test('a fresh install has nobody to resume', () async {
      expect(await profiles.resume(), isNull);
    });

    test('a removed profile is not resumed', () async {
      final maya = await create(name: 'Maya');
      await profiles.archive(maya.id);

      expect(await profiles.resume(), isNull);
    });
  });

  group('removing a profile', () {
    test('keeps the board and the history', () async {
      // A hard delete would take a whole board set and every hour of practice
      // behind it on one tap.
      final maya = await create(name: 'Maya');
      final buttonsBefore = await db.select(db.buttons).get();

      await profiles.archive(maya.id);

      expect(await profiles.list(), isEmpty);
      expect(await profiles.byId(maya.id), isNotNull);
      expect(
        await db.select(db.buttons).get(),
        hasLength(buttonsBefore.length),
      );
    });

    test('the device falls back to someone who is left', () async {
      final maya = await create(name: 'Maya');
      await create(name: 'Sam');

      await profiles.archive(maya.id);
      expect((await profiles.resume())!.displayName, 'Sam');
    });
  });

  test('an existing single-profile install keeps working', () async {
    // What is already on a device: one profile from before profiles existed,
    // with no birthday and nothing remembered. It must resume, not be treated
    // as a fresh install and sent through setup.
    await seedCoreBoardSet(db);

    final resumed = await profiles.resume();
    expect(resumed, isNotNull);
    expect(resumed!.activeVocabularyId, isNotNull);
  });
}
