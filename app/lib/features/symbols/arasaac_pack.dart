import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'drawable.dart';
import 'symbol_pack.dart';

/// ARASAAC pictograms, fetched on demand.
///
/// **Never bundled.** ARASAAC is CC BY-NC-SA: shipping it inside a build that
/// is sold — or sold with hardware, or behind a paid tier — breaches the
/// license. It is downloaded only after a user turns it on, so the
/// non-commercial restriction attaches to their choice. [SymbolRegistry]
/// enforces that; this class never checks it for itself.
///
/// Everything here fails soft. A search that times out returns no results, a
/// download that fails leaves the button showing its label, and neither is an
/// error the user is asked to deal with mid-conversation.
class ArasaacPack implements DownloadingSymbolPack {
  ArasaacPack({
    http.Client? client,
    Future<Directory> Function()? documentsDirectory,
    this.requestTimeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  static const apiHost = 'api.arasaac.org';
  static const staticHost = 'static.arasaac.org';

  /// The only sizes the CDN serves; every other value is a 404. Verified
  /// against the live host, not inferred from the docs.
  static const availableResolutions = {300, 500, 2500};

  /// Large enough for a full-bleed cell on a 12.9" tablet, small enough not to
  /// pull a 2500px original over a metered connection for every word.
  static const imageResolution = 500;

  final http.Client _client;
  final Future<Directory> Function() _documentsDirectory;
  final Duration requestTimeout;

  final _available = StreamController<SymbolRef>.broadcast();
  final _inFlight = <String, Future<void>>{};

  /// Pictograms whose download failed this session. Not retried: a device in a
  /// dead spot with a screen full of missing symbols would otherwise reissue
  /// every request on every rebuild. Cleared by [clearFailures] or a restart.
  final _failed = <String>{};

  /// Symbols whose cached file has been looked at and can be drawn.
  final _checked = <String>{};

  Future<Directory>? _cachedDirectory;

  @override
  String get id => 'arasaac';

  @override
  String get name => 'ARASAAC';

  @override
  String get license => 'CC-BY-NC-SA';

  /// Required wherever an ARASAAC symbol appears. Reproduced from NOTICE.md.
  @override
  String get attribution =>
      'Author of the pictographic symbols: Sergio Palao. '
      'Origin: ARASAAC (https://arasaac.org). '
      'License: CC (BY-NC-SA). '
      'Owner: Government of Aragón (Spain).';

  @override
  bool get allowsCommercialUse => false;

  @override
  bool get isBundled => false;

  @override
  Stream<SymbolRef> get available => _available.stream;

  /// ARASAAC keys on a bare language code; wordbridge vocabularies carry full
  /// tags like `en-US`, which the API answers with an empty list.
  static String apiLocale(String locale) {
    final language = locale.split(RegExp('[-_]')).first.trim().toLowerCase();
    return language.isEmpty ? 'en' : language;
  }

  static Uri searchUri(
    String query, {
    String locale = 'en',
    bool best = false,
  }) {
    // Path segments, not query parameters. A slash in the search box would
    // otherwise silently become a different endpoint.
    final term = query.trim().replaceAll('/', ' ');
    final endpoint = best ? 'bestsearch' : 'search';
    return Uri.https(
      apiHost,
      '/api/pictograms/${apiLocale(locale)}/$endpoint/$term',
    );
  }

  static Uri imageUri(String pictogramId, {int resolution = imageResolution}) {
    assert(
      availableResolutions.contains(resolution),
      'ARASAAC serves only $availableResolutions; $resolution is a 404',
    );
    return Uri.https(
      staticHost,
      '/pictograms/$pictogramId/${pictogramId}_$resolution.png',
    );
  }

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    // bestsearch is ARASAAC's curated answer for the whole phrase and is
    // usually both shorter and better ordered. The broad search is the
    // fallback for words it has no curated match for.
    var rows = await _getJsonList(
      searchUri(trimmed, locale: locale, best: true),
    );
    if (rows.isEmpty) {
      rows = await _getJsonList(searchUri(trimmed, locale: locale));
    }

    final refs = <SymbolRef>[];
    for (final row in rows) {
      final ref = _refFrom(row, trimmed);
      if (ref != null) refs.add(ref);
      if (refs.length >= limit) break;
    }
    return refs;
  }

  @override
  Future<String?> resolve(SymbolRef ref) async {
    if (ref.packId != id) return null;

    final file = await _fileFor(ref.externalId);
    if (file == null) return null;
    if (await file.exists()) {
      return await _usable(ref, file) ? file.path : null;
    }

    // Deliberately not awaited. Resolution runs while a grid is building and
    // a button must never wait on a network round trip to be pressable.
    unawaited(_queueDownload(ref, file));
    return null;
  }

  @override
  bool failedFor(SymbolRef ref) => _failed.contains(ref.externalId);

  void clearFailures() => _failed.clear();

  @override
  Future<void> dispose() async {
    await _available.close();
    _client.close();
  }

  SymbolRef? _refFrom(Object? row, String query) {
    if (row is! Map) return null;

    final pictogramId = row['_id'];
    if (pictogramId is! int) return null;

    final keywords = row['keywords'];
    final words = <String>[
      if (keywords is List)
        for (final entry in keywords)
          if (entry is Map && entry['keyword'] is String)
            entry['keyword'] as String,
    ];
    if (words.isEmpty) return null;

    // Prefer the keyword the user actually typed. A pictogram can carry half a
    // dozen synonyms and the first is not always the one being searched for.
    final needle = query.toLowerCase();
    final label = words.firstWhere(
      (w) => w.toLowerCase() == needle,
      orElse: () => words.first,
    );

    return (packId: id, externalId: '$pictogramId', label: label);
  }

  Future<List<dynamic>> _getJsonList(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode != 200) return const [];
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Application documents, never the cache directory. iOS and Android both
  /// evict caches under storage pressure without asking, and an AAC user whose
  /// symbols vanish mid-conversation has lost their voice, not a thumbnail.
  Future<File?> _fileFor(String pictogramId) async {
    try {
      final directory = await (_cachedDirectory ??= _documentsDirectory());
      return File(p.join(directory.path, 'symbols', id, '$pictogramId.png'));
    } catch (_) {
      _cachedDirectory = null;
      return null;
    }
  }

  /// Whether a file already on disk is one the renderer can read.
  ///
  /// Checked once per symbol per session, not per draw. Anything filed before
  /// §4.67 was written without this, so a device carries whatever it collected
  /// — and a bad file there throws on every attempt to draw it, forever. The
  /// only way out is to look at one, so this looks, deletes what cannot be
  /// drawn, and marks it failed like any other download that did not arrive.
  Future<bool> _usable(SymbolRef ref, File file) async {
    if (_checked.contains(ref.externalId)) return true;
    try {
      final bytes = await file.readAsBytes();
      if (looksDrawable(
        bytes,
        asSvg: file.path.toLowerCase().endsWith('.svg'),
      )) {
        _checked.add(ref.externalId);
        return true;
      }
      await file.delete();
    } catch (_) {
      // Unreadable is the same answer as undrawable, and neither is worth an
      // exception on the path a board draws itself on.
    }
    _failed.add(ref.externalId);
    return false;
  }

  Future<void> _queueDownload(SymbolRef ref, File target) {
    if (_failed.contains(ref.externalId)) return Future.value();
    // Single-flight: a grid with the same symbol on several boards, or a
    // rebuild mid-download, must issue one request rather than one per caller.
    return _inFlight.putIfAbsent(
      ref.externalId,
      () =>
          _download(
            ref,
            target,
            // A block body, and that is the whole fix. `_inFlight` holds futures, so
            // `remove` *returns* one — and an arrow body hands it back to
            // `whenComplete`, which then waits for it before completing. The future
            // it waits for is the one it is completing. Nothing downloaded ever
            // arrived at a caller that awaited it; `fetchNow` sat for twice the
            // request timeout and then reported failure for a file that was on the
            // device.
          ).whenComplete(() {
            _inFlight.remove(ref.externalId);
          }),
    );
  }

  Future<void> _download(SymbolRef ref, File target) async {
    try {
      final response = await _client
          .get(imageUri(ref.externalId))
          .timeout(requestTimeout);

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _failed.add(ref.externalId);
        return;
      }

      await target.parent.create(recursive: true);

      // What came back has to be an image before it is filed. A 200 is not
      // evidence of one: an error page, or a body cut short after the headers,
      // is written and renamed and then looks cached for the life of the
      // install, throwing on every draw (§4.67).
      if (!looksDrawable(
        response.bodyBytes,
        asSvg: target.path.toLowerCase().endsWith('.svg'),
      )) {
        _failed.add(ref.externalId);
        return;
      }

      // Write alongside and rename. A process killed mid-write must not leave
      // a truncated PNG behind, because that file would then look cached and
      // render as a broken image for good.
      final partial = File('${target.path}.part');
      await partial.writeAsBytes(response.bodyBytes, flush: true);
      await partial.rename(target.path);

      if (!_available.isClosed) _available.add(ref);
    } catch (_) {
      _failed.add(ref.externalId);
    }
  }
}
