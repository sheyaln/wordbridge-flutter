import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';

/// What a downloaded picture is called, and whether it is ever found again.
///
/// The fetching pack had one question about a file: does its URL end in
/// `.png`, and if not it is an SVG. Two things fell through that.
///
/// **A set that scanned its symbols serves `jpg`.** Those were filed as
/// `.svg`, failed the check that the bytes parse as SVG, and were marked
/// unavailable — so the picker showed "Did not load" beside a picture the
/// device had just downloaded, permanently, for the whole set.
///
/// **The URL only exists in memory.** It is learned from a search and nothing
/// writes it down, so at the next launch the pack knew a symbol's id and not
/// what its file was called. It looked for `<id>.svg`, missed every PNG it had
/// ever saved, and could not re-download it either, having no URL. A picture
/// chosen on Monday was a word on Tuesday.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('wb-fetched'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// The smallest bytes each format is recognized by.
  final svg = utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>');
  final png = [0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0];
  final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];

  String labels(int id, String url) => jsonEncode([
    {
      'text': 'drink',
      'picto': {'id': id, 'image_url': url, 'native_format': 'svg'},
    },
  ]);

  /// A pack whose search returns one symbol at [url], served as [bytes].
  GlobalSymbolsPack packServing({
    required int id,
    required String url,
    required List<int> bytes,
  }) => GlobalSymbolsPack(
    documentsDirectory: () async => temp,
    client: MockClient((request) async {
      if (request.url.host == GlobalSymbolsPack.host) {
        return http.Response(labels(id, url), 200);
      }
      return http.Response.bytes(bytes, 200);
    }),
  );

  /// Everything in the pack's directory, so a test can say what it was called.
  List<String> filed() {
    final directory = Directory('${temp.path}/symbols/globalsymbols');
    if (!directory.existsSync()) return const [];
    return [
      for (final file in directory.listSync().whereType<File>())
        file.uri.pathSegments.last,
    ]..sort();
  }

  group('a file is named for what the server serves', () {
    test('a jpg is filed as one, and draws', () async {
      final pack = packServing(
        id: 7562,
        url: 'https://example.test/15_7562_abc.jpg',
        bytes: jpeg,
      );
      addTearDown(pack.dispose);

      final ref = (await pack.search('drink')).single;
      expect(await pack.fetchNow(ref), isTrue);
      expect(filed(), ['7562.jpg']);
      expect(
        pack.failedFor(ref),
        isFalse,
        reason:
            'filed as .svg it fails the check that it parses as SVG, and the '
            'picker reports a picture already on the device as one that did '
            'not load',
      );
      expect(await pack.resolve(ref), endsWith('7562.jpg'));
    });

    test('a png is filed as one', () async {
      final pack = packServing(
        id: 42,
        url: 'https://example.test/13_42_abc.png',
        bytes: png,
      );
      addTearDown(pack.dispose);

      final ref = (await pack.search('drink')).single;
      expect(await pack.fetchNow(ref), isTrue);
      expect(filed(), ['42.png']);
    });

    test('an extension nothing can draw is not believed', () async {
      // A URL ending in something that is not a picture format says nothing
      // about the bytes. SVG is what these sets serve by default.
      final pack = packServing(
        id: 9,
        url: 'https://example.test/download?id=9',
        bytes: svg,
      );
      addTearDown(pack.dispose);

      final ref = (await pack.search('drink')).single;
      expect(await pack.fetchNow(ref), isTrue);
      expect(filed(), ['9.svg']);
    });
  });

  group('a picture survives the app being closed', () {
    test('a downloaded file is found again with no search first', () async {
      final first = packServing(
        id: 42,
        url: 'https://example.test/13_42_abc.png',
        bytes: png,
      );
      final ref = (await first.search('drink')).single;
      expect(await first.fetchNow(ref), isTrue);
      await first.dispose();

      // A new launch: same directory, nothing searched, so no URL is known
      // for anything. Every request fails, which is how the test tells a file
      // that was found from one that was fetched again.
      final next = GlobalSymbolsPack(
        documentsDirectory: () async => temp,
        client: MockClient(
          (_) async => throw const SocketException('nothing is asked for'),
        ),
      );
      addTearDown(next.dispose);

      expect(
        await next.resolve(ref),
        endsWith('42.png'),
        reason:
            'the file is on the device and the pack cannot find it, so a '
            'picture a caregiver chose becomes a word again at the next launch',
      );
      expect(next.failedFor(ref), isFalse);
    });

    test('a symbol that was never downloaded is not claimed', () async {
      final pack = GlobalSymbolsPack(
        documentsDirectory: () async => temp,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      addTearDown(pack.dispose);

      final missing = (
        packId: 'globalsymbols',
        externalId: '1234',
        label: 'drink',
      );

      expect(await pack.resolve(missing), isNull);
      expect(await pack.fetchNow(missing), isFalse);
    });
  });
}
