/// A voice's baked words, wherever this host can keep them.
///
/// A tablet files them: one pack per voice per speed, appended to as words are
/// baked, and read back on the next launch so half an hour of synthesis is
/// paid for once. A browser has nowhere to file them that is worth the
/// promise, so it keeps a session's worth in memory and says so.
///
/// The engine above this holds a pack and asks it three questions — does it
/// have this word, give me this word, keep this word — and none of those
/// depend on where the answer is kept.
library;

export 'clip_store_native.dart'
    if (dart.library.js_interop) 'clip_store_web.dart';
