/// Getting the device ready to be heard.
///
/// One line on a tablet and nothing at all in a browser, but it cannot be a
/// branch at the call site: `flutter_tts` answers the question by asking
/// `Platform.isIOS`, which is an operation a browser does not support and
/// throws rather than declines. Reaching it at all ends the launch.
library;

export 'audio_output_native.dart'
    if (dart.library.js_interop) 'audio_output_web.dart';
