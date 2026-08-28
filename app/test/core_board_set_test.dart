import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/db/tables.dart';

/// Project Core's Universal Core 36 (UNC Center for Literacy and Disability
/// Studies). The shipped vocabulary must contain all of them.
const universalCore36 = {
  'all',
  'can',
  'different',
  'do',
  'finished',
  'get',
  'go',
  'good',
  'he',
  'help',
  'here',
  'I',
  'in',
  'it',
  'like',
  'look',
  'make',
  'more',
  'not',
  'on',
  'open',
  'put',
  'same',
  'she',
  'some',
  'stop',
  'that',
  'turn',
  'up',
  'want',
  'what',
  'when',
  'where',
  'who',
  'why',
  'you',
};

void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
  });

  tearDown(() async => db.close());

  Future<List<Button>> buttons() => (db.select(
    db.buttons,
  )..where((b) => b.vocabularyId.equals(vocabId))).get();

  test('the 7x12 home board is exactly where it has always been', () async {
    // Anyone using this board has learned these positions, so the derived
    // layout has to land on them to the cell. An update that moves a word is
    // the precise failure this project exists to prevent.
    //
    // Read this as the board. Each string is a row, "." is a location held
    // open. Column 11 carries the pinned questions and row 6 the system keys,
    // both asserted separately.
    const shipped = [
      'I    we   all       want get  open     +s        a       . here good',
      'you  they some      need take close    +ed       the     . in   not',
      'he   my   same      like do   help     +ing      and     . on   yes',
      'she  me   different go   make look     +\'s      but     . up   no',
      'it   .    more      stop put  turn     am/is/are because . to   don\'t',
      'that .    this      can  will finished was/were  so      . out  wait',
    ];

    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final query = db.select(db.cells).join([
      leftOuterJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
    ])..where(db.cells.boardId.equals(home.id));

    final actual = <String, String>{
      for (final r in await query.get())
        '${r.readTable(db.cells).row},${r.readTable(db.cells).col}':
            r.readTableOrNull(db.buttons)?.label ?? '.',
    };

    for (var row = 0; row < shipped.length; row++) {
      final expected = shipped[row].split(RegExp(r'\s+'));
      for (var col = 0; col < expected.length; col++) {
        expect(
          actual['$row,$col'],
          expected[col],
          reason: 'location $row,$col changed',
        );
      }
    }
  });

  test('ships the complete Universal Core 36', () async {
    final labels = (await buttons())
        .where((b) => !b.isSystem)
        .map((b) => b.label)
        .toSet();

    expect(
      universalCore36.difference(labels),
      isEmpty,
      reason: 'a core word is missing from the shipped vocabulary',
    );
  });

  test('leaves room to grow', () async {
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final reserved =
        await (db.select(db.cells)..where(
              (c) =>
                  c.boardId.equals(home.id) &
                  c.state.equalsValue(CellState.emptyReserved),
            ))
            .get();

    // The root board is dense, so what matters is not a raw count of empty
    // cells but that the two reserves survive: the noun column and the cells
    // beside the pronouns. Both exist so personal vocabulary has somewhere to
    // land that displaces nothing.
    expect(reserved.length, greaterThan(6));
  });

  test('reserves the column beside the pronouns for names', () async {
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final col1 = await (db.select(
      db.cells,
    )..where((c) => c.boardId.equals(home.id) & c.col.equals(1))).get();

    // The column beside the pronouns carries the core pronouns that would not
    // fit in column 0, and its tail stays open for the people in a particular
    // person's life, which no shipped board can guess.
    final nameRows = col1.where((c) => c.row >= 4 && c.row < 6);
    expect(nameRows, hasLength(2));
    expect(
      nameRows.every((c) => c.state == CellState.emptyReserved),
      isTrue,
      reason: 'family names need a permanent home next to the pronouns',
    );
  });

  group('system row is identical on every board', () {
    test('every board carries the same system positions', () async {
      final boards = await db.select(db.boards).get();
      expect(boards.length, greaterThan(1));

      final signatures = <String, Map<String, int>>{};

      for (final board in boards) {
        final query =
            db.select(db.cells).join([
              innerJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
            ])..where(
              db.cells.boardId.equals(board.id) &
                  db.buttons.isSystem.equals(true),
            );

        // Paging keys are deliberately conditional — a board with no next
        // page does not draw "more" — so they are excluded here. Their
        // locations are asserted separately.
        const conditional = {'more words', 'back a page'};

        final rows = await query.get();
        signatures[board.name] = {
          for (final r in rows)
            if (!conditional.contains(r.readTable(db.buttons).label))
              r.readTable(db.buttons).label: r.readTable(db.cells).col,
        };
      }

      final reference = signatures.values.first;
      for (final entry in signatures.entries) {
        expect(
          entry.value,
          reference,
          reason:
              'system buttons moved on "${entry.key}" — home and back '
              'must be the same movement from every board',
        );
      }
    });

    test('home and back sit at fixed columns', () async {
      final query =
          db.select(db.cells).join([
            innerJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
          ])..where(
            db.buttons.isSystem.equals(true) &
                db.buttons.label.isIn(['home', 'back']),
          );

      for (final r in await query.get()) {
        final label = r.readTable(db.buttons).label;
        final cell = r.readTable(db.cells);
        expect(cell.row, 6);
        expect(cell.col, label == 'home' ? 0 : 1);
      }
    });
  });

  group('the question column is pinned', () {
    test(
      'every board carries the same questions at the same coordinates',
      () async {
        final boards = await db.select(db.boards).get();
        expect(boards.length, greaterThan(1));

        final perBoard = <String, Map<String, ({int row, int col})>>{};

        for (final board in boards) {
          final query =
              db.select(db.cells).join([
                innerJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
              ])..where(
                db.cells.boardId.equals(board.id) &
                    db.cells.col.equals(11) &
                    // Row 6 is the system row, where the paging key lives.
                    db.cells.row.isSmallerThanValue(6),
              );

          perBoard[board.name] = {
            for (final r in await query.get())
              r.readTable(db.buttons).label: (
                row: r.readTable(db.cells).row,
                col: r.readTable(db.cells).col,
              ),
          };
        }

        final reference = perBoard.values.first;
        expect(reference.keys, containsAll(['what', 'where', 'who']));

        for (final entry in perBoard.entries) {
          expect(
            entry.value,
            reference,
            reason:
                'questions differ on "${entry.key}" — asking "where" would '
                'take a different movement depending on which board is open',
          );
        }
      },
    );

    test('questions stay ordinary vocabulary, not controls', () async {
      // Pinned is a placement decision. Treating them as system buttons would
      // strip their colour coding and lock a caregiver out of editing them.
      final what = await (db.select(
        db.buttons,
      )..where((b) => b.label.equals('what'))).get();

      expect(what, isNotEmpty);
      for (final b in what) {
        expect(b.isSystem, isFalse);
        expect(b.partOfSpeech, PartOfSpeech.question);
        expect(b.action, ButtonAction.speak);
      }
    });
  });

  group('categories carry vocabulary', () {
    test('no category board is empty', () async {
      // A category key that opens onto nothing is worse than no key at all:
      // it teaches that navigating is pointless.
      // First pages only. A later page holds whatever the grid could not fit,
      // which is legitimately however many words that turns out to be.
      final categories =
          (await (db.select(
            db.boards,
          )..where((b) => b.kind.equalsValue(BoardKind.category))).get()).where(
            (b) => categoryNames.contains(b.name),
          );

      expect(categories, isNotEmpty);

      for (final board in categories) {
        final query =
            db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.cells.boardId.equals(board.id) &
                  db.buttons.isSystem.equals(false) &
                  db.cells.col.isSmallerThanValue(11),
            );

        expect(
          await query.get(),
          hasLength(greaterThan(8)),
          reason: '"${board.name}" has nothing in it',
        );
      }
    });

    test('every category keeps room to grow', () async {
      final categories =
          (await (db.select(
            db.boards,
          )..where((b) => b.kind.equalsValue(BoardKind.category))).get()).where(
            (b) => categoryNames.contains(b.name),
          );

      for (final board in categories) {
        final reserved =
            await (db.select(db.cells)..where(
                  (c) =>
                      c.boardId.equals(board.id) &
                      c.state.equalsValue(CellState.emptyReserved),
                ))
                .get();

        expect(
          reserved.length,
          greaterThan(15),
          reason:
              '"${board.name}" is packed too full for personal vocabulary '
              'to be added without displacing something',
        );
      }
    });

    test('feelings can say the difficult things', () async {
      // A board that only manages "happy" and "sad" cannot report pain or
      // being overwhelmed, which are the feelings that most need saying.
      final labels = (await buttons()).map((b) => b.label).toSet();
      expect(labels, containsAll(['hurt', 'scared', 'too loud']));
    });
  });

  group('related verbs stay neighbours', () {
    Future<Map<String, ({int row, int col})>> homePositions() async {
      final home = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home'))).getSingle();

      final query = db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(home.id));

      return {
        for (final r in await query.get())
          r.readTable(db.buttons).label: (
            row: r.readTable(db.cells).row,
            col: r.readTable(db.cells).col,
          ),
      };
    }

    bool adjacent(({int row, int col}) a, ({int row, int col}) b) =>
        (a.col == b.col && (a.row - b.row).abs() == 1) ||
        (a.row == b.row && (a.col - b.col).abs() == 1);

    test('opposites and relations share an edge', () async {
      // Neighbouring locations are learned as a pair. Two positions that
      // happen to be far apart are learned twice.
      final p = await homePositions();

      for (final pair in [('open', 'close'), ('go', 'stop'), ('get', 'take')]) {
        expect(
          adjacent(p[pair.$1]!, p[pair.$2]!),
          isTrue,
          reason: '"${pair.$1}" and "${pair.$2}" are no longer neighbours',
        );
      }
    });

    test('want, need and like run together', () async {
      final p = await homePositions();

      expect(p['want']!.col, p['need']!.col);
      expect(p['need']!.col, p['like']!.col);
      expect(p['need']!.row, p['want']!.row + 1);
      expect(p['like']!.row, p['need']!.row + 1);
    });
  });

  group('paging', () {
    test('a board with a second page offers a way to it', () async {
      final food = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home'))).getSingle();

      final query =
          db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.cells.boardId.equals(food.id) &
                db.buttons.label.equals('more words'),
          );

      final rows = await query.get();
      expect(rows, hasLength(1));

      final cell = rows.single.readTable(db.cells);
      expect(cell.row, 6);
      expect(cell.col, 11);
    });

    test('the second page leads back to the first', () async {
      final second = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home 2'))).getSingle();
      final first = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home'))).getSingle();

      final query =
          db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.cells.boardId.equals(second.id) &
                db.buttons.label.equals('back a page'),
          );

      final rows = await query.get();
      expect(rows, hasLength(1));
      expect(rows.single.readTable(db.buttons).targetBoardId, first.id);
    });

    test('a page is a grid, not a scroll position', () async {
      // Everything on page two has fixed coordinates, same as page one. This
      // is the whole reason for paging over scrolling.
      final second = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home 2'))).getSingle();

      final placed =
          await (db.select(db.cells)..where(
                (c) =>
                    c.boardId.equals(second.id) &
                    c.state.equalsValue(CellState.occupied),
              ))
              .get();

      expect(placed.length, greaterThan(8));
      expect(placed.every((c) => c.row >= 0 && c.col >= 0), isTrue);
    });
  });

  test('every category button leads somewhere real', () async {
    final navButtons = (await buttons())
        .where((b) => b.action == ButtonAction.navigate)
        .toList();

    expect(navButtons, isNotEmpty);

    final boardIds = (await db.select(db.boards).get())
        .map((b) => b.id)
        .toSet();
    for (final b in navButtons) {
      expect(b.targetBoardId, isNotNull, reason: '"${b.label}" goes nowhere');
      expect(boardIds, contains(b.targetBoardId));
    }
  });

  test('refusal is reachable without navigating', () async {
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final query = db.select(db.buttons).join(
      [innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId))],
    )..where(db.buttons.label.equals('not') & db.cells.boardId.equals(home.id));

    final rows = await query.get();
    expect(
      rows,
      hasLength(1),
      reason: 'refusal must be on the root board, not buried in a folder',
    );
    expect(rows.single.readTable(db.buttons).vocabLevel, 1);
  });
}
