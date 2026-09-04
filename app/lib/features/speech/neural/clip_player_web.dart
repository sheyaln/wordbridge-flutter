import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:web/web.dart' as web;

import 'audio_clip.dart';

/// Plays a clip through Web Audio, and comes back when it has finished.
///
/// The same promise the platform channel makes, so the board's auto-return
/// waits the same way whichever engine is speaking.
///
/// **The context is resumed on every play.** A browser starts an
/// `AudioContext` suspended unless it was created inside a gesture, and
/// suspends it again when the tab goes to the background. Every call here is
/// on the far side of a tap, which is the gesture that makes the resume
/// allowed; asking once at startup would give a board that goes silent the
/// first time somebody switches tab and comes back.
class ClipPlayer {
  /// [channel] is what the tablet's player takes and is ignored here, so a
  /// caller that constructs one either way does not have to know which it got.
  ClipPlayer({MethodChannel? channel});

  web.AudioContext? _context;
  web.AudioBufferSourceNode? _playing;

  /// Whether Web Audio answered. False only where the browser has none at all,
  /// in which case the neural voice cannot be offered — see §5
  /// non-negotiable 9.
  bool get isAvailable => _available;
  bool _available = true;

  web.AudioContext? _open() {
    final existing = _context;
    if (existing != null) return existing;
    try {
      return _context = web.AudioContext();
    } catch (_) {
      _available = false;
      return null;
    }
  }

  Future<void> play(AudioClip clip, {double volume = 1.0}) async {
    final context = _open();
    if (context == null) return;

    try {
      if (context.state != 'running') await context.resume().toDart;

      await stop();

      final samples = _samples(clip.pcm16);
      final buffer = context.createBuffer(
        1,
        samples.length,
        clip.sampleRate.toDouble(),
      );
      buffer.copyToChannel(samples.toJS, 0);

      final gain = context.createGain();
      gain.gain.value = volume.clamp(0.0, 1.0);
      gain.connect(context.destination);

      final source = context.createBufferSource();
      source.buffer = buffer;
      source.connect(gain);

      final finished = Completer<void>();
      source.onended = (JSAny _) {
        if (!finished.isCompleted) finished.complete();
      }.toJS;

      _playing = source;
      source.start();
      await finished.future;
      _available = true;
    } catch (_) {
      // A clip that will not play is a word the user does not get, and the
      // ladder above this can still speak it. Failing loudly here would take
      // the sentence with it.
      _available = false;
    } finally {
      _playing = null;
    }
  }

  Future<void> stop() async {
    final playing = _playing;
    _playing = null;
    if (playing == null) return;
    try {
      playing.stop();
    } catch (_) {
      // Already finished, or never started.
    }
  }

  /// Signed 16-bit little-endian, as [toPcm16] wrote it, back to the floats
  /// Web Audio wants.
  static Float32List _samples(Uint8List pcm16) {
    final bytes = ByteData.view(
      pcm16.buffer,
      pcm16.offsetInBytes,
      pcm16.lengthInBytes,
    );
    final out = Float32List(pcm16.lengthInBytes ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = bytes.getInt16(i * 2, Endian.little) / 32768;
    }
    return out;
  }
}
