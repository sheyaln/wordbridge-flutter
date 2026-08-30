import 'dart:math' as math;
import 'dart:typed_data';

/// A piece of speech this app owns the samples of.
///
/// The distinction from platform speech is the whole point: these are bytes,
/// not a call into somebody else's synthesiser, so they can be stored, played
/// again identically, and made louder than the tablet's own maximum.
///
/// Signed 16-bit, little-endian, one channel. Sixteen bits rather than the
/// model's float32 because it halves the pack for no audible loss on speech,
/// and one channel because the model produces one.
typedef AudioClip = ({Uint8List pcm16, int sampleRate});

/// How long [clip] lasts.
Duration clipDuration(AudioClip clip) => Duration(
  microseconds:
      (clip.pcm16.lengthInBytes / 2 / clip.sampleRate * 1000000).round(),
);

/// Anything quieter than this counts as padding rather than speech.
///
/// Kokoro's padding is close to digital silence, so this does not have to be
/// finely judged — it has to be well under the quietest consonant and well
/// over the noise floor, and there are two orders of magnitude between them.
const _silenceFloor = 0.005;

/// Kept either side of the speech, so an onset is never clipped.
///
/// A plosive starts with a near-silent closure. Cutting to the first sample
/// over the floor removes it and the word arrives sounding bitten off.
const _keepMargin = Duration(milliseconds: 20);

/// [samples] with the model's leading and trailing silence taken off.
///
/// Kokoro pads every utterance, and measured over the whole shipped vocabulary
/// the padding is **30% of the bytes** — `I` comes back 660 ms long. Trimming
/// is not only a saving: it is the difference between a tap that speaks and a
/// tap that pauses first, which on this board is the difference that matters.
///
/// A clip that is silent throughout comes back whole. Something that produced
/// no speech is a fault worth hearing as it is rather than as an empty buffer.
Float32List trimSilence(Float32List samples, int sampleRate) {
  var first = 0;
  while (first < samples.length && samples[first].abs() < _silenceFloor) {
    first++;
  }
  if (first == samples.length) return samples;

  var last = samples.length - 1;
  while (last > first && samples[last].abs() < _silenceFloor) {
    last--;
  }

  final margin = (_keepMargin.inMicroseconds * sampleRate / 1000000).round();
  final from = math.max(0, first - margin);
  final to = math.min(samples.length, last + 1 + margin);
  return Float32List.sublistView(samples, from, to);
}

/// Turns the model's floats into the bytes that get stored and played.
///
/// [gain] multiplies before conversion, and may exceed 1.0 — which is the one
/// thing platform speech could never be asked for (§4.4, §5 non-negotiable 5).
/// The shaping is `tanh`-like rather than a hard clip: clipping a voice does
/// not make it louder, it makes it fuzzy, and a person whose only voice this
/// is should not have to choose between quiet and distorted.
Uint8List toPcm16(Float32List samples, {double gain = 1.0}) {
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    var v = samples[i] * gain;
    if (gain != 1.0) v = math.tan(math.atan(v));
    if (v > 1.0) {
      v = 1.0;
    } else if (v < -1.0) {
      v = -1.0;
    }
    out[i] = (v * 32767).round();
  }
  return out.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes);
}
