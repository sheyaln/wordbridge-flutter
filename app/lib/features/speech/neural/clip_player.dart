import 'package:flutter/services.dart';

import 'audio_clip.dart';

/// Plays audio this app made, without writing a file first.
///
/// A separate channel rather than an audio package because the packages do not
/// do this on the device it has to happen on: `audioplayers` answers
/// `setSourceBytes is not currently implemented on iOS`, which leaves a file
/// written between a tap and a word. §4.4 rejected that route for the loudness
/// work, and the reason has not changed.
///
/// A [wavOf] wrapper goes across rather than bare samples, so both platforms
/// receive one self-describing thing and neither side has to be told the
/// sample rate twice.
class ClipPlayer {
  ClipPlayer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_name);

  static const _name = 'org.wordbridge/clip_audio';

  final MethodChannel _channel;

  /// Whether the last call reached a platform that could answer it.
  ///
  /// Read by the caregiver screen: a device with no way to play a buffer
  /// cannot have the neural voice, and it should say so rather than offering a
  /// switch that silently does nothing (§5 non-negotiable 9).
  bool get isAvailable => _available;
  bool _available = true;

  /// Plays [clip] and comes back when it has finished.
  ///
  /// The same promise `FlutterTtsEngine.speak` makes, so the board's auto-
  /// return waits the same way whichever engine is speaking.
  ///
  /// [volume] is a share of the device's own, matching the platform engine's
  /// scale. Gain above 1.0 belongs to the samples, not here — see [toPcm16].
  Future<void> play(AudioClip clip, {double volume = 1.0}) async {
    try {
      await _channel.invokeMethod<void>('play', {
        'wav': wavOf(clip),
        'volume': volume.clamp(0.0, 1.0),
      });
      _available = true;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // A clip that will not play is a word the user does not get, and the
      // ladder above this can still speak it. Failing loudly here would take
      // the sentence with it.
      _available = false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
  }
}
