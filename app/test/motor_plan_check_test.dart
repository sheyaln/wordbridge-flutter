import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/developer/motor_plan_check.dart';
import 'package:wordbridge/features/editor/remap.dart';

/// The one invariant this app has, asked of a real device.
///
/// `motor_plan_invariant_test.dart` asks it of a database that was seeded a
/// moment ago. The devices that matter are the ones that have had a top-up, an
/// import, a row moved and a pin taken back, months apart, and none of that
/// happens in a test — so there has to be a way to ask a tablet in somebody's
/// hands whether every word is still where it was.
///
/// What this guards against is the check being reassuring rather than true: a
/// comparison that missed a move, or reported one where a word had merely been
/// hidden, would be worse than having no check, because somebody would believe
/// it.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    vocabularyId = await seedCoreBoardSet(db, rows: 7, cols: 12);
  });

  tearDown(() => db.close());

  /// A word on the board, and a location nothing is using.
  Future<Button> anyWord() async =>
      (await (db.select(db.buttons)
                ..where((b) => b.vocabularyId.equals(vocabularyId))
                ..where((b) => b.isSystem.equals(false))
                ..limit(1))
              .get())
          .single;

  Future<Cell> aFreeCell() async =>
      (await (db.select(db.cells)
                ..where((c) => c.state.equalsValue(CellState.emptyReserved))
                ..limit(1))
              .get())
          .single;

  group('a board set nobody has touched', () {
    test('reports that nothing has moved', () async {
      final before = await motorPlanOf(db, vocabularyId);
      final after = await motorPlanOf(db, vocabularyId);

      final check = compareMotorPlans(before, after);

      expect(check.holds, isTrue);
      expect(check.moved, isEmpty);
      expect(check.added, isEmpty);
      expect(check.removed, isEmpty);
      expect(check.unchanged, before.length);
      expect(before, isNotEmpty, reason: 'the premise');
    });

    test('and hiding a word is not a move', () async {
      // A hidden word keeps its location, which is the whole promise. A check
      // that called this a move would cry wolf on the one operation that is
      // guaranteed safe.
      final before = await motorPlanOf(db, vocabularyId);
      final word = await anyWord();

      await (db.update(db.buttons)..where((b) => b.id.equals(word.id))).write(
        const ButtonsCompanion(hidden: Value(true)),
      );

      final check = compareMotorPlans(
        before,
        await motorPlanOf(db, vocabularyId),
      );

      expect(check.holds, isTrue);
      expect(check.unchanged, before.length);
    });
  });

  group('a word that has moved', () {
    test('is named, with where it was and where it is', () async {
      final before = await motorPlanOf(db, vocabularyId);
      final word = await anyWord();
      final was = before[word.id]!.path;
      final target = await aFreeCell();

      await RemapService(db).moveButton(buttonId: word.id, toCellId: target.id);

      final check = compareMotorPlans(
        before,
        await motorPlanOf(db, vocabularyId),
      );

      expect(check.holds, isFalse);
      expect(check.moved, hasLength(1));
      expect(check.moved.single.label, word.label);
      expect(check.moved.single.was, was);
      expect(check.moved.single.now, (
        boardId: target.boardId,
        row: target.row,
        col: target.col,
      ));
      expect(check.unchanged, before.length - 1);
    });
  });

  group('a word arriving and a word leaving', () {
    test('are reported, and neither is a move', () async {
      // Both are things somebody does on purpose. Only a word that is
      // somewhere else is the invariant broken.
      final before = await motorPlanOf(db, vocabularyId);
      final word = await anyWord();
      final target = await aFreeCell();

      await RemapService(db).deleteButton(buttonId: word.id);
      final added = await db
          .into(db.buttons)
          .insertReturning(
            ButtonsCompanion.insert(
              id: newId(),
              cellId: Value(target.id),
              vocabularyId: vocabularyId,
              label: 'kayak',
              message: 'kayak',
              action: ButtonAction.speak,
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );

      final check = compareMotorPlans(
        before,
        await motorPlanOf(db, vocabularyId),
      );

      expect(check.holds, isTrue);
      expect(check.removed, [word.label]);
      expect(check.added, [added.label]);
    });
  });

  group('the fingerprint kept between runs', () {
    test('reads back exactly what was written', () async {
      final store = MotorPlanStore(db);
      final plan = await motorPlanOf(db, vocabularyId);

      await store.write(vocabularyId, plan);
      final read = await store.read();

      expect(read, isNotNull);
      expect(read!.vocabularyId, vocabularyId);
      expect(read.plan, plan);
      // Round tripped through JSON, so a check run after a restart compares
      // the same paths rather than paths that have lost a field.
      expect(compareMotorPlans(read.plan, plan).holds, isTrue);
    });

    test('and is nothing at all before one is taken', () async {
      expect(await MotorPlanStore(db).read(), isNull);
    });

    test('and a row nothing can parse reads as no fingerprint', () async {
      // The recovery is to take another one, which is one tap. Throwing would
      // take a developer screen down over a row nobody can act on.
      await db
          .into(db.appState)
          .insert(
            AppStateCompanion.insert(
              key: MotorPlanStore.key,
              value: '{"plan": "not a map"}',
            ),
          );

      expect(await MotorPlanStore(db).read(), isNull);
    });
  });
}
