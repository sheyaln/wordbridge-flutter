import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/interop/obf_export.dart';
import 'package:wordbridge/features/interop/obf_import.dart';
import 'package:wordbridge/features/interop/obf_model.dart';

/// One word's location, qualified by the board it sits on.
///
/// [motorPaths] in motor_plan_invariant_test.dart keys by label alone, which
/// is enough within a single board. Across a board set the system row repeats
/// the same labels on every board, so the board name has to be part of the
/// key or seven "home" buttons collapse into one.
typedef Placement = ({String board, String label, int row, int col});

Future<List<Placement>> placements(
  WordbridgeDatabase db,
  String vocabularyId,
) async {
  final query = db.select(db.buttons).join([
    innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
  ])..where(db.buttons.vocabularyId.equals(vocabularyId));

  final rows = [
    for (final r in await query.get())
      (
        board: r.readTable(db.boards).name,
        label: r.readTable(db.buttons).label,
        row: r.readTable(db.cells).row,
        col: r.readTable(db.cells).col,
      ),
  ];

  rows.sort((a, b) {
    final byBoard = a.board.compareTo(b.board);
    if (byBoard != 0) return byBoard;
    final byRow = a.row.compareTo(b.row);
    if (byRow != 0) return byRow;
    return a.col.compareTo(b.col);
  });
  return rows;
}

/// Every navigation link as (source board, label, destination board).
Future<Set<({String from, String label, String to})>> navigation(
  WordbridgeDatabase db,
  String vocabularyId,
) async {
  final boards = {
    for (final b in await (db.select(
      db.boards,
    )..where((b) => b.vocabularyId.equals(vocabularyId))).get())
      b.id: b.name,
  };

  final query =
      db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
        innerJoin(db.boards, db.boards.id.equalsExp(db.cells.boardId)),
      ])..where(
        db.buttons.vocabularyId.equals(vocabularyId) &
            db.buttons.action.equalsValue(ButtonAction.navigate),
      );

  return {
    for (final r in await query.get())
      (
        from: r.readTable(db.boards).name,
        label: r.readTable(db.buttons).label,
        to: boards[r.readTable(db.buttons).targetBoardId] ?? '<dangling>',
      ),
  };
}

List<int> zipOf(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

Future<Cell> cell(WordbridgeDatabase db, String boardId, int row, int col) =>
    cellAt(db, boardId: boardId, row: row, col: col);

Future<Button?> buttonIn(WordbridgeDatabase db, Cell c) => (db.select(
  db.buttons,
)..where((b) => b.cellId.equals(c.id))).getSingleOrNull();

Future<Board> boardNamed(WordbridgeDatabase db, String name) =>
    (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

/// A hand-written board exercising the corners of the spec: a numeric id, an
/// `actions` array with no `action` fallback, a vocalization that differs from
/// the label, an rgb color, an unreferenced image, and null grid entries.
const minimalObf = '''
{
  "format": "open-board-0.1",
  "id": "snack-1",
  "locale": "en",
  "name": "snack",
  "description_html": "A <b>tiny</b> board.",
  "license": {
    "type": "CC-By-SA",
    "author_name": "Bob Jones",
    "Copyright_notice_url": "https://creativecommons.org/licenses/by-sa/4.0"
  },
  "buttons": [
    {
      "id": "1",
      "label": "biscuit",
      "image_id": "9",
      "background_color": "rgb(255, 214, 165)",
      "border_color": "rgb(0, 0, 55)"
    },
    { "id": "2", "label": "more", "vocalization": "I want more" },
    { "id": "3", "label": "clear", "action": ":clear" },
    { "id": 4, "label": "home", "actions": [":home"] }
  ],
  "grid": {
    "rows": 2,
    "columns": 3,
    "order": [
      ["1", null, "2"],
      ["3", null, 4]
    ]
  },
  "images": [
    { "id": "9", "url": "http://example.com/biscuit.png" }
  ],
  "sounds": []
}
''';

String linkedBoard({
  required String id,
  required String name,
  required int rows,
  required int columns,
  required List<List<String?>> order,
  required List<Map<String, Object?>> buttons,
}) => jsonEncode({
  'format': obfFormat,
  'id': id,
  'locale': 'en',
  'name': name,
  'buttons': buttons,
  'grid': {'rows': rows, 'columns': columns, 'order': order},
});

/// A board set whose links go one way, so part of it can be exported.
///
/// The shipped set puts a category key on every board, so there every board
/// reaches every other and a subset export has nothing to leave out. Here
/// `home` opens `food` and `play`, `food` opens `fruit`, and `play` opens
/// nothing.
typedef LinkedSet = ({String vocabularyId, Map<String, String> boards});

Future<LinkedSet> linkedSet(WordbridgeDatabase db) async {
  final vocabularyId = newId();
  final ts = nowMs();
  await db
      .into(db.vocabularies)
      .insert(
        VocabulariesCompanion.insert(
          id: vocabularyId,
          name: 'Sam',
          gridRows: 2,
          gridCols: 2,
          createdAt: ts,
          updatedAt: ts,
        ),
      );

  final boards = <String, String>{};
  for (final name in ['home', 'food', 'fruit', 'play']) {
    boards[name] = await materializeBoard(
      db,
      vocabularyId: vocabularyId,
      name: name,
      kind: name == 'home' ? BoardKind.root : BoardKind.category,
    );
  }
  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabularyId)))
      .write(VocabulariesCompanion(rootBoardId: Value(boards['home'])));

  Future<void> place(
    String board,
    int col,
    String label, {
    String? opens,
    String? symbolId,
  }) async {
    await placeButton(
      db,
      vocabularyId: vocabularyId,
      cellId: (await cell(db, boards[board]!, 0, col)).id,
      label: label,
      message: label,
      action: opens == null ? ButtonAction.speak : ButtonAction.navigate,
      targetBoardId: opens == null ? null : boards[opens],
      symbolId: symbolId,
    );
  }

  await place('home', 0, 'food', opens: 'food');
  await place('home', 1, 'play', opens: 'play');
  await place('food', 0, 'fruit', opens: 'fruit');
  await place('food', 1, 'apple');
  await place('fruit', 0, 'pear');
  await place('play', 0, 'ball');

  return (vocabularyId: vocabularyId, boards: boards);
}

