import 'package:flutter/foundation.dart';

import 'symbol_pack.dart';

/// The symbol sets the app knows about, and which of them may currently be
/// used.
///
/// This class exists for one rule: a set whose license forbids commercial use
/// is inert until a person explicitly turns it on. Not merely hidden from the
/// picker: not searched, not resolved, not drawn. ARASAAC and the AAC Image
/// Library are CC BY-NC-SA; fetching one on a user's instruction is their
/// choice to make, while shipping one enabled by default would make it ours.
///
/// **Sets are the unit, not packs.** A pack is how pictures arrive; a set is
/// whose drawings they are. One set can be served by two packs — Stellar ships
/// inside `core` and is also searchable through Global Symbols — and a switch
/// that governed only one of those would be lying about what it turned off. So
/// packs are never switched here. A pack is asked for the sets that are on,
/// and skipped entirely when none of them is.
class SymbolRegistry extends ChangeNotifier {
  SymbolRegistry({
    Iterable<SymbolPack> packs = const [],
    Map<String, bool> choices = const {},
    this.searchBudget = const Duration(seconds: 10),
  }) {
    for (final pack in packs) {
      _packs[pack.id] = pack;
    }
    _choices.addAll(choices);
  }

  /// Insertion-ordered, which is what makes combined search results stable.
  final _packs = <String, SymbolPack>{};

  /// Only sets a person has deliberately switched, keyed by slug. Anything
  /// absent falls back to its license, so a set added in a later release gets
  /// the correct default rather than inheriting a saved map that predates it.
  final _choices = <String, bool>{};

  /// How long a single pack may hold up a combined search.
  ///
  /// Must exceed what a downloading pack allows itself, or this cancels work
  /// that had already arrived and reports it as an empty catalog. At five
  /// seconds against a pack that allowed itself six, the fetching pack could
  /// never contribute a result at all.
  final Duration searchBudget;

  List<SymbolPack> get packs => List.unmodifiable(_packs.values);

  /// Persist verbatim; hand it back to the constructor on the next launch.
  Map<String, bool> get choices => Map.unmodifiable(_choices);

  SymbolPack? packFor(String packId) => _packs[packId];

  void register(SymbolPack pack) {
    _packs[pack.id] = pack;
    notifyListeners();
  }

  /// Every set any registered pack can serve, deduplicated by slug.
  ///
  /// In pack order, which puts what ships before what is fetched and the
  /// noncommercial sets last: the order of what a set costs to use, which is
  /// the order somebody deciding reads them in.
  List<SymbolSet> get sets {
    final found = <String, SymbolSet>{};
    for (final pack in _packs.values) {
      for (final set in pack.sets) {
        found.putIfAbsent(set.slug, () => set);
      }
    }
    return List.unmodifiable(found.values);
  }

  SymbolSet? setFor(String slug) {
    for (final pack in _packs.values) {
      for (final set in pack.sets) {
        if (set.slug == slug) return set;
      }
    }
    return null;
  }

  /// Which packs can serve [slug], bundled ones first.
  ///
  /// More than one where a set both ships and is fetched, which is the case
  /// that makes a set rather than a pack the thing worth switching.
  List<SymbolPack> packsOffering(String slug) {
    final offering = _packs.values.where(
      (p) => p.sets.any((s) => s.slug == slug),
    );
    return [
      ...offering.where((p) => p.isBundled),
      ...offering.where((p) => !p.isBundled),
    ];
  }

  bool isSetEnabled(String slug) {
    final set = setFor(slug);
    if (set == null) return false;
    return _choices[slug] ?? set.allowsCommercialUse;
  }

  void setSetEnabled(String slug, bool enabled) {
    if (setFor(slug) == null) return;
    if (_choices[slug] == enabled) return;
    _choices[slug] = enabled;
    notifyListeners();
  }

  /// The slugs [pack] may currently be asked for.
  Set<String> enabledSetsOf(SymbolPack pack) => {
    for (final set in pack.sets)
      if (isSetEnabled(set.slug)) set.slug,
  };

  /// Whether a pack has anything left to offer.
  ///
  /// Derived, never stored. A pack whose every set is off is a pack with
  /// nothing to say, and keeping a second answer to that question is how the
  /// two come to disagree.
  bool isEnabled(String packId) {
    final pack = _packs[packId];
    return pack != null && enabledSetsOf(pack).isNotEmpty;
  }

  /// Packs with at least one set switched on, bundled ones first.
  ///
  /// Order is the preference: where a bundled pack and a downloadable one both
  /// match a word, the local image should be the one offered.
  List<SymbolPack> get enabledPacks {
    final enabled = _packs.values.where((p) => isEnabled(p.id));
    return [
      ...enabled.where((p) => p.isBundled),
      ...enabled.where((p) => !p.isBundled),
    ];
  }

  /// Searches every enabled set and merges the results, bundled first.
  ///
  /// Packs are queried concurrently, and one that fails or hangs contributes
  /// nothing rather than emptying the drawer for the others. A pack that
  /// answers *well* cannot empty it either: the merge is round-robin, so
  /// bundled-first decides who is at the top of the results and not who is in
  /// them at all. See [fairMerge].
  ///
  /// [setSlug] narrows it to one set, for somebody comparing what each one has
  /// for a word. **It does not reach a set that is switched off.** Naming one
  /// explicitly is the obvious way around the rule this class exists for — a
  /// set that is off is not searched, and asking for it by name returns
  /// nothing rather than an exception, because the caller that would hit this
  /// is a filter holding a set somebody has just switched off.
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    String? packId,
    String? setSlug,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    final targets = <({SymbolPack pack, Set<String> sets})>[];
    for (final pack in enabledPacks) {
      if (packId != null && pack.id != packId) continue;
      final allowed = enabledSetsOf(pack)
        ..removeWhere((s) => setSlug != null && s != setSlug);
      if (allowed.isEmpty) continue;
      targets.add((pack: pack, sets: allowed));
    }
    if (targets.isEmpty) return const [];

    final answers = await Future.wait([
      for (final target in targets)
        _searchOne(target.pack, trimmed, locale, limit, target.sets),
    ]);

    return fairMerge(answers, limit);
  }

  Future<List<SymbolRef>> _searchOne(
    SymbolPack pack,
    String query,
    String locale,
    int limit,
    Set<String> sets,
  ) async {
    try {
      return await pack
          .search(query, locale: locale, limit: limit, sets: sets)
          .timeout(searchBudget);
    } catch (_) {
      return const [];
    }
  }

  /// Resolves through the owning pack, or returns null if that pack is unknown
  /// or has nothing switched on.
  ///
  /// A set that is off stops resolving even for images already on the device.
  /// Opting out of a noncommercial set has to actually remove it from the app,
  /// otherwise the opt-in meant nothing — and for the rest, most of what a new
  /// device draws came out of the binary, so a switch that spared those would
  /// read as one that does nothing.
  Future<String?> resolve(SymbolRef ref) async {
    final pack = _packs[ref.packId];
    if (pack == null) return null;

    final allowed = enabledSetsOf(pack);
    if (allowed.isEmpty) return null;
    try {
      return await pack.resolve(ref, sets: allowed);
    } catch (_) {
      return null;
    }
  }
}
