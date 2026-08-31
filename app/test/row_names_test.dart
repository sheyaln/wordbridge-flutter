import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/grid/region_labels.dart';

/// §4.26. A caregiver saying what a row is for.
///
/// The labels in §4.19 come from the shipped layout, so a board somebody made
/// by hand has none and a row whose contents they changed keeps the name the
/// seed gave it. Both are cases where the person who knows the user should be
/// able to say what a row holds.
void main() {
  const oneBand = BoardRegions(
    axis: BandAxis.rows,
    bands: [(name: 'verbs', first: 1, last: 3)],
  );

  group('what a caregiver chose', () {
    test('survives being written down and read back', () {
      final names = RegionNames.empty.with_(1, 'swimming club');
      expect(
        RegionNames.decode(RegionNames.encode(names)).forLine(1),
        'swimming club',
      );
    });

    test('a name is trimmed, and an empty one is no name', () {
      expect(RegionNames.empty.with_(1, '  fruit  ').forLine(1), 'fruit');
      expect(RegionNames.empty.with_(1, '   ').forLine(1), isNull);
      expect(RegionNames.empty.with_(1, 'fruit').with_(1, '').isEmpty, isTrue);
    });

    test('and clearing one falls back to what the layout called it', () {
      final named = RegionNames.empty.with_(1, 'swimming club');
      expect(named.without(1).forLine(1), isNull);
    });

    test('nothing recorded reads as nothing named', () {
      expect(RegionNames.decode(null).isEmpty, isTrue);
      expect(RegionNames.decode('').isEmpty, isTrue);
    });

    test('and a damaged column does not stop the board drawing', () {
      // A board that will not draw is worse than one whose rows are unnamed.
      expect(RegionNames.decode('not json').isEmpty, isTrue);
      expect(RegionNames.decode('{"x":"y"}').isEmpty, isTrue);
      expect(RegionNames.decode('{"1":null}').isEmpty, isTrue);
    });
  });

  group('what the strip draws', () {
    test('the layout\'s own names, where nobody has chosen one', () {
      final labels = regionLabels(regions: oneBand, names: RegionNames.empty);

      expect(labels, hasLength(1));
      expect(labels.single.name, 'doing');
      expect(labels.single.first, 1);
      expect(labels.single.last, 3);
    });

    test('a chosen name over the top, keeping what it covers', () {
      // The name is what changes, not the extent. A renamed band still sits
      // over the lines it owns.
      final labels = regionLabels(
        regions: oneBand,
        names: RegionNames.empty.with_(1, 'swimming club'),
      );

      expect(labels.single.name, 'swimming club');
      expect(labels.single.first, 1);
      expect(labels.single.last, 3);
    });

    test('and a name on a line no band owns stands on its own', () {
      // The only kind a board somebody made by hand can have.
      final labels = regionLabels(
        regions: null,
        names: RegionNames.empty.with_(2, 'swimming club'),
      );

      expect(labels, hasLength(1));
      expect(labels.single.first, 2);
      expect(labels.single.last, 2);
    });

    test('in line order, whichever way they arrived', () {
      final labels = regionLabels(
        regions: oneBand,
        names: RegionNames.empty.with_(5, 'later').with_(0, 'first'),
      );

      expect([for (final l in labels) l.first], [0, 1, 5]);
    });

    test('and a name inside a band, not at its start, is its own label', () {
      // Naming line 2 of a band that runs 1–3 does not rename the band: the
      // caregiver pointed at a line, and the line is what gets the name.
      final labels = regionLabels(
        regions: oneBand,
        names: RegionNames.empty.with_(2, 'swimming club'),
      );

      expect(labels, hasLength(1));
      expect(labels.single.name, 'doing');
    });
  });

  group('the editor also shows the rows with nothing on them', () {
    test('so there is somewhere to tap', () {
      final labels = editableRegionLabels(
        regions: oneBand,
        names: RegionNames.empty,
        lines: 6,
      );

      expect([for (final l in labels) l.first], [0, 1, 4, 5]);
      expect(labels.first.name, isEmpty);
      expect(labels[1].name, 'doing');
    });

    test('and a board with no bands is all empty slots', () {
      final labels = editableRegionLabels(
        regions: null,
        names: RegionNames.empty,
        lines: 3,
      );

      expect(labels, hasLength(3));
      expect(labels.every((l) => l.name.isEmpty), isTrue);
    });

    test('but the talk screen shows none of them', () {
      // Blanks are scaffolding for whoever is editing. In front of the user
      // they would be chrome that says nothing.
      expect(regionLabels(regions: null, names: RegionNames.empty), isEmpty);
    });
  });

  group('the names a caregiver is offered', () {
    test('are the ones the shipped layout already uses', () {
      expect(namesToOffer, contains('doing'));
      expect(namesToOffer, contains('people you know'));
      expect(namesToOffer, contains('word endings'));
    });

    test('and are sorted, because the list is long', () {
      final sorted = [...namesToOffer]..sort();
      expect(namesToOffer, sorted);
    });

    test('with no duplicates', () {
      expect(namesToOffer.toSet(), hasLength(namesToOffer.length));
    });
  });

  group('what the board records', () {
    late WordbridgeDatabase db;

    setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('nothing, until somebody names something', () async {
      await seedCoreBoardSet(db, rows: 7, cols: 12);

      for (final board in await db.select(db.boards).get()) {
        expect(
          board.lineNames,
          isNull,
          reason: 'a board arrived carrying a name nobody chose',
        );
      }
    });

    test('and a name is kept separate from what the layout decided', () async {
      final vocabularyId = await seedCoreBoardSet(db, rows: 7, cols: 12);
      final board = (await (db.select(
        db.boards,
      )..where((b) => b.vocabularyId.equals(vocabularyId))).get()).first;

      await (db.update(db.boards)..where((b) => b.id.equals(board.id))).write(
        BoardsCompanion(
          lineNames: Value(
            RegionNames.encode(RegionNames.empty.with_(1, 'swimming club')),
          ),
        ),
      );

      final after = await (db.select(
        db.boards,
      )..where((b) => b.id.equals(board.id))).getSingle();

      // What a person chose and what the layout decided must never be
      // confused for one another.
      expect(after.bandMap, board.bandMap);
      expect(RegionNames.decode(after.lineNames).forLine(1), 'swimming club');
    });
  });
}
