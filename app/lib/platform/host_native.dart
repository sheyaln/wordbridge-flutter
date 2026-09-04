import 'dart:io' show Platform;

/// A directory this app owns, which is still there next month.
const hostKeepsFiles = true;

/// Somewhere off this device a copy of the board can be put.
///
/// Whether *this* device offers one is a further question — see
/// `cloudPlaces`, which asks the platform. This says only that the question is
/// worth asking here.
const hostBacksUpOffDevice = true;

/// What the host calls itself, for a report somebody has chosen to send.
String get hostName => Platform.operatingSystem;

String get hostVersion => Platform.operatingSystemVersion;
