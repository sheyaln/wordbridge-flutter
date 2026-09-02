import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/symbols/drawable.dart';

/// §4.67. What a downloading pack is allowed to file.
///
/// A pack checked for HTTP 200 and a non-empty body and wrote whatever came
/// back. A 200 carrying an error page, or a body cut short after the headers,
/// was renamed into place — where it then looks cached for the life of the
/// install, and every attempt to draw it throws inside the parse isolate, is
/// caught, and becomes a crash report. Ten arrived from one device in one
/// flush, all identical, and none of them said when it happened.
void main() {
  Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

  group('an SVG', () {
    test('is drawable when it is one', () {
      expect(
        looksDrawable(
          bytes('<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>'),
          asSvg: true,
        ),
        isTrue,
      );
    });

    test('with a declaration and a doctype is still one', () {
      // Three of the shipped symbols carry both, and they render.
      expect(
        looksDrawable(
          bytes(
            '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
            '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "x.dtd">'
            '<svg xmlns="http://www.w3.org/2000/svg"><path/></svg>',
          ),
          asSvg: true,
        ),
        isTrue,
      );
    });

    test('cut off partway is not', () {
      // A connection that dropped after the headers. This is the one the old
      // code filed, because it had a 200 and some bytes.
      expect(
        looksDrawable(
          bytes('<svg xmlns="http://www.w3.org/2000/svg"><pa'),
          asSvg: true,
        ),
        isFalse,
      );
    });

    test('that is really an error page is not', () {
      // Well formed, parses cleanly, draws nothing. Being readable XML is not
      // evidence of being the right document.
      expect(
        looksDrawable(
          bytes('<html><body><h1>404 Not Found</h1></body></html>'),
          asSvg: true,
        ),
        isFalse,
      );
    });

    test('that is JSON is not', () {
      expect(looksDrawable(bytes('{"error":"gone"}'), asSvg: true), isFalse);
    });

    test('and nothing at all is not', () {
      expect(looksDrawable(Uint8List(0), asSvg: true), isFalse);
    });
  });

  group('a raster image', () {
    Uint8List starting(List<int> magic) =>
        Uint8List.fromList([...magic, ...List.filled(32, 0)]);

    test('is drawable when the bytes say what it is', () {
      expect(
        looksDrawable(starting(const [0x89, 0x50, 0x4E, 0x47]), asSvg: false),
        isTrue,
      );
      expect(
        looksDrawable(starting(const [0xFF, 0xD8, 0xFF]), asSvg: false),
        isTrue,
      );
      expect(
        looksDrawable(starting(const [0x47, 0x49, 0x46, 0x38]), asSvg: false),
        isTrue,
      );
    });

    test('is judged by its bytes, not by its name', () {
      // Nine bundled files are named .png and hold JPEG. They render, because
      // the decoder reads the bytes, so this must not refuse them.
      expect(
        looksDrawable(starting(const [0xFF, 0xD8, 0xFF]), asSvg: false),
        isTrue,
      );
    });

    test('an error page in its place is not', () {
      expect(looksDrawable(bytes('<html>404</html>'), asSvg: false), isFalse);
    });

    test('and neither is an empty body', () {
      expect(looksDrawable(Uint8List(0), asSvg: false), isFalse);
    });
  });
}
