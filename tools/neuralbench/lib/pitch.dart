import 'dart:math' as math;
import 'dart:typed_data';

/// A rough pitch track, good enough to answer one question: does a question
/// mark make the end of a sentence rise?
///
/// Autocorrelation over short windows. Not a speech-research pitch tracker and
/// it does not need to be — what is being compared is two synthesised versions
/// of the same words, on the same voice, so systematic error cancels.
class Pitch {
  static const _minHz = 70.0;
  static const _maxHz = 400.0;

  /// Mean f0 over the voiced windows in [samples], or null if none were.
  static double? meanF0(Float32List samples, int sampleRate) {
    final window = (sampleRate * 0.04).round();
    final hop = (sampleRate * 0.02).round();
    final found = <double>[];

    for (var at = 0; at + window < samples.length; at += hop) {
      final f0 = _windowF0(samples, at, window, sampleRate);
      if (f0 != null) found.add(f0);
    }
    if (found.isEmpty) return null;
    return found.reduce((a, b) => a + b) / found.length;
  }

  /// Mean f0 over the last [share] of the audio, which is where a question
  /// mark does its work.
  static double? finalF0(
    Float32List samples,
    int sampleRate, {
    double share = 0.3,
  }) {
    final from = (samples.length * (1 - share)).round();
    return meanF0(Float32List.sublistView(samples, from), sampleRate);
  }

  static double? _windowF0(
    Float32List samples,
    int at,
    int window,
    int sampleRate,
  ) {
    var energy = 0.0;
    for (var i = 0; i < window; i++) {
      energy += samples[at + i] * samples[at + i];
    }
    // Silence and unvoiced consonants carry no pitch to average in.
    if (math.sqrt(energy / window) < 0.02) return null;

    final minLag = (sampleRate / _maxHz).floor();
    final maxLag = math.min((sampleRate / _minHz).ceil(), window - 1);

    var bestLag = 0;
    var best = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var sum = 0.0;
      for (var i = 0; i + lag < window; i++) {
        sum += samples[at + i] * samples[at + i + lag];
      }
      if (sum > best) {
        best = sum;
        bestLag = lag;
      }
    }
    if (bestLag == 0 || best < energy * 0.3) return null;
    return sampleRate / bestLag;
  }
}
