/// What the machine this is running on can be asked for.
///
/// The app ships to two kinds of host now, and the difference is not a matter
/// of degree. A tablet gives it a directory it owns and still owns after an
/// update; a browser gives it an origin that a person can clear from a
/// settings menu without being asked twice, and no filesystem at all. A
/// feature that writes something somebody is expected to still have next month
/// cannot be offered on the second one.
///
/// Answers about capabilities, never a platform name. A screen asks whether it
/// may offer a thing and stays silent otherwise, which is §5 non-negotiable 9
/// — a switch that does nothing is worse than an absent one. This is not
/// `kIsWeb` wearing a different coat: each answer is about one capability, so
/// a host that grows one changes a line here rather than every branch that
/// happened to mention the platform.
library;

export 'host_native.dart' if (dart.library.js_interop) 'host_web.dart';
