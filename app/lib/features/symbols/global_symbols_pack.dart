import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'symbol_pack.dart';

/// The commercially-clean symbol sets, fetched on demand.
///
/// The same four sets and the same source the offline bundler uses, reachable
/// at runtime so a caregiver adding a word does not have to wait for a release
/// to get a picture for it. All four are CC BY-SA: attribution and share-alike,
/// commercial use permitted. **ARASAAC is deliberately not here**:
/// they are CC BY-NC and stay behind their own opt-in pack.
///
/// Two different jobs, with two different standards of proof:
///
/// **[search] is for a person to look at.** It returns candidates, ranked, and
/// a caregiver picks one. A human deciding that a picture of a cup means
/// "drink" is judgment, and judgment is exactly what a caregiver is for.
///
/// **[bestMatch] is for the app to act on unattended.** It returns a symbol
/// only when the label matches exactly, because an automatic near-miss teaches
/// an AAC user that a word means whatever the picture shows. The search is a
/// substring match: "all" returns Ball, "not" returns Notebook, "she" returns
/// Sheep. A blank button honestly says "no picture yet"; a plausible wrong one
/// is a lie the user cannot contradict.
class GlobalSymbolsPack implements DownloadingSymbolPack {
  GlobalSymbolsPack({
    http.Client? client,
    Future<Directory> Function()? documentsDirectory,
    this.requestTimeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  static const host = 'globalsymbols.com';

  /// In preference order. Mulberry leads because it is a purpose-built AAC set
  /// with a consistent drawn style; the rest fill its gaps in abstract core
  /// vocabulary. Mixing styles costs visual consistency, and a blank button
  /// costs more.
  static const sets = <({String slug, String name, String attribution})>[
    (
      slug: 'mulberry',
      name: 'Mulberry Symbols',
      attribution:
          'Mulberry Symbols © Garry Paxton 2008-2017, Steve Lee 2018-. '
          'CC BY-SA 4.0. https://mulberrysymbols.org',
    ),
    (
      slug: 'stellar-symbols',
      name: 'Stellar Symbols',
      attribution: 'Stellar Symbols © Colin McNamee. CC BY-SA 4.0.',
    ),
    (
      slug: 'tawasol',
      name: 'Tawasol',
      attribution:
          'Tawasol Symbols © Mada, Qatar. CC BY-SA 4.0. '
          'http://tawasolsymbols.org',
    ),
    (
      slug: 'openmoji',
      name: 'OpenMoji',
      attribution:
          'OpenMoji © OpenMoji Project. CC BY-SA 4.0. '
          'https://openmoji.org',
    ),
  ];

  final http.Client _client;
  final Future<Directory> Function() _documentsDirectory;
  final Duration requestTimeout;

  final _available = StreamController<SymbolRef>.broadcast();
  final _inFlight = <String, Future<void>>{};
  final _failed = <String>{};
  final _urls = <String, String>{};

  Future<Directory>? _cachedDirectory;

  @override
  String get id => 'globalsymbols';

  @override
  String get name => 'More pictures';

  @override
  String get license => 'CC-BY-SA-4.0';

  @override
  String get attribution => [
    for (final set in sets) set.attribution,
    'Fetched through Global Symbols (https://globalsymbols.com).',
  ].join('\n');

  @override
  bool get allowsCommercialUse => true;

  @override
  bool get isBundled => false;

  @override
  Stream<SymbolRef> get available => _available.stream;

  static Uri searchUri(String query, String setSlug, {int limit = 12}) =>
      Uri.https(host, '/api/v1/labels/search', {
        'query': query.trim(),
        'symbolset': setSlug,
        'language': 'eng',
        'limit': '$limit',
      });

  /// Candidates for a person to choose from, best sets first.
  ///
  /// Loose on purpose. Nothing here is assigned to a button without somebody
  /// looking at it.
  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    final results = <SymbolRef>[];
    final seen = <String>{};

    for (final set in sets) {
      if (results.length >= limit) break;

      for (final entry in await _labels(trimmed, set.slug)) {
        final ref = _refFrom(entry);
        if (ref == null || !seen.add(ref.key)) continue;
        results.add(ref);
        if (results.length >= limit) break;
      }
    }

    return results;
  }

  /// The one symbol whose label *is* this word, or null.
  ///
  /// What the app is allowed to attach to a button by itself.
  Future<SymbolRef?> bestMatch(String word) async {
    final needle = _normalize(word);
    if (needle.isEmpty) return null;

    for (final set in sets) {
      for (final entry in await _labels(word, set.slug)) {
        if (_normalize(entry['text'] as String?) != needle) continue;
        final ref = _refFrom(entry);
        if (ref != null) return ref;
      }
    }
    return null;
  }

  @override
  Future<String?> resolve(SymbolRef ref) async {
    if (ref.packId != id) return null;

    final file = await _fileFor(ref);
    if (file == null) return null;
    if (await file.exists()) return file.path;

    // Not awaited. Resolution runs while a grid is building, and a button must
    // never wait on a network round trip to be pressable.
    unawaited(_queueDownload(ref, file));
    return null;
  }

  /// Downloads now and reports whether the image is on disk.
  ///
  /// Used where a caregiver has just chosen a picture and is waiting to see
  /// it, which is the one moment blocking on the network is the right thing.
  Future<bool> fetchNow(SymbolRef ref) async {
    final file = await _fileFor(ref);
    if (file == null) return false;
    if (await file.exists()) return true;

    _failed.remove(ref.externalId);
    try {
      // A ceiling, not an open wait. Somebody is looking at a spinner, and a
      // slow network should give them the choice back rather than hold the
      // sheet open indefinitely.
      await _queueDownload(ref, file).timeout(requestTimeout * 2);
    } catch (_) {
      return false;
    }
    return file.exists();
  }

  void clearFailures() => _failed.clear();

  @override
  Future<void> dispose() async {
    await _available.close();
    _client.close();
  }

  Future<List<Map<String, dynamic>>> _labels(
    String query,
    String setSlug,
  ) async {
    try {
      final response = await _client
          .get(searchUri(query, setSlug))
          .timeout(requestTimeout);
      if (response.statusCode != 200) return const [];

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body is List ? body.cast<Map<String, dynamic>>() : const [];
    } catch (_) {
      // Fails soft. No network means no extra pictures, never an error in
      // front of somebody mid-sentence.
      return const [];
    }
  }

  SymbolRef? _refFrom(Map<String, dynamic> entry) {
    final picto = entry['picto'];
    final text = entry['text'];
    if (picto is! Map || text is! String) return null;

    final pictoId = picto['id'];
    final imageUrl = picto['image_url'];
    if (pictoId is! int || imageUrl is! String) return null;

    _urls['$pictoId'] = imageUrl;
    return (packId: id, externalId: '$pictoId', label: text);
  }

  /// Application documents, never the cache directory. Both platforms evict
  /// caches under storage pressure without asking, and a user whose symbols
  /// vanish mid-conversation has lost their voice, not a thumbnail.
  Future<File?> _fileFor(SymbolRef ref) async {
    try {
      final directory = await (_cachedDirectory ??= _documentsDirectory());
      final url = _urls[ref.externalId] ?? '';
      final extension = url.toLowerCase().endsWith('.png') ? 'png' : 'svg';
      return File(
        p.join(directory.path, 'symbols', id, '${ref.externalId}.$extension'),
      );
    } catch (_) {
      _cachedDirectory = null;
      return null;
    }
  }

  Future<void> _queueDownload(SymbolRef ref, File target) {
    if (_failed.contains(ref.externalId)) return Future.value();
    return _inFlight.putIfAbsent(
      ref.externalId,
      () => _download(
        ref,
        target,
      ).whenComplete(() => _inFlight.remove(ref.externalId)),
    );
  }

  Future<void> _download(SymbolRef ref, File target) async {
    final url = _urls[ref.externalId];
    if (url == null) {
      _failed.add(ref.externalId);
      return;
    }

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(requestTimeout);

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _failed.add(ref.externalId);
        return;
      }

      await target.parent.create(recursive: true);

      // Write alongside and rename. A process killed mid-write must not leave
      // a truncated file behind, because it would then look cached and render
      // as a broken image for good.
      final partial = File('${target.path}.part');
      await partial.writeAsBytes(response.bodyBytes, flush: true);
      await partial.rename(target.path);

      if (!_available.isClosed) _available.add(ref);
    } catch (_) {
      _failed.add(ref.externalId);
    }
  }

  static String _normalize(String? text) =>
      (text ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
}
