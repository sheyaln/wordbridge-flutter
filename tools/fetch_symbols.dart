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
/// **Stellar leads.** It is small — a few hundred pictures against Mulberry's
/// 3,436 — and drawn for exactly the abstract core vocabulary Mulberry is
/// weakest on, so putting it first costs almost nothing on the concrete nouns
/// it has no entry for and wins the words a board is built around. Preferring
/// it by order rather than by naming words means a picture it adds later is
/// picked up by re-running this, instead of by somebody noticing.
///
/// Mulberry follows, with its own two extension sets behind it because they
/// are drawn to match it. It is strong on concrete nouns and weak on abstract
/// core vocabulary — its 3,436 symbols contain no "stop", "you", "not" or
/// "want" — so later entries fill those gaps. Mixing styles is a real cost to
/// visual consistency, but a pre-literate user faced with a blank button pays
/// more.
const _sets = <({String slug, int id, String name, String attribution})>[
  (
    slug: 'stellar-symbols',
    id: 133,
    name: 'Stellar Symbols',
    attribution: 'Stellar Symbols © Colin McNamee. CC BY-SA 4.0.',
  ),
  (
    slug: 'mulberry',
    id: 13,
    name: 'Mulberry Symbols',
    attribution:
        'Mulberry Symbols © Garry Paxton 2008-2017, Steve Lee 2018-. '
        'CC BY-SA 4.0. https://mulberrysymbols.org',
  ),
  // Mulberry's own two extension sets, drawn to match it. Ahead of everything
  // else because a picture in the same house style as the set beside it is
  // worth more than a nearer word in a different one.
  (
    slug: 'corona-symbols',
    id: 86,
    name: 'Mulberry Plus Collection',
    attribution:
        'Mulberry Plus Collection © Mulberry and Global Symbols. '
        'CC BY-SA 4.0. https://globalsymbols.com',
  ),
  (
    slug: 'additional-mulberry-symbols',
    id: 205,
    name: 'Mulberry Additional Symbols',
    attribution:
        'Mulberry Additional Symbols © Verlag Karin Kestner GmbH. '
        'CC BY-SA 4.0. https://www.kestner.de',
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

/// Words whose picture was chosen by a person rather than found by name.
///
/// The search matches a set's label against the word, which is right when a
/// set names the concept the way the board does and useless when it does not:
/// no set has a "tell" at all, every set's "see" is the same drawing as its
/// "look", and the picture of a napkin worth having is filed under "Tissues".
///
/// **Keyed by the upstream catalog number**, because that is what a set calls
/// its own picture and the only handle that survives a label being reworded.
/// [query] exists only to find the page the number is on — there is no
/// fetch-by-id endpoint, so a search still has to name something the set
/// indexes.
///
/// A choice made by looking at the pictures belongs here rather than in the
/// manifest. In the manifest it is indistinguishable from something the tool
/// found, and the next run that re-fetches the word silently undoes it — which
/// is exactly what nearly happened to the seventeen picked by hand in
/// `4354a08` the first time the set order changed underneath them.
const _chosen = <String, ({String query, int pictoId})>{
  // Picked by hand from the pictures themselves (4354a08).
  'far': (query: 'Distance', pictoId: 44201),
  'feelings': (query: 'emotions', pictoId: 53191),
  'friend': (query: 'friends', pictoId: 7946),
  'girl': (query: 'Girl', pictoId: 41151),
  'juice': (query: 'Orange Juice', pictoId: 5214),
  'meeting': (query: 'Meeting', pictoId: 41061),
  'name': (query: 'European Name Badge', pictoId: 44139),
  'pee': (query: 'Toilet', pictoId: 5984),
  'period': (query: 'period cycle', pictoId: 54311),
  'plane': (query: 'Aeroplane', pictoId: 3130),
  'pool': (query: 'Swim', pictoId: 5859),
  'think': (query: 'Thinking Face', pictoId: 40773),
  'town': (query: 'Cityscape', pictoId: 42987),
  'us': (query: 'Group', pictoId: 44206),
  'wait': (query: 'Please wait', pictoId: 53003),
  'walk': (query: 'Man Walking', pictoId: 42087),

  // The speaker the talk button draws, for the word that means saying
  // something to somebody.
  'tell': (query: 'speaker', pictoId: 43279),
  // Eyes, which is what "see" is once the looking is taken out of it. It was
  // the "look" drawing, so a board carrying both words carried one picture
  // twice.
  'see': (query: 'eye', pictoId: 4174),
  // A napkin is filed under what it is made of.
  'napkin': (query: 'tissue', pictoId: 5977),
  'knife': (query: 'knife', pictoId: 42935),
  'spoon': (query: 'spoon', pictoId: 5765),
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

  // Written as it goes, not only at the end. A run is a quarter of an hour of
  // somebody else's bandwidth, and a run that is interrupted used to leave the
  // downloaded images on disk with nothing recording what they were — so the
  // next run asked for all five hundred again and the first run's work was
  // spent for nothing.
  void save() {
    final encoded = const JsonEncoder.withIndent('  ').convert({
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
    });

    // Trailing newline, so the file has an end a diff can show rather than a
    // last line every run reports as changed.
    File('${dir.path}/manifest.json').writeAsStringSync('$encoded\n');
  }

  for (final word in words) {
    final chosen = _chosen[word.toLowerCase()];

    // A chosen word is re-resolved every run rather than skipped. It is in
    // the manifest either way — as whatever the search found before somebody
    // overruled it, or as the overruling — and only asking again tells the
    // two apart.
    if (chosen == null && manifest.containsKey(word.toLowerCase())) continue;
    final candidates = _searchCandidates[word] ?? [word];
    stdout.write('${word.padRight(12)} ');

    try {
      _Hit? hit;
      if (chosen != null) {
        // Every set, because the number says which one it is and naming the
        // set as well would be a second thing to keep in step with it.
        for (final set in _sets) {
          hit = await _search(
            client,
            chosen.query,
            set,
            wantPicto: chosen.pictoId,
          );
          if (hit != null) break;
        }

        if (hit == null) {
          stdout.writeln(
            'picture ${chosen.pictoId} is no longer reachable by searching '
            '"${chosen.query}" — left as it was',
          );
          failed.add(word);
          continue;
        }
      } else {
        for (final set in _sets) {
          for (final query in candidates) {
            hit = await _search(client, query, set);
            if (hit != null) break;
          }
          if (hit != null) break;
        }
      }

      if (hit == null) {
        stdout.writeln('no exact match in any set — label-only');
        missing.add(word);
        continue;
      }

      final ext = _extensionOf(hit);
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
      save();
    } catch (e) {
      stdout.writeln('failed: $e');
      failed.add(word);
    }
  }

  save();

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
  ({String slug, int id, String name, String attribution}) set, {
  int? wantPicto,
}) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      await _throttle();
      return await _searchOnce(client, query, set, wantPicto: wantPicto);
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
  ({String slug, int id, String name, String attribution}) set, {
  int? wantPicto,
}) async {
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
  //
  // [wantPicto] is how a hand-picked symbol is asked for: the search term
  // finds the page and the catalog number says which picture on it. Exact
  // either way — of somebody's decision rather than of the word.
  Map<String, dynamic>? exact;
  for (final entry in body.cast<Map<String, dynamic>>()) {
    if (wantPicto != null) {
      final picto = entry['picto'];
      if (picto is Map && picto['id'] == wantPicto) {
        exact = entry;
        break;
      }
      continue;
    }
    if (_normalise(entry['text'] as String?) == _normalise(query)) {
      exact = entry;
      break;
    }
  }
  if (exact == null) return null;

  final picto = exact['picto'];
  if (picto == null) return null;
  // A pinned number carries its own set; only a match by word has to be
  // checked against the set that was asked.
  if (wantPicto == null && picto['symbolset_id'] != set.id) return null;

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

/// What to call the file, from what the server is actually serving.
///
/// The declared format and the URL agree for nearly everything and disagree
/// for the handful of sets that scanned their symbols: those are `jpg`, which
/// was filed as `.png` because the only question asked was "is it svg". The
/// bundled renderer sniffs the bytes and draws them anyway, so nothing was
/// visibly wrong here — but the runtime pack answers the same question about
/// what it downloads, and there a wrong extension is a picture that never
/// loads at all.
String _extensionOf(_Hit hit) {
  final path = Uri.tryParse(hit.imageUrl)?.path ?? hit.imageUrl;
  final dot = path.lastIndexOf('.');
  final fromUrl = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return _drawableExtensions.contains(fromUrl) ? fromUrl : hit.format;
}

/// Extensions the app can draw. Anything else is not a picture and taking the
/// declared format is a better guess than trusting a URL that ends in a query
/// string or nothing at all.
const _drawableExtensions = {'svg', 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'};

/// Collapses case and punctuation so "want , to" can match "want".
String _normalise(String? text) => (text ?? '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
