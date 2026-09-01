import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';

void main() {
  group('working out the band from a birthday', () {
    final today = DateTime(2026, 8, 27);

    AgeBand at(int year, [int month = 1, int day = 1]) =>
        AgeBand.forBirthDate(DateTime(year, month, day), now: today);

    test('each range lands where it should', () {
      expect(at(2023), AgeBand.earlyYears);
      expect(at(2018), AgeBand.child);
      expect(at(2010), AgeBand.teen);
      expect(at(1990), AgeBand.adult);
    });

    test('a birthday that has not happened yet has not happened yet', () {
      // Someone turning 18 in December is 17 in August. Rounding up would hand
      // a teenager the adult preset with swearing switched on by default.
      expect(at(2008, 12, 25), AgeBand.teen);
      expect(at(2008, 1, 25), AgeBand.adult);
    });

    test('a birthday on today counts', () {
      expect(at(2008, 8, 27), AgeBand.adult);
    });

    test('no birthday means the preset that assumes least', () {
      // Recording a date of birth is not a condition of getting a voice.
      expect(AgeBand.forBirthDate(null), AgeBand.child);
    });

    test('a date in the future does not produce a negative age', () {
      expect(at(2030), AgeBand.child);
    });
  });

  group('what each preset receives', () {
    test('only teenagers and adults get strong language', () {
      expect(AgeBand.earlyYears.canSwear, isFalse);
      expect(AgeBand.child.canSwear, isFalse);
      expect(AgeBand.teen.canSwear, isTrue);
      expect(AgeBand.adult.canSwear, isTrue);
    });

    test('it starts on for adults and off for teenagers', () {
      expect(AgeBand.adult.swearsByDefault, isTrue);
      expect(AgeBand.teen.swearsByDefault, isFalse);
    });

    test('the youngest preset starts on core words alone', () {
      expect(AgeBand.earlyYears.startingLevel, 1);
      expect(AgeBand.child.startingLevel, greaterThan(1));
    });
  });

  group('seeding by preset', () {
    late WordbridgeDatabase db;

    setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    Future<Set<String>> labelsFor(String vocabId, {bool? visible}) async {
      final query = db.select(db.buttons)
        ..where((b) => b.vocabularyId.equals(vocabId));
      final rows = await query.get();
      return {
        for (final b in rows)
          if (visible == null || b.hidden != visible) b.label,
      };
    }

    test('an adult board can say what an adult needs to say', () async {
      final id = await seedCoreBoardSet(db, ageBand: AgeBand.adult);
      final labels = await labelsFor(id);

      expect(
        labels,
        containsAll(['medication', 'appointment', 'partner', 'patronized']),
      );
    });

    test('a child board does not carry adult vocabulary', () async {
      final id = await seedCoreBoardSet(db, ageBand: AgeBand.child);
      final labels = await labelsFor(id);

      expect(labels, isNot(contains('landlord')));
      expect(labels, isNot(contains('fuck')));
      expect(labels, isNot(contains('penis')));
    });

    group('and an adult can name their own body', () {
      // The half of "name a body part to a doctor" the `self care` band leaves
      // out. An adult who cannot name their own genitals cannot describe pain
      // in them, cannot consent, and cannot report being touched.
      test('in plain words rather than euphemisms', () async {
        final id = await seedCoreBoardSet(db, ageBand: AgeBand.adult);
        final labels = await labelsFor(id);

        expect(
          labels,
          containsAll(['penis', 'vulva', 'vagina', 'breast', 'anus']),
        );
        expect(labels, containsAll(['do not touch me']));
      });

      test('and it is not behind the profanity switch', () async {
        // That switch gates the words somebody chooses to swear with. Behind
        // one control, a caregiver turning off strong language would also take
        // away the vocabulary for a medical appointment.
        final id = await seedCoreBoardSet(
          db,
          ageBand: AgeBand.adult,
          profanity: false,
        );

        final visible = await labelsFor(id, visible: true);
        expect(visible, contains('penis'));
        expect(
          visible,
          isNot(contains('fuck')),
          reason: 'the premise: strong language really is switched off',
        );
      });

      test('and `butt` stays where a child can reach it', () async {
        // An ordinary body part on the ordinary band (§4.42), not something
        // an adult preset unlocks.
        final id = await seedCoreBoardSet(db, ageBand: AgeBand.child);
        expect(await labelsFor(id), contains('butt'));
      });
    });

    test('a teenager gets teenage words', () async {
      final id = await seedCoreBoardSet(db, ageBand: AgeBand.teen);
      final labels = await labelsFor(id);

      expect(labels, containsAll(['annoyed', 'college', 'headphones']));
    });

    test('the core board is the same whatever the preset', () async {
      // A birthday changes the fringe, never the motor plan. Re-teaching where
      // "want" lives because someone turned thirteen would be absurd.
      Future<Map<String, String>> homeOf(AgeBand band) async {
        final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        addTearDown(fresh.close);

        await seedCoreBoardSet(fresh, ageBand: band);
        final root = await (fresh.select(
          fresh.boards,
        )..where((b) => b.kind.equalsValue(BoardKind.root))).getSingle();

        final query = fresh.select(fresh.buttons).join([
          innerJoin(
            fresh.cells,
            fresh.cells.id.equalsExp(fresh.buttons.cellId),
          ),
        ])..where(fresh.cells.boardId.equals(root.id));

        return {
          for (final r in await query.get())
            '${r.readTable(fresh.cells).row},${r.readTable(fresh.cells).col}': r
                .readTable(fresh.buttons)
                .label,
        };
      }

      final child = await homeOf(AgeBand.child);
      for (final band in AgeBand.values) {
        expect(await homeOf(band), child, reason: '${band.label} moved a word');
      }
    });
  });

  group('strong language is hidden, never absent', () {
    test('a teenager gets the words, switched off', () async {
      final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final id = await seedCoreBoardSet(db, ageBand: AgeBand.teen);
      final rows =
          await (db.select(db.buttons)..where(
                (b) => b.vocabularyId.equals(id) & b.label.equals('shit'),
              ))
              .get();

      expect(rows, hasLength(1));
      expect(
        rows.single.hidden,
        isTrue,
        reason: 'a teenage profile starts with strong language switched off',
      );
    });

    test('switching it on moves nothing', () async {
      // The whole reason it is seeded hidden rather than left out. If the
      // words were added later they would take whatever locations were free by
      // then, and everything after them would shift.
      Future<Map<String, String>> feelingsOf({required bool profanity}) async {
        final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);

        await seedCoreBoardSet(
          db,
          ageBand: AgeBand.adult,
          profanity: profanity,
        );

        final board = await (db.select(
          db.boards,
        )..where((b) => b.name.equals('feelings'))).getSingle();

        final query = db.select(db.buttons).join([
          innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
        ])..where(db.cells.boardId.equals(board.id));

        return {
          for (final r in await query.get())
            '${r.readTable(db.cells).row},${r.readTable(db.cells).col}': r
                .readTable(db.buttons)
                .label,
        };
      }

      expect(
        await feelingsOf(profanity: false),
        await feelingsOf(profanity: true),
      );
    });

    test('a hidden word still holds its location', () async {
      final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final id = await seedCoreBoardSet(
        db,
        ageBand: AgeBand.adult,
        profanity: false,
      );

      final query = db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.buttons.vocabularyId.equals(id) & db.buttons.hidden);

      final hidden = await query.get();
      expect(hidden, isNotEmpty);

      for (final r in hidden) {
        expect(
          r.readTable(db.cells).state,
          CellState.occupied,
          reason: 'hiding a word must never free its location',
        );
      }
    });
  });

  group('one word, one location', () {
    // A preset appends to the shipped bands, so a word it repeats is a second
    // place to learn for the same thing and a second place usage is split
    // between. Every preset, because the shipped board is the same underneath
    // all of them and only the extras differ.
    for (final ageBand in AgeBand.values) {
      test('${ageBand.name} says "maybe" in exactly one place', () async {
        final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);

        final id = await seedCoreBoardSet(db, ageBand: ageBand);

        final query = db.select(db.buttons)
          ..where(
            (b) =>
                b.vocabularyId.equals(id) &
                b.label.equals('maybe') &
                b.deletedAt.isNull(),
          );

        expect(await query.get(), hasLength(1));
      });
    }
  });
}
