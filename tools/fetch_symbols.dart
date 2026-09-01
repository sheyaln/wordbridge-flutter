// Downloads Mulberry symbols for the shipped vocabulary and writes a bundle.
//
// Mulberry is CC BY-SA 4.0 — attribution and share-alike, but commercial use
// is permitted, which is why it is the bundled default rather than ARASAAC.
// See NOTICE.md.
//
//   dart run tools/fetch_symbols.dart
//
// Output is committed to the repo. Re-run only to add words; the manifest is
// the record of what a build actually shipped.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

const _language = 'eng';
const _outDir = 'app/assets/symbols/core';

/// A ceiling on any single request, so one unanswered call cannot stall a run
/// of several hundred behind it.
const _requestTimeout = Duration(seconds: 25);

/// Symbol sets to draw from, in preference order. **Every one must permit
/// commercial use** — see NOTICE.md. ARASAAC and Sclera are excluded on
/// purpose: they are CC BY-NC and may only ever be opt-in downloads.
///
/// Mulberry leads because it is a purpose-built AAC set with a consistent
/// drawn style. It is strong on concrete nouns and weak on abstract core
/// vocabulary — its 3,436 symbols contain no "stop", "you", "not" or "want" —
/// so later entries fill those gaps. Mixing styles is a real cost to visual
/// consistency, but a pre-literate user faced with a blank button pays more.
const _sets = <({String slug, int id, String name, String attribution})>[
  (
    slug: 'mulberry',
    id: 13,
    name: 'Mulberry Symbols',
    attribution:
        'Mulberry Symbols © Garry Paxton 2008-2017, Steve Lee 2018-. '
        'CC BY-SA 4.0. https://mulberrysymbols.org',
  ),
  (
    slug: 'stellar-symbols',
    id: 133,
    name: 'Stellar Symbols',
    attribution: 'Stellar Symbols © Colin McNamee. CC BY-SA 4.0.',
  ),
  (
    slug: 'tawasol',
    id: 15,
    name: 'Tawasol',
    attribution: 'Tawasol Symbols © Mada, Qatar. CC BY-SA 4.0. http://tawasolsymbols.org',
  ),
  (
    slug: 'openmoji',
    id: 83,
    name: 'OpenMoji',
    attribution:
        'OpenMoji © OpenMoji Project. CC BY-SA 4.0. https://openmoji.org',
  ),
];

/// Words to look for, read from a file of one label per line.
///
/// Generated from the vocabulary itself rather than kept here, because a
/// second copy of the word list drifts and the drift is invisible — words ship
/// without a picture and nobody notices:
///
///   cd app && dart run tool/vocabulary_words.dart > /tmp/wordbridge-words.txt
///   dart run tools/fetch_symbols.dart /tmp/wordbridge-words.txt
List<String> _wordsFrom(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln(
      'No word list at $path.\n\n'
      'Generate one first:\n'
      '  cd app && dart run tool/vocabulary_words.dart > $path',
    );
    exit(2);
  }

  return [
    for (final line in file.readAsLinesSync())
      if (line.trim().isNotEmpty) line.trim(),
  ];
}

