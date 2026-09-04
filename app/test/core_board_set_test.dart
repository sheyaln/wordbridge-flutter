import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/grid/region_labels.dart';

/// Project Core's Universal Core 36 (UNC Center for Literacy and Disability
/// Studies). The shipped vocabulary must contain all of them.
///
/// Written as the source publishes it, including `finished`, because this list
/// is the citation §7 and `docs/starter-vocabulary.md` rest on. Editing it to
/// match what the board happens to ship would turn the evidence into a
/// restatement of the code. See [coreShippedAsStem] for the one word the board
/// deliberately carries in another form.
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

/// Core words the board carries as a stem plus an ending key, not as the form
/// the source list publishes.
///
/// One entry, and it should stay a short list. Every one of these costs a
/// second press to say a word the core list treats as basic, so each needs a
/// reason better than tidiness.
const coreShippedAsStem = <String, ({String stem, String ending})>{
  'finished': (stem: 'finish', ending: '+ed'),
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

  test('the 7x12 home board is exactly where it ships', () async {
    // Anyone using this board has learned these positions, so the derived
    // layout has to land on them to the cell. Changing a single expectation
    // here is changing the board every new profile is set up with, and it is
    // never a formality.
    //
    // Read this as the board. Each string is a row, "." is a location held
    // open. Column 11 carries the pinned questions and row 6 the system keys,
    // both asserted separately.
    const shipped = [
      'I    we   all       want need  like     +s        a       here under good',
      'you  they some      go   stop  wait     +ed       the     in   left  not',
      'he   my   same      can  get   take     +ing      and     on   right yes',
      'she  me   different do   make  put      +\'s      but     up   off      no',
      'it   this more      open close help     am/is/are because to   forward  don\'t',
      'that .    less      look turn  finish   was/were  so      out  backward maybe',
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
      universalCore36
          .difference(labels)
          .difference(coreShippedAsStem.keys.toSet()),
      isEmpty,
      reason: 'a core word is missing from the shipped vocabulary',
    );
  });

  test('"less" sits directly under "more"', () async {
    // A pair learned as a pair. Two positions that happen to mean opposite
    // things are learned twice; one cell apart is one movement apart.
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final placed = {
      for (final r in await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(home.id))).get())
        r.readTable(db.buttons).label: (
          row: r.readTable(db.cells).row,
          col: r.readTable(db.cells).col,
        ),
    };

    expect(placed['more'], isNotNull);
    expect(placed['less'], isNotNull);
    expect(placed['less']!.col, placed['more']!.col);
    expect(placed['less']!.row, placed['more']!.row + 1);
  });

  test('the green circle is the picture for "go"', () async {
    // A chosen symbol, not a keyword match: the pack has a drawing for "go"
    // and a green circle is what people already read as go.
    final go =
        await (db.select(db.buttons)..where(
              (b) => b.vocabularyId.equals(vocabId) & b.label.equals('go'),
            ))
            .get();

    expect(go, isNotEmpty);
    for (final button in go) {
      expect(button.symbolId, 'word-1f7e2');
    }

    final symbol = await (db.select(
      db.symbols,
    )..where((s) => s.id.equals('word-1f7e2'))).getSingleOrNull();
    expect(symbol, isNotNull);
    expect(symbol!.externalId, '1f7e2');
  });

  test('every direction has a word, "under" included', () async {
    // in, on, up and out were all here and "under" was not, so a board could
    // say where a thing was in every direction but one.
    final labels = {for (final b in await buttons()) b.label};
    for (final word in ['in', 'on', 'up', 'out', 'under']) {
      expect(labels, contains(word));
    }
  });

  test('the core words carried as a stem are on the board as one', () async {
    // The deliberate deviation, kept honest by being named. `finished` seeded
    // as itself was a verb already carrying its ending, and nothing marked it
    // as such — so the board offered `+ed` after it and said "finisheded".
    // The stem takes the endings like every other verb, and the ending key it
    // needs is on the same board, so the core word is still sayable in two
    // presses rather than one.
    final labels = (await buttons())
        .where((b) => !b.isSystem)
        .map((b) => b.label)
        .toSet();

    for (final entry in coreShippedAsStem.entries) {
      expect(
        labels,
        contains(entry.value.stem),
        reason: '"${entry.key}" is not on the board even as a stem',
      );
      expect(
        labels,
        contains(entry.value.ending),
        reason:
            'the "${entry.value.ending}" key is missing, so "${entry.key}" '
            'cannot be built at all',
      );
    }
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
    //
    // Three, down from six, down from seven. §4.68 and §4.70 spent the first
    // difference on words the board could not say — `for`, `under`, `left`,
    // `right`, `less`, `whole`, the modals. The second went on `off`,
    // `forward` and `backward`: "on" had been here since the first board and
    // its opposite never had, and left and right were the only directions the
    // board could give.
    //
    // Three is the floor and not a target. What survives is what the two
    // tests below name — the noun column and the tail beside the pronouns —
    // and those are the reserves a caregiver's own words actually land in.
    // The next thing that wants a location on this board takes one of the
    // last three, and this line is what makes somebody say so out loud.
    expect(reserved.length, greaterThanOrEqualTo(3));
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
    //
    // One row, not two. §4.68 moved "this" here to sit beside "that" and "it"
    // rather than among the determiners, and it was paid for out of this tail.
    // Recorded rather than quietly absorbed: the tail is the only space a
    // shipped board reserves for a family's own names, and it is now half what
    // it was.
    final nameRows = col1.where((c) => c.row >= 5 && c.row < 6);
    expect(nameRows, hasLength(1));
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

    test('a grid too short to pin them all keeps them anyway', () async {
      // The pinned column is one short of the grid's height, so a board under
      // seven rows cannot hold all six questions in it. The ones that do not
      // fit become ordinary words on the root board. An extra movement to ask
      // "why" is a cost; losing "why" is a different thing entirely.
      final short = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(short.close);

      final ts = DateTime.now().millisecondsSinceEpoch;
      await short
          .into(short.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'p1',
              displayName: 'Maya',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      await seedCoreBoardSet(short, rows: 5, cols: 9, profileId: 'p1');

      final spoken = {
        for (final b in await short.select(short.buttons).get()) b.label,
      };

      for (final question in pinnedQuestions) {
        expect(
          spoken,
          contains(question.value.label),
          reason:
              '"${question.value.label}" does not fit the pinned column on a '
              'five-row grid and was dropped rather than placed on the board',
        );
      }
    });

    test('questions stay ordinary vocabulary, not controls', () async {
      // Pinned is a placement decision. Treating them as system buttons would
      // strip their color coding and lock a caregiver out of editing them.
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

    test('the wheel keeps the order the keys were learned in', () async {
      // The system-row keys are a window onto this list. Inserting a name
      // rather than appending one changes which board an existing key opens,
      // which relocates what a learned movement does without moving a button.
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();

      final map = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
      final order = [
        for (final c
            in (map['categories'] as List).cast<Map<String, dynamic>>())
          c['name'] as String,
      ];

      expect(order.take(6), [
        'people',
        'food',
        'play',
        'feelings',
        'places',
        'body',
      ]);
      // The tail is where new boards land, and the only place they may. Each
      // one appended here left every key already learned opening exactly what
      // it always opened; inserting one anywhere above would not have.
      expect(order.skip(6), [
        'doing',
        'numbers',
        'time',
        'objects',
        'weather',
        'clothing',
        'animals',
      ]);
    });

    test('the doing board is reachable and carries its verbs', () async {
      // A category board nobody can open, or one that opens onto nothing, is
      // worse than no key at all.
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();

      final map = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
      final entry = (map['categories'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((c) => c['name'] == 'doing');

      final board = await (db.select(
        db.boards,
      )..where((b) => b.id.equals(entry['boardId'] as String))).getSingle();
      expect(board.name, 'doing');

      // And the wheel can actually reach it. There are more categories than
      // slots at 7x12, so `doing` sits on a later turn and no key carries its
      // name until the wheel is turned — the slot is what is fixed, not the
      // word on it. What has to hold is that a turn exists which shows it.
      final cols = (map['categoryCols'] as List).length;
      final names = [
        for (final c
            in (map['categories'] as List).cast<Map<String, dynamic>>())
          c['name'] as String,
      ];
      final at = names.indexOf('doing');

      expect(at, greaterThanOrEqualTo(0));
      expect(
        at ~/ cols,
        lessThan((names.length / cols).ceil()),
        reason: 'no turn of the wheel ever shows "doing"',
      );

      // The slots themselves are on the system row, wherever the wheel stands.
      final home = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home'))).getSingle();

      final slots =
          await (db.select(db.cells)..where(
                (c) =>
                    c.boardId.equals(home.id) &
                    c.row.equals(6) &
                    c.state.equalsValue(CellState.occupied),
              ))
              .get();
      expect(slots, isNotEmpty);

      final placed =
          await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])..where(
                db.cells.boardId.equals(board.id) &
                    db.buttons.isSystem.equals(false) &
                    db.cells.col.isSmallerThanValue(11),
              ))
              .get();

      final labels = {for (final r in placed) r.readTable(db.buttons).label};

      expect(
        labels,
        containsAll(['wash', 'sit', 'ask', 'remember', 'hold', 'share']),
        reason: 'a strip of the doing board was never placed',
      );
      // One fewer since `cook` moved to `food` (§4.42), one more for the noun
      // `question` that `ask` and `answer` needed. Arithmetic, not behavior:
      // a word joining or leaving the shipped board moves this number and
      // nothing else.
      expect(labels, hasLength(48));
    });

    test('the 7x12 food board is exactly where it ships', () async {
      // The same standard as the home board: anyone using this has learned
      // these positions. Read it as the board — each string is a row, "." is a
      // location held open, column 11 is the pinned questions and row 6 the
      // system keys.
      //
      // Every row is one cluster and nothing else, which is the whole point of
      // it. A row that runs drinks into bread has to be learned word by word;
      // a row that is only drinks is learned once. The empty tails are not
      // waste — they are where a caregiver's own words for that cluster go.
      //
      // `cook` arrived here from `doing` (§4.42) and took a location that was
      // held open, which is what an addition is supposed to do: not one word
      // already on this board moved to make room for it.
      const shipped = [
        'eat drink food straw plate cook taste chew swallow pour spill',
        'water milk juice tea coffee soda . . . . .',
        'breakfast lunch dinner snack soup pizza chicken . . . .',
        'bread toast cereal rice pasta egg cheese butter honey jam .',
        'apple banana orange grapes berries melon lemon . . . .',
        'hungry thirsty yummy yucky hot cold . . . . .',
      ];

      final food = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('food'))).getSingle();

      final query = db.select(db.cells).join([
        leftOuterJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
      ])..where(db.cells.boardId.equals(food.id));

      final actual = <String, String>{
        for (final r in await query.get())
          '${r.readTable(db.cells).row},${r.readTable(db.cells).col}':
              r.readTableOrNull(db.buttons)?.label ?? '.',
      };

      for (var row = 0; row < shipped.length; row++) {
        final expected = shipped[row].split(' ');
        for (var col = 0; col < expected.length; col++) {
          expect(
            actual['$row,$col'],
            expected[col],
            reason: 'location $row,$col changed on the food board',
          );
        }
      }
    });

    test('the food clusters the grid cannot hold read on page two', () async {
      // Eight clusters, six rows. The two that give way are the ones a day
      // needs least, and they arrive on page two whole rather than as the tail
      // of whatever ran out of room.
      final second = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('food 2'))).getSingle();

      final query =
          db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.cells.boardId.equals(second.id) &
                db.buttons.isSystem.equals(false),
          );

      final byRow = <int, List<String>>{};
      for (final r in await query.get()) {
        final cell = r.readTable(db.cells);
        if (cell.col == 11) continue;
        (byRow[cell.row] ??= []).add(r.readTable(db.buttons).label);
      }

      expect(byRow[0], [
        'potato',
        'carrot',
        'peas',
        'beans',
        'tomato',
        'salad',
      ]);
      expect(byRow[1], ['cake', 'cookie', 'chips', 'yogurt']);
      // §4.42's two new clusters went to the back of the queue rather than
      // pushing `fruit` off page one — a band that has just arrived does not
      // displace one somebody may already have learned.
      expect(byRow[2], [
        'dessert',
        'sweets',
        'chocolate',
        'ice cream',
        'pudding',
      ]);
      expect(byRow[3], ['cup', 'bowl', 'spoon', 'fork', 'knife', 'napkin']);
      expect(byRow.keys, hasLength(4));
    });

    test('every row of a category board is one cluster', () async {
      // The rule the food board is only one instance of. A band owns whole
      // rows, so two clusters can share one only if a band is declared not to
      // start a line — and then the row has two meanings and the label down
      // the side can name just one of them.
      final categories =
          (await (db.select(
            db.boards,
          )..where((b) => b.kind.equalsValue(BoardKind.category))).get()).where(
            (b) => categoryNames.any(
              (c) => b.name == c || b.name.startsWith('$c '),
            ),
          );

      expect(categories, isNotEmpty);

      for (final board in categories) {
        final regions = BoardRegions.decode(board.bandMap)!;
        expect(regions.axis, BandAxis.rows);

        final owner = <int, String>{};
        for (final band in regions.bands) {
          for (var row = band.first; row <= band.last; row++) {
            expect(
              owner[row],
              isNull,
              reason:
                  'row $row of "${board.name}" is claimed by both '
                  '"${owner[row]}" and "${band.name}"',
            );
            owner[row] = band.name;
          }
        }

        // And no word landed on a row no cluster owns, which is what a band
        // filling another band's tail looks like from here.
        final query =
            db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.cells.boardId.equals(board.id) &
                  db.buttons.isSystem.equals(false) &
                  db.cells.col.isSmallerThanValue(11),
            );

        for (final r in await query.get()) {
          expect(
            owner[r.readTable(db.cells).row],
            isNotNull,
            reason:
                '"${r.readTable(db.buttons).label}" sits on a row of '
                '"${board.name}" that no cluster owns',
          );
        }
      }
    });

    test('feelings can say the difficult things', () async {
      // A board that only manages "happy" and "sad" cannot report pain or
      // being overwhelmed, which are the feelings that most need saying.
      final labels = (await buttons()).map((b) => b.label).toSet();
      expect(labels, containsAll(['hurt', 'scared', 'too loud']));
    });
  });

  group('related verbs stay neighbors', () {
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
      // Neighboring locations are learned as a pair. Two positions that
      // happen to be far apart are learned twice.
      final p = await homePositions();

      for (final pair in [('open', 'close'), ('go', 'stop'), ('get', 'take')]) {
        expect(
          adjacent(p[pair.$1]!, p[pair.$2]!),
          isTrue,
          reason: '"${pair.$1}" and "${pair.$2}" are no longer neighbors',
        );
      }
    });

    test('want, need and like run together', () async {
      final p = await homePositions();

      expect(p['want']!.row, p['need']!.row);
      expect(p['need']!.row, p['like']!.row);
      expect(p['need']!.col, p['want']!.col + 1);
      expect(p['like']!.col, p['need']!.col + 1);
    });

    test('the verbs stay inside the Fitzgerald "does" region', () async {
      // Filling the band across changes the order within it and nothing else.
      // Column position on the root board is sentence order, so a verb that
      // left these columns would be a verb in the wrong sentence slot.
      final p = await homePositions();

      const verbs = [
        'want',
        'need',
        'like',
        'go',
        'stop',
        'wait',
        'can',
        'get',
        'take',
        'do',
        'make',
        'put',
        'open',
        'close',
        'help',
        'look',
        'turn',
        'finish',
      ];

      for (final verb in verbs) {
        expect(
          p[verb]!.col,
          inInclusiveRange(3, 5),
          reason: '"$verb" left the region the verbs own',
        );
      }
    });

    test('a band reads the same way on page two', () async {
      // The verbs are filled across their band so alternatives sit side by
      // side. The words the 7x12 grid pushes onto page two are the same band,
      // so they run the same way there — a band that changed direction between
      // pages would be a second thing to learn about one group of words.
      final second = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('home 2'))).getSingle();

      final query = db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(second.id));

      final p = {
        for (final r in await query.get())
          r.readTable(db.buttons).label: (
            row: r.readTable(db.cells).row,
            col: r.readTable(db.cells).col,
          ),
      };

      for (final pair in [
        ('know', 'think'),
        ('say', 'tell'),
        ('see', 'come'),
        ('give', 'feel'),
      ]) {
        expect(
          adjacent(p[pair.$1]!, p[pair.$2]!),
          isTrue,
          reason:
              '"${pair.$1}" and "${pair.$2}" are not neighbors on page two, '
              'so the band changed direction when it overflowed',
        );
        expect(p[pair.$1]!.row, p[pair.$2]!.row);
      }
    });

    test('the pronoun paradigm still runs down its column', () async {
      // The first pronoun column is the subject set. Filling it across would
      // interleave it with "we", "they", "my" and "me" in the column beside
      // it, which is a different thing to learn.
      final p = await homePositions();

      for (final subject in ['I', 'you', 'he', 'she', 'it', 'that']) {
        expect(
          p[subject]!.col,
          0,
          reason: '"$subject" left the subject column',
        );
      }
      expect(p['you']!.row, p['I']!.row + 1);
      expect(p['he']!.row, p['you']!.row + 1);
      expect(p['we']!, (row: 0, col: 1));
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

  test('the answer between yes and no is on the root board', () async {
    // Without it every answer is a commitment, and the people in the room have
    // no way to tell an overstated "yes" from a meant one. It has to be one
    // movement from wherever a question is asked, which means the root board
    // and not a category behind a navigation step.
    final home = await (db.select(
      db.boards,
    )..where((b) => b.name.equals('home'))).getSingle();

    final query =
        db.select(db.buttons).join([
          innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
        ])..where(
          db.buttons.label.equals('maybe') & db.cells.boardId.equals(home.id),
        );

    final rows = await query.get();
    expect(
      rows,
      hasLength(1),
      reason: 'a board that can say yes and no and not maybe overstates',
    );
    expect(rows.single.readTable(db.buttons).vocabLevel, 1);

    // Beside the answers it qualifies, not stranded in another region.
    final yes =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.buttons.label.equals('yes') & db.cells.boardId.equals(home.id),
            ))
            .getSingle();

    expect(
      rows.single.readTable(db.cells).col,
      yes.readTable(db.cells).col,
      reason: '"maybe" answers the same question as "yes" and "no"',
    );
  });

  test('the degrees of not knowing are reachable on feelings', () async {
    // "maybe" on the root board is the whole of the job at level 1; these are
    // the refinements, and a board that cannot draw them all on page one has
    // to page them rather than drop them.
    final feelings = (await (db.select(
      db.boards,
    )..where((b) => b.name.like('feelings%'))).get()).map((b) => b.id).toSet();

    final query = db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.cells.boardId.isIn(feelings));

    final onFeelings = {
      for (final r in await query.get()) r.readTable(db.buttons).label,
    };

    expect(
      onFeelings,
      containsAll(['unsure', 'probably', 'possibly', 'perhaps']),
      reason: 'a hedge a person cannot reach is a hedge they do not have',
    );
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

  /// §4.68. The engine could always make these; no board could ask for them.
  group('the comparative endings', () {
    Future<Button> keyFor(String label) async =>
        (db.select(db.buttons)..where(
              (b) => b.vocabularyId.equals(vocabId) & b.label.equals(label),
            ))
            .getSingle();

    test('are on the board, at level 3', () async {
      for (final label in ['+er', '+est']) {
        final button = await keyFor(label);
        expect(button.action, ButtonAction.morpheme);
        expect(
          button.vocabLevel,
          3,
          reason:
              'a comparative needs an adjective already in the bar, which is '
              'a later skill than the endings beside it',
        );
      }
    });

    test('carry the kinds the engine already dispatches', () async {
      // The whole point: `applyMorpheme` has handled both since it was
      // written, irregulars included — good becomes better, bad becomes worse.
      // A key wired to the wrong kind draws correctly and says the wrong word.
      expect((await keyFor('+er')).morphemeKind, MorphemeKind.comparativeEr);
      expect((await keyFor('+est')).morphemeKind, MorphemeKind.superlativeEst);
    });

    test('and they page off before the linking words do', () async {
      // §4.68. They first shipped at `grammarKeyPageRank`, like every other
      // ending, which put them ahead of the conjunctions at 20 — so on a 7x11
      // board `and but because so` went to page two and two suffixes stayed.
      // Linking words are what turn a run of words into a sentence. A
      // comparative is not, and it goes first.
      for (final cols in [11, 12]) {
        final narrow = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        addTearDown(narrow.close);
        final id = await seedCoreBoardSet(narrow, rows: 7, cols: cols);

        final boards = await (narrow.select(
          narrow.boards,
        )..where((b) => b.vocabularyId.equals(id))).get();
        final root = boards.firstWhere((b) => b.name == 'home');

        final onRoot = {
          for (final r in await (narrow.select(narrow.buttons).join([
            innerJoin(
              narrow.cells,
              narrow.cells.id.equalsExp(narrow.buttons.cellId),
            ),
          ])..where(narrow.cells.boardId.equals(root.id))).get())
            r.readTable(narrow.buttons).label,
        };

        for (final word in ['and', 'but', 'because', 'so']) {
          expect(
            onRoot,
            contains(word),
            reason: '"$word" was pushed off the root board at 7x$cols',
          );
        }
        expect(
          onRoot,
          isNot(contains('+er')),
          reason: 'a comparative held a root location a linking word needed',
        );
      }
    });

    test('and they did not push anything off the board', () async {
      // They took a column that was already blank. Every word that shipped
      // before them still ships, which is what to check after a band claims
      // another column.
      final labels = {for (final b in await buttons()) b.label};
      for (final word in ['a', 'the', 'because', 'here', 'good', 'maybe']) {
        expect(
          labels,
          contains(word),
          reason: '"$word" fell off when the endings band grew',
        );
      }
    });
  });
}
