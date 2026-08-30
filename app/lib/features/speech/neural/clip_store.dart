import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'audio_clip.dart';

/// Every word this profile can say, as audio, in one file.
///
/// **One file, not 1231 of them.** Measured: at 48 kbps over the mean clip of
/// 569 ms the audio is 3.4 KB and an `.m4a` of it is 8.2 KB — at half a second
/// a clip the container header *is* the file, and 1231 directory entries cost
/// more than the speech does. So the clips are stored bare, end to end, and an
/// index says where each one starts.
///
/// **Not in the database, either.** Board layout is user data and is backed up
/// five times over with `VACUUM INTO`; audio is regenerable and thirty
/// megabytes of it. Putting the two together would multiply every backup by
/// the cache and copy it again on every restore, to protect something a bake
/// can rebuild.
///
/// A pack belongs to one voice **at one speed**. Speed is baked in — Kokoro
/// takes it as a generation parameter, not a playback rate — so changing
/// either invalidates the lot, which is why both are in [packId] and why the
/// caregiver screen has to say so before it happens.
class ClipStore {
  ClipStore._(
    this._pack,
    this._index,
    this.packId,
    this._entries,
    this._sampleRate,
  );

  final File _pack;
  final File _index;
  final String packId;
  final Map<String, _Entry> _entries;
  int _sampleRate;

  RandomAccessFile? _reader;

  /// What a pack of this voice at this speed is called.
  ///
  /// Speed to the nearest hundredth, because a slider that reports 0.8199999
  /// must not be a different cache from one that reports 0.82.
  /// Names the pack a clip belongs in.
  ///
  /// [recipe] is bumped whenever what the model is *given* changes, not just
  /// when the voice or speed does. Clips made under an older recipe are still
  /// playable and still wrong — they were made from a different string — so
  /// they have to be retired rather than reused. Recipe 2 added the terminal
  /// full stop that stops a single word ending in a schwa.
  static const recipe = 2;

  static String idFor(String voiceId, double speed) =>
      '$voiceId-r${(speed * 100).round()}-v$recipe';

  static const _headerPrefix = '#wordbridge-clips 1 ';

  /// The clips already made, so the bake knows what is left rather than
  /// synthesising 1231 words to discover it has them.
  Iterable<String> get texts => _entries.keys;

  int get count => _entries.length;

  int get sampleRate => _sampleRate;

  int get bytesOnDisk =>
      (_pack.existsSync() ? _pack.lengthSync() : 0) +
      (_index.existsSync() ? _index.lengthSync() : 0);

  bool contains(String text) => _entries.containsKey(text);

  /// Opens a pack, rebuilding what the index can still be trusted about.
  ///
  /// Audio is written before the index entry that points at it, so a process
  /// killed between the two leaves bytes nothing refers to — wasted, and
  /// harmless. The reverse order would leave an entry pointing past the end of
  /// the file, which is a word that plays as a crash.
  ///
  /// An entry that does point past the end is therefore taken as the moment
  /// the tablet was interrupted, and everything from there is dropped.
  static Future<ClipStore> open({
    required Directory root,
    required String packId,
  }) async {
    root.createSync(recursive: true);
    final pack = File(p.join(root.path, '$packId.pack'));
    final index = File(p.join(root.path, '$packId.index'));

    final entries = <String, _Entry>{};
    var sampleRate = 0;

    if (index.existsSync() && pack.existsSync()) {
      final packLength = pack.lengthSync();
      final kept = <String>[];
      var truncated = false;

      for (final line in await index.readAsLines()) {
        if (line.isEmpty) continue;
        if (line.startsWith(_headerPrefix)) {
          sampleRate = int.tryParse(line.substring(_headerPrefix.length)) ?? 0;
          kept.add(line);
          continue;
        }
        final parts = line.split(',');
        if (parts.length != 3) {
          truncated = true;
          break;
        }
        final offset = int.tryParse(parts[0]);
        final length = int.tryParse(parts[1]);
        if (offset == null || length == null || offset + length > packLength) {
          truncated = true;
          break;
        }
        entries[utf8.decode(base64Decode(parts[2]))] = (
          offset: offset,
          length: length,
        );
        kept.add(line);
      }

      // Rewritten rather than left with a torn tail, so the same lines are not
      // re-read and re-rejected on every launch for the life of the pack.
      if (truncated) await index.writeAsString('${kept.join('\n')}\n');
    }

    return ClipStore._(pack, index, packId, entries, sampleRate);
  }

  /// The audio for [text], or null where it was never baked.
  ///
  /// Null is the whole of the cache-miss signal. It is not an error and it
  /// must not be treated as one: a miss on the tap path speaks in the platform
  /// voice and does so now.
  Future<AudioClip?> read(String text) async {
    final entry = _entries[text];
    if (entry == null) return null;

    try {
      final reader = _reader ??= await _pack.open();
      await reader.setPosition(entry.offset);
      final bytes = await reader.read(entry.length);
      if (bytes.lengthInBytes != entry.length) return null;
      return (pcm16: bytes, sampleRate: _sampleRate);
    } catch (_) {
      // A pack that has gone missing under a running app is a miss, not a
      // crash. The ladder below it still speaks.
      return null;
    }
  }

  /// Adds [clip], and only then says where it is.
  ///
  /// Both writes are flushed. An index entry that outlives the audio it points
  /// at is the one failure this file cannot recover from at read time.
  Future<void> write(String text, AudioClip clip) async {
    if (_entries.containsKey(text)) return;

    if (_sampleRate == 0) {
      _sampleRate = clip.sampleRate;
      await _index.writeAsString(
        '$_headerPrefix${clip.sampleRate}\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    // The end of the file, not the end of the index. An interrupted write may
    // have left bytes behind, and appending after them is free; appending over
    // them is not.
    final offset = _pack.existsSync() ? _pack.lengthSync() : 0;
    await _pack.writeAsBytes(clip.pcm16, mode: FileMode.append, flush: true);
    await _index.writeAsString(
      '$offset,${clip.pcm16.lengthInBytes},'
      '${base64Encode(utf8.encode(text))}\n',
      mode: FileMode.append,
      flush: true,
    );

    _entries[text] = (offset: offset, length: clip.pcm16.lengthInBytes);
  }

  Future<void> close() async {
    await _reader?.close();
    _reader = null;
  }

  /// Throws this pack away. Used when the voice or the speed changes, which
  /// makes every clip in it wrong rather than stale.
  Future<void> delete() async {
    await close();
    if (_pack.existsSync()) _pack.deleteSync();
    if (_index.existsSync()) _index.deleteSync();
    _entries.clear();
    _sampleRate = 0;
  }

  /// Where packs live, under the same directory as the model.
  static Directory directoryIn(Directory neuralVoiceRoot) =>
      Directory(p.join(neuralVoiceRoot.path, 'clips'));

  /// Removes every pack except [keep].
  ///
  /// Run when a voice is chosen. A tablet that has tried four voices is
  /// carrying four packs, three of which nothing will ever read again, and
  /// this feature is for a device that is short of space.
  static Future<int> pruneTo(Directory root, String keep) async {
    if (!root.existsSync()) return 0;
    var freed = 0;
    for (final entry in root.listSync()) {
      if (entry is! File) continue;
      final name = p.basenameWithoutExtension(entry.path);
      if (name == keep) continue;
      final extension = p.extension(entry.path);
      if (extension != '.pack' && extension != '.index') continue;
      freed += entry.lengthSync();
      entry.deleteSync();
    }
    return freed;
  }
}

typedef _Entry = ({int offset, int length});
