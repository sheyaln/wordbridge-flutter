import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Storage here belongs to the origin, not to the app.
///
/// A browser will hand back bytes under a key and will also drop every one of
/// them when somebody clears site data, and it does not ask which app the data
/// belonged to. The board itself survives that no better, which is why the web
/// build says on screen that it is somewhere to try the app rather than
/// somewhere to keep a voice.
const hostKeepsFiles = false;

const hostBacksUpOffDevice = false;

const hostName = 'web';

/// The browser's own string for itself.
///
/// Not a version number and not comparable to one — `Platform
/// .operatingSystemVersion` gives a release, and this gives a sentence of
/// vendor history. It is what a browser will say when asked, and a report is
/// better with it than without.
String get hostVersion {
  final navigator = globalContext.getProperty('navigator'.toJS);
  if (navigator == null) return '';
  final agent = (navigator as JSObject).getProperty('userAgent'.toJS);
  return agent == null ? '' : (agent as JSString).toDart;
}
