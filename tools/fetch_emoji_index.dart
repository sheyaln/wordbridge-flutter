// Builds the searchable index behind the device-emoji symbol pack.
//
// The pack draws emoji with whatever font the operating system provides, so
// nothing here fetches, converts, or writes a picture — and nothing here ever
// may. Apple Color Emoji and Segoe UI Emoji are proprietary: rasterizing a
// glyph to a file would put their artwork in the repository. **This tool
// writes codepoints and words, and no image byte of any kind.**
//
// What it does write is the part the OS does not expose: a list of which
// emoji exist and what words find them. Unicode CLDR carries that, under the
// Unicode license, which permits redistribution with the notice kept — see
// NOTICE.md.
//
//   dart run tools/fetch_emoji_index.dart
//
// Output is committed to the repo, the same way tools/fetch_symbols.dart
// commits the core pack.

import 'dart:convert';
import 'dart:io';

const _outDir = 'app/assets/symbols/system-emoji';

/// A ceiling on any single request, so one unanswered call cannot stall the
/// run behind it.
const _requestTimeout = Duration(seconds: 60);

/// The CLDR release the committed index was built from, pinned rather than
/// tracking `main`: a generated file that changes because upstream moved is a
/// diff nobody asked for and cannot review.
const _cldrRelease = '48.2.0';

/// Which emoji may go in the index.
///
/// A codepoint the device's font has never heard of draws as a missing-glyph
/// box, and a box on a button is exactly the broken picture an AAC user must
/// never be shown. Emoji 13.1 is from 2020 and is present on every platform
/// version this app builds for; newer sets add little a picker needs. Raising
/// it is a deliberate trade of coverage for that guarantee, not a routine
/// bump.
const _emojiVersion = '13.1';

/// Keywords kept per emoji, after those already in the name are dropped.
///
/// CLDR gives up to fifteen for some entries. The tail is synonyms of
/// synonyms; carrying all of them triples the index for search results nobody
/// scrolls to.
const _maxKeywords = 6;

Future<void> main() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 10);

  try {
    stdout.writeln('emoji $_emojiVersion + CLDR $_cldrRelease\n');

    final sequences = _fullyQualified(
      await _get(
        client,
        Uri.https('unicode.org', '/Public/emoji/$_emojiVersion/emoji-test.txt'),
      ),
    );
    stdout.writeln('${sequences.length} fully-qualified emoji sequences');

    final annotations = _annotations(
      await _get(
        client,
        Uri.https(
          'raw.githubusercontent.com',
          [
            'unicode-org/cldr-json',
            _cldrRelease,
            'cldr-json/cldr-annotations-full/annotations/en/annotations.json',
          ].join('/'),
        ),
      ),
    );
    stdout.writeln('${annotations.length} CLDR annotations');

    // In emoji-test.txt order, which is the order Unicode groups them in and
    // therefore the order a person expects to meet them in.
    final symbols = <String, Map<String, Object>>{};
    for (final sequence in sequences) {
      final annotation = annotations[_withoutVariationSelectors(sequence)];
      if (annotation == null) continue;

      // First wins. A sequence and its unqualified twin share an annotation,
      // and two rows drawing the same character is a duplicate in the picker.
      symbols.putIfAbsent(
        _codepoints(sequence),
        () => {
          'name': annotation.name,
          if (annotation.keywords.isNotEmpty) 'keywords': annotation.keywords,
        },
      );
    }

    // Everything CLDR annotates that is not an emoji — braces, digits, the
    // skin-tone modifiers on their own — falls out here, because it is absent
    // from emoji-test.txt.
    final unmatched = annotations.length - symbols.length;

    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'pack': 'system-emoji',
        'name': 'Emoji from this device',
        'license': 'Unicode-3.0',
        'allows_commercial_use': true,
        'emoji_version': _emojiVersion,
        'cldr_version': _cldrRelease,
        'source': 'https://github.com/unicode-org/cldr-json',
        'attributions': {
          'cldr':
              'Emoji names and search words from Unicode CLDR '
              '$_cldrRelease. Copyright © 1991-2026 Unicode, Inc. '
              'Distributed under the Unicode License v3 '
              '(https://www.unicode.org/license.txt). The pictures are drawn '
              'by this device using its own emoji font, and no part of that '
              'font is copied, stored, or shipped by wordbridge.',
        },
        'symbols': symbols,
      }),
    );

    final bytes = File('$_outDir/manifest.json').lengthSync();
    stdout.writeln(
      '\n${symbols.length} emoji -> $_outDir/manifest.json '
      '(${(bytes / 1024).round()} KB)',
    );
    stdout.writeln('$unmatched annotated characters are not emoji — skipped');
  } finally {
    client.close();
  }
}

typedef _Annotation = ({String name, List<String> keywords});

/// Every fully-qualified sequence in `emoji-test.txt`, in file order.
///
/// Fully-qualified only, because that is the form with its variation
/// selectors in place — the form a font is obliged to draw in color rather
/// than as monochrome text.
List<String> _fullyQualified(String source) {
  final out = <String>[];

  for (final line in const LineSplitter().convert(source)) {
    final content = line.split('#').first.trim();
    if (content.isEmpty) continue;

    final fields = content.split(';');
    if (fields.length != 2 || fields[1].trim() != 'fully-qualified') continue;

    out.add(
      String.fromCharCodes([
        for (final hex in fields[0].trim().split(RegExp(r'\s+')))
          int.parse(hex, radix: 16),
      ]),
    );
  }

  return out;
}

/// CLDR annotations keyed by character sequence.
///
/// `tts` is the name a screen reader speaks and is the label a button gets;
/// `default` is the search vocabulary.
Map<String, _Annotation> _annotations(String source) {
  final decoded = jsonDecode(source);
  final entries =
      (decoded as Map)['annotations']['annotations'] as Map<String, dynamic>;

  final out = <String, _Annotation>{};
  for (final entry in entries.entries) {
    final value = entry.value as Map<String, dynamic>;
    final tts = value['tts'];
    if (tts is! List || tts.isEmpty) continue;

    final name = (tts.first as String).toLowerCase().trim();
    if (name.isEmpty) continue;

    // A keyword the name already contains buys nothing: the name is searched
    // too, so "grinning" alongside "grinning face" is a byte cost with no
    // additional query answered.
    final inName = name.split(RegExp(r'\s+')).toSet();
    final raw = value['default'];
    final keywords = <String>[
      if (raw is List)
        for (final word in raw.cast<String>())
          if (!inName.contains(word.toLowerCase().trim()))
            word.toLowerCase().trim(),
    ];

    out[_withoutVariationSelectors(entry.key)] = (
      name: name,
      keywords: keywords.take(_maxKeywords).toList(),
    );
  }

  return out;
}

/// CLDR keys omit U+FE0F where emoji-test.txt carries it, so one side has to
/// be normalized before the two can be joined.
String _withoutVariationSelectors(String sequence) =>
    sequence.replaceAll('️', '');

/// `1f469-200d-1f373`. The stored form of an emoji, and the only form of it
/// this project ever stores.
String _codepoints(String sequence) =>
    sequence.runes.map((r) => r.toRadixString(16)).join('-');

Future<String> _get(HttpClient client, Uri uri) async {
  stdout.writeln('fetching $uri');
  final res = await (await client.getUrl(uri)).close().timeout(_requestTimeout);

  if (res.statusCode != 200) {
    // Drained before throwing: an unread response holds its socket open.
    await res.drain<void>();
    throw HttpException('HTTP ${res.statusCode} from $uri');
  }

  return res.transform(utf8.decoder).join().timeout(_requestTimeout);
}
