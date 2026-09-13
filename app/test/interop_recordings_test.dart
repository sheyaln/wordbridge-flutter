import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/interop/board_files.dart';
import 'package:wordbridge/features/interop/obf_export.dart';
import 'package:wordbridge/features/interop/obf_import.dart';
import 'package:wordbridge/features/interop/obf_model.dart';
import 'package:wordbridge/features/interop/recordings.dart';

/// A board whose keys hold somebody's own voice.
///
/// Message banking is why this matters: the recordings on a board like this
/// were made by a person who may no longer be able to make them, and an import
/// that dropped them without a word would be asking for them again.
const recordingBytes = <int>[
  0x49,
  0x44,
  0x33,
  ...[0x03, 0x00, 0x00, 0x00],
  ...[0x77, 0x6F, 0x72, 0x64],
];

const otherRecordingBytes = <int>[
  0x49,
  0x44,
  0x33,
  ...[0x03, 0x00, 0x00, 0x00],
  ...[0x62, 0x72, 0x69, 0x64],
];

String get recordingDataUri =>
    'data:audio/mpeg;base64,${base64Encode(recordingBytes)}';

/// One board, two keys, the first of them carrying a recording.
String obfWithSound({
  Map<String, Object?>? sound,
  String? soundId = 's1',
  String label = 'hello',
  String? vocalization,
}) => jsonEncode({
  'format': obfFormat,
  'id': 'banked-1',
  'locale': 'en',
  'name': 'voice',
  'buttons': [
    {
      'id': '1',
      'label': label,
      'vocalization': ?vocalization,
      'sound_id': ?soundId,
    },
    {'id': '2', 'label': 'more'},
  ],
  'grid': {
    'rows': 1,
    'columns': 2,
    'order': [
      ['1', '2'],
    ],
  },
  'sounds': [?sound],
});

List<int> zipOf(Map<String, Object> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(switch (entry.value) {
      final String text => ArchiveFile.string(entry.key, text),
      final List<int> bytes => ArchiveFile.bytes(
        entry.key,
        Uint8List.fromList(bytes),
      ),
      _ => throw ArgumentError.value(entry.value),
    });
  }
  return ZipEncoder().encodeBytes(archive);
}

/// An `.obz` whose one key holds a recording, carried as a file in the zip.
List<int> bankedPackage() => zipOf({
  'manifest.json': jsonEncode({
    'format': obfFormat,
    'root': 'boards/1.obf',
    'paths': {
      'boards': {'banked-1': 'boards/1.obf'},
      'sounds': {'s1': 'sounds/hello.mp3'},
    },
  }),
  'boards/1.obf': obfWithSound(
    sound: {
      'id': 's1',
      'path': 'sounds/hello.mp3',
      'content_type': 'audio/mpeg',
    },
  ),
  'sounds/hello.mp3': recordingBytes,
});

Map<String, ArchiveFile> filesIn(List<int> zip) => {
  for (final file in ZipDecoder().decodeBytes(zip).files) file.name: file,
};

ObfBoard boardIn(Map<String, ArchiveFile> files, String path) =>
    ObfBoard.parse(utf8.decode(files[path]!.readBytes()!));

ObzManifest manifestIn(Map<String, ArchiveFile> files) =>
    ObzManifest.parse(utf8.decode(files['manifest.json']!.readBytes()!));