/// Alternative search terms, tried in order, for words whose own label is not
/// how Mulberry names the concept.
///
/// Every candidate must still be a genuine synonym. Where none matches
/// exactly the button renders label-only, which is the correct outcome — a
/// blank button honestly says "no picture yet", whereas a plausible-looking
/// wrong one teaches a false association to someone who cannot easily
/// contradict it.
const _searchCandidates = <String, List<String>>{
  'I': ['I', 'me'],
  'people': ['people', 'person'],
  'he': ['he', 'boy', 'man'],
  // A girl/woman image for a third-person pronoun is standard AAC practice,
  // not a loose match.
  'she': ['she', 'her', 'girl', 'woman'],
  'you': ['you'],
  'all': ['all', 'everything', 'every'],
  'different': ['different', 'difference', 'other'],
  'finished': ['finished', 'finish', 'done', 'end'],
  'home': ['home', 'house'],
  'can': ['can', 'able'],
  // British labels that the sets index under other names. Every one of these
  // is the same referent, not a near-enough guess.
  'mum': ['mum', 'mother', 'mummy', 'mom'],
  'dad': ['dad', 'father', 'daddy'],
  'everybody': ['everybody', 'everyone'],
  'nobody': ['nobody', 'no one', 'none'],
  'biscuit': ['biscuit', 'cookie'],
  'bathroom': ['bathroom', 'toilet', 'washroom'],
  'garden': ['garden', 'yard'],
  'blocks': ['blocks', 'bricks', 'building blocks'],
  'puzzle': ['puzzle', 'jigsaw'],
  'toy': ['toy', 'toys'],
  'snack': ['snack', 'snacks'],
  // Object pronouns take the same treatment as "she": a picture of a person is
  // standard AAC practice for a third-person pronoun, not a loose match.
  'him': ['him', 'he', 'boy', 'man'],
  'her': ['her', 'she', 'girl', 'woman'],
  'them': ['them', 'they'],
  'me': ['me', 'I'],
  'my': ['my', 'mine'],
  // "don't" is the imperative negator, which these sets index unabbreviated.
  "don't": ["don't", 'do not', 'dont'],
  "I don't know": ["I don't know", 'I do not know', 'do not know'],
  "I don't understand": ["I don't understand", 'do not understand'],
  'hello': ['hello', 'hi'],
  'bye': ['bye', 'goodbye', 'bye bye'],
  'thank you': ['thank you', 'thanks'],
  // British nursery words for the same referents.
  'wee': ['wee', 'urine', 'pee'],
  'poo': ['poo', 'poop', 'faeces'],
  'toilet': ['toilet', 'lavatory', 'wc'],
  'medication': ['medication', 'medicine'],
  'allergic': ['allergic', 'allergy'],
  'wheelchair': ['wheelchair', 'wheel chair'],
  'glasses': ['glasses', 'spectacles'],
  'headphones': ['headphones', 'headphone'],
  'video call': ['video call', 'videocall'],
  'support worker': ['support worker', 'carer', 'helper'],
  'it hurts': ['it hurts', 'hurt', 'pain'],
  'yoghurt': ['yoghurt', 'yogurt'],
};

