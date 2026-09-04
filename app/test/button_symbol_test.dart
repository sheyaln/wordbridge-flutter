import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/board_editor.dart';
import 'package:wordbridge/features/editor/symbol_picker.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';

/// The picture a caregiver chose is the picture both boards draw.
///
/// Auto-attachment takes exact keyword matches only, so the picture a word
/// resolves to on its own is usually the picture somebody opens the picker to
/// get rid of. If a keyword match can outrank a choice, then changing a
/// picture, removing one, and photographing the real cup all do nothing, and
/// the person reading the button cannot say so.
void main() {
  late WordbridgeDatabase db;
  late Directory documents;
  late String vocabId;
  late String boardId;

  /// What the word "water" resolves to on its own.
  late String packPicture;

  /// What a caregiver picked instead.
  late String chosenPicture;

  /// A photograph of the real thing.
  late String photo;

  String writeImage(String name) {
    final path = '${documents.path}/$name';
    File(path).writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
    return path;
  }

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    documents = await Directory.systemTemp.createTemp('wordbridge-symbols');
    packPicture = writeImage('water.png');
    chosenPicture = writeImage('cup.png');
    photo = writeImage('photo.png');

    vocabId = newId();
    final ts = nowMs();
    await db
        .into(db.vocabularies)
        .insert(
          VocabulariesCompanion.insert(
            id: vocabId,
            name: 'test',
            gridRows: 2,
            gridCols: 3,
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    boardId = await materializeBoard(
      db,
      vocabularyId: vocabId,
      name: 'home',
      kind: BoardKind.root,
    );
  });

  // The database is deliberately not closed: closing it inside a widget test
  // waits on work the fake clock never runs.
  tearDown(() async => documents.delete(recursive: true));

  /// Serves "water" and nothing else, from disk rather than the network.
  _FakePack packServingWater({String name = 'core'}) => _FakePack(
    name: name,
    words: const {'water': 'water.png'},
    files: {'water.png': packPicture, 'cup.png': chosenPicture},
  );

  SymbolResolver resolverWith(SymbolPack pack, {WordbridgeDatabase? database}) {
    final resolver = SymbolResolver(
      registry: SymbolRegistry(packs: [pack]),
      db: database ?? db,
    );
    addTearDown(resolver.dispose);
    return resolver;
  }

  Future<String> packSymbol({
    required String externalId,
    required String label,
  }) async {
    final id = newId();
    await db
        .into(db.symbols)
        .insert(
          SymbolsCompanion.insert(
            id: id,
            packId: const Value('core'),
            externalId: Value(externalId),
            source: SymbolSource.downloaded,
            localUri: Value(chosenPicture),
            label: label,
            license: 'CC-BY-SA-4.0',
            attribution: 'test',
            createdAt: nowMs(),
          ),
        );
    return id;
  }

  Future<String> ownPhoto(String path) async {
    final id = newId();
    await db
        .into(db.symbols)
        .insert(
          SymbolsCompanion.insert(
            id: id,
            source: SymbolSource.custom,
            localUri: Value(path),
            label: 'Nana',
            license: 'user-owned',
            attribution: 'Supplied by the device owner.',
            createdAt: nowMs(),
          ),
        );
    return id;
  }

  Future<Button> place(
    int row,
    int col,
    String label, {
    String? symbolId,
  }) async {
    final cell = await cellAt(db, boardId: boardId, row: row, col: col);
    final id = await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: label,
      symbolId: symbolId,
    );
    return (db.select(db.buttons)..where((b) => b.id.equals(id))).getSingle();
  }

  Future<Button> reread(String buttonId) =>
      (db.select(db.buttons)..where((b) => b.id.equals(buttonId))).getSingle();

  Future<void> setSymbol(String buttonId, String? symbolId) =>
      (db.update(db.buttons)..where((b) => b.id.equals(buttonId))).write(
        ButtonsCompanion(symbolId: Value(symbolId), updatedAt: Value(nowMs())),
      );

  group('resolving what a button draws', () {
    test('a chosen symbol outranks the picture for the word', () async {
      final resolver = resolverWith(packServingWater());
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');

      final resolved = await resolver.resolveButton(
        symbolId: chosen,
        label: 'water',
        packIds: const ['core'],
      );

      expect(resolved.image?.uri, chosenPicture);
    });

    test('a word with no symbol of its own still takes the pack picture', () {
      final resolver = resolverWith(packServingWater());

      expect(
        resolver
            .resolveButton(
              symbolId: null,
              label: 'water',
              packIds: const ['core'],
            )
            .then((r) => r.image?.uri),
        completion(packPicture),
      );
    });

    test('a photograph on this device draws', () async {
      final resolver = resolverWith(packServingWater());
      final chosen = await ownPhoto(photo);

      final resolved = await resolver.resolveButton(
        symbolId: chosen,
        label: 'Nana',
        packIds: const ['core'],
      );

      expect(resolved.image, (kind: SymbolImageKind.file, uri: photo));
    });

    test('a chosen symbol whose file is gone leaves the word alone', () async {
      final resolver = resolverWith(packServingWater());
      final chosen = await ownPhoto('${documents.path}/deleted.png');

      final resolved = await resolver.resolveButton(
        symbolId: chosen,
        // The word the packs illustrate, so a fallback would be visible.
        label: 'water',
        packIds: const ['core'],
      );

      expect(resolved.image, isNull);
      expect(resolved.label, 'water');
    });

    test('a symbol carrying no image at all draws nothing', () async {
      final resolver = resolverWith(packServingWater());
      final id = newId();
      await db
          .into(db.symbols)
          .insert(
            SymbolsCompanion.insert(
              id: id,
              source: SymbolSource.custom,
              label: '',
              license: '',
              attribution: '',
              createdAt: nowMs(),
            ),
          );

      final resolved = await resolver.resolveButton(
        symbolId: id,
        label: 'water',
        packIds: const ['core'],
      );

      expect(resolved.image, isNull);
    });

    test(
      'with no symbol store a button keeps the picture for its word',
      () async {
        // Nothing can read a choice, so nothing is claimed about one — least of
        // all that the button lost the picture it was drawing.
        final resolver = SymbolResolver(
          registry: SymbolRegistry(packs: [packServingWater()]),
        );
        addTearDown(resolver.dispose);
        final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');

        final resolved = await resolver.resolveButton(
          symbolId: chosen,
          label: 'water',
          packIds: const ['core'],
        );

        expect(resolved.image?.uri, packPicture);
      },
    );

    test('a chosen symbol from a pack switched off draws nothing', () async {
      // Opting out of a pack has to take its pictures off the board, and a
      // path stored on the symbol row is not a way around that.
      final registry = SymbolRegistry(packs: [packServingWater()]);
      registry.setSetEnabled('core', false);
      final resolver = SymbolResolver(registry: registry, db: db);
      addTearDown(resolver.dispose);
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');

      final resolved = await resolver.resolveButton(
        symbolId: chosen,
        label: 'water',
        packIds: const ['core'],
      );

      expect(resolved.image, isNull);
    });

    test('a symbol row that is not there is not an exception', () async {
      final resolver = resolverWith(packServingWater());

      final resolved = await resolver.resolveButton(
        symbolId: 'gone',
        label: 'water',
        packIds: const ['core'],
      );

      expect(resolved.image, isNull);
    });
  });

  group('drawing a button', () {
    Finder cell(int row, int col) => find.byKey(ValueKey('$row:$col'));

    Finder inCell(int row, int col, Finder matching) =>
        find.descendant(of: cell(row, col), matching: matching);

    /// The file the location is showing, or null if it is showing its word.
    String? pictureIn(WidgetTester tester, int row, int col) {
      final drawn = tester.widgetList<Image>(
        inCell(row, col, find.byType(Image)),
      );
      if (drawn.isEmpty) return null;
      return (drawn.first.image as FileImage).file.path;
    }

    /// Resolution reads the disk, and a widget test holds real file access at
    /// the door until the real event loop is let turn.
    Future<void> settle(WidgetTester tester, {int turns = 12}) async {
      for (var i = 0; i < turns; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> pumpBoard(
      WidgetTester tester, {
      required List<PlacedCell> cells,
      required SymbolResolver resolver,
      void Function(PlacedCell)? onSelect,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GridSurface(
                rows: 2,
                cols: 3,
                cells: cells,
                vocabLevel: 1,
                colorConvention: ColorConvention.modifiedFitzgerald,
                resolver: resolver,
                onSelect: onSelect ?? (_) {},
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> pumpEditor(
      WidgetTester tester, {
      required SymbolResolver resolver,
      SymbolRegistry? registry,
    }) async {
      // Tall enough for the picker sheet, which is a fraction of the screen.
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: BoardEditor(
            db: db,
            vocabularyId: vocabId,
            boardId: boardId,
            resolver: resolver,
            registry: registry,
          ),
        ),
      );
      await settle(tester);
    }

    /// Opens the picker on its own, with no editor behind it, so that what a
    /// removal writes is whatever the picker itself decided to write.
    Future<void> pumpPicker(
      WidgetTester tester, {
      required Button button,
      required SymbolPack pack,
    }) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final registry = SymbolRegistry(packs: [pack]);
      final resolver = resolverWith(pack);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => SymbolPicker.show(
                  context,
                  db: db,
                  registry: registry,
                  resolver: resolver,
                  button: button,
                ),
                child: const Text('open the picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open the picker'));
      await settle(tester, turns: 20);
    }

    Future<void> closeBoard(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      // Drift schedules a zero-duration timer when a query stream is dropped.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<List<PlacedCell>> boardCells() async {
      final cells = await (db.select(
        db.cells,
      )..where((c) => c.boardId.equals(boardId))).get();
      final buttons = await db.select(db.buttons).get();
      return [
        for (final c in cells)
          (cell: c, button: buttons.where((b) => b.cellId == c.id).firstOrNull),
      ];
    }

    testWidgets('the user sees the chosen picture, not the word match', (
      tester,
    ) async {
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');
      await place(0, 0, 'water', symbolId: chosen);

      await pumpBoard(
        tester,
        cells: await boardCells(),
        resolver: resolverWith(packServingWater()),
      );

      expect(
        pictureIn(tester, 0, 0),
        chosenPicture,
        reason: 'a picture nobody chose is on the board over one somebody did',
      );
      expect(inCell(0, 0, find.text('water')), findsOneWidget);

      await closeBoard(tester);
    });

    testWidgets('changing the picture changes what is drawn', (tester) async {
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');
      final button = await place(0, 0, 'water');
      final resolver = resolverWith(packServingWater());

      await pumpBoard(tester, cells: await boardCells(), resolver: resolver);
      expect(pictureIn(tester, 0, 0), packPicture);

      await setSymbol(button.id, chosen);
      await pumpBoard(tester, cells: await boardCells(), resolver: resolver);

      expect(
        pictureIn(tester, 0, 0),
        chosenPicture,
        reason: 'the picker wrote a choice the board went on ignoring',
      );

      await closeBoard(tester);
    });

    testWidgets('a photograph of the real thing draws', (tester) async {
      final chosen = await ownPhoto(photo);
      await place(0, 0, 'Nana', symbolId: chosen);

      await pumpBoard(
        tester,
        cells: await boardCells(),
        resolver: resolverWith(packServingWater()),
      );

      expect(pictureIn(tester, 0, 0), photo);

      await closeBoard(tester);
    });

    testWidgets('a chosen symbol with no file left shows the word only', (
      tester,
    ) async {
      final chosen = await ownPhoto('${documents.path}/deleted.png');
      await place(0, 0, 'water', symbolId: chosen);

      await pumpBoard(
        tester,
        cells: await boardCells(),
        resolver: resolverWith(packServingWater()),
      );

      expect(pictureIn(tester, 0, 0), isNull);
      expect(inCell(0, 0, find.text('water')), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(tester.takeException(), isNull);

      await closeBoard(tester);
    });

    testWidgets('the editor draws the button the talk screen draws', (
      tester,
    ) async {
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');
      await place(0, 0, 'water', symbolId: chosen);
      final resolver = resolverWith(packServingWater());

      await pumpBoard(tester, cells: await boardCells(), resolver: resolver);
      final asDrawnForTheUser = pictureIn(tester, 0, 0);
      await closeBoard(tester);

      await pumpEditor(tester, resolver: resolver);
      final asDrawnForTheCaregiver = pictureIn(tester, 0, 0);

      expect(asDrawnForTheUser, chosenPicture);
      expect(
        asDrawnForTheCaregiver,
        asDrawnForTheUser,
        reason: 'the pictures are audited on a board nobody uses',
      );
      expect(
        inCell(0, 0, find.byIcon(Icons.add_photo_alternate_outlined)),
        findsNothing,
      );

      await closeBoard(tester);
    });

    testWidgets('removing the picture removes it, and it stays removed', (
      tester,
    ) async {
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');
      final button = await place(0, 0, 'water', symbolId: chosen);
      final pack = packServingWater();
      final resolver = resolverWith(pack);

      await pumpEditor(
        tester,
        resolver: resolver,
        registry: SymbolRegistry(packs: [pack]),
      );
      expect(pictureIn(tester, 0, 0), chosenPicture);

      await tester.tap(cell(0, 0));
      await settle(tester, turns: 20);
      await tester.tap(find.text('Change the picture'));
      await settle(tester, turns: 20);

      await tester.tap(find.text('Remove the picture'));
      await settle(tester, turns: 20);

      expect(
        pictureIn(tester, 0, 0),
        isNull,
        reason: 'the word re-resolved to the picture that was just removed',
      );
      expect(inCell(0, 0, find.text('water')), findsOneWidget);
      expect(
        inCell(0, 0, find.byIcon(Icons.add_photo_alternate_outlined)),
        findsOneWidget,
        reason: 'a button with no picture has to read as having none',
      );

      // The removal is a state of its own, not an absent one: it survives a
      // relaunch, where a null would be read as "never chosen" and draw the
      // pack picture straight back.
      expect((await reread(button.id)).symbolId, removedPictureSymbolId);
      await closeBoard(tester);

      await pumpEditor(
        tester,
        resolver: resolverWith(packServingWater()),
        registry: SymbolRegistry(packs: [pack]),
      );
      expect(pictureIn(tester, 0, 0), isNull);

      await closeBoard(tester);
    });

    testWidgets(
      'the picker is what records a removal, with nothing behind it',
      (tester) async {
        final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');
        final button = await place(0, 0, 'water', symbolId: chosen);

        await pumpPicker(tester, button: button, pack: packServingWater());
        await tester.tap(find.text('Remove the picture'));
        await settle(tester, turns: 20);

        expect(
          (await reread(button.id)).symbolId,
          removedPictureSymbolId,
          reason:
              'the removal is only a removal once something else translates '
              'it, which is not what the picker writes',
        );

        final events = await (db.select(
          db.editEvents,
        )..where((e) => e.buttonId.equals(button.id))).get();
        expect(
          events.map((e) => e.kind),
          contains(EditKind.resymbol),
          reason:
              'a picture came off a button and the edit log does not say so',
        );
      },
    );

    testWidgets('a search result says which pack drew it', (tester) async {
      // A search puts several packs' answers to one word side by side, and
      // choosing between house styles nobody can name is how a board ends up
      // assembled from four sets. The licenses also require the credit to be
      // reachable from inside the app, and this is where it is useful.
      final button = await place(0, 0, 'water');

      await pumpPicker(
        tester,
        button: button,
        pack: packServingWater(name: 'Mulberry'),
      );

      expect(
        find.text('Mulberry'),
        findsWidgets,
        reason: 'the result does not say where the picture came from',
      );
    });

    testWidgets('a picture nobody chose can still be taken off', (
      tester,
    ) async {
      // Most of the shipped board is like this: no symbol of its own, drawing
      // whatever the packs hold for the word. Asking whether a picture was
      // *chosen* hides the control on exactly the buttons somebody is looking
      // at a picture on.
      final button = await place(0, 0, 'water');
      expect(button.symbolId, isNull);

      await pumpPicker(tester, button: button, pack: packServingWater());

      expect(
        find.text('Remove the picture'),
        findsOneWidget,
        reason:
            'the button draws a pack picture and there is no way to take it '
            'off',
      );

      await tester.tap(find.text('Remove the picture'));
      await settle(tester, turns: 20);

      expect((await reread(button.id)).symbolId, removedPictureSymbolId);
    });

    testWidgets('a slow pack does not make the control appear late', (
      tester,
    ) async {
      // The other way to get this wrong: waiting for the answer before
      // offering the control. A caregiver who opens the sheet, sees no way to
      // take the picture off and closes it has been told something false by a
      // pack that had not replied yet.
      final button = await place(0, 0, 'water');

      await pumpPicker(
        tester,
        button: button,
        pack: _FakePack(hangs: true, name: 'slow'),
      );

      expect(
        find.text('Remove the picture'),
        findsOneWidget,
        reason: 'the control waits for the lookup instead of leading it',
      );

      // Let the search and the resolver's own ceilings on a pack that never
      // answers expire, so nothing is left pending at teardown. Longer than
      // `SymbolRegistry.searchBudget`, which is what governs here — a pack
      // that never replies is cut off by that and by nothing else.
      await tester.pump(const Duration(seconds: 12));
    });

    testWidgets('the preview is what the board draws, not what any pack has', (
      tester,
    ) async {
      // The picker searches every pack, which is the point of it. What the
      // button is *currently* drawing is a different question with a different
      // answer: the board falls back to the curated pack alone, so a preview
      // taken from all of them shows the caregiver a picture the user never
      // sees — and offers to remove it.
      final button = await place(0, 0, 'water');

      await pumpPicker(
        tester,
        button: button,
        pack: _FakePack(
          words: {'water': 'cup.png'},
          files: {'cup.png': '/tmp/cup.png'},
          name: 'elsewhere',
          id: 'elsewhere',
        ),
      );

      expect(
        find.text('Remove the picture'),
        findsNothing,
        reason:
            'the button draws no picture on the board, so there is nothing '
            'here to take off',
      );
    });

    testWidgets('a word with no picture anywhere is not offered it', (
      tester,
    ) async {
      final button = await place(0, 1, 'because');

      await pumpPicker(tester, button: button, pack: packServingWater());

      expect(
        find.text('Remove the picture'),
        findsNothing,
        reason:
            'a control offering to take off a picture that was never there '
            'is reported as broken, because it is',
      );
    });

    testWidgets('a button already marked as having none is not offered it', (
      tester,
    ) async {
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');
      final button = await place(0, 0, 'water', symbolId: chosen);

      await pumpPicker(tester, button: button, pack: packServingWater());
      await tester.tap(find.text('Remove the picture'));
      await settle(tester, turns: 20);

      await pumpPicker(
        tester,
        button: await reread(button.id),
        pack: packServingWater(),
      );

      expect(
        find.text('Remove the picture'),
        findsNothing,
        reason:
            'a control offering to take off a picture that is already off '
            'is reported as broken, because it is',
      );
    });

    testWidgets('a picture still being looked for does not hold up a tap', (
      tester,
    ) async {
      final chosen = await packSymbol(externalId: 'cup.png', label: 'cup');
      await place(0, 0, 'water', symbolId: chosen);
      final spoken = <String>[];

      await pumpBoard(
        tester,
        cells: await boardCells(),
        resolver: resolverWith(_FakePack(hangs: true)),
        onSelect: (placed) => spoken.add(placed.button!.label),
      );

      expect(inCell(0, 0, find.text('water')), findsOneWidget);
      await tester.tap(cell(0, 0));
      await tester.pump();

      expect(spoken, [
        'water',
      ], reason: 'a button that cannot find its picture cannot be pressed');

      // Let the resolver's own ceiling on a pack that never answers expire.
      await tester.pump(const Duration(seconds: 3));
      await closeBoard(tester);
    });

    testWidgets('a picture that arrives late needs no second visit', (
      tester,
    ) async {
      final pack = _LatePack();
      await place(0, 0, 'water');

      await pumpBoard(
        tester,
        cells: await boardCells(),
        resolver: resolverWith(pack),
      );
      expect(pictureIn(tester, 0, 0), isNull);

      pack.land(packPicture);
      await settle(tester);

      expect(
        pictureIn(tester, 0, 0),
        packPicture,
        reason: 'a download that landed is on screen only after a revisit',
      );

      await closeBoard(tester);
    });
  });
}

/// A pack holding a fixed set of words, answered from disk.
///
/// Nothing here reaches the network.
class _FakePack implements SymbolPack {
  _FakePack({
    this.words = const {},
    this.files = const {},
    this.hangs = false,
    this.name = 'core',
    this.id = 'core',
  });

  /// Word to the symbol illustrating it, as a search answers.
  final Map<String, String> words;

  /// Symbol to the file on disk.
  final Map<String, String> files;

  /// Stands for a pack that never answers: a queued download, a slow disk.
  final bool hangs;

  @override
  final String id;

  @override
  final String name;

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => 'test';

  @override
  List<SymbolSet> get sets => [
    (
      slug: id,
      name: name,
      attribution: attribution,
      license: license,
      allowsCommercialUse: true,
    ),
  ];

  /// Not bundled, so resolution yields a file path and no test needs an asset
  /// in the build.
  @override
  bool get isBundled => false;

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    Set<String>? sets,
  }) async {
    if (hangs) return Completer<List<SymbolRef>>().future;
    final externalId = words[query];
    if (externalId == null) return const [];
    return [(packId: id, externalId: externalId, label: query)];
  }

  @override
  Future<String?> resolve(SymbolRef ref, {Set<String>? sets}) {
    if (hangs) return Completer<String?>().future;
    return Future.value(files[ref.externalId]);
  }
}

/// A pack whose image arrives after the board has been drawn.
class _LatePack implements DownloadingSymbolPack {
  final _available = StreamController<SymbolRef>.broadcast();
  static const _ref = (packId: 'core', externalId: 'water.png', label: 'water');

  String? _path;

  void land(String path) {
    _path = path;
    _available.add(_ref);
  }

  @override
  bool failedFor(SymbolRef ref) => false;

  @override
  Stream<SymbolRef> get available => _available.stream;

  @override
  String get id => 'core';

  @override
  String get name => 'core';

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => 'test';

  @override
  List<SymbolSet> get sets => [
    (
      slug: id,
      name: name,
      attribution: attribution,
      license: license,
      allowsCommercialUse: true,
    ),
  ];

  @override
  bool get isBundled => false;

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    Set<String>? sets,
  }) async => query == 'water' ? const [_ref] : const [];

  @override
  Future<String?> resolve(SymbolRef ref, {Set<String>? sets}) async => _path;

  @override
  Future<void> dispose() => _available.close();
}
