import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'symbol_pack.dart';

/// A symbol pack shipped inside the application binary.
///
/// Images live at `assets/symbols/<id>/<filename>` and are indexed by
/// `assets/symbols/<id>/manifest.json`, a flat `{"keyword": "filename"}` map.
/// Nothing here is generated: dropping a manifest and its images into the
/// assets tree and declaring the directory in `pubspec.yaml` is the whole
/// installation procedure.
///
/// Every failure path ends in an empty pack. A build with no symbol assets
/// yet, a truncated manifest, an image the manifest names but the build did
/// not ship — all of them produce label-only buttons, which are usable. An
/// exception on the render path produces a device that cannot speak.
class BundledSymbolPack implements SymbolPack {
  BundledSymbolPack({
    required this.id,
    required this.name,
    required this.license,
    required this.attribution,
    AssetBundle? bundle,
  }) : _bundle = bundle ?? rootBundle;

  @override
  final String id;

  @override
  final String name;

  @override
  final String license;

  @override
  final String attribution;

  final AssetBundle _bundle;

  /// Only packs whose licence permits commercial use are ever bundled, so this
  /// is a property of being bundled rather than of any particular pack. A
  /// non-commercial pack that reached this class would be a distribution
  /// problem, not a configuration one.
  @override
  bool get allowsCommercialUse => true;

  @override
  bool get isBundled => true;

  String get assetRoot => 'assets/symbols/$id';

  String get manifestKey => '$assetRoot/manifest.json';

  String assetKeyFor(String filename) => '$assetRoot/$filename';

  Future<Map<String, String>>? _manifest;

  /// Memoised including the empty result, so a missing pack costs one failed
  /// asset lookup per launch rather than one per keystroke in the search box.
  Future<Map<String, String>> manifest() => _manifest ??= _loadManifest();

  Future<Map<String, String>> _loadManifest() async {
    try {
      final decoded = json.decode(await _bundle.loadString(manifestKey));
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            (entry.key as String).toLowerCase().trim(): entry.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty || limit <= 0) return const [];

    final entries = await manifest();
    if (entries.isEmpty) return const [];

    // Exact before prefix before substring: searching "in" must not bury the
    // word "in" under "inside", "interesting" and "swimming".
    final exact = <SymbolRef>[];
    final prefix = <SymbolRef>[];
    final substring = <SymbolRef>[];

    for (final entry in entries.entries) {
      final ref = (packId: id, externalId: entry.value, label: entry.key);
      if (entry.key == needle) {
        exact.add(ref);
      } else if (entry.key.startsWith(needle)) {
        prefix.add(ref);
      } else if (entry.key.contains(needle)) {
        substring.add(ref);
      }
    }

    return [
      ...exact,
      ...prefix,
      ...substring,
    ].take(limit).toList(growable: false);
  }

  @override
  Future<String?> resolve(SymbolRef ref) async {
    if (ref.packId != id) return null;

    final key = assetKeyFor(ref.externalId);
    try {
      // Costs one asset load, which the image widget is about to perform
      // anyway. Without it a manifest naming a file the build did not ship
      // reaches the grid as a broken image rather than as a label.
      await _bundle.load(key);
      return key;
    } catch (_) {
      return null;
    }
  }
}

/// The packs wordbridge ships.
///
/// All four permit commercial use. Nothing may be added to this list without
/// that being true of it as well — see NOTICE.md.
///
/// Licence identifiers for Mulberry and Tawasol are deliberately unversioned:
/// upstream states "CC BY-SA" without a version, and inventing one here would
/// be worse than being vague.
List<BundledSymbolPack> bundledSymbolPacks({AssetBundle? bundle}) => [
  BundledSymbolPack(
    id: 'mulberry',
    name: 'Mulberry Symbols',
    license: 'CC-BY-SA',
    attribution:
        'Mulberry Symbols © Garry Paxton 2008–2017, Steve Lee 2018–. '
        'Licensed CC BY-SA.',
    bundle: bundle,
  ),
  BundledSymbolPack(
    id: 'openmoji',
    name: 'OpenMoji',
    license: 'CC-BY-SA-4.0',
    attribution:
        'OpenMoji (https://openmoji.org) — the open-source emoji and icon '
        'project. Licensed CC BY-SA 4.0.',
    bundle: bundle,
  ),
  BundledSymbolPack(
    id: 'twemoji',
    name: 'Twemoji',
    license: 'CC-BY-4.0',
    attribution:
        'Twemoji © Twitter, Inc. and other contributors. '
        'Licensed CC BY 4.0.',
    bundle: bundle,
  ),
  BundledSymbolPack(
    id: 'tawasol',
    name: 'Tawasol Symbols',
    license: 'CC-BY-SA',
    attribution: 'Tawasol Symbols — Mada Center, Qatar. Licensed CC BY-SA.',
    bundle: bundle,
  ),
];
