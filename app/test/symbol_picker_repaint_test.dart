import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/symbol_picker.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';

/// Choosing a picture means looking at it.
///
/// Results from a downloading pack have no image on the first pass, and the
/// picker is worth nothing until each one redraws itself when its download
/// lands. A caregiver reading a column of words is choosing blind.
void main() {
  late WordbridgeDatabase db;
  late Directory documents;
  late String picture;
  late Button button;

  const ref = (packId: 'testpack', externalId: 'w1', label: 'tap water');
  const other = (packId: 'testpack', externalId: 'w2', label: 'still water');

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    documents = await Directory.systemTemp.createTemp('wordbridge-picker');
    picture = '${documents.path}/water.png';
    File(picture)
        .writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));

    final vocabId = newId();
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
    final boardId = await materializeBoard(
      db,
      vocabularyId: vocabId,
      name: 'home',
      kind: BoardKind.root,
    );
    final cell = await cellAt(db, boardId: boardId, row: 0, col: 0);
    final buttonId = await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: 'water',
      message: 'water',
    );
    button = await (db.select(
      db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingle();
  });

  // The database is deliberately not closed: closing it inside a widget test
  // waits on work the fake clock never runs.
  tearDown(() async => documents.delete(recursive: true));

  /// Pumps the picker on its own rather than through the editor, so nothing
  /// but the sheet can be the thing that rebuilds it.
  Future<SymbolResolver> pumpPicker(
    WidgetTester tester,
    _QueueingPack pack,
  ) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final resolver = SymbolResolver(
      registry: SymbolRegistry(packs: [pack]),
      db: db,
    );
    addTearDown(resolver.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SymbolPicker(
            db: db,
            registry: resolver.registry,
            resolver: resolver,
            button: button,
          ),
        ),
      ),
    );

    // The search and the first resolution each take a turn.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return resolver;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a download that lands draws itself without being asked twice', (
    tester,
  ) async {
    final pack = _QueueingPack(file: picture, refs: const [ref]);
    addTearDown(pack.dispose);
    await pumpPicker(tester, pack);

    expect(
      find.text('tap water'),
      findsOneWidget,
      reason: 'a result with no picture yet still has to be listed',
    );
    expect(find.byType(Image), findsNothing);

    pack.land(ref);
    await settle(tester);

    expect(
      find.byType(Image),
      findsOneWidget,
      reason:
          'the picture is on disk and the row still shows a word, so nothing '
          'short of choosing it blind would ever reveal it',
    );
  });

  testWidgets('only the result that arrived is redrawn', (tester) async {
    final pack = _QueueingPack(file: picture, refs: const [ref, other]);
    addTearDown(pack.dispose);
    await pumpPicker(tester, pack);

    expect(find.byType(Image), findsNothing);

    pack.land(other);
    await settle(tester);

    expect(find.byType(Image), findsOneWidget);

    // Every tile prints its word now, so the absence of a word no longer says
    // anything about whether a picture arrived. Asserted against the tiles
    // themselves instead, which is what the claim was always about: the
    // picture belongs to the result that landed and to no other.
    Finder tileFor(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(InkWell));

    expect(find.text('tap water'), findsOneWidget);
    expect(find.text('still water'), findsOneWidget);
    expect(
      find.descendant(of: tileFor('still water'), matching: find.byType(Image)),
      findsOneWidget,
      reason: 'the picture belongs to the result that landed',
    );
    expect(
      find.descendant(of: tileFor('tap water'), matching: find.byType(Image)),
      findsNothing,
      reason: 'a symbol that has not arrived cannot borrow another one',
    );
  });

  testWidgets('a picture that is not coming says so, and stays listed', (
    tester,
  ) async {
    // The pack still offers it. This device cannot fetch it today, which is an
    // outage worth reporting rather than a reason to shorten the catalog: a
    // result silently dropped reads as "no such picture exists".
    final pack = _QueueingPack(file: picture, refs: const [ref, other])
      ..failures.add(ref.key);
    addTearDown(pack.dispose);
    await pumpPicker(tester, pack);

    expect(
      find.text('tap water'),
      findsOneWidget,
      reason:
          'a picture that failed to download is still a picture that exists',
    );
    expect(find.text('Did not load'), findsOneWidget);

    // The one that has not failed is still worth waiting for, and must not be
    // tarred by its neighbour.
    expect(find.text('still water'), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);
  });

  testWidgets('a picture that arrives stops explaining itself', (tester) async {
    final pack = _QueueingPack(file: picture, refs: const [ref]);
    addTearDown(pack.dispose);
    await pumpPicker(tester, pack);

    expect(find.text('Loading'), findsOneWidget);

    pack.land(ref);
    await settle(tester);

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Loading'), findsNothing);
    expect(find.text('Did not load'), findsNothing);
  });

  testWidgets('a closed sheet stops resolving', (tester) async {
    final pack = _QueueingPack(file: picture, refs: const [ref]);
    addTearDown(pack.dispose);
    await pumpPicker(tester, pack);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);

    final before = pack.resolveCalls;
    pack.land(ref);
    await settle(tester);

    expect(
      pack.resolveCalls,
      before,
      reason:
          'the resolver outlives the sheet, so a subscription left behind '
          'keeps resolving for rows nobody is looking at',
    );
    expect(tester.takeException(), isNull);
  });
}

/// A pack whose images exist only once something says they have landed.
///
/// Stands in for the download path: resolution answers with nothing, then the
/// file appears and the arrival is announced. Nothing here reaches the network.
class _QueueingPack implements DownloadingSymbolPack {
  _QueueingPack({required this.file, required this.refs});

  final String file;
  final List<SymbolRef> refs;

  final _available = StreamController<SymbolRef>.broadcast();
  final _landed = <String>{};

  int resolveCalls = 0;

  /// Set to mark a symbol as given up on, so the tile can say so.
  final failures = <String>{};

  @override
  bool failedFor(SymbolRef ref) => failures.contains(ref.key);

  @override
  String get id => 'testpack';

  @override
  String get name => 'test';

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
  Stream<SymbolRef> get available => _available.stream;

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    Set<String>? sets,
  }) async => refs;

  @override
  Future<String?> resolve(SymbolRef ref, {Set<String>? sets}) async {
    resolveCalls++;
    return _landed.contains(ref.externalId) ? file : null;
  }

  void land(SymbolRef ref) {
    _landed.add(ref.externalId);
    _available.add(ref);
  }

  @override
  Future<void> dispose() async {
    if (!_available.isClosed) await _available.close();
  }
}