Future<Board> boardNamed(WordbridgeDatabase db, String name) =>
    (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

bool mentions(List<String> notes, String fragment) =>
    notes.any((n) => n.contains(fragment));

void main() {
  late WordbridgeDatabase db;
  late Directory documents;
  late RecordingStore recordings;

  setUp(() {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    documents = Directory.systemTemp.createTempSync('wordbridge-recordings');
    recordings = RecordingStore(documentsDirectory: () async => documents);
  });

  tearDown(() async {
    await db.close();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  group('THE INVARIANT: a recording is never dropped in silence', () {
    test('an import with nowhere to file audio says what it has', () async {
      final notes = <String>[];
      await importObf(
        db,
        obfWithSound(
          sound: {
            'id': 's1',
            'data': recordingDataUri,
            'content_type': 'audio/mpeg',
          },
        ),
        notes: notes,
      );

      expect(mentions(notes, 'recorded message'), isTrue);
      expect(mentions(notes, 'not kept'), isTrue);
      expect(
        mentions(notes, 'speak their words'),
        isTrue,
        reason: 'a key whose audio did not arrive still has to say something',
      );
    });

    test('a board set leaves with the audio it came in with', () async {
      final notes = <String>[];
      await importObf(
        db,
        obfWithSound(
          sound: {
            'id': 's1',
            'data': recordingDataUri,
            'content_type': 'audio/mpeg',
            'duration': 2,
          },
        ),
        notes: notes,
        recordings: recordings,
      );
      expect(mentions(notes, 'kept with it'), isTrue);

      final exportNotes = <String>[];
      final exported = ObfBoard.parse(
        await exportObf(
          db,
          (await boardNamed(db, 'voice')).id,
          notes: exportNotes,
          recordings: recordings,
        ),
      );

      final sound = exported.sounds.single;
      final hello = exported.buttons.firstWhere((b) => b.label == 'hello');
      expect(
        hello.soundId,
        sound.id,
        reason: 'the recording has to come back out on the key it came in on',
      );
      expect(sound.contentType, 'audio/mpeg');
      expect(sound.duration, 2);
      expect(sound.data, startsWith('data:audio/mpeg;base64,'));
      expect(base64Decode(sound.data!.split(',').last), recordingBytes);

      expect(mentions(exportNotes, 'travel with this file'), isTrue);
    });

    test(
      'a full .obz round trip keeps the same bytes on the same key',
      () async {
        final package = zipOf({
          'manifest.json': jsonEncode({
            'format': obfFormat,
            'root': 'boards/1.obf',
            'paths': {
              'boards': {'banked-1': 'boards/1.obf'},
              'sounds': {'s1': 'sounds/hello.mp3'},
            },
          }),
          'boards/1.obf': obfWithSound(
            sound: {'id': 's1', 'content_type': 'audio/mpeg'},
          ),
          'sounds/hello.mp3': recordingBytes,
        });

        final notes = <String>[];
        final vocabId = await importObz(
          db,
          package,
          notes: notes,
          recordings: recordings,
        );
        expect(mentions(notes, 'kept with it'), isTrue);

        final files = filesIn(
          await exportObz(db, vocabId, recordings: recordings),
        );
        final manifest = manifestIn(files);
        final board = boardIn(files, manifest.root!);
        final sound = board.sounds.single;

        expect(manifest.sounds[sound.id], isNotNull);
        expect(files.keys, contains(manifest.sounds[sound.id]));
        expect(files[sound.path]!.readBytes(), recordingBytes);
        expect(
          board.buttons.firstWhere((b) => b.label == 'hello').soundId,
          sound.id,
        );

        // The second trip is the one that matters: a recipient importing this
        // into another copy of wordbridge and exporting it again still has the
        // voice that started out on the key.
        final second = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        addTearDown(second.close);
        final elsewhere = Directory.systemTemp.createTempSync(
          'wordbridge-again',
        );
        addTearDown(() => elsewhere.deleteSync(recursive: true));
        final theirs = RecordingStore(
          documentsDirectory: () async => elsewhere,
        );

        final again = filesIn(
          await exportObz(
            second,
            await importObz(
              second,
              ZipEncoder().encodeBytes(
                ZipDecoder().decodeBytes(
                  await exportObz(db, vocabId, recordings: recordings),
                ),
              ),
              recordings: theirs,
            ),
            recordings: theirs,
          ),
        );
        final theirBoard = boardIn(again, manifestIn(again).root!);
        expect(
          again[theirBoard.sounds.single.path]!.readBytes(),
          recordingBytes,
        );
      },
    );

    test('a recording named only by the manifest is found', () async {
      final package = zipOf({
        'manifest.json': jsonEncode({
          'format': obfFormat,
          'root': 'boards/1.obf',
          'paths': {
            'boards': {'banked-1': 'boards/1.obf'},
            'sounds': {'s1': 'sounds/hello.mp3'},
          },
        }),
        // No `path` on the sound itself, which is where the spec says the
        // manifest earns its keep.
        'boards/1.obf': obfWithSound(sound: {'id': 's1'}),
        'sounds/hello.mp3': recordingBytes,
      });

      final notes = <String>[];
      final vocabId = await importObz(
        db,
        package,
        notes: notes,
        recordings: recordings,
      );

      expect(mentions(notes, 'kept with it'), isTrue);
      final files = filesIn(
        await exportObz(db, vocabId, recordings: recordings),
      );
      final board = boardIn(files, manifestIn(files).root!);
      expect(files[board.sounds.single.path]!.readBytes(), recordingBytes);
      expect(
        board.sounds.single.path,
        endsWith('.mp3'),
        reason: 'the name in the manifest is what says what the audio is',
      );
    });

    test('audio past what one import may copy is left, and said', () async {
      final small = RecordingStore(
        documentsDirectory: () async => documents,
        budgetBytes: 4,
      );

      final notes = <String>[];
      final vocabId = await importObf(
        db,
        obfWithSound(
          sound: {
            'id': 's1',
            'data': recordingDataUri,
            'content_type': 'audio/mpeg',
          },
        ),
        notes: notes,
        recordings: small,
      );

      expect(mentions(notes, 'are not kept'), isTrue);
      expect(mentions(notes, 'more audio than one import'), isTrue);

      final files = filesIn(await exportObz(db, vocabId, recordings: small));
      expect(files.keys.where((n) => n.startsWith('sounds/')), isEmpty);
    });
  });

  group('audio this app will not go and get', () {
    test('a recording behind a url stays a url', () async {
      final notes = <String>[];
      final vocabId = await importObf(
        db,
        obfWithSound(
          sound: {'id': 's1', 'url': 'https://example.com/hello.mp3'},
        ),
        notes: notes,
        recordings: recordings,
      );

      expect(mentions(notes, 'links to files on the internet'), isTrue);
      expect(mentions(notes, 'nothing was downloaded'), isTrue);

      final files = filesIn(
        await exportObz(db, vocabId, recordings: recordings),
      );
      expect(
        files.keys.where((n) => n.startsWith('sounds/')),
        isEmpty,
        reason: 'nothing was fetched, so there is nothing to carry',
      );

      final sound = boardIn(files, manifestIn(files).root!).sounds.single;
      expect(sound.url, 'https://example.com/hello.mp3');
      expect(sound.data, isNull);
      expect(sound.path, isNull);
    });

    test('a sound with neither bytes nor link is reported', () async {
      final notes = <String>[];
      final vocabId = await importObf(
        db,
        obfWithSound(sound: {'id': 's1', 'content_type': 'audio/mpeg'}),
        notes: notes,
        recordings: recordings,
      );

      expect(mentions(notes, 'are not kept'), isTrue);

      // Nothing to point at, so no sound_id either: an id naming a sound that
      // carries nothing is a key that reads as recorded and is not.
      final files = filesIn(
        await exportObz(db, vocabId, recordings: recordings),
      );
      final board = boardIn(files, manifestIn(files).root!);
      expect(board.sounds, isEmpty);
      expect(board.buttons.every((b) => b.soundId == null), isTrue);
    });
  });

  group('what the caregiver is told', () {
    test('a key carrying a recording and no words is counted', () async {
      final notes = <String>[];
      await importObf(
        db,
        obfWithSound(
          label: '',
          sound: {
            'id': 's1',
            'data': recordingDataUri,
            'content_type': 'audio/mpeg',
          },
        ),
        notes: notes,
        recordings: recordings,
      );

      expect(mentions(notes, 'a recording and no words'), isTrue);
    });

    test('a key that has words is not counted as wordless', () async {
      final notes = <String>[];
      await importObf(
        db,
        obfWithSound(
          label: '',
          vocalization: 'I want the red one',
          sound: {
            'id': 's1',
            'data': recordingDataUri,
            'content_type': 'audio/mpeg',
          },
        ),
        notes: notes,
        recordings: recordings,
      );

      expect(mentions(notes, 'a recording and no words'), isFalse);
    });

    test('recordings on pages left out of a file are named', () async {
      final package = zipOf({
        'manifest.json': jsonEncode({
          'format': obfFormat,
          'root': 'boards/1.obf',
          'paths': {
            'boards': {'1': 'boards/1.obf', '2': 'boards/2.obf'},
            'sounds': {'s1': 'sounds/a.mp3', 's2': 'sounds/b.mp3'},
          },
        }),
        'boards/1.obf': jsonEncode({
          'format': obfFormat,
          'id': '1',
          'name': 'home',
          'buttons': [
            {'id': 'a', 'label': 'hello', 'sound_id': 's1'},
          ],
          'grid': {
            'rows': 1,
            'columns': 1,
            'order': [
              ['a'],
            ],
          },
          'sounds': [
            {'id': 's1', 'path': 'sounds/a.mp3', 'content_type': 'audio/mpeg'},
          ],
        }),
        'boards/2.obf': jsonEncode({
          'format': obfFormat,
          'id': '2',
          'name': 'people',
          'buttons': [
            {'id': 'b', 'label': 'mum', 'sound_id': 's2'},
          ],
          'grid': {
            'rows': 1,
            'columns': 1,
            'order': [
              ['b'],
            ],
          },
          'sounds': [
            {'id': 's2', 'path': 'sounds/b.mp3', 'content_type': 'audio/mpeg'},
          ],
        }),
        'sounds/a.mp3': recordingBytes,
        'sounds/b.mp3': otherRecordingBytes,
      });

      await importObz(db, package, recordings: recordings);

      final notes = <String>[];
      await exportObf(
        db,
        (await boardNamed(db, 'home')).id,
        notes: notes,
        recordings: recordings,
      );

      expect(mentions(notes, 'travel with this file'), isTrue);
      expect(mentions(notes, 'stay behind'), isTrue);
    });

    test('a board with no recordings says nothing about them', () async {
      final notes = <String>[];
      final vocabId = await importObf(
        db,
        obfWithSound(soundId: null),
        notes: notes,
        recordings: recordings,
      );
      expect(mentions(notes, 'recorded message'), isFalse);

      final exportNotes = <String>[];
      final files = filesIn(
        await exportObz(
          db,
          vocabId,
          notes: exportNotes,
          recordings: recordings,
        ),
      );

      expect(exportNotes, isEmpty);
      expect(manifestIn(files).sounds, isEmpty);
      expect(boardIn(files, manifestIn(files).root!).sounds, isEmpty);
    });
  });

  group('the store', () {
    test('audio is written under the vocabulary it belongs to', () async {
      final vocabId = await importObf(
        db,
        obfWithSound(
          sound: {
            'id': 's1',
            'data': recordingDataUri,
            'content_type': 'audio/mpeg',
          },
        ),
        recordings: recordings,
      );

      final folder = Directory(
        '${documents.path}/${RecordingStore.folder}/$vocabId',
      );
      expect(folder.existsSync(), isTrue);
      expect(
        folder.listSync().map((e) => e.path.split('/').last),
        containsAll(<String>['1.mp3', 'index.json']),
      );
    });

    test('audio gone from the device is reported, not faked', () async {
      final vocabId = await importObf(
        db,
        obfWithSound(
          sound: {
            'id': 's1',
            'data': recordingDataUri,
            'content_type': 'audio/mpeg',
          },
        ),
        recordings: recordings,
      );
      File('${documents.path}/${RecordingStore.folder}/$vocabId/1.mp3')
          .deleteSync();

      final notes = <String>[];
      final files = filesIn(
        await exportObz(db, vocabId, notes: notes, recordings: recordings),
      );

      expect(mentions(notes, 'no longer on this device'), isTrue);
      final board = boardIn(files, manifestIn(files).root!);
      expect(board.sounds, isEmpty);
      expect(board.buttons.every((b) => b.soundId == null), isTrue);
    });

    test('one recording on six keys is one file and one sound', () async {
      final vocabId = await importObf(
        db,
        jsonEncode({
          'format': obfFormat,
          'id': 'shared-1',
          'name': 'shared',
          'buttons': [
            for (var i = 1; i <= 3; i++)
              {'id': '$i', 'label': 'key $i', 'sound_id': 's1'},
          ],
          'grid': {
            'rows': 1,
            'columns': 3,
            'order': [
              ['1', '2', '3'],
            ],
          },
          'sounds': [
            {
              'id': 's1',
              'data': recordingDataUri,
              'content_type': 'audio/mpeg',
            },
          ],
        }),
        recordings: recordings,
      );

      final files = filesIn(
        await exportObz(db, vocabId, recordings: recordings),
      );
      expect(files.keys.where((n) => n.startsWith('sounds/')), hasLength(1));

      final board = boardIn(files, manifestIn(files).root!);
      expect(board.sounds, hasLength(1));
      expect(board.buttons.map((b) => b.soundId).toSet(), {
        board.sounds.single.id,
      });
    });
  });

  group('the route a caregiver takes', () {
    test(
      'a file from the folder leaves with the voice it arrived with',
      () async {
        final boards = BoardFileStore(
          db,
          documentsDirectory: () async => documents,
        );
        final folder = Directory('${documents.path}/${BoardFileStore.folder}')
          ..createSync(recursive: true);
        final file = File('${folder.path}/banked.obz')
          ..writeAsBytesSync(bankedPackage());

        final imported = await boards.import((
          path: file.path,
          name: 'banked.obz',
          bytes: file.lengthSync(),
          at: DateTime.now(),
        ));
        expect(imported.problem, isNull);
        expect(mentions(imported.notes, 'kept with it'), isTrue);

        final vocabulary = (await db.select(db.vocabularies).get()).single;
        final exported = await boards.export(
          vocabularyId: vocabulary.id,
          scope: ExportScope.boardSet,
        );
        expect(mentions(exported.notes, 'travel with this file'), isTrue);

        final written = filesIn(File(exported.file.path).readAsBytesSync());
        final board = boardIn(written, manifestIn(written).root!);
        expect(written[board.sounds.single.path]!.readBytes(), recordingBytes);
      },
    );
  });
}
