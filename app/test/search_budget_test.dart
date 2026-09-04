import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';

/// Whether a slow catalog costs one set or the whole pack.
///
/// Every set is asked at once and `Future.wait` waits for the slowest, so one
/// set that hangs held the pack for its full request timeout. That timeout was
/// six seconds and the registry's budget was five, which meant the registry
/// cancelled the pack before it could ever answer — and `_searchOne` catches a
/// budget overrun and returns an empty list, so the picker showed the fetching
/// sets as having nothing for the word rather than as not having been waited
/// for. The sets a caregiver came for were unreachable and nothing said so.
void main() {
  /// A pack whose `slow` set never answers and whose others answer at once.
  GlobalSymbolsPack packWithAHangingSet({required String slow}) =>
      GlobalSymbolsPack(
        searchTimeout: const Duration(milliseconds: 200),
        client: MockClient((request) async {
          if (request.url.queryParameters['symbolset'] == slow) {
            await Future<void>.delayed(const Duration(seconds: 30));
          }
          return http.Response(
            jsonEncode([
              {
                'text': 'drink',
                'picto': {
                  'id': request.url.queryParameters['symbolset'].hashCode.abs(),
                  'image_url': 'https://example.test/a.svg',
                  'native_format': 'svg',
                },
              },
            ]),
            200,
          );
        }),
      );

  test('a set that hangs costs only itself', () async {
    final pack = packWithAHangingSet(slow: 'mulberry');
    addTearDown(pack.dispose);

    final results = await pack.search('drink', limit: 60);

    expect(
      results,
      hasLength(GlobalSymbolsPack.commercialSets.length - 1),
      reason: 'one slow set took the whole pack down with it',
    );
  });

  test('and the pack answers well inside the registry budget', () async {
    // The numbers, not just the behaviour: the inner bound has to be the one
    // that fires. Equal or larger and the registry cancels work that arrived.
    final pack = GlobalSymbolsPack();
    addTearDown(pack.dispose);
    final registry = SymbolRegistry(packs: [pack]);

    expect(
      pack.searchTimeout,
      lessThan(registry.searchBudget),
      reason:
          'the pack may not allow itself longer than the registry allows it, '
          'or a late result is thrown away and read as an empty catalog',
    );
  });

  test('a hanging set does not stop the registry hearing the rest', () async {
    final pack = packWithAHangingSet(slow: 'openmoji');
    addTearDown(pack.dispose);
    final registry = SymbolRegistry(
      packs: [pack],
      searchBudget: const Duration(seconds: 5),
    );

    final results = await registry.search('drink', limit: 60);

    expect(
      results,
      isNotEmpty,
      reason: 'the registry reported an empty catalog for a pack that answered',
    );
  });
}
