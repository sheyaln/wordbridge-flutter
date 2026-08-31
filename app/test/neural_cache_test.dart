import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wordbridge/features/speech/neural/audio_clip.dart';
import 'package:wordbridge/features/speech/neural/clip_store.dart';

AudioClip clipOf(int bytes, {int fill = 7}) =>
    (pcm16: Uint8List(bytes)..fillRange(0, bytes, fill), sampleRate: 24000);

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wordbridge-clips');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<ClipStore> open([String packId = 'af_bella-r100']) =>
      ClipStore.open(root: root, packId: packId);

  group('one pack, not 1231 files', () {
    test('every clip lands in the same two files', () async {
      final store = await open();
      for (var i = 0; i < 20; i++) {
        await store.write('word$i', clipOf(100));
      }
      await store.close();

      final files = root.listSync().whereType<File>().toList();
      expect(files.length, 2);
      expect(files.map((f) => p.extension(f.path)).toSet(), {
        '.pack',
        '.index',
      });
    });

    test('a clip comes back exactly as it went in', () async {
      final store = await open();
      final clip = (pcm16: Uint8List.fromList([1, 2, 3, 4]), sampleRate: 24000);
      await store.write('want', clip);

      final read = await store.read('want');
      expect(read, isNotNull);
      expect(read!.pcm16, [1, 2, 3, 4]);
      expect(read.sampleRate, 24000);
    });

    test('a word that was never baked is a miss, not an error', () async {
      // The whole of the cache-miss signal. A miss speaks in the platform
      // voice and does so now; it must not throw and it must not wait.
      final store = await open();
      expect(await store.read('never'), isNull);
      expect(store.contains('never'), isFalse);
    });

    test('a second write of the same word does not grow the pack', () async {
      final store = await open();
      await store.write('more', clipOf(100));
      final after = store.bytesOnDisk;
      await store.write('more', clipOf(100));
      expect(store.bytesOnDisk, after);
      expect(store.count, 1);
    });
  });

  group('being interrupted', () {
    test('a reopened pack knows what it already has', () async {
      // The pack is the progress: nothing else has to remember where a bake
      // got to.
      final first = await open();
      await first.write('yes', clipOf(120));
      await first.write('no', clipOf(140));
      await first.close();

      final second = await open();
      expect(second.count, 2);
      expect(second.contains('yes'), isTrue);
      expect((await second.read('no'))!.pcm16.lengthInBytes, 140);
      expect(second.sampleRate, 24000);
    });

    test('an index entry pointing past the audio is dropped', () async {
      // Audio is written before the entry that points at it, so this is what a
      // process killed between the two looks like from the other side. The
      // reverse order would be a word that plays as a crash.
      final store = await open();
      await store.write('yes', clipOf(120));
      await store.close();

      final index = File(p.join(root.path, 'af_bella-r100.index'));
      await index.writeAsString(
        '999999,120,${base64Encode(utf8.encode('ghost'))}\n',
        mode: FileMode.append,
      );

      final reopened = await open();
      expect(reopened.contains('yes'), isTrue);
      expect(reopened.contains('ghost'), isFalse);
      expect(await reopened.read('ghost'), isNull);
    });

    test('a torn index is rewritten, not re-read every launch', () async {
      final store = await open();
      await store.write('yes', clipOf(120));
      await store.close();

      final index = File(p.join(root.path, 'af_bella-r100.index'));
      await index.writeAsString('9999,12', mode: FileMode.append);

      await (await open()).close();
      expect(await index.readAsString(), isNot(contains('9999,12')));
    });

    test('bytes left behind by a torn write are stepped over', () async {
      final store = await open();
      await store.write('yes', clipOf(120));
      await store.close();

      // Audio written, then the process died before the index entry.
      await File(p.join(root.path, 'af_bella-r100.pack'))
          .writeAsBytes(Uint8List(64), mode: FileMode.append);

      final reopened = await open();
      await reopened.write('no', clipOf(140, fill: 3));
      expect((await reopened.read('no'))!.pcm16.every((b) => b == 3), isTrue);
      expect((await reopened.read('yes'))!.pcm16.every((b) => b == 7), isTrue);
    });

    test('a word with a newline in it survives the round trip', () async {
      // The index is a line-oriented file and a caregiver types the words.
      final store = await open();
      await store.write('two\nlines', clipOf(60));
      await store.close();

      expect((await open()).contains('two\nlines'), isTrue);
    });
  });

  group('a pack belongs to one voice at one speed', () {
    test('speed is part of the name, to the nearest hundredth', () {
      // Kokoro takes speed as a generation parameter, not a playback rate, so
      // it is baked into every clip. A slider reporting 0.8199999 must not be
      // a different cache from one reporting 0.82.
      const v = ClipStore.recipe;
      expect(ClipStore.idFor('af_bella', 0.82), 'af_bella-r82-v$v');
      expect(ClipStore.idFor('af_bella', 0.8199999), 'af_bella-r82-v$v');
      expect(ClipStore.idFor('af_bella', 1.0), 'af_bella-r100-v$v');
      expect(ClipStore.idFor('bm_george', 1.25), 'bm_george-r125-v$v');
    });

    test('what the model was given is part of the name too', () {
      // Clips made under an older recipe are playable and wrong — they came
      // from a different string. Bumping the recipe is how they are retired
      // rather than reused, so the number has to reach the pack's name.
      expect(
        ClipStore.idFor('af_bella', 1.0),
        endsWith('-v${ClipStore.recipe}'),
      );
      expect(ClipStore.recipe, greaterThan(1));
    });

    test('two voices do not read each other clips', () async {
      final bella = await open('af_bella-r100');
      await bella.write('hello', clipOf(100, fill: 1));
      await bella.close();

      final george = await open('bm_george-r100');
      expect(george.contains('hello'), isFalse);
    });

    test('pruning keeps the one in use and frees the rest', () async {
      // A tablet that has tried four voices carries four packs, three of which
      // nothing will read again.
      for (final id in ['af_bella-r100', 'bm_george-r100', 'af_sky-r82']) {
        final store = await open(id);
        await store.write('hello', clipOf(1000));
        await store.close();
      }

      final freed = await ClipStore.pruneTo(root, 'af_bella-r100');
      expect(freed, greaterThan(0));
      expect((await open('af_bella-r100')).count, 1);
      expect((await open('bm_george-r100')).count, 0);
      expect((await open('af_sky-r82')).count, 0);
    });
  });
}
