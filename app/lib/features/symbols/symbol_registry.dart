import 'package:flutter/foundation.dart';

import 'symbol_pack.dart';

/// The packs the app knows about, and which of them may currently be used.
///
/// This class exists for one rule: a pack whose license forbids commercial use
/// is inert until a person explicitly turns it on. Not merely hidden from the
/// picker: not searched, not resolved, not drawn. ARASAAC is
/// CC BY-NC; fetching one on a user's instruction is their choice to make,
/// while shipping one enabled by default would make it ours.
class SymbolRegistry extends ChangeNotifier {
  SymbolRegistry({
    Iterable<SymbolPack> packs = const [],
    Map<String, bool> choices = const {},
    this.searchBudget = const Duration(seconds: 5),
  }) {
    for (final pack in packs) {
      _packs[pack.id] = pack;
    }
    _choices.addAll(choices);
  }

  /// Insertion-ordered, which is what makes combined search results stable.
  final _packs = <String, SymbolPack>{};

  /// Only packs a person has deliberately switched. Anything absent falls back
  /// to its license, so a pack added in a later release gets the correct
  /// default rather than inheriting a saved set that predates it.
  final _choices = <String, bool>{};

  /// How long a single pack may hold up a combined search.
  final Duration searchBudget;

  List<SymbolPack> get packs => List.unmodifiable(_packs.values);

  /// Persist verbatim; hand it back to the constructor on the next launch.
  Map<String, bool> get choices => Map.unmodifiable(_choices);

  SymbolPack? packFor(String packId) => _packs[packId];

  void register(SymbolPack pack) {
    _packs[pack.id] = pack;
    notifyListeners();
  }

  bool isEnabled(String packId) {
    final pack = _packs[packId];
    if (pack == null) return false;
    return _choices[packId] ?? pack.allowsCommercialUse;
  }

  void setEnabled(String packId, bool enabled) {
    if (!_packs.containsKey(packId)) return;
    if (_choices[packId] == enabled) return;
    _choices[packId] = enabled;
    notifyListeners();
  }

  /// Enabled packs, bundled ones first.
  ///
  /// Order is the preference: where a bundled pack and a downloadable one both
  /// match a word, the license-clean local image should be the one offered.
  List<SymbolPack> get enabledPacks {
    final enabled = _packs.values.where((p) => isEnabled(p.id));
    return [
      ...enabled.where((p) => p.isBundled),
      ...enabled.where((p) => !p.isBundled),
    ];
  }

  /// Searches every enabled pack and merges the results, bundled first.
  ///
  /// Packs are queried concurrently, and one that fails or hangs contributes
  /// nothing rather than emptying the drawer for the others. A pack that
  /// answers *well* cannot empty it either: the merge is round-robin, so
  /// bundled-first decides who is at the top of the results and not who is in
  /// them at all. See [fairMerge].
  ///
  /// [packId] narrows it to one set, for somebody comparing what each one has
  /// for a word. **It does not reach a disabled pack.** Naming one explicitly
  /// is the obvious way around the rule this class exists for — a pack that is
  /// off is not searched, and asking for it by name returns nothing rather
  /// than an exception, because the caller that would hit this is a filter
  /// holding a pack somebody has just switched off.
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    String? packId,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    final targets = packId == null
        ? enabledPacks
        : enabledPacks.where((p) => p.id == packId).toList(growable: false);
    if (targets.isEmpty) return const [];
    final answers = await Future.wait([
      for (final pack in targets) _searchOne(pack, trimmed, locale, limit),
    ]);

    return fairMerge(answers, limit);
  }

  Future<List<SymbolRef>> _searchOne(
    SymbolPack pack,
    String query,
    String locale,
    int limit,
  ) async {
    try {
      return await pack
          .search(query, locale: locale, limit: limit)
          .timeout(searchBudget);
    } catch (_) {
      return const [];
    }
  }

  /// Resolves through the owning pack, or returns null if that pack is unknown
  /// or disabled.
  ///
  /// A disabled pack stops resolving even for images already on disk. Opting
  /// out of a non-commercial pack has to actually remove it from the app,
  /// otherwise the opt-in meant nothing.
  Future<String?> resolve(SymbolRef ref) async {
    final pack = _packs[ref.packId];
    if (pack == null || !isEnabled(pack.id)) return null;
    try {
      return await pack.resolve(ref);
    } catch (_) {
      return null;
    }
  }
}
