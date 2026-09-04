import 'package:flutter_tts/flutter_tts.dart';

/// Routes speech to the speaker regardless of the ringer switch.
///
/// Without this an iPad with the ringer switch off is silent, which for an AAC
/// device means a user who cannot speak. Not optional.
Future<void> prepareAudioOutput(FlutterTts tts) =>
    tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
      IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      IosTextToSpeechAudioCategoryOptions.duckOthers,
    ], IosTextToSpeechAudioMode.defaultMode);

/// Turns "1.0 means normal" into the number the plugin wants.
///
/// The plugin's own scale puts ordinary speech at **0.5** on both platforms:
/// iOS passes the number straight to `AVSpeechUtterance.rate`, whose default
/// is 0.5 and whose maximum is 1.0, and the Android side doubles it before
/// handing it to a synthesizer whose normal is 1.0. Sending 1.0 for "normal
/// speed" therefore asks both of them for double, which is too fast to make
/// any of the words out.
double speechRateFor(double rate) => (rate * 0.5).clamp(0.0, 1.0);
