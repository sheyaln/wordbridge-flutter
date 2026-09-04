/// Getting the neural voice onto this host, and saying what that costs.
///
/// A tablet fetches one archive from a fixed GitHub release, checks it against
/// a published digest and unpacks it into its own documents directory — which
/// is a place the app owns and keeps. A browser cannot do any of that: nothing
/// in a page decompresses bzip2, and there is no directory. It fetches the
/// unpacked files from wherever the app itself is served and keeps them in the
/// browser's cache.
///
/// What both sides owe the screen above them is the same: whether the voice is
/// here, what it cost, how far a running install has got, and how to be rid of
/// it.
library;

export 'model_progress.dart';
export 'voice_model_native.dart'
    if (dart.library.js_interop) 'voice_model_web.dart';
