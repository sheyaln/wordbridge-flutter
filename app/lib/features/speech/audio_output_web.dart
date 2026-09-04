import 'package:flutter_tts/flutter_tts.dart';

/// Nothing to route. A page is given one output and no say in it.
Future<void> prepareAudioOutput(FlutterTts tts) async {}

/// The Web Speech API is already on the scale this app states rates in.
///
/// `SpeechSynthesisUtterance.rate` puts ordinary speech at 1.0, so the halving
/// the two native plugins need would hand a browser half speed for "normal" —
/// which is the same class of mistake in the other direction, and the reason
/// the mapping belongs to the host rather than to the caller. Clamped to the
/// range the specification defines.
double speechRateFor(double rate) => rate.clamp(0.1, 10.0);
