import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/symbols/arasaac_pack.dart';
import 'package:wordbridge/features/symbols/bundled_pack.dart';
import 'package:wordbridge/features/symbols/custom_upload.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';

void main() {
  // rootBundle needs a binding; the bundled-pack degradation test uses it.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('license gate', () {
    test('a non-commercial pack is not searched until it is enabled', () async {
      final arasaac = _FakePack(
        id: 'arasaac',
        allowsCommercialUse: false,
        isBundled: false,
        refs: [(packId: 'arasaac', externalId: '1', label: 'water')],
      );
      final registry = SymbolRegistry(packs: [arasaac]);

      expect(registry.isEnabled('arasaac'), isFalse);
      expect(await registry.search('water'), isEmpty);
      expect(
        arasaac.searchCount,
        0,
        reason: 'a CC BY-NC pack must not be queried before the user opts in',
      );

      registry.setEnabled('arasaac', true);

      expect(await registry.search('water'), hasLength(1));
      expect(arasaac.searchCount, 1);
    });

    test('a non-commercial pack is not resolved until it is enabled', () async {
      final arasaac = _FakePack(
        id: 'arasaac',
        allowsCommercialUse: false,
        isBundled: false,
        uri: '/documents/symbols/arasaac/1.png',
      );
      final registry = SymbolRegistry(packs: [arasaac]);
      const ref = (packId: 'arasaac', externalId: '1', label: 'water');

      expect(await registry.resolve(ref), isNull);
      expect(arasaac.resolveCount, 0);

      registry.setEnabled('arasaac', true);

      expect(await registry.resolve(ref), '/documents/symbols/arasaac/1.png');
    });

    test('opting out again stops images already on disk resolving', () async {
      final arasaac = _FakePack(
        id: 'arasaac',
        allowsCommercialUse: false,
        isBundled: false,
        uri: '/documents/symbols/arasaac/1.png',
      );
      final registry = SymbolRegistry(
        packs: [arasaac],
        choices: {'arasaac': true},
      );
      const ref = (packId: 'arasaac', externalId: '1', label: 'water');

      expect(await registry.resolve(ref), isNotNull);

      registry.setEnabled('arasaac', false);
      expect(await registry.resolve(ref), isNull);
    });

    test('packs permitting commercial use are on by default', () {
      final registry = SymbolRegistry(packs: bundledSymbolPacks());
      for (final pack in registry.packs) {
        expect(registry.isEnabled(pack.id), isTrue, reason: pack.id);
      }
    });

    test('choices round-trip for persistence', () {
      final packs = [
        _FakePack(id: 'mulberry'),
        _FakePack(id: 'arasaac', allowsCommercialUse: false, isBundled: false),
      ];
      final registry = SymbolRegistry(packs: packs)
        ..setEnabled('arasaac', true);

      final restored = SymbolRegistry(packs: packs, choices: registry.choices);
      expect(restored.isEnabled('arasaac'), isTrue);
    });

    test('an unknown pack cannot be enabled into existence', () {
      final registry = SymbolRegistry()..setEnabled('sclera', true);
      expect(registry.isEnabled('sclera'), isFalse);
      expect(registry.choices, isEmpty);
    });
  });

  group('combined search', () {
    test('offers bundled packs before downloadable ones', () async {
      final registry = SymbolRegistry(
        packs: [
          _FakePack(
            id: 'arasaac',
            allowsCommercialUse: false,
            isBundled: false,
            refs: [(packId: 'arasaac', externalId: '1', label: 'water')],
          ),
          _FakePack(
            id: 'mulberry',
            refs: [
              (packId: 'mulberry', externalId: 'water.png', label: 'water'),
            ],
          ),
        ],
        choices: {'arasaac': true},
      );

      expect(registry.enabledPacks.map((p) => p.id), ['mulberry', 'arasaac']);
      expect(
        (await registry.search('water')).first.packId,
        'mulberry',
        reason: 'a license-clean local image should win over a download',
      );
    });

    test('one broken pack does not empty the drawer', () async {
      final registry = SymbolRegistry(
        packs: [
          _FakePack(id: 'broken', throws: true),
          _FakePack(
            id: 'mulberry',
            refs: [
              (packId: 'mulberry', externalId: 'water.png', label: 'water'),
            ],
          ),
        ],
      );

      expect(await registry.search('water'), hasLength(1));
    });

    test('a hanging pack does not hold up the others', () async {
      final registry = SymbolRegistry(
        packs: [
          _FakePack(id: 'slow', hangs: true),
          _FakePack(
            id: 'mulberry',
            refs: [
              (packId: 'mulberry', externalId: 'water.png', label: 'water'),
            ],
          ),
        ],
        searchBudget: const Duration(milliseconds: 20),
      );

      expect(await registry.search('water'), hasLength(1));
    });

    test('an empty query asks no pack anything', () async {
      final pack = _FakePack(id: 'mulberry');
      final registry = SymbolRegistry(packs: [pack]);

      expect(await registry.search('   '), isEmpty);
      expect(pack.searchCount, 0);
    });

    test('the same symbol from one pack is not offered twice', () async {
      const ref = (packId: 'mulberry', externalId: 'water.png', label: 'water');
      final registry = SymbolRegistry(
        packs: [
          _FakePack(id: 'mulberry', refs: const [ref, ref]),
        ],
      );

      expect(await registry.search('water'), hasLength(1));
    });
  });

  group('resolver', () {
    test('yields a label, not an exception, when nothing resolves', () async {
      final registry = SymbolRegistry(packs: [_FakePack(id: 'mulberry')]);
      final resolver = SymbolResolver(registry: registry);
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolve((
        packId: 'mulberry',
        externalId: 'missing.png',
        label: 'water',
      ));

      expect(resolved.image, isNull);
      expect(resolved.label, 'water');
    });

    test('a throwing pack yields a label', () async {
      final registry = SymbolRegistry(
        packs: [_FakePack(id: 'broken', throws: true)],
      );
      final resolver = SymbolResolver(registry: registry);
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolve((
        packId: 'broken',
        externalId: '1',
        label: 'help',
      ));
      expect(resolved.image, isNull);
    });

    test('an unknown pack yields a label', () async {
      final resolver = SymbolResolver(registry: SymbolRegistry());
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolve((
        packId: 'sclera',
        externalId: '1',
        label: 'toilet',
      ));
      expect(resolved.image, isNull);
      expect(resolved.label, 'toilet');
    });

    test('a hanging pack yields a label within the budget', () async {
      final registry = SymbolRegistry(
        packs: [_FakePack(id: 'slow', hangs: true)],
      );
      final resolver = SymbolResolver(
        registry: registry,
        budget: const Duration(milliseconds: 20),
      );
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolve((
        packId: 'slow',
        externalId: '1',
        label: 'more',
      ));
      expect(resolved.image, isNull);
    });

    test('a hanging pack yields a label by word too', () async {
      // The same ceiling, reached the other way in: a button with no symbol of
      // its own asks by word, and without a bound there it sits at "still
      // looking" until the app is restarted.
      final registry = SymbolRegistry(
        packs: [_FakePack(id: 'slow', hangs: true)],
      );
      final resolver = SymbolResolver(
        registry: registry,
        budget: const Duration(milliseconds: 20),
      );
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolveLabel('more', const ['slow']);

      expect(resolved.image, isNull);
      expect(resolved.label, 'more');
    });

    test('a bundled hit is an asset key, a downloaded one is a file', () async {
      final registry = SymbolRegistry(
        packs: [
          _FakePack(id: 'mulberry', uri: 'assets/symbols/mulberry/water.png'),
          _FakePack(
            id: 'arasaac',
            allowsCommercialUse: false,
            isBundled: false,
            uri: '/documents/symbols/arasaac/1.png',
          ),
        ],
        choices: {'arasaac': true},
      );
      final resolver = SymbolResolver(registry: registry);
      addTearDown(resolver.dispose);

      final bundled = await resolver.resolve((
        packId: 'mulberry',
        externalId: 'water.png',
        label: 'water',
      ));
      expect(bundled.image?.kind, SymbolImageKind.asset);

      final downloaded = await resolver.resolve((
        packId: 'arasaac',
        externalId: '1',
        label: 'water',
      ));
      expect(downloaded.image?.kind, SymbolImageKind.file);
    });

    test('candidate order puts bundled packs first', () {
      final registry = SymbolRegistry(
        packs: [
          _FakePack(
            id: 'arasaac',
            allowsCommercialUse: false,
            isBundled: false,
          ),
          _FakePack(id: 'mulberry'),
        ],
      );
      final resolver = SymbolResolver(registry: registry);
      addTearDown(resolver.dispose);

      const candidates = [
        (packId: 'arasaac', externalId: '1', label: 'water'),
        (packId: 'unknown', externalId: '2', label: 'water'),
        (packId: 'mulberry', externalId: 'water.png', label: 'water'),
      ];

      expect(resolver.orderCandidates(candidates).map((r) => r.packId), [
        'mulberry',
        'arasaac',
        'unknown',
      ]);
    });

    test('resolveFirst prefers the bundled candidate', () async {
      final registry = SymbolRegistry(
        packs: [
          _FakePack(
            id: 'arasaac',
            allowsCommercialUse: false,
            isBundled: false,
            uri: '/documents/symbols/arasaac/1.png',
          ),
          _FakePack(id: 'mulberry', uri: 'assets/symbols/mulberry/water.png'),
        ],
        choices: {'arasaac': true},
      );
      final resolver = SymbolResolver(registry: registry);
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolveFirst(const [
        (packId: 'arasaac', externalId: '1', label: 'water'),
        (packId: 'mulberry', externalId: 'water.png', label: 'water'),
      ]);

      expect(resolved.image?.uri, 'assets/symbols/mulberry/water.png');
    });

    test('resolveFirst falls through to a label', () async {
      final registry = SymbolRegistry(packs: [_FakePack(id: 'mulberry')]);
      final resolver = SymbolResolver(registry: registry);
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolveFirst(const [
        (packId: 'mulberry', externalId: 'x.png', label: 'water'),
      ], label: 'water');
      expect(resolved.image, isNull);
      expect(resolved.label, 'water');
    });

    test('a miss is not cached, so a later download can win', () async {
      final pack = _FakePack(id: 'mulberry');
      final registry = SymbolRegistry(packs: [pack]);
      final resolver = SymbolResolver(registry: registry);
      addTearDown(resolver.dispose);

      const ref = (packId: 'mulberry', externalId: 'water.png', label: 'water');
      await resolver.resolve(ref);
      expect(resolver.cached(ref), isNull);

      pack.uri = 'assets/symbols/mulberry/water.png';
      expect((await resolver.resolve(ref)).image, isNotNull);
      expect(resolver.cached(ref), isNotNull);
    });

    test(
      'a landed download invalidates the label and announces itself',
      () async {
        final pack = _FakeDownloadPack(id: 'arasaac');
        final registry = SymbolRegistry(
          packs: [pack],
          choices: {'arasaac': true},
        );
        final resolver = SymbolResolver(registry: registry);
        addTearDown(() async {
          await resolver.dispose();
          await pack.dispose();
        });

        const ref = (packId: 'arasaac', externalId: '1', label: 'water');
        pack.uri = '/documents/symbols/arasaac/1.png';
        expect((await resolver.resolve(ref)).image, isNotNull);

        final announced = resolver.ready.first;
        pack.announce(ref);

        expect(await announced, ref);
        expect(
          resolver.cached(ref),
          isNull,
          reason: 'a fresh download must not be masked by a stale answer',
        );
      },
    );
  });

  group('bundled pack', () {
    test('degrades to empty when no manifest has been dropped in', () async {
      final pack = BundledSymbolPack(
        id: 'mulberry',
        name: 'Mulberry Symbols',
        license: 'CC-BY-SA',
        attribution: 'Mulberry Symbols.',
      );

      expect(await pack.manifest(), isEmpty);
      expect(await pack.search('water'), isEmpty);
      expect(
        await pack.resolve((
          packId: 'mulberry',
          externalId: 'water.png',
          label: 'water',
        )),
        isNull,
      );
    });

    test('degrades to empty on a malformed manifest', () async {
      final pack = _bundledWith({
        'assets/symbols/mulberry/manifest.json': '{oh no',
      });
      expect(await pack.search('water'), isEmpty);
    });

    test('ignores manifest entries that are not keyword to filename', () async {
      final pack = _bundledWith({
        'assets/symbols/mulberry/manifest.json': json.encode({
          'water': 'water.png',
          'more': ['more.png'],
          'help': 3,
        }),
        'assets/symbols/mulberry/water.png': 'png',
      });

      expect(await pack.manifest(), {'water': 'water.png'});
    });

    test('finds a symbol once a manifest and its images are present', () async {
      final pack = _bundledWith({
        'assets/symbols/mulberry/manifest.json': json.encode({
          'watering can': 'watering-can.png',
          'water': 'water.png',
          'underwater': 'underwater.png',
        }),
        'assets/symbols/mulberry/water.png': 'png',
      });

      final hits = await pack.search('water');
      expect(hits.map((r) => r.label), [
        'water',
        'watering can',
        'underwater',
      ], reason: 'exact before prefix before substring');

      expect(
        await pack.resolve(hits.first),
        'assets/symbols/mulberry/water.png',
      );
    });

    test(
      'a manifest naming a file the build did not ship resolves to null',
      () async {
        final pack = _bundledWith({
          'assets/symbols/mulberry/manifest.json': json.encode({
            'water': 'water.png',
          }),
        });

        final hits = await pack.search('water');
        expect(hits, hasLength(1));
        expect(
          await pack.resolve(hits.first),
          isNull,
          reason: 'a missing image must become a label, never a broken image',
        );
      },
    );

    test('refuses a ref belonging to another pack', () async {
      final pack = _bundledWith({
        'assets/symbols/mulberry/manifest.json': json.encode({
          'water': 'water.png',
        }),
        'assets/symbols/mulberry/water.png': 'png',
      });

      expect(
        await pack.resolve((
          packId: 'twemoji',
          externalId: 'water.png',
          label: 'water',
        )),
        isNull,
      );
    });
  });

  group('pack metadata', () {
    List<SymbolPack> everyPack() {
      final arasaac = ArasaacPack();
      addTearDown(arasaac.dispose);
      return [...bundledSymbolPacks(), arasaac];
    }

    test('every pack carries license and attribution', () {
      for (final pack in everyPack()) {
        expect(pack.id.trim(), isNotEmpty);
        expect(pack.name.trim(), isNotEmpty, reason: pack.id);
        expect(pack.license.trim(), isNotEmpty, reason: pack.id);
        expect(
          pack.attribution.trim(),
          isNotEmpty,
          reason: 'every license in use requires credit reachable in-app',
        );
      }
    });

    test('pack ids are unique', () {
      final ids = everyPack().map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every bundled pack actually ships images', () async {
      // A pack with no assets is not a pack. Four once sat in this list with
      // no asset directory: every search against them returned nothing, and
      // the credits screen implied the app carried symbol sets it did not.
      for (final pack in bundledSymbolPacks()) {
        final hits = <SymbolRef>[];
        for (final word in ['water', 'happy', 'go', 'more', 'help']) {
          hits.addAll(await pack.search(word));
        }
        expect(
          hits,
          isNotEmpty,
          reason:
              '${pack.id} is offered to caregivers and answers nothing, for '
              'any word',
        );
      }
    });

    test('the sets core is assembled from are still credited', () async {
      // Dropping those four as packs must not drop their credit: the licenses
      // require it wherever the work appears, and the work still appears.
      final raw = await rootBundle.loadString(
        'assets/symbols/core/manifest.json',
      );
      final attributions =
          (json.decode(raw) as Map)['attributions'] as Map<String, dynamic>;

      final used = {
        for (final entry
            in ((json.decode(raw) as Map)['symbols'] as Map).values)
          (entry as Map)['set'] as String?,
      }..remove(null);

      expect(used, isNotEmpty);
      for (final set in used) {
        expect(
          attributions[set],
          isNotNull,
          reason: 'core draws on "$set" and credits it nowhere',
        );
      }
    });

    test('every bundled pack permits commercial use', () {
      for (final pack in bundledSymbolPacks()) {
        expect(
          pack.allowsCommercialUse,
          isTrue,
          reason: '${pack.id} may not ship inside the app',
        );
        expect(pack.isBundled, isTrue);
      }
    });

    test('ARASAAC is non-commercial and never bundled', () {
      final pack = ArasaacPack();
      addTearDown(pack.dispose);
      expect(pack.allowsCommercialUse, isFalse);
      expect(pack.isBundled, isFalse);
      expect(pack.license, contains('NC'));
    });

    test('ARASAAC carries the credit its license demands', () {
      final pack = ArasaacPack();
      addTearDown(pack.dispose);
      final attribution = pack.attribution;
      for (final fragment in const [
        'Sergio Palao',
        'ARASAAC',
        'https://arasaac.org',
        'CC (BY-NC-SA)',
        'Government of Aragón (Spain)',
      ]) {
        expect(attribution, contains(fragment));
      }
    });
  });

  group('ARASAAC urls', () {
    test('search and bestsearch', () {
      expect(
        ArasaacPack.searchUri('water').toString(),
        'https://api.arasaac.org/api/pictograms/en/search/water',
      );
      expect(
        ArasaacPack.searchUri('water', best: true).toString(),
        'https://api.arasaac.org/api/pictograms/en/bestsearch/water',
      );
    });

    test('a full locale tag is reduced to the language the API keys on', () {
      expect(ArasaacPack.apiLocale('en-US'), 'en');
      expect(ArasaacPack.apiLocale('ar_QA'), 'ar');
      expect(ArasaacPack.apiLocale('ES'), 'es');
      expect(ArasaacPack.apiLocale(''), 'en');
      expect(
        ArasaacPack.searchUri('agua', locale: 'es-ES').toString(),
        'https://api.arasaac.org/api/pictograms/es/search/agua',
      );
    });

    test('a multi-word query stays one path segment', () {
      expect(
        ArasaacPack.searchUri('watering can').toString(),
        'https://api.arasaac.org/api/pictograms/en/search/watering%20can',
      );
      expect(
        ArasaacPack.searchUri('and/or').toString(),
        'https://api.arasaac.org/api/pictograms/en/search/and%20or',
      );
    });

    test('images are requested at a resolution the CDN actually serves', () {
      expect(ArasaacPack.availableResolutions, {300, 500, 2500});
      expect(
        ArasaacPack.availableResolutions,
        contains(ArasaacPack.imageResolution),
      );
      expect(
        ArasaacPack.imageUri('2248').toString(),
        'https://static.arasaac.org/pictograms/2248/2248_500.png',
      );
    });
  });

  group('ARASAAC behavior', () {
    late Directory documents;

    setUp(() async {
      documents = await Directory.systemTemp.createTemp('wordbridge-arasaac');
    });

    tearDown(() async => documents.delete(recursive: true));

    ArasaacPack packWith(MockClient client) =>
        ArasaacPack(client: client, documentsDirectory: () async => documents);

    test('parses pictogram records into refs', () async {
      final pack = packWith(
        MockClient(
          (_) async => http.Response(
            json.encode([
              {
                '_id': 2248,
                'keywords': [
                  {'keyword': 'liquid'},
                  {'keyword': 'water'},
                ],
              },
            ]),
            200,
          ),
        ),
      );
      addTearDown(pack.dispose);

      final refs = await pack.search('water');
      expect(refs, hasLength(1));
      expect(refs.single.externalId, '2248');
      expect(
        refs.single.label,
        'water',
        reason: 'the keyword the user typed, not merely the first synonym',
      );
    });

    test('falls back to the broad search when bestsearch is empty', () async {
      final asked = <String>[];
      final pack = packWith(
        MockClient((request) async {
          asked.add(request.url.path);
          if (request.url.path.contains('/bestsearch/')) {
            return http.Response('[]', 200);
          }
          return http.Response(
            json.encode([
              {
                '_id': 7,
                'keywords': [
                  {'keyword': 'water'},
                ],
              },
            ]),
            200,
          );
        }),
      );
      addTearDown(pack.dispose);

      expect(await pack.search('water'), hasLength(1));
      expect(asked, hasLength(2));
    });

    test('a failing search returns nothing rather than throwing', () async {
      final pack = packWith(
        MockClient((_) async => throw const SocketException('offline')),
      );
      addTearDown(pack.dispose);

      expect(await pack.search('water'), isEmpty);
    });

    test('a 500 and malformed json both return nothing', () async {
      final broken = packWith(
        MockClient((_) async => http.Response('nope', 500)),
      );
      addTearDown(broken.dispose);
      expect(await broken.search('water'), isEmpty);

      final garbled = packWith(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      addTearDown(garbled.dispose);
      expect(await garbled.search('water'), isEmpty);
    });

    test('resolve returns nothing now and the file afterwards', () async {
      final pack = packWith(
        MockClient((_) async => http.Response.bytes(_pngBytes(), 200)),
      );
      addTearDown(pack.dispose);

      const ref = (packId: 'arasaac', externalId: '2248', label: 'water');
      final announced = pack.available.first;

      expect(
        await pack.resolve(ref),
        isNull,
        reason: 'a button must not wait on a download to become pressable',
      );
      expect(await announced, ref);

      final path = await pack.resolve(ref);
      expect(path, endsWith('symbols/arasaac/2248.png'));
      expect(File(path!).existsSync(), isTrue);
      expect(
        File('$path.part').existsSync(),
        isFalse,
        reason: 'the partial write must be renamed, not left behind',
      );
    });

    test('downloads land in documents, never in a cache directory', () async {
      final pack = packWith(
        MockClient((_) async => http.Response.bytes(_pngBytes(), 200)),
      );
      addTearDown(pack.dispose);

      const ref = (packId: 'arasaac', externalId: '2248', label: 'water');
      // Waited on rather than pumped for. `available` is the pack saying the
      // file has landed; a fixed number of turns of the event queue is a guess
      // about how fast the machine is, and it was wrong on a slower one.
      final announced = pack.available.first;
      await pack.resolve(ref);
      await announced;

      expect(
        (await pack.resolve(ref))!.startsWith(documents.path),
        isTrue,
        reason: 'the OS evicts caches; a lost symbol is a lost voice',
      );
    });

    test('one request per symbol, no retry storm after a failure', () async {
      var requests = 0;
      final pack = packWith(
        MockClient((_) async {
          requests++;
          return http.Response('missing', 404);
        }),
      );
      addTearDown(pack.dispose);

      const ref = (packId: 'arasaac', externalId: '2248', label: 'water');
      for (var attempt = 0; attempt < 5; attempt++) {
        expect(await pack.resolve(ref), isNull);
        await pumpEventQueue(times: 100);
      }

      expect(requests, 1);

      pack.clearFailures();
      expect(await pack.resolve(ref), isNull);
      await pumpEventQueue(times: 100);
      expect(requests, 2);
    });

    test('an empty body is not written to disk', () async {
      final pack = packWith(
        MockClient((_) async => http.Response.bytes(const [], 200)),
      );
      addTearDown(pack.dispose);

      const ref = (packId: 'arasaac', externalId: '2248', label: 'water');
      await pack.resolve(ref);
      await pumpEventQueue(times: 100);

      expect(await pack.resolve(ref), isNull);
    });

    test('refuses a ref belonging to another pack', () async {
      final pack = packWith(MockClient((_) async => http.Response('', 200)));
      addTearDown(pack.dispose);

      expect(
        await pack.resolve((
          packId: 'mulberry',
          externalId: '2248',
          label: 'water',
        )),
        isNull,
      );
    });
  });

  group('custom uploads', () {
    late WordbridgeDatabase db;
    late Directory documents;
    late CustomSymbolImporter importer;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      documents = await Directory.systemTemp.createTemp('wordbridge-custom');
      importer = CustomSymbolImporter(
        db: db,
        documentsDirectory: () async => documents,
      );
    });

    tearDown(() async {
      await db.close();
      await documents.delete(recursive: true);
    });

    test(
      'the fixture really does carry EXIF, or this group proves nothing',
      () {
        final decoded = img.decodeJpg(_photoWithExif())!;
        expect(decoded.hasExif, isTrue);
        expect(decoded.exif.imageIfd['Make']?.toData(), isNotNull);
      },
    );

    test('EXIF is stripped', () {
      final normalized = normalizeSymbolImage(_photoWithExif())!;
      final stored = img.decodePng(normalized.bytes)!;

      expect(
        stored.hasExif,
        isFalse,
        reason: 'EXIF on a photo of a child carries the GPS fix of their home',
      );
      expect(stored.exif.isEmpty, isTrue);
    });

    test('the longest edge is clamped and small images are left alone', () {
      final large = normalizeSymbolImage(_photoWithExif())!;
      expect(large.width, customSymbolMaxEdge);
      expect(large.height, lessThan(customSymbolMaxEdge));

      final small = normalizeSymbolImage(_solidImage(64, 48))!;
      expect(small.width, 64);
      expect(small.height, 48);
    });

    test('undecodable bytes yield null rather than an exception', () {
      expect(normalizeSymbolImage(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test(
      'an import is recorded as user-owned and written to documents',
      () async {
        final symbol = await importer.store(_photoWithExif(), label: 'my cup');

        expect(symbol, isNotNull);
        expect(symbol!.source, SymbolSource.custom);
        expect(symbol.license, 'user-owned');
        expect(symbol.packId, isNull);
        expect(symbol.contentHash, isNotNull);
        expect(symbol.width, customSymbolMaxEdge);
        expect(symbol.localUri, startsWith(documents.path));
        expect(File(symbol.localUri!).existsSync(), isTrue);
      },
    );

    test('the same photo imported twice is one symbol', () async {
      final first = await importer.store(_photoWithExif(), label: 'my cup');
      final second = await importer.store(_photoWithExif(), label: 'my cup');

      expect(second!.id, first!.id);
      expect(await db.select(db.symbols).get(), hasLength(1));
    });

    test('one photo can carry two labels without being stored twice', () async {
      final nana = await importer.store(_photoWithExif(), label: 'Nana');
      final grandma = await importer.store(_photoWithExif(), label: 'grandma');

      expect(grandma!.id, isNot(nana!.id));
      expect(grandma.localUri, nana.localUri);
      expect(
        Directory(p.join(documents.path, 'symbols', 'custom')).listSync(),
        hasLength(1),
      );
    });

    test('an undecodable import records nothing', () async {
      expect(
        await importer.store(Uint8List.fromList([1, 2, 3]), label: 'broken'),
        isNull,
      );
      expect(await db.select(db.symbols).get(), isEmpty);
    });
  });
}

BundledSymbolPack _bundledWith(Map<String, String> assets) => BundledSymbolPack(
  id: 'mulberry',
  name: 'Mulberry Symbols',
  license: 'CC-BY-SA',
  attribution: 'Mulberry Symbols.',
  bundle: _FakeAssetBundle({
    for (final entry in assets.entries) entry.key: utf8.encode(entry.value),
  }),
);

Uint8List _pngBytes() => img.encodePng(_solidImageRaw(4, 4));

img.Image _solidImageRaw(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 160, 200));
  return image;
}

