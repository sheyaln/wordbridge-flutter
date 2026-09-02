import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml_events.dart';

/// Every bundled SVG has to survive the parser that will actually be handed it.
///
/// §4.67. Ten symbols shipped as `.svg` that `flutter_svg` could not read. They
/// were well formed XML, so every check that had been run passed: the files
/// existed, the manifest pointed at them, nothing was orphaned. The parser
/// underneath is stricter than an XML well-formedness check, and nothing was
/// asking it.
///
/// The failure is invisible on the way in and loud on the way out — one caught
/// fault per unreadable file, at launch, on a device somebody is meant to talk
/// on.
void main() {
  final directory = Directory('assets/symbols/core');

  test('the bundled pack is there to check', () {
    expect(directory.existsSync(), isTrue);
  });

  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.svg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('every one of them compiles', () {
    final broken = <String, String>{};
    for (final file in files) {
      try {
        // The same stage that failed on the device: `flutter_svg` reads an
        // SVG as a stream of XML events, and that parser is stricter than a
        // document-level well-formedness check. Drained rather than merely
        // created, because the events are lazy and an unread iterator throws
        // nothing.
        parseEvents(file.readAsStringSync()).toList();
      } catch (e) {
        broken[file.uri.pathSegments.last] = '$e'.split('\n').first;
      }
    }

    expect(
      broken,
      isEmpty,
      reason:
          'these ship as SVG and the renderer cannot read them, so each one is '
          'a caught fault at launch:\n'
          '${broken.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}',
    );
  });
}
