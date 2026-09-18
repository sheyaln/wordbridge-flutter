import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/features/symbols/stored_path.dart';

/// Where a file this device owns actually is (§4.90).
///
/// iOS moves the app's data container and takes every absolute path written
/// down before the move with it. The file is still there under the same name;
/// only the folder above it changed.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('docs');
    storedPathRoot = () async => root;
    resetStoredPathRoot();
  });

  tearDown(() async {
    resetStoredPathRoot();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<File> photoNamed(String name) async {
    final file = File(p.join(root.path, 'symbols', 'custom', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }

  test('a relative path is read under the documents directory', () async {
    final file = await photoNamed('abc.png');
    expect(
      await resolveStoredPath('symbols/custom/abc.png'),
      file.path,
    );
  });

  test('an absolute path that is still right is used as it is', () async {
    final file = await photoNamed('abc.png');
    expect(await resolveStoredPath(file.path), file.path);
  });

  test('a path from a container that has moved still finds the file', () async {
    // The bug, exactly: the row was written under one container UUID and the
    // app is now running under another.
    final file = await photoNamed('abc.png');
    const gone =
        '/var/mobile/Containers/Data/Application/'
        'B968E79A-CADE-419D-9D99-B80EC4AB8A07/Documents/'
        'symbols/custom/abc.png';

    expect(
      await resolveStoredPath(gone),
      file.path,
      reason: 'the photograph was looked for in last week’s folder',
    );
  });

  test('a file that is genuinely gone resolves to nothing', () async {
    expect(await resolveStoredPath('symbols/custom/never.png'), isNull);
  });

  test('the part kept is everything below Documents', () {
    expect(
      relativeStoredPath('/a/b/Documents/symbols/custom/x.png'),
      'symbols/custom/x.png',
    );
    // No Documents segment at all: the name is all that can be trusted.
    expect(relativeStoredPath('/somewhere/else/x.png'), 'x.png');
    expect(relativeStoredPath('symbols/custom/x.png'), isNull);
  });
}
