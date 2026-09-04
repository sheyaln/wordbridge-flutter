import 'dart:io' show Directory;

import 'audio_clip.dart';

/// This session's baked words, and no longer.
///
/// The tablet's pack is a file that outlives the app, which is what makes a
/// bake worth starting: half an hour of synthesis is paid for once. A browser
/// is offered nothing it could make the same promise with — origin storage is
/// cleared by a menu item nobody warns the app about — so rather than a cache
/// that is sometimes there, this is a cache that is honestly only for as long
/// as the page is open.
///
/// What that costs is one wait per word per visit, which the ladder above
/// already covers: the first press of a word speaks in the browser's own voice
/// while the model works, and every press after it is this map.
class ClipStore {
  ClipStore._(this.packId);

  final String packId;

  final Map<String, AudioClip> _clips = {};

  /// Bumped when a stored clip stops meaning what it meant, so that a pack
  /// made by an older recipe is not read as if it were current. Kept in step
  /// with the tablet's, because the words are the same words.
  static const recipe = 2;

  /// Which pack a voice at a speed belongs to.
  static String idFor(String voiceId, double speed) =>
      '$voiceId-r${(speed * 100).round()}-v$recipe';

  int get count => _clips.length;

  int get sampleRate => _sampleRate;
  int _sampleRate = 0;

  int get bytesOnDisk => 0;

  bool contains(String text) => _clips.containsKey(text);

  /// Whether a word baked into this pack is still here next time.
  ///
  /// No. Which is why nothing pre-fills it: a bake is thirty minutes of
  /// synthesis, and thirty minutes spent on a pack that dies with the page
  /// would be spent again on the next visit, for words this person may never
  /// press. Filled as they are said instead — the first press of a word waits
  /// or falls back, and every press after it is instant.
  bool get survivesTheSession => false;

  Future<AudioClip?> read(String text) async => _clips[text];

  Future<void> write(String text, AudioClip clip) async {
    _clips[text] = clip;
    _sampleRate = clip.sampleRate;
  }

  Future<void> close() async => _clips.clear();

  Future<void> delete() async => _clips.clear();

  static Future<ClipStore> open({
    required Directory root,
    required String packId,
  }) async => ClipStore._(packId);
}

/// A pack for [packId], made fresh. There is nothing to look for first.
Future<ClipStore> openClipPack({
  required Future<Directory> Function() documentsDirectory,
  required String packId,
}) async => ClipStore._(packId);

/// Nothing to throw away: a pack this session is not using was never written.
Future<int> pruneClipPacks({
  required Future<Directory> Function() documentsDirectory,
  required String keep,
}) async => 0;