/// A picture row, with whatever license the test is asking a question about.
Future<String> addSymbol(
  WordbridgeDatabase db, {
  required String id,
  required String license,
  String? packId,
  String? externalId,
  String? localUri,
  String attribution = '',
}) async {
  await db
      .into(db.symbols)
      .insert(
        SymbolsCompanion.insert(
          id: id,
          packId: Value(packId),
          source: SymbolSource.downloaded,
          externalId: Value(externalId),
          localUri: Value(localUri),
          label: id,
          license: license,
          attribution: attribution,
          createdAt: nowMs(),
        ),
      );
  return id;
}

/// A one-pixel PNG, recognizable by sight in a hexdump of a zip.
final pngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...'wordbridge-test-picture'.codeUnits,
]);

Map<String, ArchiveFile> filesIn(List<int> zip) => {
  for (final file in ZipDecoder().decodeBytes(zip).files) file.name: file,
};

ObfBoard boardIn(Map<String, ArchiveFile> files, String path) =>
    ObfBoard.parse(utf8.decode(files[path]!.readBytes()!));

ObzManifest manifestIn(Map<String, ArchiveFile> files) =>
    ObzManifest.parse(utf8.decode(files['manifest.json']!.readBytes()!));

void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('THE INVARIANT: interop must not move a word', () {
    test('a full .obz round trip lands every word where it started', () async {
      final sourceVocab = await seedCoreBoardSet(db);
      final before = await placements(db, sourceVocab);

      final package = await exportObz(db, sourceVocab);

      final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);

      final notes = <String>[];
      final importedVocab = await importObz(fresh, package, notes: notes);
      final after = await placements(fresh, importedVocab);

      expect(
        after.length,
        before.length,
        reason:
            'the round trip lost or invented ${(after.length - before.length).abs()} word(s)',
      );

      for (var i = 0; i < before.length; i++) {
        expect(
          after[i],
          before[i],
          reason:
              '"${before[i].label}" left ${before[i].board} '
              '${before[i].row},${before[i].col} and arrived as '
              '${after[i].board} ${after[i].row},${after[i].col}. '
              'A learned motor pattern was destroyed by an export and import.',
        );
      }

      // Every note our own package still produces, and the one thing they are
      // all about. The export writes `images` in full — pack, external id,
      // license, attribution — and the import drops them on the floor, so a
      // board that leaves and comes back keeps every word in its place and
      // arrives with no pictures. §4.69 made that visible by putting symbols
      // on the frame keys; before it, the shipped board had none stored and
      // this passed by having nothing to lose.
      //
      // Held as "only this" rather than "none": a note about anything else
      // means our own package has stopped round tripping cleanly, which is
      // what this was written to catch. Narrow it further, never wider.
      expect(
        notes.where((n) => !n.contains('symbol handling is not wired up yet')),
        isEmpty,
        reason:
            'our own package should import without a judgment call about '
            'anything but its pictures',
      );
    });

    test('geometry and the root board survive the round trip', () async {
      final sourceVocab = await seedCoreBoardSet(db);
      final source = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(sourceVocab))).getSingle();

      final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);
      final importedVocab = await importObz(
        fresh,
        await exportObz(db, sourceVocab),
      );

      final imported = await (fresh.select(
        fresh.vocabularies,
      )..where((v) => v.id.equals(importedVocab))).getSingle();

      expect(imported.gridRows, source.gridRows);
      expect(imported.gridCols, source.gridCols);
      expect(imported.name, source.name);
      expect(imported.locale, source.locale);
      expect(imported.sourceLicense, source.sourceLicense);

      final root = await (fresh.select(
        fresh.boards,
      )..where((b) => b.id.equals(imported.rootBoardId!))).getSingle();
      expect(root.name, 'home');
      expect(root.kind, BoardKind.root);
    });

    test('every category link still points at the same board', () async {
      final sourceVocab = await seedCoreBoardSet(db);
      final before = await navigation(db, sourceVocab);

      final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);
      final importedVocab = await importObz(
        fresh,
        await exportObz(db, sourceVocab),
      );

      expect(await navigation(fresh, importedVocab), before);
      expect(before, isNotEmpty);
    });

    test('actions and vocabulary levels survive the round trip', () async {
      final sourceVocab = await seedCoreBoardSet(db);
      Future<Set<String>> signature(WordbridgeDatabase d, String v) async => {
        for (final b in await (d.select(
          d.buttons,
        )..where((x) => x.vocabularyId.equals(v))).get())
          '${b.label}|${b.action.name}|${b.message}|${b.vocabLevel}|'
              '${b.partOfSpeech?.name}|${b.isSystem}',
      };

      final before = await signature(db, sourceVocab);

      final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);
      final importedVocab = await importObz(
        fresh,
        await exportObz(db, sourceVocab),
      );

      expect(await signature(fresh, importedVocab), before);
    });
  });

  group('importing a single .obf', () {
    late String vocabId;
    late Board board;
    late List<String> notes;

    setUp(() async {
      notes = <String>[];
      vocabId = await importObf(db, minimalObf, notes: notes);
      board = await boardNamed(db, 'snack');
    });

    test('geometry comes from the grid, not the button count', () async {
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();

      expect(vocab.gridRows, 2);
      expect(vocab.gridCols, 3);
      expect(vocab.name, 'snack');
      expect(vocab.locale, 'en');

      final cells = await (db.select(
        db.cells,
      )..where((c) => c.boardId.equals(board.id))).get();
      expect(cells.length, 6);
    });

    test('buttons land on the coordinates the grid gave them', () async {
      final biscuit = await buttonIn(db, await cell(db, board.id, 0, 0));
      expect(biscuit!.label, 'biscuit');
      expect(biscuit.message, 'biscuit');
      expect(biscuit.action, ButtonAction.speak);
      expect(biscuit.backgroundColor, 'rgb(255, 214, 165)');
      expect(biscuit.borderColor, 'rgb(0, 0, 55)');

      final more = await buttonIn(db, await cell(db, board.id, 0, 2));
      expect(more!.label, 'more');
      expect(
        more.speakText,
        'I want more',
        reason: 'OBF vocalization is our speakText',
      );
    });

    test('a null grid entry leaves the location reserved', () async {
      for (final row in [0, 1]) {
        final reserved = await cell(db, board.id, row, 1);
        expect(
          reserved.state,
          CellState.emptyReserved,
          reason:
              'a null in grid.order is a location held open for later, not a '
              'location that does not exist',
        );
        expect(await buttonIn(db, reserved), isNull);
      }
    });

    test('specialty actions map onto our own', () async {
      final clear = await buttonIn(db, await cell(db, board.id, 1, 0));
      expect(clear!.action, ButtonAction.clear);
      expect(clear.message, '', reason: 'an action button says nothing');
      expect(clear.isSystem, isTrue);

      // Numeric id in both the button and the grid, and the action only
      // present in the `actions` array.
      final home = await buttonIn(db, await cell(db, board.id, 1, 2));
      expect(home!.label, 'home');
      expect(home.action, ButtonAction.home);
    });

    test('the license is carried across as readable text', () async {
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();

      expect(vocab.sourceLicense, contains('CC-By-SA'));
      expect(vocab.sourceLicense, contains('Bob Jones'));
      expect(vocab.sourceLicense, contains('creativecommons.org'));
    });

    test('an undeclared license is recorded as all rights reserved', () async {
      final id = await importObf(
        db,
        jsonEncode({
          'format': obfFormat,
          'id': 'x',
          'name': 'no license',
          'buttons': [
            {'id': '1', 'label': 'hi'},
          ],
          'grid': {
            'rows': 1,
            'columns': 1,
            'order': [
              ['1'],
            ],
          },
        }),
      );

      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(id))).getSingle();
      expect(vocab.sourceLicense, contains('all rights reserved'));
    });

    test('symbols are not silently dropped', () {
      expect(notes.any((n) => n.contains('Symbol "9"')), isTrue);
    });

    test(
      'a word the grid never places lands unplaced, not somewhere',
      () async {
        final log = <String>[];
        final id = await importObf(
          db,
          jsonEncode({
            'format': obfFormat,
            'id': 'x',
            'name': 'strays',
            'buttons': [
              {'id': '1', 'label': 'placed'},
              {'id': '2', 'label': 'orphan'},
            ],
            'grid': {
              'rows': 1,
              'columns': 2,
              'order': [
                ['1', null],
              ],
            },
          }),
          notes: log,
        );

        final orphan = await (db.select(
          db.buttons,
        )..where((b) => b.label.equals('orphan'))).getSingle();

        expect(orphan.vocabularyId, id);
        expect(
          orphan.cellId,
          isNull,
          reason:
              'the free cell at 0,1 is reserved for a word someone chooses to '
              'put there, not for whatever the importer had left over',
        );
        expect(log.any((n) => n.contains('imported unplaced')), isTrue);

        final free = await cell(db, (await boardNamed(db, 'strays')).id, 0, 1);
        expect(free.state, CellState.emptyReserved);
      },
    );

    test('an id repeated across cells keeps only its first location', () async {
      final log = <String>[];
      await importObf(
        db,
        jsonEncode({
          'format': obfFormat,
          'id': 'x',
          'name': 'merged',
          'buttons': [
            {'id': '1', 'label': 'wide'},
          ],
          // How some exporters encode a merged cell. We have no span to recover.
          'grid': {
            'rows': 1,
            'columns': 3,
            'order': [
              ['1', '1', '1'],
            ],
          },
        }),
        notes: log,
      );

      final board = await boardNamed(db, 'merged');
      expect(
        (await buttonIn(db, await cell(db, board.id, 0, 0)))!.label,
        'wide',
      );
      expect(await buttonIn(db, await cell(db, board.id, 0, 1)), isNull);
      expect(await buttonIn(db, await cell(db, board.id, 0, 2)), isNull);
      expect(log.any((n) => n.contains('more than once')), isTrue);
    });

    test('an action we do not support still keeps its location', () async {
      await importObf(
        db,
        jsonEncode({
          'format': obfFormat,
          'id': 'x',
          'name': 'keyboard',
          'buttons': [
            {'id': '1', 'label': 'F', 'action': '+f'},
            {'id': '2', 'label': 'space', 'action': ':space'},
          ],
          'grid': {
            'rows': 1,
            'columns': 2,
            'order': [
              ['1', '2'],
            ],
          },
        }),
      );

      final board = await boardNamed(db, 'keyboard');
      for (final col in [0, 1]) {
        final button = await buttonIn(db, await cell(db, board.id, 0, col));
        expect(
          button!.action,
          ButtonAction.speak,
          reason:
              'we have no keyboard yet, but dropping the button would leave a '
              'hole in a layout somebody may already have learned',
        );
      }
    });

    test('the system cell map is derived from the root board', () async {
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();

      expect(jsonDecode(vocab.systemCellMap), {
        'clear': [1, 0],
        'home': [1, 2],
      });
    });

    test('an unknown key or a stray images payload does not crash', () async {
      final id = await importObf(
        db,
        jsonEncode({
          'format': obfFormat,
          'id': 'x',
          'name': 'odd',
          'wibble': {'nested': true},
          'buttons': [
            {'id': '1', 'label': 'hi', 'left': 0.1, 'top': 0.2},
          ],
          'grid': {
            'rows': 1,
            'columns': 1,
            'order': [
              ['1'],
            ],
          },
          'images': [
            {'id': '1', 'data': 'data:image/png;base64,iVBORw0KGgo='},
          ],
          'sounds': [
            {'id': '1', 'url': 'http://example.com/a.mp3'},
          ],
        }),
      );
      expect(id, isNotEmpty);
    });
  });

  group('importing an .obz', () {
    String board(String id, String name, List<Map<String, Object?>> buttons) =>
        linkedBoard(
          id: id,
          name: name,
          rows: 1,
          columns: 2,
          order: [
            [buttons.isEmpty ? null : buttons[0]['id'] as String, null],
          ],
          buttons: buttons,
        );

    test('load_board links resolve to real boards', () async {
      final package = zipOf({
        'manifest.json': jsonEncode({
          'format': obfFormat,
          'root': 'boards/1.obf',
          'paths': {
            'boards': {'1': 'boards/1.obf', '2': 'boards/2.obf'},
            'images': <String, String>{},
            'sounds': <String, String>{},
          },
        }),
        // The link points forward at a board defined later in the package,
        // which is why the import has to create every board before placing
        // any button.
        'boards/1.obf': board('1', 'home', [
          {
            'id': 'a',
            'label': 'drinks',
            'load_board': {'id': '2', 'name': 'drinks', 'path': 'boards/2.obf'},
          },
        ]),
        'boards/2.obf': board('2', 'drinks', [
          {
            'id': 'b',
            'label': 'back home',
            'load_board': {'id': '1'},
          },
        ]),
      });

      final notes = <String>[];
      final vocabId = await importObz(db, package, notes: notes);

      expect(await navigation(db, vocabId), {
        (from: 'home', label: 'drinks', to: 'drinks'),
        (from: 'drinks', label: 'back home', to: 'home'),
      });
      expect(notes, isEmpty);

      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final root = await (db.select(
        db.boards,
      )..where((b) => b.id.equals(vocab.rootBoardId!))).getSingle();
      expect(root.name, 'home');
    });

    test('a link out of the package is reported, not faked', () async {
      final package = zipOf({
        'manifest.json': jsonEncode({
          'format': obfFormat,
          'root': 'boards/1.obf',
          'paths': {
            'boards': {'1': 'boards/1.obf'},
          },
        }),
        'boards/1.obf': board('1', 'home', [
          {
            'id': 'a',
            'label': 'elsewhere',
            'load_board': {'url': 'http://example.com/boards/9'},
          },
        ]),
      });

      final notes = <String>[];
      final vocabId = await importObz(db, package, notes: notes);

      expect(await navigation(db, vocabId), {
        (from: 'home', label: 'elsewhere', to: '<dangling>'),
      });
      expect(notes.any((n) => n.contains('outside this package')), isTrue);
    });
  });

  group('boards that disagree about grid size', () {
    late String vocabId;
    late List<String> notes;

    setUp(() async {
      final package = zipOf({
        'manifest.json': jsonEncode({
          'format': obfFormat,
          'root': 'boards/small.obf',
          'paths': {
            'boards': {'s': 'boards/small.obf', 'l': 'boards/large.obf'},
          },
        }),
        'boards/small.obf': linkedBoard(
          id: 's',
          name: 'small',
          rows: 2,
          columns: 2,
          order: [
            ['s0', null],
            [null, 's1'],
          ],
          buttons: [
            {'id': 's0', 'label': 'yes'},
            {'id': 's1', 'label': 'no'},
          ],
        ),
        'boards/large.obf': linkedBoard(
          id: 'l',
          name: 'large',
          rows: 3,
          columns: 5,
          order: [
            [null, null, null, null, 'l0'],
            [null, null, null, null, null],
            ['l1', null, null, null, null],
          ],
          buttons: [
            {'id': 'l0', 'label': 'far right'},
            {'id': 'l1', 'label': 'bottom left'},
          ],
        ),
      });

      notes = <String>[];
      vocabId = await importObz(db, package, notes: notes);
    });

    test('the vocabulary takes the largest grid found', () async {
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();

      expect(vocab.gridRows, 3);
      expect(vocab.gridCols, 5);
    });

    test('nothing is reflowed to fit', () async {
      expect(await placements(db, vocabId), [
        (board: 'large', label: 'far right', row: 0, col: 4),
        (board: 'large', label: 'bottom left', row: 2, col: 0),
        (board: 'small', label: 'yes', row: 0, col: 0),
        (board: 'small', label: 'no', row: 1, col: 1),
      ]);
    });

    test('the short board gains reserved cells, not new words', () async {
      final small = await boardNamed(db, 'small');
      final cells = await (db.select(
        db.cells,
      )..where((c) => c.boardId.equals(small.id))).get();

      expect(cells.length, 15, reason: 'every board is materialized at 3x5');
      expect(cells.where((c) => c.state == CellState.occupied).length, 2);
    });

    test('the decision is recorded, not silent', () async {
      expect(notes.any((n) => n.contains('3×5')), isTrue);
      expect(notes.any((n) => n.contains('different grid sizes')), isTrue);

      final events = await (db.select(
        db.editEvents,
      )..where((e) => e.vocabularyId.equals(vocabId))).get();
      expect(events, hasLength(1));
      expect(events.single.kind, EditKind.gridResize);

      final after =
          jsonDecode(events.single.afterJson!) as Map<String, Object?>;
      expect(after['gridRows'], 3);
      expect(after['gridCols'], 5);
      expect(after['notes'], isNotEmpty);
    });
  });

  group('exporting', () {
    test('.obf emits a full rows x columns grid with nulls', () async {
      final vocabId = await importObf(db, minimalObf);
      final board = await boardNamed(db, 'snack');

      final exported = ObfBoard.parse(await exportObf(db, board.id));

      expect(exported.format, obfFormat);
      expect(exported.name, 'snack');
      expect(exported.grid!.rows, 2);
      expect(exported.grid!.columns, 3);
      expect(exported.grid!.order, hasLength(2));
      expect(exported.grid!.order.every((r) => r.length == 3), isTrue);
      expect(exported.grid!.order[0][1], isNull);
      expect(exported.grid!.order[1][1], isNull);

      final byId = {for (final b in exported.buttons) b.id: b};
      final more = byId[exported.grid!.order[0][2]]!;
      expect(more.label, 'more');
      expect(
        more.vocalization,
        'I want more',
        reason: 'our speakText is OBF vocalization',
      );

      final clear = byId[exported.grid!.order[1][0]]!;
      expect(clear.action, ':clear');

      expect(vocabId, isNotEmpty);
    });

    test('.obz carries a manifest naming the root board', () async {
      final vocabId = await seedCoreBoardSet(db);
      final archive = ZipDecoder().decodeBytes(await exportObz(db, vocabId));

      // Derived rather than hardcoded: the shipped vocabulary gains boards
      // as it grows, and a literal here fails for the wrong reason every time
      // it does. What matters is that every board is in the package.
      final boardCount = await db.boards.count().getSingle();

      final names = archive.files.map((f) => f.name).toSet();
      expect(names, contains('manifest.json'));
      expect(names.where((n) => n.endsWith('.obf')), hasLength(boardCount));

      final manifest = ObzManifest.parse(
        utf8.decode(
          archive.files
              .firstWhere((f) => f.name == 'manifest.json')
              .readBytes()!,
        ),
      );
      expect(manifest.format, obfFormat);
      expect(manifest.boards, hasLength(boardCount));
      expect(names, contains(manifest.root));

      final root = ObfBoard.parse(
        utf8.decode(
          archive.files.firstWhere((f) => f.name == manifest.root).readBytes()!,
        ),
      );
      expect(root.name, 'home');

      // Every link resolves to a path that is actually in the package.
      for (final file in archive.files.where((f) => f.name.endsWith('.obf'))) {
        final obf = ObfBoard.parse(utf8.decode(file.readBytes()!));
        for (final button in obf.buttons) {
          final path = button.loadBoard?.path;
          if (path == null) continue;
          expect(names, contains(path));
        }
      }
    });
  });

  /// Guards the whole point of a partial export: that a file holding one board
  /// is still a valid, honest OBF document, and that the boards it does not
  /// hold are named rather than quietly cut off the keys that opened them.
  group('exporting part of a set', () {
    late LinkedSet set;

    setUp(() async => set = await linkedSet(db));

    test('a category is the board and everything it opens', () async {
      expect(await linkedBoardIds(db, set.boards['food']!), {
        set.boards['food'],
        set.boards['fruit'],
      });

      // Following links rather than parentage: `play` opens nothing, and
      // nothing about being a category board makes it reach the rest.
      expect(await linkedBoardIds(db, set.boards['play']!), {
        set.boards['play'],
      });
      expect(
        await linkedBoardIds(db, set.boards['home']!),
        set.boards.values.toSet(),
      );
    });

    test('one board goes out on its own, with its links named', () async {
      final notes = <String>[];
      final obf = ObfBoard.parse(
        await exportObf(db, set.boards['food']!, notes: notes),
      );

      expect(obf.name, 'food');
      expect(obf.buttons.map((b) => b.label), containsAll(['fruit', 'apple']));

      // The choice, made visible. A dropped link would leave a key that looks
      // like every other key and does nothing; the name means the importer can
      // say which page is missing.
      final fruit = obf.buttons.firstWhere((b) => b.label == 'fruit');
      expect(fruit.loadBoard!.name, 'fruit');
      expect(fruit.loadBoard!.id, set.boards['fruit']);
      expect(
        fruit.loadBoard!.path,
        isNull,
        reason: 'a standalone .obf has no package for a path to address',
      );

      expect(notes, hasLength(1));
      expect(notes.single, contains('"fruit"'));
      expect(notes.single, contains('not in this file'));
    });

    test('a category package holds exactly its own boards', () async {
      final notes = <String>[];
      final files = filesIn(
        await exportObz(
          db,
          set.vocabularyId,
          boardIds: await linkedBoardIds(db, set.boards['food']!),
          rootBoardId: set.boards['food'],
          notes: notes,
        ),
      );

      final manifest = manifestIn(files);
      expect(manifest.boards, hasLength(2));
      expect(boardIn(files, manifest.root!).name, 'food');
      expect(
        files.keys.where((n) => n.endsWith('.obf')),
        hasLength(2),
        reason: 'home and play were not asked for',
      );

      // Inside the package the link resolves; nothing points out of it, so
      // there is nothing to warn about.
      final food = boardIn(files, manifest.root!);
      final fruit = food.buttons.firstWhere((b) => b.label == 'fruit');
      expect(files.keys, contains(fruit.loadBoard!.path));
      expect(notes, isEmpty);
    });

    test('a package that leaves boards behind says which', () async {
      final notes = <String>[];
      await exportObz(
        db,
        set.vocabularyId,
        boardIds: [set.boards['home']!],
        notes: notes,
      );

      expect(notes, hasLength(1));
      expect(notes.single, contains('"food"'));
      expect(notes.single, contains('"play"'));
      expect(notes.single, contains('2 key(s)'));
    });

    test('a category survives the trip out and back', () async {
      final package = await exportObz(
        db,
        set.vocabularyId,
        boardIds: await linkedBoardIds(db, set.boards['food']!),
        rootBoardId: set.boards['food'],
      );

      final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);
      final imported = await importObz(fresh, package);

      final boards = await (fresh.select(
        fresh.boards,
      )..where((b) => b.vocabularyId.equals(imported))).get();
      expect(boards.map((b) => b.name).toSet(), {'food', 'fruit'});

      expect(await navigation(fresh, imported), {
        (from: 'food', label: 'fruit', to: 'fruit'),
      });

      final vocabulary = await (fresh.select(
        fresh.vocabularies,
      )..where((v) => v.id.equals(imported))).getSingle();
      final root = boards.firstWhere((b) => b.id == vocabulary.rootBoardId);
      expect(root.name, 'food', reason: 'the category is what it opens on');
    });

    test('one board comes back with its dangling link reported', () async {
      final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);

      final notes = <String>[];
      final imported = await importObf(
        fresh,
        await exportObf(db, set.boards['food']!),
        notes: notes,
      );

      // The key is still there, still a link, and still named - it just has
      // nowhere to go, and the person importing is told so.
      expect(await navigation(fresh, imported), {
        (from: 'food', label: 'fruit', to: '<dangling>'),
      });
      expect(
        notes.where((n) => n.contains('outside this package')),
        hasLength(1),
      );
    });
  });

  /// Guards the licensing boundary NOTICE.md commits to. ARASAAC and Sclera
  /// are CC BY-NC and this app may not pass their images on; a file it writes
  /// carrying those bytes would be exactly that, sitting in somebody's email.
  group('pictures an exported file may and may not carry', () {
    late LinkedSet set;

    setUp(() async => set = await linkedSet(db));

    Future<void> giveApple(String symbolId) async {
      final apple = await (db.select(
        db.buttons,
      )..where((b) => b.label.equals('apple'))).getSingle();
      await (db.update(db.buttons)..where((b) => b.id.equals(apple.id))).write(
        ButtonsCompanion(symbolId: Value(symbolId), updatedAt: Value(nowMs())),
      );
    }

    test('a CC BY-SA picture travels, as a file in the package', () async {
      await giveApple(
        await addSymbol(
          db,
          id: 'sa',
          license: 'CC-BY-SA-4.0',
          attribution: 'Mulberry Symbols',
          packId: 'core',
          externalId: 'apple.png',
          localUri: '/symbols/apple.png',
        ),
      );

      final notes = <String>[];
      final files = filesIn(
        await exportObz(
          db,
          set.vocabularyId,
          notes: notes,
          readImage: (_) async => pngBytes,
        ),
      );

      final manifest = manifestIn(files);
      expect(manifest.images, hasLength(1));
      final path = manifest.images['sa']!;
      expect(files[path]!.readBytes(), pngBytes);

      final food = boardIn(files, manifest.boards[set.boards['food']]!);
      final image = food.images.single;
      expect(image.path, path);
      expect(image.contentType, 'image/png');

      // Redistributed bytes travel with the credit that permits it.
      expect(image.license!.type, 'CC-BY-SA-4.0');
      expect(image.license!.authorName, 'Mulberry Symbols');
      expect(notes, isEmpty);
    });

    test(
      'a non-commercial picture is named and credited, never copied',
      () async {
        await giveApple(
          await addSymbol(
            db,
            id: 'nc',
            license: 'CC-BY-NC-SA',
            attribution: 'Sergio Palao. Origin: ARASAAC.',
            packId: 'arasaac',
            externalId: '2462',
            localUri: '/symbols/arasaac/2462.png',
          ),
        );

        final notes = <String>[];
        final package = await exportObz(
          db,
          set.vocabularyId,
          notes: notes,
          readImage: (_) async => pngBytes,
        );
        final files = filesIn(package);

        expect(manifestIn(files).images, isEmpty);
        expect(files.keys.where((n) => n.startsWith('images/')), isEmpty);
        expect(
          package.join(','),
          isNot(contains(pngBytes.join(','))),
          reason:
              'the bytes must not be anywhere in the file, stored or deflated',
        );

        // What does travel: enough to fetch it, and the credit ARASAAC requires
        // wherever its symbols appear.
        final food = boardIn(
          files,
          manifestIn(files).boards[set.boards['food']]!,
        );
        final image = food.images.single;
        expect(image.data, isNull);
        expect(image.path, isNull);
        expect(image.symbol!.set, 'arasaac');
        expect(image.symbol!.filename, '2462');
        expect(image.license!.authorName, contains('ARASAAC'));

        expect(notes, hasLength(1));
        expect(notes.single, contains('CC-BY-NC-SA'));
        expect(notes.single, contains('not copied into it'));
      },
    );

    test('a standalone .obf embeds under the same rule', () async {
      await giveApple(
        await addSymbol(
          db,
          id: 'sa',
          license: 'CC-BY-SA-4.0',
          localUri: '/symbols/apple.png',
        ),
      );

      final embedded = ObfBoard.parse(
        await exportObf(
          db,
          set.boards['food']!,
          readImage: (_) async => pngBytes,
        ),
      );
      expect(embedded.images.single.data, startsWith('data:image/png;base64,'));

      await giveApple(
        await addSymbol(
          db,
          id: 'nc',
          license: 'CC-BY-NC-SA',
          packId: 'arasaac',
          externalId: '2462',
          localUri: '/symbols/arasaac/2462.png',
        ),
      );

      final referenced = ObfBoard.parse(
        await exportObf(
          db,
          set.boards['food']!,
          readImage: (_) async => pngBytes,
        ),
      );
      expect(referenced.images.single.data, isNull);
      expect(referenced.images.single.symbol!.set, 'arasaac');
    });

    test('an emoji is neither carried nor complained about', () async {
      // A glyph pack answers with the characters to draw, not a path. There
      // are no bytes to withhold, so a note about a withheld picture would be
      // a warning about the system row on every board.
      await giveApple(
        await addSymbol(
          db,
          id: 'emoji',
          license: 'Unicode-3.0',
          packId: 'system-emoji',
          externalId: '1f34e',
          localUri: '\u{1f34e}',
        ),
      );

      final notes = <String>[];
      final files = filesIn(
        await exportObz(db, set.vocabularyId, notes: notes),
      );

      expect(manifestIn(files).images, isEmpty);
      expect(notes, isEmpty);

      final food = boardIn(
        files,
        manifestIn(files).boards[set.boards['food']]!,
      );
      expect(food.images.single.symbol!.filename, '1f34e');
    });

    test(
      'a picture this device does not have is left as a reference',
      () async {
        await giveApple(
          await addSymbol(
            db,
            id: 'sa',
            license: 'CC-BY-SA-4.0',
            packId: 'core',
            externalId: 'apple.png',
            localUri: '/symbols/apple.png',
          ),
        );

        final notes = <String>[];
        final files = filesIn(
          await exportObz(
            db,
            set.vocabularyId,
            notes: notes,
            readImage: (_) async => null,
          ),
        );

        // Not a licensing question, so nothing to say about it: the recipient
        // gets the same reference they would have got before any of this.
        expect(manifestIn(files).images, isEmpty);
        expect(notes, isEmpty);
      },
    );
  });
}
