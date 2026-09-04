/// Playing audio this app made, on whatever this host plays audio with.
///
/// A tablet has a platform channel written for it, because the audio packages
/// do not do this on the device it has to happen on. A browser has Web Audio,
/// which does exactly this and nothing else. Both take the samples as they are
/// stored, with their rate beside them: wrapping them in a container first
/// would be a header to write and parse on every tap for something both sides
/// already know.
library;

export 'clip_player_native.dart'
    if (dart.library.js_interop) 'clip_player_web.dart';
