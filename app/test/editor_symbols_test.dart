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
import 'package:wordbridge/features/editor/board_editor.dart';
import 'package:wordbridge/features/editor/symbol_picker.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';

/// The caregiver reads the word; the user reads the picture.
///
/// The board is opened to find out which pictures are wrong, so it has to say
/// what each location currently shows the user, and say which locations have
/// no picture at all — otherwise answering "which of these look wrong?" on a
/// 7x12 board costs 84 taps.
void main() {
  _originTests();
  _tileStateTests();

  late WordbridgeDatabase db;
  late Directory documents;
  late String vocabId;
  late String boardId;
  late String picture;

  /// Serves one word and nothing else, from disk rather than the network.
  ///
  /// [hangs] and [throws] stand for the two ways resolution legitimately fails
  /// to produce an image: a pack that never answers, and one that breaks.
  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    documents = await Directory.systemTemp.createTemp('wordbridge-editor');
    picture = '${documents.path}/water.png';
    File(picture)
        .writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));

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
  // waits on work the fake clock never runs. Each test gets its own in-memory
  // instance and the process ends with the file.
  tearDown(() async => documents.delete(recursive: true));

  Future<void> place(
    int row,
    int col,
    String label, {
    bool hidden = false,
  }) async {
    final cell = await cellAt(db, boardId: boardId, row: row, col: col);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: label,
      hidden: hidden,
    );
  }

  SymbolResolver resolverWith(_FakePack pack) {
    final resolver = SymbolResolver(registry: SymbolRegistry(packs: [pack]));
    addTearDown(resolver.dispose);
    return resolver;
  }

  Future<void> pumpEditor(WidgetTester tester, SymbolResolver? resolver) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BoardEditor(
          db: db,
          vocabularyId: vocabId,
          boardId: boardId,
          resolver: resolver,
        ),
      ),
    );

    // The board arrives over several turns: the vocabulary read, the first
    // cells off the query stream, then each resolution. `pumpAndSettle` cannot
    // be used — the loading spinner never stops.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> closeEditor(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Drift schedules a zero-duration timer when a query stream is dropped.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder cell(int row, int col) => find.byKey(ValueKey('$row:$col'));

  Finder inCell(int row, int col, Finder matching) =>
      find.descendant(of: cell(row, col), matching: matching);

  Color groundOf(WidgetTester tester, int row, int col) => tester
      .widgetList<Material>(inCell(row, col, find.byType(Material)))
      .first
      .color!;

  Set<Color> outlinesOf(WidgetTester tester, int row, int col) => {
    for (final box in tester.widgetList<DecoratedBox>(
      inCell(row, col, find.byType(DecoratedBox)),
    ))
      if (box.decoration case BoxDecoration(border: final Border border))
        border.top.color,
  };

  bool labelIsItalic(WidgetTester tester, int row, int col) =>
      tester
          .widgetList<Text>(inCell(row, col, find.byType(Text)))
          .first
          .style
          ?.fontStyle ==
      FontStyle.italic;

  bool isDimmed(WidgetTester tester, int row, int col) => tester
      .widgetList<Opacity>(inCell(row, col, find.byType(Opacity)))
      .any((o) => o.opacity < 1);

  testWidgets('a word with a picture shows it', (tester) async {
    await place(0, 0, 'water');
    await pumpEditor(
      tester,
      resolverWith(_FakePack(images: {'water': picture})),
    );

    expect(
      inCell(0, 0, find.byType(Image)),
      findsOneWidget,
      reason:
          'the picture the user reads is not on the board a caregiver '
          'audits',
    );
    expect(inCell(0, 0, find.text('water')), findsOneWidget);
    expect(inCell(0, 0, find.byType(Icon)), findsNothing);

    await closeEditor(tester);
  });

  testWidgets('a word with no picture is marked, not left blank', (
    tester,
  ) async {
    await place(0, 0, 'zebra');
    await pumpEditor(
      tester,
      resolverWith(_FakePack(images: {'water': picture})),
    );

    expect(
      inCell(0, 0, find.byIcon(Icons.add_photo_alternate_outlined)),
      findsOneWidget,
      reason: '"no picture yet" is what this screen is scanned for',
    );
    expect(
      inCell(0, 0, find.byIcon(Icons.more_horiz)),
      findsNothing,
      reason: 'a finished lookup that found nothing is not a lookup in flight',
    );
    expect(outlinesOf(tester, 0, 0), contains(const Color(0xFFEF6C00)));
    expect(inCell(0, 0, find.text('zebra')), findsOneWidget);

    expect(
      inCell(0, 0, find.byType(Image)),
      findsNothing,
      reason: 'nothing resolved, so there is nothing to draw',
    );
    expect(tester.takeException(), isNull);

    // A free location stays a quiet blank, so it cannot be read as a word
    // waiting for a picture.
    expect(inCell(0, 1, find.byType(Icon)), findsNothing);
    expect(inCell(0, 1, find.byType(Text)), findsNothing);

    await closeEditor(tester);
  });

  testWidgets('a lookup in flight reads differently from no picture', (
    tester,
  ) async {
    await place(0, 0, 'water');
    await pumpEditor(tester, resolverWith(_FakePack(hangs: true)));

    expect(
      inCell(0, 0, find.byIcon(Icons.more_horiz)),
      findsOneWidget,
      reason: 'a word still being looked up is being reported as having none',
    );
    expect(
      inCell(0, 0, find.byIcon(Icons.add_photo_alternate_outlined)),
      findsNothing,
    );

    // The grid is drawn and working while resolution is outstanding: a queued
    // download must never hold up the editor.
    expect(inCell(0, 0, find.text('water')), findsOneWidget);
    await tester.tap(cell(1, 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('What goes here?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();

    // Let the resolver's own ceiling on a pack that never answers expire.
    await tester.pump(const Duration(seconds: 3));
    await closeEditor(tester);
  });

  testWidgets('a lookup that never answers gives up rather than hanging', (
    tester,
  ) async {
    await place(0, 0, 'water');
    await pumpEditor(tester, resolverWith(_FakePack(hangs: true)));

    expect(inCell(0, 0, find.byIcon(Icons.more_horiz)), findsOneWidget);

    // Past the ceiling the resolver puts on a pack that never answers.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(
      inCell(0, 0, find.byIcon(Icons.add_photo_alternate_outlined)),
      findsOneWidget,
      reason: 'a pack that hangs marks the location "still looking" for good',
    );
    expect(inCell(0, 0, find.byIcon(Icons.more_horiz)), findsNothing);
    expect(inCell(0, 0, find.text('water')), findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(tester.takeException(), isNull);

    await closeEditor(tester);
  });

  testWidgets('a hidden word stays visibly hidden with a picture on it', (
    tester,
  ) async {
    await place(0, 0, 'water', hidden: true);
    await place(0, 1, 'water');
    await pumpEditor(
      tester,
      resolverWith(_FakePack(images: {'water': picture})),
    );

    expect(
      inCell(0, 0, find.byType(Image)),
      findsOneWidget,
      reason: 'a hidden word needs auditing for a wrong picture too',
    );
    expect(
      groundOf(tester, 0, 0),
      const Color(0xFFF0F0F0),
      reason: 'a word switched off reads as a live one once it has a picture',
    );
    expect(groundOf(tester, 0, 1), isNot(const Color(0xFFF0F0F0)));
    expect(labelIsItalic(tester, 0, 0), isTrue);
    expect(labelIsItalic(tester, 0, 1), isFalse);
    expect(isDimmed(tester, 0, 0), isTrue);
    expect(isDimmed(tester, 0, 1), isFalse);

    await closeEditor(tester);
  });

  testWidgets('a pack that breaks leaves a usable editor', (tester) async {
    await place(0, 0, 'water');
    await pumpEditor(tester, resolverWith(_FakePack(throws: true)));

    expect(tester.takeException(), isNull);
    expect(inCell(0, 0, find.text('water')), findsOneWidget);
    expect(
      inCell(0, 0, find.byIcon(Icons.add_photo_alternate_outlined)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image), findsNothing);

    await tester.tap(cell(1, 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('What goes here?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();
    await closeEditor(tester);
  });

  testWidgets('an editor with no resolver claims nothing about pictures', (
    tester,
  ) async {
    // Nothing to resolve with means nothing is known about which pictures are
    // missing, and saying otherwise would send a caregiver hunting for
    // pictures that are already there.
    await place(0, 0, 'water');
    await pumpEditor(tester, null);

    expect(inCell(0, 0, find.text('water')), findsOneWidget);
    expect(inCell(0, 0, find.byType(Icon)), findsNothing);

    await closeEditor(tester);
  });

  testWidgets('the word picked up for moving is marked where it sits', (
    tester,
  ) async {
    await place(0, 0, 'water');
    await pumpEditor(
      tester,
      resolverWith(_FakePack(images: {'water': picture})),
    );

    await tester.tap(cell(0, 0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Move to another location'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      outlinesOf(tester, 0, 0),
      contains(const Color(0xFF3F51B5)),
      reason: 'the word being moved is not marked on the board it moves on',
    );
    expect(
      outlinesOf(tester, 1, 2),
      isNot(contains(const Color(0xFF3F51B5))),
      reason: 'every location is marked as picked up',
    );

    await closeEditor(tester);
  });
}

/// A pack holding a fixed set of words, answered from disk.
///
/// Nothing here reaches the network.
class _FakePack implements SymbolPack {
  _FakePack({this.images = const {}, this.hangs = false, this.throws = false});

  /// Word to the file illustrating it.
  final Map<String, String> images;

  final bool hangs;
  final bool throws;

  @override
  String get id => 'core';

  @override
  String get name => 'core';

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => 'test';

  @override
  bool get allowsCommercialUse => true;

  /// Not bundled, so resolution yields a file path and the test never needs an
  /// asset in the build.
  @override
  bool get isBundled => false;

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) {
    if (hangs) return Completer<List<SymbolRef>>().future;
    if (throws) throw StateError('broken');
    if (!images.containsKey(query)) return Future.value(const []);
    return Future.value([(packId: id, externalId: query, label: query)]);
  }

  @override
  Future<String?> resolve(SymbolRef ref) {
    if (hangs) return Completer<String?>().future;
    if (throws) throw StateError('broken');
    return Future.value(images[ref.label]);
  }
}

/// A pack that knows which upstream set each symbol came from.
class _AssembledPack implements AssembledSymbolPack {
  _AssembledPack(this.sources);

  /// Word to the set that drew it.
  final Map<String, String> sources;

  @override
  String get id => 'core';

  @override
  String get name => 'Wordbridge AAC core symbols';

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => 'Assembled.';

  @override
  bool get allowsCommercialUse => true;

  @override
  bool get isBundled => true;

  @override
  String? sourceOf(SymbolRef ref) => sources[ref.label];

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async => const [];

  @override
  String? creditFor(SymbolRef ref) =>
      sourceOf(ref) == null ? null : 'Drawn by ${sourceOf(ref)}';

  @override
  Future<String?> resolve(SymbolRef ref) async => null;
}

void _originTests() {
  group('naming where a picture came from', () {
    SymbolRef ref(String label, String external) =>
        (packId: 'core', externalId: external, label: label);

    test('an assembled pack names the set, not itself', () {
      // "Wordbridge AAC core symbols" is true of all four sets and
      // none of them, which is what made a replacement impossible to ask for.
      final pack = _AssembledPack({'woman': 'tawasol', 'all': 'mulberry'});

      expect(symbolOrigin(pack, ref('woman', 'woman.svg')), 'tawasol');
      expect(symbolOrigin(pack, ref('all', 'all.svg')), 'mulberry');
    });

    test('falls back to the pack when the set is unknown', () {
      expect(
        symbolOrigin(_AssembledPack(const {}), ref('woman', 'woman.svg')),
        'Wordbridge AAC core symbols',
      );
    });

    test('a numbered pack keeps its catalog number', () {
      // The only stable handle those sets have, and what they call themselves.
      expect(
        symbolOrigin(_FakePack(), (
          packId: 'core',
          externalId: '2462',
          label: 'woman',
        )),
        'core 2462',
      );
    });

    test('a filename is not shown, because it repeats the label', () {
      expect(symbolOrigin(_FakePack(), ref('woman', 'woman.svg')), 'core');
    });

    test('no pack, nothing to say', () {
      expect(symbolOrigin(null, ref('woman', 'woman.svg')), isNull);
    });
  });
}

/// A downloading pack that can be told a fetch has been given up on.
class _DownloadingPack implements DownloadingSymbolPack {
  _DownloadingPack({this.failed = const {}});

  /// Refs, by key, whose fetch has been abandoned.
  final Set<String> failed;

  @override
  String get id => 'globalsymbols';

  @override
  String get name => 'Global Symbols';

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => 'Global Symbols.';

  @override
  bool get allowsCommercialUse => true;

  @override
  bool get isBundled => false;

  @override
  Stream<SymbolRef> get available => const Stream.empty();

  @override
  bool failedFor(SymbolRef ref) => failed.contains(ref.key);

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async => const [];

  @override
  Future<String?> resolve(SymbolRef ref) async => null;

  @override
  Future<void> dispose() async {}
}

void _tileStateTests() {
  group('why a tile is showing a word', () {
    const ref = (packId: 'globalsymbols', externalId: '2462', label: 'woman');

    test('a picture that is drawn is just drawn', () {
      expect(
        symbolTileState(
          hasImage: true,
          pending: false,
          pack: _DownloadingPack(),
          ref: ref,
        ),
        SymbolTileState.showing,
      );
    });

    test('a resolution still running is worth waiting for', () {
      expect(
        symbolTileState(
          hasImage: false,
          pending: true,
          pack: _DownloadingPack(),
          ref: ref,
        ),
        SymbolTileState.looking,
      );
    });

    test('a download not yet attempted is still coming', () {
      // Resolution only queues a fetch, so an empty answer from a downloading
      // pack is the normal first state and not a failure.
      expect(
        symbolTileState(
          hasImage: false,
          pending: false,
          pack: _DownloadingPack(),
          ref: ref,
        ),
        SymbolTileState.looking,
      );
    });

    test('a download given up on says so rather than waiting for ever', () {
      expect(
        symbolTileState(
          hasImage: false,
          pending: false,
          pack: _DownloadingPack(failed: {ref.key}),
          ref: ref,
        ),
        SymbolTileState.unavailable,
      );
    });

    test('one symbol failing says nothing about another', () {
      expect(
        symbolTileState(
          hasImage: false,
          pending: false,
          pack: _DownloadingPack(failed: {'globalsymbols/9999'}),
          ref: ref,
        ),
        SymbolTileState.looking,
      );
    });

    test('a bundled pack has already answered, so nothing is coming', () {
      // Its images ship with the app. An empty answer is final.
      expect(
        symbolTileState(
          hasImage: false,
          pending: false,
          pack: _FakePack(),
          ref: ref,
        ),
        SymbolTileState.none,
      );
    });

    test('no pack at all is nothing coming', () {
      expect(
        symbolTileState(hasImage: false, pending: false, pack: null, ref: ref),
        SymbolTileState.none,
      );
    });
  });
}
