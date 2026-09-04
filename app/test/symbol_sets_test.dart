import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wordbridge/features/symbols/arasaac_pack.dart';
import 'package:wordbridge/features/symbols/bundled_pack.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';
import 'package:wordbridge/features/symbols/symbol_credits.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_sets.dart';

/// Switching one picture set off, and everything that has to stop.
///
/// The failure this guards is a switch that lies. Stellar and OpenMoji ship
/// inside `core` *and* are fetched from Global Symbols, so a switch wired to a
/// pack could only ever turn off one half of a set: the search would go quiet
/// while the shipped board carried on drawing the same pictures. Turned round,
/// a set switched off that still costs a request, still answers [
/// GlobalSymbolsPack.bestMatch], or still draws a picture chosen last month is
/// the same lie told the other way.
///
/// And the second half: every set a person can reach has to be credited. All
/// of these are CC BY-SA or CC BY-NC-SA, which require it wherever the work
/// appears, and the sets behind the fetching pack were credited nowhere in the
/// app at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String labels(List<({String text, int id})> hits) => jsonEncode([
    for (final hit in hits)
      {
        'text': hit.text,
        'picto': {
          'id': hit.id,
          'image_url': 'https://example.test/${hit.id}.svg',
          'native_format': 'svg',
        },
      },
  ]);

  group('a set that is off is not asked', () {
    /// Records which sets were actually queried, so "it was filtered out of
    /// the answer" cannot pass for "it was never asked".
    ({GlobalSymbolsPack pack, List<String> asked}) probe() {
      final asked = <String>[];
      final pack = GlobalSymbolsPack(
        client: MockClient((request) async {
          final set = request.url.queryParameters['symbolset']!;
          asked.add(set);
          return http.Response(
            labels([(text: 'drink', id: set.hashCode)]),
            200,
          );
        }),
      );
      return (pack: pack, asked: asked);
    }

    test('so switching one off costs fewer requests, never more', () async {
      final all = probe();
      addTearDown(all.pack.dispose);
      await SymbolRegistry(packs: [all.pack]).search('drink');

      final fewer = probe();
      addTearDown(fewer.pack.dispose);
      final registry = SymbolRegistry(packs: [fewer.pack])
        ..setSetEnabled('tawasol', false);
      await registry.search('drink');

      expect(fewer.asked, isNot(contains('tawasol')));
      expect(fewer.asked, hasLength(all.asked.length - 1));
    });

    test('and a pack with every set off is not called at all', () async {
      final quiet = probe();
      addTearDown(quiet.pack.dispose);
      final registry = SymbolRegistry(packs: [quiet.pack]);
      for (final set in GlobalSymbolsPack.commercialSets) {
        registry.setSetEnabled(set.slug, false);
      }

      expect(await registry.search('drink'), isEmpty);
      expect(quiet.asked, isEmpty);
    });

    test('naming it on a filter reaches it no more than a search does', () {
      // A filter chip is the obvious way around the rule, and it is held by
      // whoever just switched the set off.
      final chip = probe();
      addTearDown(chip.pack.dispose);
      final registry = SymbolRegistry(packs: [chip.pack])
        ..setSetEnabled('tawasol', false);

      expect(registry.search('drink', setSlug: 'tawasol'), completion(isEmpty));
    });

    test('nor can the app attach one to a button by itself', () async {
      // `bestMatch` is what runs unwatched. A set that is off answering it
      // would put a picture on a button nobody chose it for.
      final pack = GlobalSymbolsPack(
        client: MockClient((request) async {
          final set = request.url.queryParameters['symbolset'];
          return http.Response(
            set == 'tawasol' ? labels([(text: 'drink', id: 9)]) : '[]',
            200,
          );
        }),
      );
      addTearDown(pack.dispose);
      final registry = SymbolRegistry(packs: [pack]);

      expect(
        (await pack.bestMatch(
          'drink',
          sets: registry.enabledSetsOf(pack),
        ))?.externalId,
        '9',
      );

      registry.setSetEnabled('tawasol', false);
      expect(
        await pack.bestMatch('drink', sets: registry.enabledSetsOf(pack)),
        isNull,
      );
    });
  });

  group('one switch governs the shipped picture and the fetched one', () {
    /// A bundled pack whose manifest files "water" under Stellar and "cat"
    /// under OpenMoji, which is the shape `core` actually has.
    BundledSymbolPack bundled() => BundledSymbolPack(
      id: 'core',
      name: 'Core symbols',
      license: 'CC-BY-SA-4.0',
      attribution: 'Core symbols.',
      sets: const [stellarSymbolsSet, openmojiSet],
      bundle: _FakeBundle({
        'assets/symbols/core/manifest.json': jsonEncode({
          'symbols': {
            'water': {'file': 'water.svg', 'set': 'stellar-symbols'},
            'cat': {'file': 'cat.svg', 'set': 'openmoji'},
          },
        }),
        'assets/symbols/core/water.svg': '<svg/>',
        'assets/symbols/core/cat.svg': '<svg/>',
      }),
    );

    const water = (packId: 'core', externalId: 'water.svg', label: 'water');

    test('a bundled picture stops drawing when its set is off', () async {
      final registry = SymbolRegistry(packs: [bundled()]);

      expect(await registry.resolve(water), 'assets/symbols/core/water.svg');

      registry.setSetEnabled('stellar-symbols', false);
      expect(
        await registry.resolve(water),
        isNull,
        reason:
            'most of what a new device draws came out of the binary, so a '
            'switch that spared those reads as one that does nothing',
      );
    });

    test('and stops being searched, while the sets beside it do not', () async {
      final registry = SymbolRegistry(packs: [bundled()])
        ..setSetEnabled('stellar-symbols', false);

      expect(await registry.search('water'), isEmpty);
      expect(await registry.search('cat'), hasLength(1));
    });

    test('a set that never shipped a picture is still gated first', () async {
      // The manifest is loaded before the set is read. Asked the other way
      // round, every picture would draw on the launch that matters — a board
      // draws itself before anything has searched — and be gated on the next.
      final registry = SymbolRegistry(packs: [bundled()])
        ..setSetEnabled('stellar-symbols', false);

      expect(await registry.resolve(water), isNull);
    });

    test('and the fetching half of the same set goes with it', () async {
      final asked = <String>[];
      final fetcher = GlobalSymbolsPack(
        client: MockClient((request) async {
          asked.add(request.url.queryParameters['symbolset']!);
          return http.Response('[]', 200);
        }),
      );
      addTearDown(fetcher.dispose);

      final registry = SymbolRegistry(packs: [bundled(), fetcher])
        ..setSetEnabled('stellar-symbols', false);
      await registry.search('water');

      expect(await registry.resolve(water), isNull);
      expect(asked, isNot(contains('stellar-symbols')));
      expect(asked, contains('mulberry'));
    });
  });

  group('a picture already downloaded', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('wb-sets'));
    tearDown(() => temp.deleteSync(recursive: true));

    GlobalSymbolsPack serving() => GlobalSymbolsPack(
      documentsDirectory: () async => temp,
      client: MockClient((request) async {
        if (request.url.host == GlobalSymbolsPack.host) {
          return http.Response(
            request.url.queryParameters['symbolset'] == 'tawasol'
                ? labels([(text: 'drink', id: 7)])
                : '[]',
            200,
          );
        }
        return http.Response(
          utf8.decode(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>')),
          200,
        );
      }),
    );

    test(
      'stops drawing when its set is switched off, and comes back',
      () async {
        final pack = serving();
        addTearDown(pack.dispose);
        final registry = SymbolRegistry(packs: [pack]);

        final ref = (await registry.search('drink')).single;
        expect(await pack.fetchNow(ref), isTrue);
        expect(await registry.resolve(ref), isNotNull);

        registry.setSetEnabled('tawasol', false);
        expect(await registry.resolve(ref), isNull);

        registry.setSetEnabled('tawasol', true);
        expect(await registry.resolve(ref), isNotNull);
      },
    );

    test('and still does after the app is closed and opened', () async {
      // The API answers with a catalogue number and nothing else, so the only
      // record of which set drew a file that survives a relaunch is the
      // directory it was filed in. Without it a set switched off would blank
      // its pictures for one session and let them back the next.
      final first = serving();
      final ref = (await SymbolRegistry(packs: [first]).search('drink')).single;
      expect(await first.fetchNow(ref), isTrue);
      await first.dispose();

      final next = serving();
      addTearDown(next.dispose);
      final registry = SymbolRegistry(packs: [next])
        ..setSetEnabled('tawasol', false);

      expect(await registry.resolve(ref), isNull);

      registry.setSetEnabled('tawasol', true);
      expect(await registry.resolve(ref), isNotNull);
    });
  });

  test('the shipped manifest files nothing under an undeclared set', () async {
    // The switches are declared in code and the pictures are filed in the
    // manifest. A slug in one and not the other is either a switch that
    // governs nothing or a set nobody can turn off.
    final pack = bundledSymbolPacks().single;
    final decoded = json.decode(
      await rootBundle.loadString('assets/symbols/core/manifest.json'),
    ) as Map<String, dynamic>;

    final filed = {
      for (final entry in (decoded['symbols'] as Map).values)
        if (entry is Map && entry['set'] is String) entry['set'] as String,
    };

    expect(filed, pack.sets.map((s) => s.slug).toSet());
  });

  group('credit for every set a person can reach', () {
    /// Tall enough that every credit is built, because the list is lazy and a
    /// credit below the fold would pass for one that is not there.
    Future<void> pumpCredits(
      WidgetTester tester,
      SymbolRegistry registry, {
      String pass = 'first',
    }) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: SymbolCredits(
            // A new element each pass. The credits are read once per screen,
            // so reusing one would answer the second question with the first
            // answer.
            key: ValueKey(pass),
            registry: registry,
            manifests: const [],
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('the fetched sets are named, which they never were', (
      tester,
    ) async {
      final fetcher = GlobalSymbolsPack();
      addTearDown(fetcher.dispose);

      await pumpCredits(tester, SymbolRegistry(packs: [fetcher]));

      for (final set in GlobalSymbolsPack.commercialSets) {
        expect(find.text(set.name), findsOneWidget, reason: set.slug);
        expect(find.text(set.attribution), findsOneWidget, reason: set.slug);
      }
    });

    testWidgets('a set switched off is credited all the same', (tester) async {
      // It draws nothing today, which is an argument for leaving it out and
      // the wrong one: it is still in the app, one switch away, and the
      // licenses ask for credit for what shipped rather than for whatever is
      // switched on this afternoon. A credit that depends on a setting is a
      // credit somebody can turn off.
      final fetcher = GlobalSymbolsPack();
      addTearDown(fetcher.dispose);
      final registry = SymbolRegistry(packs: [fetcher])
        ..setSetEnabled('tawasol', false);

      await pumpCredits(tester, registry);

      expect(find.text(tawasolSet.name), findsOneWidget);
      expect(find.text(tawasolSet.attribution), findsOneWidget);
      expect(find.text(mulberrySet.name), findsOneWidget);
    });

    testWidgets('and a noncommercial set, which ships off', (tester) async {
      // Off by default and credited anyway. The credit says whose drawings
      // this app can reach, and ARASAAC's is the one the license is most
      // specific about.
      final arasaac = ArasaacPack();
      addTearDown(arasaac.dispose);
      final registry = SymbolRegistry(packs: [arasaac]);

      expect(
        registry.isSetEnabled('arasaac'),
        isFalse,
        reason: 'the premise: noncommercial sets ship switched off',
      );

      await pumpCredits(tester, registry);
      expect(find.text(ArasaacPack.set.name), findsOneWidget);
      expect(find.textContaining('Sergio Palao'), findsOneWidget);
    });
  });
}

/// An asset bundle holding exactly what a test put in it.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) throw FlutterError('missing asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}
