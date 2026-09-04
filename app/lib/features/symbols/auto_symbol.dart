/// Finding a picture for a word nobody has chosen one for.
///
/// Runs when a caregiver adds a word. The bundled pack is checked first, and
/// only if nothing there matches is the network asked — so the common case
/// costs nothing and works offline.
///
/// **Exact matches only, and no fallback to the top-ranked result.** The
/// search behind this is a substring match: "all" returns Ball, "not" returns
/// Notebook, "she" returns Sheep. Nobody is looking at the screen when this
/// runs, so a near-miss would be attached silently and teach an AAC user that
/// a word means whatever the picture shows. A blank button honestly says "no
/// picture yet"; the picker is where a person browses and decides.
library;

import 'package:drift/drift.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';
import 'global_symbols_pack.dart';
import 'symbol_pack.dart';
import 'symbol_registry.dart';

class AutoSymbol {
  const AutoSymbol({required this.db, required this.registry, this.fetcher});

  final WordbridgeDatabase db;
  final SymbolRegistry registry;

  /// Absent in tests and wherever the network is not wanted. Without it this
  /// still checks the bundled pack, which is the offline half of the job.
  final GlobalSymbolsPack? fetcher;

  /// Attaches a picture to [buttonId] if one certainly matches [label].
  ///
  /// Returns true if a symbol was attached. Never throws: a word with no
  /// picture is a working button, and a caregiver mid-edit should not be shown
  /// a network error.
  Future<bool> attachTo({
    required String buttonId,
    required String label,
  }) async {
    try {
      final ref = await _findExact(label);
      if (ref == null) return false;

      final pack = registry.packFor(ref.packId);

      // The set that drew it, where the pack can say. Its licence and its
      // credit are what belong on the row, because that row is what an export
      // carries out of this device — and a pack of six sets would otherwise
      // write all six credits onto one Mulberry picture (§4.72).
      final set = _setOf(pack, ref);

      // Nothing waits for the bytes. Resolution queues the download and the
      // pack announces it when it lands; until then the button shows its word,
      // which is exactly what it would show if no picture existed at all.
      final uri = await registry.resolve(ref);
      final symbolId = newId();

      await db
          .into(db.symbols)
          .insert(
            SymbolsCompanion.insert(
              id: symbolId,
              packId: Value(ref.packId),
              source: pack?.isBundled ?? false
                  ? SymbolSource.bundled
                  : SymbolSource.downloaded,
              externalId: Value(ref.externalId),
              localUri: Value(uri),
              label: ref.label,
              license: set?.license ?? pack?.license ?? 'unknown',
              attribution: set?.attribution ?? pack?.attribution ?? '',
              createdAt: nowMs(),
            ),
          );

      // Reaches the word rather than the row, because this runs unwatched and
      // can land after the word has been pinned (§4.16). A picture that
      // arrived on the original only would leave the pinned column showing the
      // same word blank.
      final button = await (db.select(
        db.buttons,
      )..where((b) => b.id.equals(buttonId))).getSingleOrNull();
      if (button == null) return false;

      await writeToWord(
        db,
        button,
        ButtonsCompanion(symbolId: Value(symbolId), updatedAt: Value(nowMs())),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// The one symbol whose label *is* this word, bundled first.
  ///
  /// A [GlyphSymbolPack] is never asked, however exactly it answers. Its index
  /// is emoji keywords, which are broad by design and describe a picture
  /// rather than name a word: the emoji named "dog" is one particular cartoon
  /// dog, and a board that decides unwatched that this is the dog meant has
  /// put a word in somebody's mouth. Those matches belong in the picker, where
  /// a person is looking and can say no.
  Future<SymbolRef?> _findExact(String label) async {
    final needle = _normalize(label);
    if (needle.isEmpty) return null;

    for (final pack in registry.enabledPacks) {
      if (pack is GlyphSymbolPack || !pack.isBundled) continue;
      // The sets are handed down. Asked without them the pack answers from
      // all of its own, and a word could be given a picture out of a set
      // somebody switched off.
      for (final ref in await pack.search(
        label,
        limit: 12,
        sets: registry.enabledSetsOf(pack),
      )) {
        if (_normalize(ref.label) == needle) return ref;
      }
    }

    final fetcher = this.fetcher;
    if (fetcher == null) return null;
    return fetcher.bestMatch(label, sets: registry.enabledSetsOf(fetcher));
  }

  /// The set a symbol came from, where the pack keeps that. A pack that is one
  /// set is that set; anything else answers null rather than guessing.
  SymbolSet? _setOf(SymbolPack? pack, SymbolRef ref) {
    if (pack == null) return null;
    if (pack.sets.length == 1) return pack.sets.single;
    if (pack is! AssembledSymbolPack) return null;

    final source = pack.sourceOf(ref);
    for (final set in pack.sets) {
      if (set.slug == source) return set;
    }
    return null;
  }

  static String _normalize(String? text) =>
      (text ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
}
