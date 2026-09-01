import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/grid/symbol_view.dart';
import 'package:wordbridge/features/symbols/auto_symbol.dart';
import 'package:wordbridge/features/symbols/symbol_credits.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';
import 'package:wordbridge/features/symbols/system_emoji_pack.dart';

/// The emoji the device already has, offered as pictures.
///
/// Two things are being protected here. The first is legal: the system emoji
/// fonts are proprietary, so what this feature stores has to be the codepoint
/// and never the drawing — no glyph may be extracted, rasterized or bundled.
/// The second is §5's rule: emoji keywords are broad, so these matches may
/// only ever be offered to somebody who is looking at them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const grinning = '\u{1f600}';
  const cook = '\u{1f469}\u{200d}\u{1f373}';

  SymbolRef refTo(String codepoints) =>
      (packId: SystemEmojiPack.packId, externalId: codepoints, label: 'emoji');

  group('the codepoint, never the picture', () {
    test('resolving yields characters, not somewhere to read bytes', () async {
      final pack = SystemEmojiPack();

      expect(await pack.resolve(refTo('1f600')), grinning);
      expect(await pack.resolve(refTo('1f469-200d-1f373')), cook);
    });

    test(
      'what a button is handed is a glyph, so nothing loads a file',
      () async {
        final registry = SymbolRegistry(packs: [SystemEmojiPack()]);
        final resolver = SymbolResolver(registry: registry);
        addTearDown(resolver.dispose);

        final resolved = await resolver.resolve(refTo('1f600'));

        expect(resolved.image?.kind, SymbolImageKind.glyph);
        expect(
          resolved.image?.uri,
          grinning,
          reason:
              'the uri of a glyph is the character; a path here would mean '
              'something had written the drawing to disk',
        );
      },
    );

    test('the pack ships an index and no pictures at all', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final shipped = manifest
          .listAssets()
          .where((key) => key.startsWith('assets/symbols/system-emoji/'))
          .toList();

      expect(
        shipped,
        ['assets/symbols/system-emoji/manifest.json'],
        reason:
            'anything else under here would be a system font glyph that '
            'had been rasterized and bundled, which the licenses forbid',
      );
    });

    test('a stored choice comes back as the same characters', () async {
      final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final registry = SymbolRegistry(packs: [SystemEmojiPack()]);
      final resolver = SymbolResolver(registry: registry, db: db);
      addTearDown(resolver.dispose);

      final symbolId = newId();
      await db
          .into(db.symbols)
          .insert(
            SymbolsCompanion.insert(
              id: symbolId,
              packId: const Value(SystemEmojiPack.packId),
              source: SymbolSource.downloaded,
              externalId: const Value('1f600'),
              label: 'happy',
              license: 'Unicode-3.0',
              attribution: 'CLDR',
              createdAt: nowMs(),
            ),
          );

      final resolved = await resolver.resolveChosen(symbolId, label: 'happy');

      expect(resolved.image?.kind, SymbolImageKind.glyph);
      expect(resolved.image?.uri, grinning);
    });

    test('a sequence that is not characters draws nothing', () async {
      final pack = SystemEmojiPack();

      expect(SystemEmojiPack.charactersFor(''), isNull);
      expect(SystemEmojiPack.charactersFor('   '), isNull);
      expect(SystemEmojiPack.charactersFor('water.png'), isNull);
      expect(SystemEmojiPack.charactersFor('110000'), isNull);
      expect(
        SystemEmojiPack.charactersFor('d800'),
        isNull,
        reason: 'a lone surrogate is half a character and no font can draw it',
      );
      expect(await pack.resolve(refTo('water.png')), isNull);
    });

    test('another pack\'s reference is not this pack\'s to answer', () async {
      final pack = SystemEmojiPack();

      expect(
        await pack.resolve((
          packId: 'core',
          externalId: '1f600',
          label: 'happy',
        )),
        isNull,
      );
    });
  });

  group('what a search box offers', () {
    test('an exact name leads', () async {
      final results = await SystemEmojiPack().search('cat');

      expect(results, isNotEmpty);
      expect(
        results.first.label,
        'cat',
        reason:
            'a search for a word must lead with the emoji of that word, '
            'not with "cat face" or "black cat"',
      );
    });

    test('a keyword finds an emoji whose name does not contain it', () async {
      final results = await SystemEmojiPack().search('happy');

      expect(results.map((r) => r.label), contains('grinning face'));
    });

    test('an externalId is the codepoint sequence', () async {
      final results = await SystemEmojiPack().search('grinning face');

      expect(results.first.externalId, '1f600');
    });

    test('an empty query asks for nothing', () async {
      expect(await SystemEmojiPack().search('   '), isEmpty);
      expect(await SystemEmojiPack().search('cat', limit: 0), isEmpty);
    });

    test('the limit is honored', () async {
      expect(await SystemEmojiPack().search('face', limit: 5), hasLength(5));
    });

    test('it is on without anybody having to turn it on', () {
      final pack = SystemEmojiPack();
      final registry = SymbolRegistry(packs: [pack]);

      expect(pack.allowsCommercialUse, isTrue);
      expect(registry.isEnabled(SystemEmojiPack.packId), isTrue);
    });

    test('a build with no index is an empty pack, not an exception', () async {
      final pack = SystemEmojiPack(bundle: _FakeAssetBundle(const {}));

      expect(await pack.index(), isEmpty);
      expect(await pack.search('cat'), isEmpty);
    });

    test('an index that will not parse is an empty pack', () async {
      final pack = SystemEmojiPack(
        bundle: _FakeAssetBundle({SystemEmojiPack.indexKey: '{oh no'}),
      );

      expect(await pack.search('cat'), isEmpty);
    });

    test('entries that are not name and keywords are ignored', () async {
      final pack = SystemEmojiPack(
        bundle: _FakeAssetBundle({
          SystemEmojiPack.indexKey: json.encode({
            'symbols': {
              '1f600': {
                'name': 'grinning face',
                'keywords': ['happy', 7],
              },
              '1f603': {
                'keywords': ['happy'],
              },
              '1f604': 'grinning face with smiling eyes',
            },
          }),
        }),
      );

      expect(await pack.index(), hasLength(1));
      expect((await pack.index())['1f600']?.keywords, ['happy']);
    });
  });

  group('the bundled index', () {
    test('covers thousands of emoji, all of them drawable', () async {
      final index = await SystemEmojiPack().index();

      expect(index, hasLength(greaterThan(1000)));

      for (final entry in index.entries) {
        expect(
          SystemEmojiPack.charactersFor(entry.key),
          isNotNull,
          reason: '${entry.key} is in the index but names no characters',
        );
        expect(entry.value.name, isNotEmpty);
      }
    });

    test('credits Unicode CLDR, which its license requires', () async {
      final decoded = json.decode(
        await rootBundle.loadString(SystemEmojiPack.indexKey),
      ) as Map<String, dynamic>;

      expect(decoded['license'], 'Unicode-3.0');
      expect(decoded['attributions']['cldr'], contains('Unicode'));
      expect(decoded['attributions']['cldr'], contains('CLDR'));
    });

    test('the credits screen reaches that notice', () {
      expect(
        const SymbolCredits().packs,
        contains(SystemEmojiPack.packId),
        reason:
            'the Unicode license asks for its notice to travel with the '
            'data, and in an app that means a screen somebody can open',
      );
    });
  });

  group('never attached unattended', () {
    late WordbridgeDatabase db;
    late String vocabId;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      vocabId = await seedCoreBoardSet(db);
    });
    tearDown(() async => db.close());

    Future<String> addWord(String label) async {
      final cells = await (db.select(
        db.cells,
      )..where((c) => c.state.equalsValue(CellState.emptyReserved))).get();
      final id = newId();
      await db
          .into(db.buttons)
          .insert(
            ButtonsCompanion.insert(
              id: id,
              cellId: Value(cells.first.id),
              vocabularyId: vocabId,
              label: label,
              message: label,
              action: ButtonAction.speak,
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
      return id;
    }

    Future<String?> symbolOn(String buttonId) async => (await (db.select(
      db.buttons,
    )..where((b) => b.id.equals(buttonId))).getSingle()).symbolId;

    test('the device emoji are for the picker only', () async {
      final pack = SystemEmojiPack();

      // The pack does hold an exact match, so what stops it below is the rule
      // rather than a word nothing indexes.
      expect((await pack.search('dog')).first.label, 'dog');

      final buttonId = await addWord('dog');
      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [pack]),
      ).attachTo(buttonId: buttonId, label: 'dog');

      expect(attached, isFalse);
      expect(
        await symbolOn(buttonId),
        isNull,
        reason:
            'nobody is looking when this runs, and a cartoon dog chosen '
            'unattended puts a word in somebody\'s mouth',
      );
    });

    test('a glyph pack claiming to be bundled is still refused', () async {
      final pack = _FakeGlyphPack(
        refs: [(packId: 'glyphs', externalId: '1f415', label: 'dog')],
      );

      final buttonId = await addWord('dog');
      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [pack]),
      ).attachTo(buttonId: buttonId, label: 'dog');

      expect(attached, isFalse);
      expect(
        pack.searchCount,
        0,
        reason:
            'the exclusion is the interface, not the bundled flag, so a '
            'glyph pack is never even asked',
      );
    });

    test('a pack that is not a glyph pack is attached, as before', () async {
      // The control. Without it a passing test above could mean nothing more
      // than that this harness cannot attach anything at all.
      final pack = _FakePack(
        refs: [(packId: 'core', externalId: 'dog.svg', label: 'dog')],
        uri: 'assets/symbols/core/dog.svg',
      );

      final buttonId = await addWord('dog');
      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [pack]),
      ).attachTo(buttonId: buttonId, label: 'dog');

      expect(attached, isTrue);
      expect(await symbolOn(buttonId), isNotNull);
    });
  });

  group('a glyph on a button', () {
    Future<void> pumpGlyph(WidgetTester tester, {required double side}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: const SymbolPicture((
                    kind: SymbolImageKind.glyph,
                    uri: grinning,
                  )),
                ),
              ),
            ),
          ),
        );

    testWidgets('the character is what gets drawn', (tester) async {
      await pumpGlyph(tester, side: 100);

      expect(find.text(grinning), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it scales up to fill a large cell', (tester) async {
      await pumpGlyph(tester, side: 200);
      final drawn = tester.getRect(find.text(grinning));

      expect(
        drawn.longestSide,
        greaterThan(100),
        reason: 'a glyph left at its own size is a speck in a tablet cell',
      );
    });

    testWidgets('a small cell scales it down rather than cropping it', (
      tester,
    ) async {
      const side = 24.0;
      await pumpGlyph(tester, side: side);

      final laidOut = tester.getSize(find.text(grinning));
      final drawn = tester.getRect(find.text(grinning));

      expect(
        laidOut.height,
        greaterThan(side),
        reason:
            'the character is laid out at its own size and then scaled to '
            'fit; one squeezed into the cell instead is a cropped picture, '
            'which is the broken image an AAC user must never be shown',
      );
      expect(drawn.width, lessThanOrEqualTo(side));
      expect(drawn.height, lessThanOrEqualTo(side));
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) throw FlutterError('no asset at $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

/// A glyph pack that answers exactly, and says it is bundled.
///
/// Both halves matter: auto-attach takes exact matches from bundled packs, so
/// this is the pack that would be accepted if the interface were not what
/// excludes it.
class _FakeGlyphPack implements GlyphSymbolPack {
  _FakeGlyphPack({required this.refs});

  final List<SymbolRef> refs;
  int searchCount = 0;

  @override
  String get id => 'glyphs';

  @override
  String get name => 'glyphs';

  @override
  String get license => 'Unicode-3.0';

  @override
  String get attribution => 'glyphs attribution';

  @override
  bool get allowsCommercialUse => true;

  @override
  bool get isBundled => true;

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async {
    searchCount++;
    return refs;
  }

  @override
  Future<String?> resolve(SymbolRef ref) async => '\u{1f415}';
}

class _FakePack implements SymbolPack {
  _FakePack({required this.refs, this.uri});

  final List<SymbolRef> refs;
  final String? uri;

  @override
  String get id => 'core';

  @override
  String get name => 'core';

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => 'core attribution';

  @override
  bool get allowsCommercialUse => true;

  @override
  bool get isBundled => true;

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async => refs;

  @override
  Future<String?> resolve(SymbolRef ref) async => uri;
}
