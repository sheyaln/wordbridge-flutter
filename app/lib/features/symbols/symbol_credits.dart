import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'symbol_registry.dart';

/// Credits for the symbols on the buttons.
///
/// Not a nicety. Every set here is CC BY, CC BY-SA or CC BY-NC-SA, and all of
/// those require attribution wherever the work appears — so this screen is
/// part of what makes shipping and fetching the symbols lawful, and it has to
/// stay reachable without a network connection or an account.
///
/// **Credited by set, because a set is what somebody can reach.** The screen
/// used to read the manifests of the packs whose images ship, which meant the
/// six sets behind the fetching pack were credited nowhere in the app at all:
/// a caregiver could search them, choose one and put it on a board, and every
/// one of them is CC BY-SA. [registry] is where the sets are named, so it is
/// what this reads.
///
/// A set that is switched off is not listed. It draws nothing, anywhere — the
/// registry refuses to resolve it even for a picture already on a button — so
/// there is nothing of it appearing that a credit could be owed for, and
/// listing it would claim a symbol library this device is not using.
class SymbolCredits extends StatefulWidget {
  const SymbolCredits({
    super.key,
    this.registry,
    this.manifests = const ['core', 'system-emoji'],
  });

  /// Where the sets are named, or null on a build that has no registry. Absent,
  /// this falls back to the shipped manifests, so credits are never nowhere.
  final SymbolRegistry? registry;

  /// Packs whose `assets/symbols/<id>/manifest.json` ships, read for how many
  /// of each set's pictures this build actually carries. `system-emoji` is
  /// here for its index rather than for its pictures: the emoji are drawn by
  /// the device's own font and belong to whoever wrote it, but the names and
  /// search words are Unicode CLDR data, whose license asks for the same
  /// credit as the symbol sets do.
  final List<String> manifests;

  @override
  State<SymbolCredits> createState() => _SymbolCreditsState();
}

class _SymbolCreditsState extends State<SymbolCredits> {
  late final Future<List<_SetCredit>> _credits = _load();

  Future<List<_SetCredit>> _load() async {
    final counts = <String, int>{};
    final shipped = <String, ({String name, String text, String license})>{};

    for (final pack in widget.manifests) {
      try {
        final raw = await rootBundle.loadString(
          'assets/symbols/$pack/manifest.json',
        );
        final decoded = json.decode(raw);
        if (decoded is! Map) continue;

        final symbols = decoded['symbols'];
        if (symbols is Map) {
          for (final entry in symbols.values) {
            if (entry is Map && entry['set'] is String) {
              final set = entry['set'] as String;
              counts[set] = (counts[set] ?? 0) + 1;
            }
          }
        }

        final attributions = decoded['attributions'];
        if (attributions is Map) {
          for (final entry in attributions.entries) {
            if (entry.key is String && entry.value is String) {
              shipped[entry.key as String] = (
                name: entry.key as String,
                text: entry.value as String,
                license: (decoded['license'] as String?) ?? 'unknown',
              );
            }
          }
        }
      } catch (_) {
        // A pack whose manifest is missing simply has nothing to count.
      }
    }

    final registry = widget.registry;
    if (registry == null) {
      // The manifests are the last resort, not the arrangement: they credit
      // only what ships, which is why this screen no longer relies on them.
      return [
        for (final entry in shipped.values)
          (
            name: entry.name,
            license: entry.license,
            text: entry.text,
            count: counts[entry.name] ?? 0,
          ),
      ];
    }

    return [
      for (final set in registry.sets)
        if (registry.isSetEnabled(set.slug))
          (
            name: set.name,
            license: set.license,
            text: set.attribution,
            count: counts[set.slug] ?? 0,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Symbol credits')),
      body: FutureBuilder<List<_SetCredit>>(
        future: _credits,
        builder: (context, snapshot) {
          final sets = snapshot.data;
          if (sets == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'The pictures on the buttons come from open symbol sets made '
                'by other people. Their licenses ask that they be credited '
                'wherever the symbols appear, which covers the sets this '
                'device downloads from as well as the ones that came with '
                'the app.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 28),

              for (final set in sets) ...[
                Text(
                  set.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  set.license,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Text(set.text, style: const TextStyle(height: 1.45)),
                if (set.count > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${set.count} '
                      '${set.count == 1 ? 'symbol' : 'symbols'} '
                      'in this build',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ),
                const Divider(height: 32),
              ],

              const Text(
                'Wordbridge AAC itself is open source under the MIT license. '
                'That license covers the app, not the symbols above. Each set '
                'keeps its own terms, and CC BY-SA in particular means '
                'anything derived from these symbols stays under the same '
                'license.',
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

typedef _SetCredit = ({String name, String license, String text, int count});
