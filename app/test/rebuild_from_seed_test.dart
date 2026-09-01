import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/rebuild_from_seed.dart';

/// Getting a change to the shipped vocabulary onto a board already built.
///
/// A board set is materialized once and nothing re-runs it, so a word removed
/// from the seed goes on sitting in the pinned column of a board that was
/// built before the change. That is the right rule for somebody who has
/// learned a layout and the wrong one while the layout is still being drawn.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;

  const profileId = 'p1';

  Future<List<String>> labelsIn(String vocabId) async {
    final rows =
        await (db.select(db.buttons)..where(
              (b) => b.vocabularyId.equals(vocabId) & b.cellId.isNotNull(),
            ))
            .get();
    return [for (final b in rows) b.label];
  }

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());

    final ts = nowMs();
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: 'Maya',
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
  });

  tearDown(() => db.close());

  /// A word the seed no longer places, sitting where an older build left it.
  Future<void> leaveStaleWord(String label) async {
    final free =
        await (db.select(db.cells)
              ..where((c) => c.state.equalsValue(CellState.emptyReserved))
              ..limit(1))
            .getSingle();

    await placeButton(
      db,
      vocabularyId: vocabularyId,
      cellId: free.id,
      label: label,
      message: label,
    );
  }

  test('a word the seed no longer ships is gone afterwards', () async {
    await leaveStaleWord('?');
    expect(await labelsIn(vocabularyId), contains('?'));

    final rebuilt = await rebuildFromSeed(
      db,
      profileId: profileId,
      vocabularyId: vocabularyId,
    );

    expect(rebuilt, isNot(vocabularyId));
    expect(await labelsIn(rebuilt), isNot(contains('?')));
  });

  test('a word the seed does ship arrives', () async {
    final rebuilt = await rebuildFromSeed(
      db,
      profileId: profileId,
      vocabularyId: vocabularyId,
    );

    expect(await labelsIn(rebuilt), contains('how'));
  });

  test('the profile is pointed at the new boards', () async {
    final rebuilt = await rebuildFromSeed(
      db,
      profileId: profileId,
      vocabularyId: vocabularyId,
    );

    final profile = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals(profileId))).getSingle();

    expect(profile.activeVocabularyId, rebuilt);
  });

  test('the grid is kept', () async {
    final narrow = await seedCoreBoardSet(
      db,
      rows: 6,
      cols: 10,
      profileId: 'p2',
      name: 'narrow',
    );

    final rebuilt = await rebuildFromSeed(
      db,
      profileId: 'p2',
      vocabularyId: narrow,
    );

    final vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(rebuilt))).getSingle();

    expect((vocab.gridRows, vocab.gridCols), (6, 10));
  });

  group('what it says it will cost', () {
    test('a hand-added word is named, and a shipped one is not', () async {
      await leaveStaleWord('marmalade');

      final impact = await rebuildImpact(
        db,
        profileId: profileId,
        vocabularyId: vocabularyId,
      );

      expect(impact.handAdded, contains('marmalade'));
      expect(impact.handAdded, isNot(contains('want')));
      expect(impact.handAdded, isNot(contains('how')));
    });

    test('a board nobody has touched costs nothing to rebuild', () async {
      final impact = await rebuildImpact(
        db,
        profileId: profileId,
        vocabularyId: vocabularyId,
      );

      expect(impact.handAdded, isEmpty);
      expect(impact.recordedTaps, 0);
      expect((impact.rows, impact.cols), (7, 12));
    });

    test('the shipped set knows what an age preset adds', () async {
      // The extras a preset appends are shipped words, not somebody's own, so
      // rebuilding a teen board must not offer to discard them.
      final shipped = shippedLabels(AgeBand.teen);
      expect(shipped, contains('how'));
      expect(shipped.length, greaterThan(shippedLabels(AgeBand.child).length));
    });
  });

  test(
    'the old boards are kept, because the history names their cells',
    () async {
      final rebuilt = await rebuildFromSeed(
        db,
        profileId: profileId,
        vocabularyId: vocabularyId,
      );

      final old = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabularyId))).getSingleOrNull();

      expect(old, isNotNull);
      expect(await labelsIn(vocabularyId), isNotEmpty);
      expect(rebuilt, isNot(vocabularyId));
    },
  );
}
