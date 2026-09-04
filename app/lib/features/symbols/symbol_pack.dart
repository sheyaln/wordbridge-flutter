/// A pointer to one symbol inside a pack.
///
/// Deliberately not an image. Whether a picture exists on this device is a
/// separate, failable question answered by [SymbolPack.resolve], and keeping
/// the two apart is what lets a button carry a symbol it has not downloaded
/// yet without carrying a rendering error with it.
typedef SymbolRef = ({String packId, String externalId, String label});

extension SymbolRefKey on SymbolRef {
  /// Stable identity for caching and de-duplication across packs.
  String get key => '$packId/$externalId';
}

/// The device's own emoji, named here rather than on the class that implements
/// it.
///
/// The seeded board set puts emoji on its frame keys — home, back, the page
/// arrows — and needs to say which pack they belong to. Reaching for
/// `SystemEmojiPack.packId` to do it meant the seed imported a concrete pack,
/// which is the boundary `tools/check_symbol_boundary.sh` exists to hold: app
/// code depends on this interface and never on a pack. An id is a string, and
/// a string does not need the class that serves it.
const systemEmojiPackId = 'system-emoji';

/// The packs a board consults for a word it has no chosen picture for.
///
/// Deliberately only the curated one. That fallback runs with nobody looking —
/// it is the board drawing itself — and a broad match there is a wrong picture
/// nobody chose, on a screen whose user cannot report it. Broad packs belong in
/// the picker, where a person is deciding.
///
/// One list, in one place. Three that agree today drift, and the drift reads as
/// a caregiver auditing a picture the user is not looking at.
const boardSymbolPackIds = ['core'];

/// A second symbol to draw where the chosen one has not arrived (§4.73).
///
/// One entry, and it earns itself. The `more categories` key is a handpicked
/// pictogram from a pack that fetches its images, so on a device that has
/// never had a network — or has just been set up — that key would show its
/// words indefinitely while the four keys beside it drew fine. The fallback is
/// an emoji, which is a glyph the platform already has and cannot fail to
/// fetch.
///
/// Keyed by symbol id rather than by word, because what has failed is a
/// particular picture and not the button's whole claim to have one. The moment
/// the fetch lands the chosen picture wins again: nothing here is written to
/// the button, so this never becomes the answer.
const symbolFallbacks = {'frame-53182': 'frame-1f504'};

/// Merges several packs' — or several sets' — answers to one search so that no
/// one of them can empty the budget before a later one is reached.
///
/// Concatenating them meant the first source with plenty to say was the only
/// source heard. Two layers had the same shape and the same fault: the
/// device's emoji index matches broadly and filled a sixty-result search on a
/// common word by itself, so the picture sets a caregiver was actually looking
/// for contributed nothing; and inside the fetching pack, the sets were walked
/// in order until the budget ran out, so Stellar, Tawasol and OpenMoji were
/// unreachable on any word Mulberry had a lot of. In both cases the result
/// reads as a set with nothing for the word rather than as a set nobody asked.
///
/// Preference order still decides who comes *first* — each round is walked in
/// the order given. It no longer decides who comes *only*.
///
/// Deduplicated by [SymbolRefKey.key], so a symbol two sources both carry is
/// listed once, at the earlier source's position.
List<SymbolRef> fairMerge(List<List<SymbolRef>> answers, int limit) {
  if (limit <= 0) return const [];

  final merged = <String, SymbolRef>{};
  var deepest = 0;
  for (final refs in answers) {
    if (refs.length > deepest) deepest = refs.length;
  }

  for (var round = 0; round < deepest; round++) {
    for (final refs in answers) {
      if (merged.length >= limit) return merged.values.toList(growable: false);
      if (round >= refs.length) continue;
      final ref = refs[round];
      merged.putIfAbsent(ref.key, () => ref);
    }
  }

  return merged.values.toList(growable: false);
}

/// One symbol set, and the thing a person actually switches on and off.
///
/// Not a pack. Whether a picture ships inside the binary or is fetched when a
/// word needs one is a fact about how this app is built, and somebody deciding
/// whether they want Mulberry drawings on a board should not have to hold it
/// in their head. **A set can be served by both**: Stellar and OpenMoji
/// pictures ship inside `core` and are also searchable through Global Symbols,
/// and one switch governs both or it is lying about what it does.
///
/// [slug] is Global Symbols' own identifier, because it is also what the
/// bundled manifest records against each symbol and what the search API is
/// asked for. One identifier, no mapping table to get wrong.
typedef SymbolSet = ({
  String slug,
  String name,

  /// Human-readable, shown in-app. Every license in use here requires the
  /// credit to be reachable from inside the running app, not just from the
  /// repository.
  String attribution,

  /// SPDX-ish identifier, e.g. `CC-BY-SA-4.0`.
  String license,

  /// False means the set may not be bundled, sold, or shipped on hardware that
  /// is sold. [SymbolRegistry] keeps such a set inert until somebody turns it
  /// on, so the restriction attaches to that choice.
  bool allowsCommercialUse,
});

