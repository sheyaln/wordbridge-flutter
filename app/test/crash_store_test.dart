import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/features/reporting/crash_store.dart';

/// §4.52. Where a caught fault waits until somebody has time for it.
///
/// A crash does not end the session — `installFallbackBoard` means the user is
/// still holding a tablet that still talks. Interrupting somebody mid-sentence
/// to ask about a stack trace would be the wrong thing at the wrong moment, so
/// the record is written and nothing else happens.
void main() {
  late Directory documents;
  late CrashStore store;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('wb-crash');
    store = CrashStore(documentsDirectory: () async => documents);
  });

  tearDown(() async {
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  Future<List<File>> files() async =>
      (await store.directory()).listSync().whereType<File>().toList();

  group('recording', () {
    test('keeps the fault where the next launch will find it', () async {
      await store.record(StateError('no route'), StackTrace.current);

      final waiting = await store.waiting();
      expect(waiting, hasLength(1));
      expect(waiting.single.detail, contains('no route'));
    });

    test('scrubs before it touches the disk', () async {
      // Not on the way out. There must be no window in which an unscrubbed
      // trace exists as a file on a device somebody else might pick up.
      await store.record(
        StateError('Row 3 of "Maya\'s words" already holds 4 words'),
        StackTrace.current,
      );

      final raw = await (await files()).single.readAsString();
      expect(raw, isNot(contains('Maya')));
    });

    test('and swallows a store it cannot write to', () async {
      // A store that throws while recording a crash turns one fault into two,
      // and the second one has nowhere to be written.
      final broken = CrashStore(
        documentsDirectory: () async =>
            Directory(p.join(documents.path, 'gone', 'deeper')),
      );
      await documents.delete(recursive: true);

      await expectLater(
        broken.record(StateError('x'), StackTrace.current),
        completes,
      );
    });
  });

  group('reading back', () {
    test('newest first, because that is the one still happening', () async {
      final base = DateTime.utc(2026, 8, 30, 12);
      await store.record(StateError('older'), null, at: base);
      await store.record(
        StateError('newer'),
        null,
        at: base.add(const Duration(hours: 1)),
      );

      final waiting = await store.waiting();
      expect(waiting.map((r) => r.detail.contains('newer')), [true, false]);
    });

    test('scrubs again on the way out', () async {
      // A file written by an older build, or edited by hand, is not evidence
      // that it is safe to show.
      final directory = await store.directory();
      await File(p.join(directory.path, '2026-08-30T00:00:00.000Z.json'))
          .writeAsString(
            jsonEncode({
              'at': '2026-08-30T00:00:00.000Z',
              'detail': 'failed near "Maya"',
            }),
          );

      expect((await store.waiting()).single.detail, isNot(contains('Maya')));
    });

    test('and throws away a record nobody could act on', () async {
      final directory = await store.directory();
      await File(
        p.join(directory.path, '2026-08-30T00:00:00.000Z.json'),
      ).writeAsString('not json');

      expect(await store.waiting(), isEmpty);
      expect(await files(), isEmpty, reason: 'the unreadable file was kept');
    });
  });

  group('forgetting', () {
    test('one, by name', () async {
      await store.record(StateError('x'), null);
      final id = (await store.waiting()).single.id;

      await store.discard(id);
      expect(await store.waiting(), isEmpty);
    });

    test('discarding one that is already gone is not an error', () async {
      await expectLater(store.discard('nothing.json'), completes);
    });

    test('and all of them', () async {
      for (var i = 0; i < 3; i++) {
        await store.record(
          StateError('x$i'),
          null,
          at: DateTime.utc(2026, 8, 30, i),
        );
      }
      expect(await store.waiting(), hasLength(3));

      await store.discardAll();
      expect(await store.waiting(), isEmpty);
    });
  });

  group('how many are kept', () {
    test('the newest few, oldest dropped', () async {
      // A tablet that has crashed two hundred times has a problem the first
      // few records already describe, and the rest are a folder nobody reads.
      for (var i = 0; i < CrashStore.keep + 5; i++) {
        await store.record(
          StateError('crash $i'),
          null,
          at: DateTime.utc(2026, 8, 30).add(Duration(minutes: i)),
        );
      }

      final waiting = await store.waiting();
      expect(waiting, hasLength(CrashStore.keep));
      expect(
        waiting.first.detail,
        contains('crash ${CrashStore.keep + 4}'),
        reason: 'the newest was pruned instead of the oldest',
      );
      expect(
        waiting.map((r) => r.detail).join(),
        isNot(contains('crash 0')),
        reason: 'the oldest survived',
      );
    });
  });
}
