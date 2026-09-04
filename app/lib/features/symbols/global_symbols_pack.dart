import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'drawable.dart';
import 'symbol_pack.dart';

/// Symbol sets fetched on demand from Global Symbols.
///
/// The same sets and the same source the offline bundler uses, reachable at
/// runtime so a caregiver adding a word does not have to wait for a release to
/// get a picture for it.
///
/// **Two packs, one class, and the licence is what separates them.** The
/// default constructor reaches [commercialSets] — all CC BY-SA: attribution
/// and share-alike, commercial use permitted — and is on by default.
/// [GlobalSymbolsPack.nonCommercial] reaches [nonCommercialSets] and is off
/// until somebody turns it on, because non-commercial is not an open-source
/// licence and it contaminates every path by which this app could be sold or
/// shipped on hardware. ARASAAC and Sclera stay behind their own opt-in pack
/// for the same reason.
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
  /// The commercially-clean pack: bundled-quality sets, on by default.
  GlobalSymbolsPack({
    http.Client? client,
    Future<Directory> Function()? documentsDirectory,
    this.requestTimeout = const Duration(seconds: 6),
    this.searchTimeout = const Duration(seconds: 3),
  }) : id = 'globalsymbols',
       name = 'More pictures',
       license = 'CC-BY-SA-4.0',
       allowsCommercialUse = true,
       sets = commercialSets,
       _client = client ?? http.Client(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  /// The non-commercial pack: same source, same code, different licence and
  /// therefore a different answer about whether it may be used at all.
  ///
  /// Off until somebody says otherwise, and that is not a policy this class
  /// enforces — [SymbolRegistry.isEnabled] falls back to
  /// [allowsCommercialUse] for any pack nobody has answered about, so a pack
  /// added in a release arrives correctly off without anybody migrating a
  /// stored settings map.
  ///
  /// A separate pack rather than more entries in [commercialSets], because the
  /// licence attaches to the pack and a fork that is sold has to be able to
  /// delete this one whole.
  GlobalSymbolsPack.nonCommercial({
    http.Client? client,
    Future<Directory> Function()? documentsDirectory,
    this.requestTimeout = const Duration(seconds: 6),
    this.searchTimeout = const Duration(seconds: 3),
  }) : id = 'globalsymbols-nc',
       name = 'More pictures (non-commercial)',
       license = 'CC-BY-NC-SA-4.0',
       allowsCommercialUse = false,
       sets = nonCommercialSets,
       _client = client ?? http.Client(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  static const host = 'globalsymbols.com';

  /// In preference order. Mulberry leads because it is a purpose-built AAC set
  /// with a consistent drawn style, and its own two extension sets follow it
  /// because they are drawn to match; the rest fill its gaps in abstract core
  /// vocabulary. Mixing styles costs visual consistency, and a blank button
  /// costs more.
  static const commercialSets =
      <({String slug, String name, String attribution})>[
        (
          slug: 'mulberry',
          name: 'Mulberry Symbols',
          attribution:
              'Mulberry Symbols © Garry Paxton 2008-2017, Steve Lee 2018-. '
              'CC BY-SA 4.0. https://mulberrysymbols.org',
        ),
        (
          slug: 'corona-symbols',
          name: 'Mulberry Plus Collection',
          attribution:
              'Mulberry Plus Collection © Mulberry and Global Symbols. '
              'CC BY-SA 4.0. https://globalsymbols.com',
        ),
        (
          slug: 'additional-mulberry-symbols',
          name: 'Mulberry Additional Symbols',
          attribution:
              'Mulberry Additional Symbols © Verlag Karin Kestner GmbH. '
              'CC BY-SA 4.0. https://www.kestner.de',
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

  /// Sets that may not be bundled, sold, or shipped on hardware that is sold.
  ///
  /// Kept apart from [commercialSets] rather than flagged inside it. A list
  /// where the licence is a field is a list somebody filters wrong once; two
  /// lists cannot be got wrong by forgetting to look.
  static const nonCommercialSets =
      <({String slug, String name, String attribution})>[
        (
          slug: 'aac-image-library',
          name: 'AAC Image Library',
          attribution:
              'AAC Image Library © AAC Image Library. CC BY-NC-SA 4.0. '
              'https://aacil.neocities.org',
        ),
      ];

  final http.Client _client;
  final Future<Directory> Function() _documentsDirectory;
  final Duration requestTimeout;

  /// What one set gets to answer a search in, and deliberately much shorter
  /// than [requestTimeout] and shorter still than [SymbolRegistry.searchBudget].
  ///
  /// Every set is asked at once and `Future.wait` waits for the slowest, so one
  /// set that hangs used to hold the whole pack for the full request timeout —
  /// past the registry's budget, which then threw away every set that had
  /// already answered. The pack contributed nothing to the picker at all, and
  /// silently, because a budget overrun is caught and read as "no results".
  /// Bounded here, a slow set drops out on its own and the others still count.
  final Duration searchTimeout;

  final _available = StreamController<SymbolRef>.broadcast();
  final _inFlight = <String, Future<void>>{};
  final _failed = <String>{};

  /// Symbols whose cached file has been looked at and can be drawn.
  final _checked = <String>{};
  final _urls = <String, String>{};

  Future<Directory>? _cachedDirectory;

  /// What the symbol directory held when it was last listed, by external id.
  Map<String, File>? _cachedOnDisk;

  @override
  final String id;

  @override
  final String name;

  @override
  final String license;

  @override
  final bool allowsCommercialUse;

  /// Which sets this pack reaches, in preference order.
  final List<({String slug, String name, String attribution})> sets;

  @override
  String get attribution => [
    for (final set in sets) set.attribution,
    'Fetched through Global Symbols (https://globalsymbols.com).',
  ].join('\n');

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

  /// The most any one set is asked for in a single search.
  ///
  /// A ceiling on how much of one search a set can be asked to carry, not a
  /// property of the API, which accepts more.
  static const maxSetResults = 60;

  /// Candidates for a person to choose from, best sets first.
  ///
  /// Loose on purpose. Nothing here is assigned to a button without somebody
  /// looking at it.
  ///
  /// **Every set is asked, at once, for as much as the caller wanted.** This
  /// used to send a fixed twelve whatever it was asked for and then walk the
  /// sets in order until the budget ran out, which had two results a person
  /// searching could see: a set with forty pictures of a word offered twelve,
  /// and the sets after the first generous one were never reached at all.
  /// Their pictures existed, were licensed, were listed on the set-filter
  /// chips — and could not be found by searching for them.
  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    final depth = limit.clamp(1, maxSetResults);
    final answers = await Future.wait([
      for (final set in sets) _labels(trimmed, set.slug, limit: depth),
    ]);

    return fairMerge([
      for (final entries in answers)
        [
          // Every entry is turned into a ref, including ones the merge will
          // drop: that is what records the URL each one is downloadable from,
          // and a result the caller pages past today may be chosen tomorrow.
          for (final entry in entries) ?_refFrom(entry),
        ],
    ], limit);
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

    final held = await _held(ref);
    if (held != null) return await _usable(ref, held) ? held.path : null;

    final target = await _targetFor(ref);
    if (target == null) return null;

    // Not awaited. Resolution runs while a grid is building, and a button must
    // never wait on a network round trip to be pressable.
    unawaited(_queueDownload(ref, target));
    return null;
  }

  /// Downloads now and reports whether the image is on disk.
  ///
  /// Used where a caregiver has just chosen a picture and is waiting to see
  /// it, which is the one moment blocking on the network is the right thing.
  Future<bool> fetchNow(SymbolRef ref) async {
    final held = await _held(ref);
    if (held != null) return _usable(ref, held);

    final target = await _targetFor(ref);
    if (target == null) return false;

    _failed.remove(ref.externalId);
    try {
      // A ceiling, not an open wait. Somebody is looking at a spinner, and a
      // slow network should give them the choice back rather than hold the
      // sheet open indefinitely.
      await _queueDownload(ref, target).timeout(requestTimeout * 2);
    } catch (_) {
      return false;
    }
    return target.exists();
  }

  @override
  bool failedFor(SymbolRef ref) => _failed.contains(ref.externalId);

  void clearFailures() => _failed.clear();

  @override
  Future<void> dispose() async {
    await _available.close();
    _client.close();
  }

  Future<List<Map<String, dynamic>>> _labels(
    String query,
    String setSlug, {
    int limit = 12,
  }) async {
    try {
      final response = await _client
          .get(searchUri(query, setSlug, limit: limit))
          .timeout(searchTimeout);
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
  Future<Directory?> _directory() async {
    try {
      final documents = await (_cachedDirectory ??= _documentsDirectory());
      return Directory(p.join(documents.path, 'symbols', id));
    } catch (_) {
      _cachedDirectory = null;
      return null;
    }
  }

  /// The file this device already holds for [ref], whatever it is called.
  ///
  /// Found by listing rather than by constructing a name, because the name
  /// cannot be constructed: a symbol's extension is whatever the source served
  /// it as, and the only record of that is the URL a search returned — which
  /// lives in memory and is gone at the next launch. Building a name anyway
  /// meant every downloaded PNG stopped being found the moment the app
  /// restarted, and was then re-fetched or, with no URL to fetch from, marked
  /// unavailable.
  ///
  /// One listing per session answers for every symbol on every board.
  Future<File?> _held(SymbolRef ref) async => (await _onDisk())[ref.externalId];

  Future<Map<String, File>> _onDisk() async {
    final held = _cachedOnDisk;
    if (held != null) return held;

    final found = <String, File>{};
    try {
      final directory = await _directory();
      if (directory != null && directory.existsSync()) {
        for (final entry in directory.listSync().whereType<File>()) {
          final name = p.basenameWithoutExtension(entry.path);
          // Partial downloads are named `<id>.<ext>.part`, which leaves the
          // extension as the stem and would file them under the symbol's name.
          if (p.extension(entry.path) == '.part') continue;
          found.putIfAbsent(name, () => entry);
        }
      }
    } catch (_) {
      // An unreadable directory is a device with no cached symbols, which is
      // where every install starts.
    }
    return _cachedOnDisk = found;
  }

  /// Where a symbol that is not held yet would be written.
  ///
  /// Null where the URL is unknown, which is the honest answer: without it
  /// there is nothing to download and no way to know what to call the result.
  Future<File?> _targetFor(SymbolRef ref) async {
    final url = _urls[ref.externalId];
    if (url == null) return null;

    final directory = await _directory();
    if (directory == null) return null;

    return File(
      p.join(directory.path, '${ref.externalId}.${_extensionOf(url)}'),
    );
  }

  /// The extension the server is actually serving, not a guess between two.
  ///
  /// Some sets scanned their symbols and serve `jpg`. Every one of those was
  /// filed as `.svg` — the only question asked was "does the URL end in png" —
  /// and then failed the check that the bytes are drawable as SVG, so it was
  /// marked unavailable and never drew. The picker showed it as "Did not
  /// load", permanently, for a picture that was on the device the whole time.
  static String _extensionOf(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    final extension = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return _drawableExtensions.contains(extension) ? extension : 'svg';
  }

  /// Extensions the renderer can read. Anything else is not a picture, and
  /// treating an unrecognized URL as SVG is what this did before.
  static const _drawableExtensions = {
    'svg',
    'png',
    'jpg',
    'jpeg',
    'gif',
    'bmp',
    'webp',
  };

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
      _cachedOnDisk?.remove(ref.externalId);
    } catch (_) {
      // Unreadable is the same answer as undrawable, and neither is worth an
      // exception on the path a board draws itself on.
    }
    _failed.add(ref.externalId);
    return false;
  }

  Future<void> _queueDownload(SymbolRef ref, File target) {
    if (_failed.contains(ref.externalId)) return Future.value();
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
      // a truncated file behind, because it would then look cached and render
      // as a broken image for good.
      final partial = File('${target.path}.part');
      await partial.writeAsBytes(response.bodyBytes, flush: true);
      await partial.rename(target.path);
      _cachedOnDisk?[ref.externalId] = target;

      if (!_available.isClosed) _available.add(ref);
    } catch (_) {
      _failed.add(ref.externalId);
    }
  }

  static String _normalize(String? text) =>
      (text ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
}
