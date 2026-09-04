/// Somewhere to keep the PIN's salt that is not the board's database.
///
/// The point is separation, not secrecy in itself: keeping the salt out of
/// `wordbridge.sqlite` means somebody who copies that file off a tablet still
/// cannot brute-force the PIN offline. What that separation is worth depends
/// entirely on the host, and the two hosts differ — see each side.
library;

export 'device_secret_native.dart'
    if (dart.library.js_interop) 'device_secret_web.dart';