Future<void> main(List<String> args) async {
  final words = _wordsFrom(
    args.isEmpty ? '/tmp/wordbridge-words.txt' : args.first,
  );
  stdout.writeln('${words.length} words in the vocabulary\n');

  // A hard ceiling on sockets, so a connection this tool fails to release
  // shows up as a stall it can time out of rather than one it waits in
  // forever.
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 10)
    ..maxConnectionsPerHost = 4;
  final dir = Directory(_outDir)..createSync(recursive: true);

  // Resume rather than restart. A run is ~600 requests, and a transient
  // failure partway through used to be indistinguishable from a word that
  // genuinely has no symbol — which is how "car" and "bus" ended up filed as
  // missing when both exist upstream.
  final manifest = <String, Map<String, dynamic>>{};
  final existing = File('${dir.path}/manifest.json');
  if (existing.existsSync()) {
    final decoded = jsonDecode(existing.readAsStringSync());
    final symbols = decoded is Map ? decoded['symbols'] : null;
    if (symbols is Map) {
      for (final e in symbols.entries) {
        manifest[e.key as String] = Map<String, dynamic>.from(e.value as Map);
      }
    }
    stdout.writeln(
      'resuming with ${manifest.length} symbols already fetched\n',
    );
  }

  // Every run resolves the stylesheets of everything already on disk, not only
  // what it is about to fetch. Idempotent, and it means a fix to the resolver
  // reaches the symbols that shipped before it existed.
  var restyled = 0;
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.svg')) continue;
    final before = file.readAsStringSync();
    if (!before.contains('<style')) continue;
    _writeSymbol(file, utf8.encode(before), 'svg');
    restyled++;
  }
  if (restyled > 0) {
    stdout.writeln('resolved the stylesheets of $restyled symbols\n');
  }

  // Two different outcomes, kept apart. A word no set indexes is an answer
  // and its button renders label-only. A word whose lookup failed is not an
  // answer at all, and the next run should ask again — which it will, because
  // only successes reach the manifest.
  final missing = <String>[];
  final failed = <String>[];
  final usedSets = <String>{
    for (final v in manifest.values) v['set'] as String,
  };

  for (final word in words) {
    if (manifest.containsKey(word.toLowerCase())) continue;
    final candidates = _searchCandidates[word] ?? [word];
    stdout.write('${word.padRight(12)} ');

    try {
      _Hit? hit;
      for (final set in _sets) {
        for (final query in candidates) {
          hit = await _search(client, query, set);
          if (hit != null) break;
        }
        if (hit != null) break;
      }

      if (hit == null) {
        stdout.writeln('no exact match in any set — label-only');
        missing.add(word);
        continue;
      }

      final ext = hit.format == 'svg' ? 'svg' : 'png';
      final filename = '${_slug(word)}.$ext';
      final bytes = await _download(client, hit.imageUrl);

      _writeSymbol(File('${dir.path}/$filename'), bytes, ext);
      usedSets.add(hit.setSlug);

      manifest[word.toLowerCase()] = {
        'file': filename,
        'set': hit.setSlug,
        'picto_id': hit.pictoId,
        'matched': hit.text,
        'part_of_speech': hit.partOfSpeech,
      };
      stdout.writeln('${hit.setSlug.padRight(16)} ${hit.text}');
    } catch (e) {
      stdout.writeln('failed: $e');
      failed.add(word);
    }
  }

  File('${dir.path}/manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'pack': 'core',
      'name': 'wordbridge core symbols',
      'license': 'CC-BY-SA-4.0',
      'allows_commercial_use': true,
      'source': 'https://globalsymbols.com',
      'attributions': {
        for (final s in _sets)
          if (usedSets.contains(s.slug)) s.slug: s.attribution,
      },
      'symbols': manifest,
    }),
  );

  client.close();

  stdout.writeln('\n${manifest.length} symbols -> ${dir.path}');
  if (missing.isNotEmpty) {
    stdout.writeln('\nno symbol in any set for: ${missing.join(', ')}');
    stdout.writeln('those buttons render label-only, which is fine.');
  }
  if (failed.isNotEmpty) {
    stdout.writeln('\nlookup failed for: ${failed.join(', ')}');
    stdout.writeln('not an answer — run again to ask about these.');
  }
}

typedef _Hit = ({
  int pictoId,
  String text,
  String imageUrl,
  String format,
  String? partOfSpeech,
  String setSlug,
});

/// Raised for a 429, so it can be backed off from differently.
///
/// Being told to slow down is not a network failure and is not an answer
/// about the word. It is the one error worth waiting a long time over.
class _RateLimited implements Exception {
  const _RateLimited(this.retryAfter);

  /// What the server asked for, when it said.
  final Duration? retryAfter;

  @override
  String toString() =>
      'rate limited${retryAfter == null ? '' : ', '
                'asked to wait ${retryAfter!.inSeconds}s'}';
}

/// Retries around network flakiness and rate limiting.
///
/// Distinguishing "this set has no such word" from "the request failed" is
/// the whole point: the first is a real answer, the second is noise that must
/// not be recorded as one. Recording a 429 as "no symbol" is how a word that
/// has a perfectly good picture ends up shipping blank.
Future<_Hit?> _search(
  HttpClient client,
  String query,
  ({String slug, int id, String name, String attribution}) set,
) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      await _throttle();
      return await _searchOnce(client, query, set);
    } on _RateLimited catch (e) {
      if (attempt == 3) rethrow;
      // Long waits, because the server has said in as many words that it is
      // being asked too often. Honor what it asked for when it says.
      await Future<void>.delayed(
        e.retryAfter ?? Duration(seconds: 5 * (attempt + 1)),
      );
    } on Object {
      if (attempt == 3) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }
  return null;
}

