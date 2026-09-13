import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'obf_model.dart';

/// A recording that came in on a button.
///
/// [fileName] names bytes in the vocabulary's folder; [url] names a file this
/// app will not go and get. One or the other, never both.
typedef Recording = ({
  String id,
  String? fileName,
  String? url,
  String? contentType,
  int? duration,
  ObfLicense? license,
});

/// A button's recording on its way in, with the bytes where the package
/// carried them as a file of its own.
typedef PendingRecording = ({
  String buttonId,
  ObfSound sound,
  Uint8List? bytes,
});

/// What became of the recordings an import offered.
///
/// Counted per recording rather than per key: one recording shared by six keys
/// is one thing kept, and six is a number that would mislead whoever reads it.
typedef RecordingsKept = ({int kept, int linked, int dropped, bool overBudget});

/// The recordings a board arrived with, kept so that it can leave with them.
///
/// Message banking — a person's own voice, or a sibling's, on the keys they
/// will press — is standard of care in ALS and MND, and those recordings
/// cannot be made again once the voice is gone. This app speaks with a
/// synthesizer and has nothing that plays an arbitrary audio file, so what it
/// can honestly do is carry them: an import files the audio here, an export
/// writes it back out, and a board that came in carrying somebody's voice
/// leaves carrying it.
///
/// Nothing here touches the speech path. A key with a recording speaks its
/// words like any other key, which is the only acceptable answer to audio that
/// cannot be played — silence from a key somebody pressed is not one.
///
/// **On disk rather than in a column.** A snapshot is the whole database
/// copied with `VACUUM INTO` and five of them are kept, so audio in a row is
/// audio copied five times over; `features/speech/neural/clip_store.dart` keeps
/// its clips out for the same reason. The cost is the same one that store
/// carries: a restore onto a different device brings the board and not these.
/// The file the board was imported from is the other copy of them.
///
/// A recording belongs to the button row it arrived on. Rebuilding a board set
/// makes new rows, which these do not follow; an export counts what stayed
/// behind and says so.
class RecordingStore {
  RecordingStore({
    Future<Directory> Function()? documentsDirectory,
    this.budgetBytes = defaultBudgetBytes,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  /// How much audio one import may write here.
  final int budgetBytes;

  /// Where recordings live, under the application documents directory.
  ///
  /// One folder per vocabulary, so a board set's audio is one directory and
  /// nothing has to be untangled to find it.
  static const folder = 'recordings';

  /// What one import writes before it starts leaving audio behind.
  ///
  /// The package is already on the tablet and this copies what is in it. A
  /// file naming half a gigabyte of audio must not be able to fill the device
  /// somebody speaks with; past this, recordings stay in the file they came in
  /// and the import says how many did.
  static const defaultBudgetBytes = 64 * 1024 * 1024;

  static const _indexName = 'index.json';

  /// Files the audio [incoming] carries and records which key each one is on.
  ///
  /// Never throws. An import that has already placed a board set must not fail
  /// over audio it could not write; what did not survive comes back in the
  /// counts for the screen to read out.
  Future<RecordingsKept> keep(
    String vocabularyId,
    List<PendingRecording> incoming,
  ) async {
    if (incoming.isEmpty) {
      return (kept: 0, linked: 0, dropped: 0, overBudget: false);
    }

    final sounds = <String, Recording>{};
    final buttons = <String, String>{};
    var kept = 0;
    var linked = 0;
    var dropped = 0;
    var overBudget = false;

    try {
      final directory = Directory(await _pathOf(vocabularyId));
      await directory.create(recursive: true);

      final ids = <String, String>{};
      final decided = <String>{};
      var spent = 0;

      for (final item in incoming) {
        final known = ids[item.sound.id];
        if (known != null) {
          buttons[item.buttonId] = known;
          continue;
        }
        // A sound several keys share is one decision, counted once.
        if (!decided.add(item.sound.id)) continue;

        final id = '${sounds.length + 1}';
        final payload = _payloadOf(item.sound, item.bytes);
        final bytes = payload.bytes;

        if (bytes == null) {
          final url = item.sound.url;
          if (url == null) {
            dropped++;
            continue;
          }
          // Left as a link deliberately. Reaching for it would put a network
          // between a person and a key they have already pressed.
          sounds[id] = (
            id: id,
            fileName: null,
            url: url,
            contentType: payload.contentType,
            duration: item.sound.duration,
            license: item.sound.license,
          );
          linked++;
        } else if (spent + bytes.length > budgetBytes) {
          overBudget = true;
          dropped++;
          continue;
        } else {
          final name = '$id${audioExtension(payload.contentType)}';
          await File(p.join(directory.path, name))
              .writeAsBytes(bytes, flush: true);
          spent += bytes.length;
          sounds[id] = (
            id: id,
            fileName: name,
            url: null,
            contentType: payload.contentType,
            duration: item.sound.duration,
            license: item.sound.license,
          );
          kept++;
        }

        ids[item.sound.id] = id;
        buttons[item.buttonId] = id;
      }

      // Written once, after the audio it points at. An index naming a file
      // that is not there is a recording that reads as present and is not.
      await File(p.join(directory.path, _indexName)).writeAsString(
        jsonEncode({
          'sounds': {
            for (final entry in sounds.entries)
              entry.key: {
                'file': entry.value.fileName,
                'url': entry.value.url,
                'content_type': entry.value.contentType,
                'duration': entry.value.duration,
                'license': entry.value.license?.toJson(),
              },
          },
          'buttons': buttons,
        }),
        flush: true,
      );
    } catch (_) {
      return (
        kept: 0,
        linked: 0,
        dropped: {for (final item in incoming) item.sound.id}.length,
        overBudget: false,
      );
    }

    return (
      kept: kept,
      linked: linked,
      dropped: dropped,
      overBudget: overBudget,
    );
  }

  /// Every recording this vocabulary holds, keyed by the button it is on.
  ///
  /// Empty for a vocabulary that came from anywhere but an import carrying
  /// audio, and empty for an index that will not read — which costs an export
  /// its recordings and must not cost it the board.
  Future<Map<String, Recording>> of(String vocabularyId) async {
    try {
      final file = File(p.join(await _pathOf(vocabularyId), _indexName));
      if (!await file.exists()) return const {};

      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final sounds = <String, Recording>{};
      for (final entry in (json['sounds']! as Map).entries) {
        final id = entry.key.toString();
        final value = entry.value as Map;
        final license = value['license'];
        sounds[id] = (
          id: id,
          fileName: value['file'] as String?,
          url: value['url'] as String?,
          contentType: value['content_type'] as String?,
          duration: value['duration'] as int?,
          license: license == null
              ? null
              : ObfLicense.fromJson({
                  for (final e in (license as Map).entries)
                    e.key.toString(): e.value,
                }),
        );
      }

      return {
        for (final entry in (json['buttons']! as Map).entries)
          entry.key.toString(): ?sounds[entry.value.toString()],
      };
    } catch (_) {
      return const {};
    }
  }

  /// The audio behind [recording], or null for one that is a link or has gone
  /// missing off this device.
  Future<Uint8List?> bytes(String vocabularyId, Recording recording) async {
    final name = recording.fileName;
    if (name == null) return null;
    try {
      final file = File(p.join(await _pathOf(vocabularyId), name));
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _pathOf(String vocabularyId) async =>
      p.join((await _documentsDirectory()).path, folder, vocabularyId);
}

/// The audio a sound names, and what to call it.
///
/// [carried] is what an `.obz` held at the sound's `path`; a `data:` URI is
/// read here. A `url` names nothing on this device and is handled by the
/// caller, which keeps the link rather than following it.
({Uint8List? bytes, String? contentType}) _payloadOf(
  ObfSound sound,
  Uint8List? carried,
) {
  final declared = sound.contentType ?? audioContentType(sound.path);
  if (carried != null) return (bytes: carried, contentType: declared);

  final data = sound.data;
  if (data == null) return (bytes: null, contentType: declared);

  try {
    final uri = UriData.parse(data);
    final mime = uri.mimeType;
    return (
      bytes: uri.contentAsBytes(),
      // `UriData` answers text/plain for a URI that declares nothing, which
      // would name the file as something it is not.
      contentType: declared ?? (mime.startsWith('audio/') ? mime : null),
    );
  } catch (_) {
    return (bytes: null, contentType: declared);
  }
}

const _audioTypes = <String, String>{
  '.mp3': 'audio/mpeg',
  '.m4a': 'audio/mp4',
  '.mp4': 'audio/mp4',
  '.aac': 'audio/aac',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg',
  '.oga': 'audio/ogg',
  '.opus': 'audio/opus',
  '.webm': 'audio/webm',
  '.flac': 'audio/flac',
  '.caf': 'audio/x-caf',
  '.amr': 'audio/amr',
  '.3gp': 'audio/3gpp',
};

/// Media type for a file name, or null where the name says nothing.
String? audioContentType(String? path) =>
    path == null ? null : _audioTypes[p.url.extension(path).toLowerCase()];

/// File extension for a media type.
///
/// `.bin` for a type nothing here recognizes: the bytes are kept either way,
/// and a name that claimed a format they are not is worse than one that claims
/// nothing.
String audioExtension(String? contentType) {
  if (contentType == null) return '.bin';
  final type = contentType.split(';').first.trim().toLowerCase();
  for (final entry in _audioTypes.entries) {
    if (entry.value == type) return entry.key;
  }
  return switch (type) {
    'audio/mp3' || 'audio/x-mpeg' => '.mp3',
    'audio/x-m4a' => '.m4a',
    'audio/x-wav' || 'audio/wave' || 'audio/vnd.wave' => '.wav',
    'audio/x-flac' => '.flac',
    _ => '.bin',
  };
}
