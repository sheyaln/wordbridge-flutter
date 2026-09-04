/// Drawing a picture that lives in a file.
///
/// The two kinds of picture that reach a button this way are a photo somebody
/// took and a drawing fetched on demand, and both of them are a path on a
/// disk. A host with no disk has neither, so this is the one place that has to
/// differ rather than every caller.
library;

export 'symbol_file_native.dart'
    if (dart.library.js_interop) 'symbol_file_web.dart';