/// A source of symbols.
///
/// Application code depends on this interface and never on a concrete pack.
/// The reason is licensing, not tidiness: ARASAAC is CC BY-NC-SA and
/// cannot ship in a build that is sold, so a commercial fork has to be able to
/// delete those files and still compile. See NOTICE.md.
///
/// A pack is plumbing. It is how pictures arrive — out of the binary, off the
/// network, out of the platform's font — and it is not what anybody chooses
/// between. [sets] is.
abstract interface class SymbolPack {
  /// Stable across releases — it is written into `symbols.pack_id` rows and is
  /// how a stored symbol finds its way back to a pack after a cache wipe.
  String get id;

  String get name;

  /// SPDX-ish identifier for the pack as a whole. A pack that serves several
  /// sets under one license; where they differ, the set's own is the answer.
  String get license;

  /// The whole pack's credit, which for a pack of several sets names all of
  /// them. Beside one picture that is a list rather than a credit — use
  /// [AssembledSymbolPack.creditFor] there.
  String get attribution;

  /// True if the images ship inside the application binary.
  bool get isBundled;

  /// The sets this pack can serve, in preference order.
  ///
  /// One entry for a pack that is its own source. Two packs may name the same
  /// set, and must use the same slug when they do.
  List<SymbolSet> get sets;

  /// [sets] restricts the search to those slugs; null asks everything the pack
  /// has.
  ///
  /// **In-app callers pass it.** [SymbolRegistry] works out which sets are
  /// switched on and hands them down, so a set that is off costs no request
  /// at all rather than being filtered back out of an answer that was already
  /// paid for.
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    Set<String>? sets,
  });

  /// An asset key for a bundled pack, an absolute file path for a downloaded
  /// one, or null when no image is on the device.
  ///
  /// [sets] is the same restriction as on [search], and it is what makes a set
  /// that is off stop *drawing* rather than merely stop being searched. A
  /// switch that left the shipped board untouched would read as one that does
  /// nothing, since most of what a new device shows came out of the binary.
  ///
  /// A pack that cannot say which set a symbol belongs to draws it. That is
  /// the honest answer rather than a guess either way, and it is why the packs
  /// that can — see [AssembledSymbolPack] — are the ones this matters for.
  ///
  /// Implementations must not throw and must not wait on the network: this is
  /// called while a grid is being built.
  Future<String?> resolve(SymbolRef ref, {Set<String>? sets});
}

/// A pack assembled from several upstream sets, which therefore knows which
/// one each individual symbol came from.
///
/// Separate from [SymbolPack] rather than a method on it, because most packs
/// are their own source and answering the question is meaningless for them.
///
/// It matters twice. A pack drawn from several sets owes a different
/// attribution per symbol, and a person choosing between two otherwise
/// identical tiles has no way to tell them apart, or to name one afterwards to
/// ask for it to be replaced.
abstract interface class AssembledSymbolPack implements SymbolPack {
  /// The upstream set this symbol came from, or null when it is not known.
  ///
  /// Synchronous and best effort: it is read while a tile is being built, so
  /// it answers null rather than waiting on a manifest that has not loaded.
  String? sourceOf(SymbolRef ref);

  /// The credit for the set [ref] came from, rather than for the whole pack.
  ///
  /// A pack assembled from several upstream sets has an `attribution` that
  /// names all of them. Beside one picture that is not a credit, it is a list
  /// — and it tells somebody looking at a Mulberry drawing who made the
  /// OpenMoji ones (§4.72).
  String? creditFor(SymbolRef ref);
}

/// A pack whose pictures the device draws for itself.
///
/// [SymbolPack.resolve] answers with the characters to draw rather than with
/// anywhere they are stored, because they are not stored: the platform's own
/// font renders them, exactly as it renders any other text. The system emoji
/// fonts are proprietary, so **only the codepoint may ever be kept** —
/// extracting, rasterizing or bundling one of their glyphs would put somebody
/// else's artwork in this repository.
///
/// Split out because two callers have to be able to tell such a pack apart:
/// the resolver, since a glyph is neither an asset nor a file, and the
/// auto-attacher, which must not attach one unattended. A glyph pack is
/// indexed on broad keywords, so its matches belong in a picker somebody is
/// watching.
abstract interface class GlyphSymbolPack implements SymbolPack {}

/// A pack that fetches its images at runtime.
///
/// Split out so the resolver can react to a download landing without knowing
/// which pack did the downloading — the interface boundary has to hold even
/// for the packs that behave least like the bundled ones.
abstract interface class DownloadingSymbolPack implements SymbolPack {
  /// Emits once a queued image has been written to disk, so a grid already on
  /// screen can pick it up instead of polling.
  Stream<SymbolRef> get available;

  /// Whether fetching this symbol has already been tried and given up on.
  ///
  /// A tile with no picture is either one still on its way or one that is not
  /// coming, and those look identical while being opposite facts. Somebody
  /// choosing a picture needs to know which, because only one of them is worth
  /// waiting for.
  ///
  /// Synchronous, and false where the pack has no opinion yet.
  bool failedFor(SymbolRef ref);

  Future<void> dispose();
}
