import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';

/// A pack that answers a search with however many results it is told to.
class _Countable implements SymbolPack {
  _Countable(this.id, this.available, {this.isBundled = false});

  @override
  final String id;

  /// How many results this pack has for anything.
  final int available;

  @override
  final bool isBundled;

  @override
  String get name => id;
  @override
  String get license => 'CC-BY-SA-4.0';
  @override
  String get attribution => id;
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
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    Set<String>? sets,
  }) async => [
    for (var i = 0; i < available && i < limit; i++)
      (packId: id, externalId: '$i', label: '$id $i'),
  ];

  @override
  Future<String?> resolve(SymbolRef ref, {Set<String>? sets}) async => null;
}

/// Whether a set a person can see listed is a set they can find anything in.
///
/// Both merges — packs in the registry, sets inside the fetching pack — used
/// to concatenate their sources and stop at the budget. That makes preference
/// order decide not who is first but who is present, and the sources at the
/// back are unreachable on exactly the common words a person is most likely to
/// search for. The set is offered on a filter chip, has pictures for the word,
/// and appears to have none.
void main() {
  group('one source cannot empty the budget', () {
    test('a generous pack does not silence the ones after it', () async {
      // The shape that hid Global Symbols behind the device's emoji index:
      // the emoji search matches broadly and fills any budget by itself.
      final registry = SymbolRegistry(
        packs: [
          _Countable('emoji', 500, isBundled: true),
          _Countable('globalsymbols', 40),
        ],
      );

      final results = await registry.search('go', limit: 60);

      expect(results, hasLength(60));
      expect(
        results.where((r) => r.packId == 'globalsymbols'),
        isNotEmpty,
        reason:
            'the sets a caregiver came to the picker for contributed nothing, '
            'and read as sets with no picture for the word',
      );
      expect(
        results.first.packId,
        'emoji',
        reason: 'preference order still decides who is first',
      );
    });

    test('a source with less than its share does not hold a slot', () async {
      final registry = SymbolRegistry(
        packs: [_Countable('small', 2), _Countable('large', 100)],
      );

      final results = await registry.search('go', limit: 20);

      expect(results, hasLength(20));
      expect(results.where((r) => r.packId == 'small'), hasLength(2));
      expect(results.where((r) => r.packId == 'large'), hasLength(18));
    });

    test('the same symbol from two sources is listed once', () {
      const shared = (packId: 'a', externalId: '1', label: 'drink');
      final merged = fairMerge([
        [shared],
        [shared, (packId: 'b', externalId: '2', label: 'drink')],
      ], 10);

      expect(merged, hasLength(2));
    });
  });

  group('every set is asked', () {
    /// Records which sets were asked for what, and answers with [per] results
    /// for each.
    ({GlobalSymbolsPack pack, List<Uri> asked}) packAnswering(int per) {
      final asked = <Uri>[];
      final pack = GlobalSymbolsPack(
        client: MockClient((request) async {
          asked.add(request.url);
          final set = request.url.queryParameters['symbolset'];
          return http.Response(
            jsonEncode([
              for (var i = 0; i < per; i++)
                {
                  'text': '$set $i',
                  'picto': {
                    'id': '$set$i'.hashCode.abs(),
                    'image_url': 'https://example.test/$set-$i.svg',
                    'native_format': 'svg',
                  },
                },
            ]),
            200,
          );
        }),
      );
      return (pack: pack, asked: asked);
    }

    test('a set at the back of the list still answers', () async {
      final probe = packAnswering(30);
      addTearDown(probe.pack.dispose);

      final results = await probe.pack.search('go', limit: 60);

      expect(
        probe.asked.map((u) => u.queryParameters['symbolset']),
        containsAll(GlobalSymbolsPack.commercialSets.map((s) => s.slug)),
        reason:
            'the sets were walked in order until the budget ran out, so the '
            'ones at the back were never asked on a word the front had plenty '
            'of',
      );

      // Six sets of thirty, into a budget of sixty: every set represented.
      expect(results, hasLength(60));
      for (final set in GlobalSymbolsPack.commercialSets) {
        expect(
          results.where((r) => r.label.startsWith('${set.slug} ')),
          isNotEmpty,
          reason: '${set.slug} contributed nothing',
        );
      }
    });

    test('a set is asked for as much as the caller wants', () async {
      final probe = packAnswering(1);
      addTearDown(probe.pack.dispose);

      await probe.pack.search('go', limit: 60);

      for (final uri in probe.asked) {
        expect(
          int.parse(uri.queryParameters['limit']!),
          60,
          reason:
              'a fixed dozen was sent whatever was asked for, so a set with '
              'forty pictures of a word offered twelve',
        );
      }
    });

    test('no set is asked for more than its ceiling', () async {
      final probe = packAnswering(1);
      addTearDown(probe.pack.dispose);

      await probe.pack.search('go', limit: 500);

      for (final uri in probe.asked) {
        expect(
          int.parse(uri.queryParameters['limit']!),
          GlobalSymbolsPack.maxSetResults,
        );
      }
    });
  });
}