/// Keeps a polite distance between requests.
///
/// A run is several hundred lookups against somebody else\'s free service. Not
/// pacing them gets this tool rate limited, which is both rude and — until the
/// 429 was being read as an answer — silently wrong.
DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

Future<void> _throttle() async {
  const gap = Duration(milliseconds: 350);
  final since = DateTime.now().difference(_lastRequest);
  if (since < gap) await Future<void>.delayed(gap - since);
  _lastRequest = DateTime.now();
}

Future<_Hit?> _searchOnce(
  HttpClient client,
  String query,
  ({String slug, int id, String name, String attribution}) set,
) async {
  final uri = Uri.https('globalsymbols.com', '/api/v1/labels/search', {
    'query': query,
    'symbolset': set.slug,
    'language': _language,
    'limit': '10',
  });

  final res = await (await client.getUrl(uri)).close().timeout(_requestTimeout);

  // A refusal is not an answer. The API returns 200 with an empty list when a
  // set genuinely has no such word, so any other status is the server saying
  // "not now" — usually rate limiting. Throwing sends it back through the
  // retry, where a "no symbol for" line is what it deserves only if it still
  // fails three times.
  //
  // The body is drained first either way. An unread response holds its socket
  // open, and enough of them exhaust the connection pool and wedge the run.
  if (res.statusCode != 200) {
    await res.drain<void>();

    if (res.statusCode == 429) {
      final header = res.headers.value('retry-after');
      final seconds = header == null ? null : int.tryParse(header.trim());
      throw _RateLimited(seconds == null ? null : Duration(seconds: seconds));
    }

    throw HttpException('${res.statusCode} from ${set.slug} for "$query"');
  }

  final body = jsonDecode(
    await res.transform(utf8.decoder).join().timeout(_requestTimeout),
  );
  if (body is! List || body.isEmpty) return null;

  // Exact matches only, and no fallback to the top-ranked result.
  //
  // The search is a substring match over labels, so "all" returns Ball, "not"
  // returns Notebook, "she" returns Sheep. Accepting a near-miss would teach
  // an AAC user that a word means whatever the picture shows — a wrong symbol
  // is worse than none, and a blank button honestly says "no picture yet".
  Map<String, dynamic>? exact;
  for (final entry in body.cast<Map<String, dynamic>>()) {
    if (_normalise(entry['text'] as String?) == _normalise(query)) {
      exact = entry;
      break;
    }
  }
  if (exact == null) return null;

  final picto = exact['picto'];
  if (picto == null || picto['symbolset_id'] != set.id) return null;

  return (
    pictoId: picto['id'] as int,
    text: exact['text'] as String,
    imageUrl: picto['image_url'] as String,
    format: (picto['native_format'] as String?) ?? 'svg',
    partOfSpeech: picto['part_of_speech'] as String?,
    setSlug: set.slug,
  );
}

Future<List<int>> _download(HttpClient client, String url) async {
  await _throttle();

  final res = await (await client.getUrl(Uri.parse(url)))
      .close()
      .timeout(_requestTimeout);

  if (res.statusCode != 200) {
    // Drained before throwing. An unread response holds its socket open.
    await res.drain<void>();
    throw HttpException('HTTP ${res.statusCode}');
  }

  return (await res
          .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
          .timeout(_requestTimeout))
      .takeBytes();
}

