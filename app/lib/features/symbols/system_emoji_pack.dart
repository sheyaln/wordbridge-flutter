import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'symbol_pack.dart';

/// The emoji the device can already draw, offered as symbols.
///
/// **Store the codepoint, never the picture.** Drawing an emoji character with
/// the platform's font is displaying text and redistributes nothing, which is
/// what makes this lawful. Apple Color Emoji and Segoe UI Emoji are
/// proprietary: their glyphs may not be extracted, rasterised to files,
/// bundled or shipped. So [resolve] answers with characters, never with a
/// path, and no code in this pack or downstream of it may write an image
/// derived from a system font. If a change here starts rendering into an image
/// buffer, that is the line.
///
/// What is bundled is a keyword index and nothing else — the operating system
/// exposes no searchable list of what it can draw, so without one a search box
/// has nothing to answer from. Names and search words come from Unicode CLDR,
/// under the Unicode license; see NOTICE.md and the manifest's own
/// attribution, which the symbol credits screen reads.
///
/// The trade this makes, stated where somebody will find it: the drawing is
/// not the same on another device, or after an operating system update. The
/// motor plan is the location rather than the picture, so it costs less than
/// it sounds, but a board exported elsewhere renders differently. It is a
/// per-device convenience, not a portable symbol set.
///
/// Nothing here touches the network, at any point, for any reason.
class SystemEmojiPack implements GlyphSymbolPack {
  SystemEmojiPack({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  /// Written into `symbols.pack_id`, so a stored choice finds its way back
  /// here on the next launch.
  static const packId = 'system-emoji';

  static const indexKey = 'assets/symbols/$packId/manifest.json';

  final AssetBundle _bundle;

  @override
  String get id => packId;

  @override
  String get name => 'Emoji from this device';

  /// The license of the index, which is the only thing this pack ships. The
  /// glyphs belong to whoever wrote the device's font and are not
  /// redistributed by anyone here.
  @override
  String get license => 'Unicode-3.0';

  @override
  String get attribution =>
      'Emoji names and search words from Unicode CLDR, © Unicode, Inc., '
      'under the Unicode License v3. The pictures are drawn by this device '
      'with its own emoji font and are not part of wordbridge.';

  @override
  bool get allowsCommercialUse => true;

  /// False, and it matters. No picture ships inside the binary — only the
  /// codepoints that ask the platform for one.
  @override
  bool get isBundled => false;

  Future<Map<String, EmojiEntry>>? _index;

  /// Memoised including the empty result, so a build without the asset costs
  /// one failed lookup per launch rather than one per keystroke.
  Future<Map<String, EmojiEntry>> index() => _index ??= _loadIndex();

  Future<Map<String, EmojiEntry>> _loadIndex() async {
    try {
      final decoded = json.decode(await _bundle.loadString(indexKey));
      if (decoded is! Map) return const {};

      final symbols = decoded['symbols'];
      if (symbols is! Map) return const {};

      return {
        for (final entry in symbols.entries)
          if (entry.key is String && entry.value is Map)
            if ((entry.value as Map)['name'] is String)
              entry.key as String: (
                name: ((entry.value as Map)['name'] as String)
                    .toLowerCase()
                    .trim(),
                keywords: [
                  for (final word in ((entry.value as Map)['keywords'] ?? []))
                    if (word is String) word.toLowerCase().trim(),
                ],
              ),
      };
    } catch (_) {
      // An index that will not parse is a pack with no emoji in it, which
      // costs a caregiver a search result. Throwing would cost somebody the
      // screen the search box is on.
      return const {};
    }
  }

  /// Emoji whose CLDR name or keywords match [query].
  ///
  /// Deliberately loose, and only ever shown to somebody who is looking. The
  /// buckets rank the name above the keywords because keywords are shared
  /// widely — "happy" is on two dozen faces, while "grinning face" is one
  /// emoji — and an exact name above a partial one, so searching "cat" leads
  /// with the cat rather than with "cat face" or "black cat".
  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty || limit <= 0) return const [];

    final entries = await index();
    if (entries.isEmpty) return const [];

    final exact = <SymbolRef>[];
    final namePrefix = <SymbolRef>[];
    final keywordExact = <SymbolRef>[];
    final nameSubstring = <SymbolRef>[];
    final keywordPrefix = <SymbolRef>[];

    for (final entry in entries.entries) {
      final emoji = entry.value;
      final ref = (packId: id, externalId: entry.key, label: emoji.name);

      if (emoji.name == needle) {
        exact.add(ref);
      } else if (emoji.name.startsWith(needle)) {
        namePrefix.add(ref);
      } else if (emoji.keywords.contains(needle)) {
        keywordExact.add(ref);
      } else if (emoji.name.contains(needle)) {
        nameSubstring.add(ref);
      } else if (emoji.keywords.any((word) => word.startsWith(needle))) {
        keywordPrefix.add(ref);
      }
    }

    return [
      ...exact,
      ...namePrefix,
      ...keywordExact,
      ...nameSubstring,
      ...keywordPrefix,
    ].take(limit).toList(growable: false);
  }

  /// The characters to draw, which is all a glyph pack has to give.
  ///
  /// The index is not consulted. It answers what exists to be searched for; a
  /// picture somebody already chose has to keep being drawn even after the
  /// index it was found through is regenerated without it.
  @override
  Future<String?> resolve(SymbolRef ref) async {
    if (ref.packId != id) return null;
    return charactersFor(ref.externalId);
  }

  /// `1f469-200d-1f373` as the characters it names, or null if it names none.
  static String? charactersFor(String codepoints) {
    final parts = codepoints.trim().split('-');
    if (parts.isEmpty || codepoints.trim().isEmpty) return null;

    final runes = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part, radix: 16);
      if (value == null || value < 0 || value > 0x10ffff) return null;

      // A lone surrogate is half a character. Left in, it builds a string
      // that no font can draw and that some platforms refuse to encode.
      if (value >= 0xd800 && value <= 0xdfff) return null;

      runes.add(value);
    }

    return String.fromCharCodes(runes);
  }
}

typedef EmojiEntry = ({String name, List<String> keywords});
