import 'dart:async';
import 'dart:io';

import '../../db/database.dart';
import 'symbol_pack.dart';
import 'symbol_registry.dart';

/// Where a resolved image lives. Bundled packs answer with an asset key,
/// runtime packs with a filesystem path, and a [GlyphSymbolPack] with the
/// characters themselves — nowhere at all, because the platform's own font
/// draws them. Which one it is comes from the pack, so the widget layer never
/// has to guess from the shape of the string.
enum SymbolImageKind { asset, file, glyph }

typedef SymbolImage = ({SymbolImageKind kind, String uri});

/// What a button should draw.
///
/// A null [image] is a normal outcome, not a failure: the symbol has not been
/// downloaded, or the pack is off, or none was ever chosen. The grid renders
/// the label and the button speaks exactly as it would have done.
typedef ResolvedSymbol = ({String label, SymbolImage? image});

/// Turns a [SymbolRef] into something drawable, or into a label.
///
/// Two rules govern this class and neither is negotiable:
///
/// 1. It never throws. A resolution failure is a button without a picture.
/// 2. It never delays a press. Resolution is asynchronous and off the input
///    path; the button speaks whether or not a picture ever arrives.
///
/// The chain is: the symbol chosen for the button, and failing that its
/// label — bundled asset, then a file already on disk, then a queued download
/// (which returns nothing now and fires [ready] later), then the label itself.
/// A button carrying a chosen symbol stops at it, drawn or not.
class SymbolResolver {
  SymbolResolver({
    required this.registry,
    this.db,
    this.budget = const Duration(seconds: 2),
  }) {
    registry.addListener(_attachToPacks);
    _attachToPacks();
  }

  final SymbolRegistry registry;

  /// Where the symbol chosen for a button is read from. Without it every
  /// button falls to the pack picture for its word, and a caregiver's choice
  /// of picture cannot be drawn at all.
  final WordbridgeDatabase? db;

  /// Upper bound on one resolution, whichever way it was asked for. A pack
  /// that hangs yields a label rather than a cell that never paints.
  final Duration budget;

  final _memo = <String, ResolvedSymbol>{};
  final _chosen = <String, SymbolImage>{};
  final _ready = StreamController<SymbolRef>.broadcast();
  final _subscriptions = <String, StreamSubscription<SymbolRef>>{};

  /// Fires when a symbol that resolved to a label has since become drawable,
  /// so a grid already on screen can pick it up.
  Stream<SymbolRef> get ready => _ready.stream;

  static ResolvedSymbol labelOnly(String label) => (label: label, image: null);

  /// The answer already known, if any.
  ///
  /// Synchronous on purpose: a rebuild of a grid that has already resolved
  /// must not flicker from picture to label and back while a future settles.
  ResolvedSymbol? cached(SymbolRef ref) => _memo[ref.key];

  Future<ResolvedSymbol> resolve(SymbolRef ref) async {
    final hit = _memo[ref.key];
    if (hit != null) return hit;

    final resolved = await _resolve(ref)
        .timeout(budget, onTimeout: () => labelOnly(ref.label));

    // Only successes are memoized. A miss usually means "queued for download",
    // and caching it would hold the button at label-only until the next launch.
    if (resolved.image != null) _memo[ref.key] = resolved;
    return resolved;
  }

  /// What a button draws: the symbol chosen for it, or — only where none has
  /// been chosen — whatever the packs carry for its word.
  ///
  /// The precedence is the whole point of letting anyone choose. A keyword
  /// match that outranked a choice would make the picker inert, and the picker
  /// is the only lever there is on a picture that is teaching the wrong thing.
  ///
  /// With no [db] there is no such thing as a chosen symbol, so a button is
  /// read as one that has none rather than being stripped of the picture it
  /// was drawing.
  Future<ResolvedSymbol> resolveButton({
    required String? symbolId,
    required String label,
    required List<String> packIds,
  }) => symbolId == null || db == null
      ? resolveLabel(label, packIds)
      : resolveChosen(symbolId, label: label);

  /// Resolves the symbol recorded on a button, and nothing else.
  ///
  /// Yields the label whenever that symbol cannot be drawn: a pack switched
  /// off, a download still queued, a file that is gone, or a row deliberately
  /// carrying no image. The word's keyword match is never consulted as a
  /// fallback — it is what a recorded choice exists to override, and putting
  /// it back would undo a removal or reinstate a replaced picture.
  Future<ResolvedSymbol> resolveChosen(
    String symbolId, {
    required String label,
  }) async {
    final hit = _chosen[symbolId];
    if (hit != null) return (label: label, image: hit);

    final resolved = await _resolveChosen(
      symbolId,
      label,
    ).timeout(budget, onTimeout: () => labelOnly(label));

    // As in [resolve], only successes are held: a miss is usually a download
    // still in flight, and caching it would pin the button to its word.
    final image = resolved.image;
    if (image != null) _chosen[symbolId] = image;
    return resolved;
  }

