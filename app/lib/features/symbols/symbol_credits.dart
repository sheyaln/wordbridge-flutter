import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Credits for the symbols on the buttons.
///
/// Not a nicety. Every bundled pack is CC BY-SA or CC BY, and all of those
/// require attribution wherever the work appears — so this screen is part of
/// what makes shipping the symbols lawful, and it has to stay reachable
/// without a network connection or an account.
///
/// Credits are read from each pack's own manifest rather than hardcoded here,
/// because a pack assembled from several sources owes a different credit per
/// symbol, and a list written by hand drifts from what the build shipped.
class SymbolCredits extends StatefulWidget {
  /// `system-emoji` is here for its index rather than for its pictures: the
  /// emoji are drawn by the device's own font and belong to whoever wrote it,
  /// but the names and search words are Unicode CLDR data, whose license asks
  /// for the same credit as the symbol sets do.
  const SymbolCredits({super.key, this.packs = const ['core', 'system-emoji']});

  final List<String> packs;

  @override
  State<SymbolCredits> createState() => _SymbolCreditsState();
}

class _SymbolCreditsState extends State<SymbolCredits> {
  late final Future<List<_PackCredit>> _credits = _load();

  Future<List<_PackCredit>> _load() async {
    final out = <_PackCredit>[];

    for (final pack in widget.packs) {
      try {
        final raw = await rootBundle.loadString(
          'assets/symbols/$pack/manifest.json',
        );
        final decoded = json.decode(raw);
        if (decoded is! Map) continue;

        final symbols = decoded['symbols'];
        final counts = <String, int>{};
        if (symbols is Map) {
          for (final entry in symbols.values) {
            if (entry is Map && entry['set'] is String) {
              final set = entry['set'] as String;
              counts[set] = (counts[set] ?? 0) + 1;
            }
          }
        }

        final attributions = decoded['attributions'];
        out.add((
          name: (decoded['name'] as String?) ?? pack,
          license: (decoded['license'] as String?) ?? 'unknown',
          sources: [
            if (attributions is Map)
              for (final entry in attributions.entries)
                (
                  slug: entry.key as String,
                  text: entry.value as String,
                  count: counts[entry.key] ?? 0,
                ),
          ]..sort((a, b) => b.count.compareTo(a.count)),
        ));
      } catch (_) {
        // A pack whose manifest is missing simply has nothing to credit.
      }
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Symbol credits')),
      body: FutureBuilder<List<_PackCredit>>(
        future: _credits,
        builder: (context, snapshot) {
          final packs = snapshot.data;
          if (packs == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'The pictures on the buttons come from open symbol sets made '
                'by other people. Their licenses ask that they be credited '
                'wherever the symbols appear.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 28),

              for (final pack in packs) ...[
                Text(
                  pack.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  pack.license,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                for (final source in pack.sources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(source.text, style: const TextStyle(height: 1.45)),
                        if (source.count > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${source.count} '
                              '${source.count == 1 ? 'symbol' : 'symbols'} '
                              'in this build',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 32),
              ],

              const Text(
                'wordbridge itself is open source under the MIT license. That '
                'license covers the app, not the symbols above. Each set '
                'keeps its own terms, and CC BY-SA in particular means '
                'anything derived from these symbols stays under the same '
                'license.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Photos you add yourself stay yours and are never uploaded.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

typedef _PackCredit = ({
  String name,
  String license,
  List<({String slug, String text, int count})> sources,
});