Uint8List _solidImage(int width, int height) =>
    img.encodePng(_solidImageRaw(width, height));

/// A JPEG carrying the kind of metadata a phone camera attaches: a maker tag
/// and a GPS fix.
Uint8List _photoWithExif() {
  final image = _solidImageRaw(900, 600);
  image.exif.imageIfd['Make'] = 'wordbridge-test';
  image.exif.gpsIfd[0x0002] = img.IfdValueRational(51, 1);
  return img.encodeJpg(image);
}

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.assets);

  final Map<String, List<int>> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw FlutterError('no asset at $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _FakePack implements SymbolPack {
  _FakePack({
    required this.id,
    this.allowsCommercialUse = true,
    this.isBundled = true,
    this.refs = const [],
    this.uri,
    this.throws = false,
    this.hangs = false,
  });

  @override
  final String id;

  @override
  String get name => id;

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => '$id attribution';

  @override
  final bool allowsCommercialUse;

  @override
  final bool isBundled;

  final List<SymbolRef> refs;
  String? uri;
  final bool throws;
  final bool hangs;

  int searchCount = 0;
  int resolveCount = 0;

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) {
    searchCount++;
    if (hangs) return Completer<List<SymbolRef>>().future;
    if (throws) throw StateError('$id is broken');
    return Future.value(refs);
  }

  @override
  Future<String?> resolve(SymbolRef ref) {
    resolveCount++;
    if (hangs) return Completer<String?>().future;
    if (throws) throw StateError('$id is broken');
    return Future.value(uri);
  }
}

class _FakeDownloadPack implements DownloadingSymbolPack {
  _FakeDownloadPack({required this.id});

  @override
  final String id;

  @override
  String get name => id;

  @override
  String get license => 'CC-BY-NC-SA';

  @override
  String get attribution => '$id attribution';

  @override
  bool get allowsCommercialUse => false;

  @override
  bool get isBundled => false;

  String? uri;

  final _controller = StreamController<SymbolRef>.broadcast();

  @override
  Stream<SymbolRef> get available => _controller.stream;

  void announce(SymbolRef ref) => _controller.add(ref);

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async => const [];

  @override
  Future<String?> resolve(SymbolRef ref) async => uri;

  @override
  Future<void> dispose() => _controller.close();
}
