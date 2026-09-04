/// The downloaded model, behind whichever runtime this host can run it on.
///
/// A tablet runs Kokoro through `sherpa_onnx`'s native library over FFI, off
/// the main isolate because `generate()` blocks the thread it is called on. A
/// browser runs the same model through the same project's WebAssembly build,
/// which is a different loading story and a different threading story, and
/// nothing above this file has to know which.
library;

export 'kokoro_native.dart'
    if (dart.library.js_interop) 'kokoro_web.dart';
