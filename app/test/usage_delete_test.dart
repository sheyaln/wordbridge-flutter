import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/usage/usage_queries.dart';

/// §4.78. Deleting a usage history, as opposed to stopping one.
///
/// The switch in settings stops the recording from the moment it is turned off
/// and leaves everything already on disk, which is a different promise from the
/// one a person asking to be forgotten is making. Before this the only way to
/// delete a usage history was to uninstall the app, and that takes the board
/// set with it — months of somebody's practice, to erase a log.
void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> record(
    String profileId, {
    required int times,
    String cellId = 'cell',
  }) async {
    for (var i = 0; i < times; i++) {
      await db
          .into(db.usageEvents)
          .insert(
            UsageEventsCompanion.insert(
              deviceId: 'device',
              profileId: profileId,
              vocabularyId: 'vocab',
              boardId: 'board',
              cellId: cellId,
              action: ButtonAction.speak,
              source: UsageSource.touch,
              occurredAt: nowMs(),
            ),
          );
    }
  }

  group('counting what is there', () {
    test('is what the profile recorded, not what the device did', () async {
      await record('maya', times: 3);
      await record('sam', times: 5);

      final usage = UsageQueries(db);
      expect(await usage.recordedFor('maya'), 3);
      expect(await usage.recordedFor('sam'), 5);
    });

    test('and nothing is nothing rather than an error', () async {
      expect(await UsageQueries(db).recordedFor('nobody'), 0);
    });
  });

  group('deleting it', () {
    test('takes the profile’s history', () async {
      await record('maya', times: 4);

      final usage = UsageQueries(db);
      expect(await usage.forgetProfile('maya'), 4);
      expect(await usage.recordedFor('maya'), 0);
    });

    test('and leaves everybody else’s alone', () async {
      // The switch that stops the recording is per profile because what it
      // records is one person's selections. Deleting has to be scoped the same
      // way, or one caregiver clears another child's history from a screen
      // that never named them.
      await record('maya', times: 4);
      await record('sam', times: 6);

      final usage = UsageQueries(db);
      await usage.forgetProfile('maya');

      expect(await usage.recordedFor('sam'), 6);
    });

    test('reports nothing to delete rather than failing', () async {
      expect(await UsageQueries(db).forgetProfile('nobody'), 0);
    });

    test('leaves the board alone', () async {
      // Deleting a log is not deleting a board. Worth stating: these rows are
      // reached through cell and button ids, and a delete written against the
      // wrong table would pass every count assertion above.
      await seedCoreBoardSet(db);
      final boards = (await db.select(db.boards).get()).length;
      final buttons = (await db.select(db.buttons).get()).length;
      expect(boards, greaterThan(0));

      await record('maya', times: 2);
      await UsageQueries(db).forgetProfile('maya');

      expect(await db.select(db.boards).get(), hasLength(boards));
      expect(await db.select(db.buttons).get(), hasLength(buttons));
    });
  });

  group('the sentence somebody agrees to', () {
    test('carries the number, because that is the cost', () {
      expect(usageDeletionWarning(341), contains('341'));
    });

    test('says what stops working', () {
      // The log has one job. Deleting it takes the number out of the remap
      // warning, and that is the thing worth knowing before agreeing.
      expect(usageDeletionWarning(341), contains('practice'));
      expect(usageDeletionWarning(341), contains('move'));
    });

    test('counts one as one', () {
      expect(usageDeletionWarning(1), contains('1 recorded selection.'));
      expect(usageDeletionWarning(2), contains('2 recorded selections.'));
    });

    test('says so when there is nothing to delete', () {
      expect(
        usageDeletionWarning(0),
        'Nothing has been recorded for this profile yet.',
      );
    });

    test('and holds to the house style', () {
      // §5: no dashes or hyphens in anything a person reads.
      for (final n in [0, 1, 2, 341]) {
        expect(usageDeletionWarning(n), isNot(contains('-')));
        expect(usageDeletionWarning(n), isNot(contains('—')));
      }
    });
  });
}
