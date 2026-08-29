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

/// A source of symbols.
///
/// Application code depends on this interface and never on a concrete pack.
/// The reason is licensing, not tidiness: ARASAAC and Sclera are CC BY-NC and
/// cannot ship in a build that is sold, so a commercial fork has to be able to
/// delete those files and still compile. See NOTICE.md.
abstract interface class SymbolPack {
  /// Stable across releases — it is written into `symbols.pack_id` rows and is
  /// how a stored symbol finds its way back to a pack after a cache wipe.
  String get id;

  String get name;

  /// SPDX-ish identifier, e.g. `CC-BY-SA-4.0`.
  String get license;

  /// Human-readable, shown in-app. Every licence in use here requires the
  /// credit to be reachable from inside the running app, not just from the
  /// repository.
  String get attribution;

  /// False means the pack may not be bundled, sold, or shipped on hardware
  /// that is sold. [SymbolRegistry] keeps such packs inert until a user turns
  /// them on, so the restriction attaches to that choice.
  bool get allowsCommercialUse;

  /// True if the images ship inside the application binary.
  bool get isBundled;

  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  });

  /// An asset key for a bundled pack, an absolute file path for a downloaded
  /// one, or null when no image is on the device.
  ///
  /// Implementations must not throw and must not wait on the network: this is
  /// called while a grid is being built.
  Future<String?> resolve(SymbolRef ref);
}

/// A pack whose pictures the device draws for itself.
///
/// [SymbolPack.resolve] answers with the characters to draw rather than with
/// anywhere they are stored, because they are not stored: the platform's own
/// font renders them, exactly as it renders any other text. The system emoji
/// fonts are proprietary, so **only the codepoint may ever be kept** —
/// extracting, rasterising or bundling one of their glyphs would put somebody
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

  Future<void> dispose();
}
