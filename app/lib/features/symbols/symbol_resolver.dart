import 'dart:async';

import 'symbol_pack.dart';
import 'symbol_registry.dart';

/// Where a resolved image lives. Bundled packs answer with an asset key,
/// runtime packs with a filesystem path; the pack's own [SymbolPack.isBundled]
/// flag is the only thing that separates them, so the widget layer never has
/// to guess from the shape of the string.
enum SymbolImageKind { asset, file }

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
/// The chain is: bundled asset, then a file already on disk, then a queued
/// download (which returns nothing now and fires [ready] later), then the
/// label.
class SymbolResolver {
  SymbolResolver({
    required this.registry,
    this.budget = const Duration(seconds: 2),
  }) {
    registry.addListener(_attachToPacks);
    _attachToPacks();
  }

  final SymbolRegistry registry;

  /// Upper bound on one resolution. A pack that hangs yields a label rather
  /// than a cell that never paints.
  final Duration budget;

  final _memo = <String, ResolvedSymbol>{};
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

    final resolved = await _resolve(
      ref,
    ).timeout(budget, onTimeout: () => labelOnly(ref.label));

    // Only successes are memoised. A miss usually means "queued for download",
    // and caching it would hold the button at label-only until the next launch.
    if (resolved.image != null) _memo[ref.key] = resolved;
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

  /// Bundled candidates first, then the rest, each in the order given.
  List<SymbolRef> orderCandidates(Iterable<SymbolRef> candidates) {
    bool bundled(SymbolRef ref) => registry.packFor(ref.packId)?.isBundled ?? false;
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

  Future<ResolvedSymbol> _resolve(SymbolRef ref) async {
    try {
      final pack = registry.packFor(ref.packId);
      if (pack == null) return labelOnly(ref.label);

      final uri = await registry.resolve(ref);
      if (uri == null || uri.isEmpty) return labelOnly(ref.label);

      return (
        label: ref.label,
        image: (
          kind: pack.isBundled ? SymbolImageKind.asset : SymbolImageKind.file,
          uri: uri,
        ),
      );
    } catch (_) {
      return labelOnly(ref.label);
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
