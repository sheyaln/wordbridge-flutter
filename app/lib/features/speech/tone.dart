/// The ways of speaking that platform text-to-speech can honestly produce.
///
/// `flutter_tts` exposes three dials — rate, pitch and volume — and nothing
/// else. Every tone here is built from those three, and the list stops exactly
/// where they stop.
///
/// **What is deliberately absent, and why.** Sarcasm needs a prosodic contour
/// — a particular rise and fall across a sentence — that no platform engine
/// lets an app specify. A whisper needs breathiness, which is not a parameter
/// at all; low volume and low pitch sound like a quiet voice, not a whispering
/// one. Both were asked for and neither is here, because a preset that does
/// not do what its name says is worse than a missing one — most of all for
/// someone who cannot hear the mismatch and correct it, and who will be taken
/// to mean whatever came out.
///
/// These need a bundled neural voice rather than the platform's. Until there
/// is one, this list is what is true.
enum Tone {
  /// The voice as chosen, unmodified.
  normal(label: 'Normal', rate: 1.0, pitch: 1.0, volume: 1.0),

  /// Slower and a little lower. Genuinely reads as unhurried.
  calm(label: 'Calm', rate: 0.82, pitch: 0.92, volume: 0.95),

  /// Faster, higher and at full volume. Genuinely reads as pressing, which
  /// matters most for the sentences that are: "stop", "it hurts", "help".
  urgent(label: 'Urgent', rate: 1.25, pitch: 1.18, volume: 1.0),

  /// Quiet, and named for what it is rather than what was asked for. This is
  /// the same voice turned down, not a whisper.
  quiet(label: 'Quiet', rate: 0.95, pitch: 1.0, volume: 0.35);

  const Tone({
    required this.label,
    required this.rate,
    required this.pitch,
    required this.volume,
  });

  final String label;

  /// Multipliers on the profile's own settings, not absolute values. A user
  /// who has set a slow rate because that is what they follow should get a
  /// slower urgent, not everybody's urgent.
  final double rate;
  final double pitch;
  final double volume;

  /// The fastest [applyTone] will hand the engine, which is the top of the
  /// platform scale once `FlutterTtsEngine.engineRate` has halved it.
  static const maxRate = 2.0;

  /// The largest profile rate this tone carries before [maxRate] takes over.
  ///
  /// Every setting above it speaks at the same speed, so a screen offering
  /// rates past it has to say where it stops.
  double get rateCeiling => maxRate / rate;

  static Tone byName(String? name) {
    for (final tone in values) {
      if (tone.name == name) return tone;
    }
    return normal;
  }
}

/// Rate, pitch and volume as they will be handed to the engine.
///
/// Clamped, because the multipliers can take a profile that already sits near
/// an end of a range past it. Both platforms accept pitch only within 0.5–2.0
/// and volume within 0.0–1.0, and refuse anything outside those ranges
/// silently: the plugin answers with a status code the Dart wrapper drops, so
/// an out-of-range dial does not fail, it leaves the previous value in force —
/// a voice that sounds like the last one somebody set, with nothing on screen
/// to say so.
typedef VoiceParameters = ({double rate, double pitch, double volume});

VoiceParameters applyTone(
  Tone tone, {
  required double rate,
  required double pitch,
  required double volume,
}) => (
  rate: _clamp(rate * tone.rate, min: 0.1, max: Tone.maxRate),
  pitch: _clamp(pitch * tone.pitch, min: 0.5, max: 2.0),
  volume: _clamp(volume * tone.volume, min: 0.0, max: 1.0),
);

double _clamp(double value, {required double min, required double max}) =>
    value < min
    ? min
    : value > max
    ? max
    : value;
