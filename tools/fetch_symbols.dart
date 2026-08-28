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
    attribution: 'Mulberry Symbols © Garry Paxton 2008-2017, Steve Lee 2018-. '
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
    attribution:
        'Tawasol Symbols © Mada, Qatar. CC BY-SA 4.0. http://tawasolsymbols.org',
  ),
  (
    slug: 'openmoji',
    id: 83,
    name: 'OpenMoji',
    attribution: 'OpenMoji © OpenMoji Project. CC BY-SA 4.0. https://openmoji.org',
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
  // Editing controls: the concept is erasing the last word, not "undo" in the
  // software sense.
  'undo': ['undo', 'delete', 'erase', 'rub out'],
  'clear': ['clear', 'empty', 'rubbish', 'bin'],
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

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
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
    stdout.writeln('resuming with ${manifest.length} symbols already fetched\n');
  }

  final missing = <String>[];
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

      File('${dir.path}/$filename').writeAsBytesSync(bytes);
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
      missing.add(word);
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
    stdout.writeln('no symbol for: ${missing.join(', ')}');
    stdout.writeln('those buttons render label-only, which is fine.');
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

/// Retries around network flakiness.
///
/// Distinguishing "this set has no such word" from "the request failed" is
/// the whole point: the first is a real answer, the second is noise that must
/// not be recorded as one.
Future<_Hit?> _search(
  HttpClient client,
  String query,
  ({String slug, int id, String name, String attribution}) set,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      return await _searchOnce(client, query, set);
    } on Object {
      if (attempt == 2) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }
  return null;
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

  final res = await (await client.getUrl(uri)).close();
  if (res.statusCode != 200) return null;

  final body = jsonDecode(await res.transform(utf8.decoder).join());
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
  final res = await (await client.getUrl(Uri.parse(url))).close();
  if (res.statusCode != 200) {
    throw HttpException('HTTP ${res.statusCode}');
  }
  return (await res.fold<BytesBuilder>(
    BytesBuilder(),
    (b, d) => b..add(d),
  )).takeBytes();
}

String _slug(String word) =>
    word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

/// Collapses case and punctuation so "want , to" can match "want".
String _normalise(String? text) => (text ?? '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
