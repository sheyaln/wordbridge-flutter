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
class BundledSymbolPack implements AssembledSymbolPack {
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

  /// Only packs whose license permits commercial use are ever bundled, so this
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

  /// Which upstream set each word's picture came from, by word.
  ///
  /// Filled by the same pass that reads the manifest, and empty until then.
  /// [sourceOf] is synchronous because it is read while a tile is being built,
  /// so it answers null before the first search rather than blocking on a load.
  final Map<String, String> _sources = {};

  /// Memoized including the empty result, so a missing pack costs one failed
  /// asset lookup per launch rather than one per keystroke in the search box.
  Future<Map<String, String>> manifest() => _manifest ??= _loadManifest();

  Future<Map<String, String>> _loadManifest() async {
    try {
      final decoded = json.decode(await _bundle.loadString(manifestKey));
      if (decoded is! Map) return const {};

      // Two shapes are accepted. The flat `{"word": "file.svg"}` form is the
      // minimum a pack has to provide. Generated packs use a nested form that
      // also carries which source set each symbol came from, because a pack
      // assembled from several sets owes a different attribution per symbol
      // and losing that would breach the licenses.
      final symbols = decoded['symbols'];
      final entries = symbols is Map ? symbols : decoded;

      final files = <String, String>{};
      for (final entry in entries.entries) {
        if (entry.key is! String) continue;
        final word = (entry.key as String).toLowerCase().trim();
        final value = entry.value;

        if (value is String) {
          files[word] = value;
        } else if (value is Map && value['file'] is String) {
          files[word] = value['file'] as String;
          // The nested form's whole reason for existing. Dropping it here is
          // what left four sets indistinguishable behind one pack name.
          if (value['set'] is String) _sources[word] = value['set'] as String;
        }
      }
      return files;
    } catch (_) {
      return const {};
    }
  }

  @override
  String? sourceOf(SymbolRef ref) =>
      ref.packId == id ? _sources[ref.label.toLowerCase().trim()] : null;

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
/// License identifiers for Mulberry and Tawasol are deliberately unversioned:
/// upstream states "CC BY-SA" without a version, and inventing one here would
/// be worse than being vague.
List<BundledSymbolPack> bundledSymbolPacks({AssetBundle? bundle}) => [
  // Generated by tools/fetch_symbols.dart, and the only pack whose images ship.
  //
  // The sets it draws from are not listed here as packs of their own. They were
  // once, and none of them carried any assets, so every search against them
  // returned nothing while the credits screen implied the app carried four
  // symbol sets it did not. Their credits are per-symbol and travel in this
  // pack's manifest, which is where the licenses are satisfied.
  //
  // Adding one back means shipping its images and declaring the asset
  // directory in pubspec.yaml. A pack with no assets is not a pack.
  BundledSymbolPack(
    id: 'core',
    name: 'Wordbridge AAC core symbols',
    license: 'CC-BY-SA-4.0',
    attribution:
        'Assembled from Mulberry Symbols, Stellar Symbols, Tawasol and '
        'OpenMoji via Global Symbols. All CC BY-SA. Credits for each symbol '
        'are listed in the pack manifest and on the Symbol credits screen.',
    bundle: bundle,
  ),
];