/// Writes a symbol, with its stylesheet resolved into the shapes it styles.
///
/// The renderer this app uses does not read `<style>` blocks. Several sets
/// draw entirely through CSS classes and carry no `fill` attributes at all, so
/// left alone those symbols arrive as black silhouettes — legible as shapes,
/// wrong as pictures, and invisible where the class said white.
///
/// Resolving it here rather than at render time means what ships is what is
/// seen, and no device has to be able to parse CSS to show a word.
void _writeSymbol(File file, List<int> bytes, String extension) {
  if (extension != 'svg') {
    file.writeAsBytesSync(bytes);
    return;
  }

  final source = utf8.decode(bytes, allowMalformed: true);
  final inlined = _inlineStyles(source);

  if (inlined.contains('<style')) {
    // Loud rather than quiet. A stylesheet this cannot resolve is a picture
    // that will render wrong, and the whole point of bundling is knowing what
    // shipped.
    stderr.writeln(
      '\n  ! ${file.path} keeps a stylesheet that could not be resolved. '
      'It will render without its colors.',
    );
  }

  file.writeAsStringSync(inlined);
}

/// Turns `.st0{fill:#fff}` plus `class="st0"` into `fill="#fff"`.
///
/// Only class selectors are handled, because that is all these sets use. A
/// stylesheet containing anything else is left in place for the caller to
/// complain about rather than half-applied — a partly-styled symbol is harder
/// to notice than an unstyled one.
String _inlineStyles(String svg) {
  final styleBlock = RegExp(
    r'<style[^>]*>(.*?)</style\s*>',
    dotAll: true,
    caseSensitive: false,
  );
  final match = styleBlock.firstMatch(svg);
  if (match == null) return svg;

  var css = match.group(1)!;
  css = css.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
  css = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  // At-rules go, and `@font-face` is why. Sets sometimes embed an entire
  // base64 typeface to letter one word — half a megabyte for a symbol, in a
  // form the renderer cannot use either way. The text falls back to a system
  // font, which is what it would have done regardless.
  css = css.replaceAll(RegExp(r'@[\w-]+[^{]*\{[^{}]*\}', dotAll: true), '');

  // Declarations accumulate per class in source order, so a later rule
  // narrowing `stroke-width` wins over the one that set it first.
  final byClass = <String, Map<String, String>>{};

  for (final rule in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
    final selectors = rule.group(1)!.split(',').map((s) => s.trim());
    final declarations = <String, String>{};

    for (final part in rule.group(2)!.split(';')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      declarations[part.substring(0, colon).trim()] = part
          .substring(colon + 1)
          .trim();
    }

    for (final selector in selectors) {
      if (!RegExp(r'^\.[A-Za-z_][\w-]*$').hasMatch(selector)) return svg;
      byClass.putIfAbsent(selector.substring(1), () => {}).addAll(declarations);
    }
  }

  // No early return when there are no class rules. A stylesheet that was
  // nothing but an embedded font still has to go, or the symbol keeps half a
  // megabyte of typeface it never draws with.

  // Whole elements rather than bare class attributes, so a declaration can be
  // dropped when the element already states that property itself. Emitting it
  // anyway would leave the tag with the attribute twice.
  final withAttributes = svg.replaceAllMapped(RegExp(r'<[a-zA-Z][^>]*>'), (m) {
    final tag = m.group(0)!;
    final classAttr = RegExp(r'''\sclass\s*=\s*["']([^"']*)["']''')
        .firstMatch(tag);
    if (classAttr == null) return tag;

    final declarations = <String, String>{};
    for (final name in classAttr.group(1)!.trim().split(RegExp(r'\s+'))) {
      final rules = byClass[name];
      if (rules != null) declarations.addAll(rules);
    }

    final added = [
      for (final entry in declarations.entries)
        if (!RegExp('\\s${entry.key}\\s*=').hasMatch(tag))
          ' ${entry.key}="${entry.value}"',
    ].join();

    return tag.replaceRange(classAttr.start, classAttr.end, added);
  });

  return withAttributes.replaceFirst(styleBlock, '');
}

String _slug(String word) =>
    word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

/// Collapses case and punctuation so "want , to" can match "want".
String _normalise(String? text) => (text ?? '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