  /// Resolves the first candidate that yields an image, bundled packs first.
  ///
  /// Used where a button has more than one way to be illustrated — its own
  /// symbol plus whatever the packs offer for its label — so a downloadable
  /// pictogram never displaces a bundled one that is already on the device.
  Future<ResolvedSymbol> resolveFirst(
    Iterable<SymbolRef> candidates, {
    String? label,
  }) async {
    final ordered = orderCandidates(candidates);
    for (final ref in ordered) {
      final resolved = await resolve(ref);
      if (resolved.image != null) return resolved;
    }
    final fallback = label ?? (ordered.isEmpty ? '' : ordered.first.label);
    return labelOnly(fallback);
  }

  /// Resolves by word rather than by filename.
  ///
  /// Packs index on keyword, so a button knows what it means but not which
  /// file illustrates it. Only an exact keyword match is accepted: a pack's
  /// search also returns prefix and substring hits, and taking those puts a
  /// notebook on the word "not" and a sheep on "she". A wrong picture is
  /// worse than none, because it teaches a false association to someone who
  /// cannot easily contradict it.
  ///
  /// The [budget] covers the whole walk rather than each pack along it, so a
  /// board full of words looking through several hanging packs still costs one
  /// button one interval of showing its word alone.
  Future<ResolvedSymbol> resolveLabel(String label, List<String> packIds) {
    final needle = label.toLowerCase().trim();
    if (needle.isEmpty) return Future.value(labelOnly(label));

    return _resolveLabel(
      needle,
      label,
      packIds,
    ).timeout(budget, onTimeout: () => labelOnly(label));
  }

  /// Bundled candidates first, then the rest, each in the order given.
  List<SymbolRef> orderCandidates(Iterable<SymbolRef> candidates) {
    bool bundled(SymbolRef ref) =>
        registry.packFor(ref.packId)?.isBundled ?? false;
    return [
      ...candidates.where(bundled),
      ...candidates.where((ref) => !bundled(ref)),
    ];
  }

  Future<void> dispose() async {
    registry.removeListener(_attachToPacks);
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _ready.close();
  }

  Future<ResolvedSymbol> _resolveLabel(
    String needle,
    String label,
    List<String> packIds,
  ) async {
    for (final packId in packIds) {
      if (!registry.isEnabled(packId)) continue;
      final pack = registry.packFor(packId);
      if (pack == null) continue;

      try {
        for (final ref in await pack.search(needle, limit: 4)) {
          if (ref.label.toLowerCase().trim() != needle) continue;
          final resolved = await resolve(ref);
          if (resolved.image != null) return resolved;
        }
      } catch (_) {
        // A pack that misbehaves costs this button its picture, nothing more.
      }
    }

    return labelOnly(label);
  }

  Future<ResolvedSymbol> _resolve(SymbolRef ref) async {
    try {
      final pack = registry.packFor(ref.packId);
      if (pack == null) return labelOnly(ref.label);

      final uri = await registry.resolve(ref);
      if (uri == null || uri.isEmpty) return labelOnly(ref.label);

      return (label: ref.label, image: (kind: _kindOf(pack), uri: uri));
    } catch (_) {
      return labelOnly(ref.label);
    }
  }

  /// A glyph is checked for first because it is neither of the other two: its
  /// `uri` is the character to draw, not a place to read bytes from.
  static SymbolImageKind _kindOf(SymbolPack pack) {
    if (pack is GlyphSymbolPack) return SymbolImageKind.glyph;
    return pack.isBundled ? SymbolImageKind.asset : SymbolImageKind.file;
  }

  Future<ResolvedSymbol> _resolveChosen(String symbolId, String label) async {
    final db = this.db;
    if (db == null) return labelOnly(label);

    try {
      final row = await (db.select(
        db.symbols,
      )..where((s) => s.id.equals(symbolId))).getSingleOrNull();
      if (row == null || row.deletedAt != null) return labelOnly(label);

      // A symbol owned by a pack goes through that pack even though the row
      // carries a path of its own: a pack switched off has to stop drawing,
      // and a cache the OS has emptied has to be fetched again.
      final packId = row.packId;
      final externalId = row.externalId;
      if (packId != null && externalId != null) {
        final resolved = await resolve((
          packId: packId,
          externalId: externalId,
          label: row.label,
        ));
        return (label: label, image: resolved.image);
      }

      // Everything else is a file this device owns, a caregiver's photograph
      // above all. A photograph whose file has gone leaves the word doing the
      // work rather than a gap where a picture used to be.
      final uri = row.localUri;
      if (uri == null || uri.isEmpty) return labelOnly(label);
      if (!await File(uri).exists()) return labelOnly(label);

      return (label: label, image: (kind: SymbolImageKind.file, uri: uri));
    } catch (_) {
      return labelOnly(label);
    }
  }

  /// Idempotent; re-run whenever the registry gains a pack.
  void _attachToPacks() {
    for (final pack in registry.packs.whereType<DownloadingSymbolPack>()) {
      _subscriptions.putIfAbsent(
        pack.id,
        () => pack.available.listen(_onAvailable),
      );
    }
  }

  void _onAvailable(SymbolRef ref) {
    _memo.remove(ref.key);
    if (!_ready.isClosed) _ready.add(ref);
  }
}
