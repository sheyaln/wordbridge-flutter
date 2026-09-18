/// Where a file this device owns actually is, now (§4.90).
///
/// **iOS moves the app's data container.** Its path carries a UUID —
/// `/var/mobile/Containers/Data/Application/<UUID>/Documents/…` — and that
/// UUID is not stable: a reinstall, and sometimes a restore or an OS
/// migration, hands the same app a new one. Every absolute path written down
/// before that point then names a file that does not exist, while the file
/// itself is sitting safely under the new container with the same name.
///
/// This cost a caregiver a photograph and cost a long time to find, because
/// nothing about it looks like a bug: the picker takes the photo, writes the
/// file and records the row, and the button goes on showing its word. The
/// picture is not lost and not broken — it is being looked for in last
/// week's folder.
///
/// So a stored path is treated as a *hint*, never as an address. What is
/// trusted is the part after `Documents/`, which is ours and stable; the part
/// before it belongs to the operating system and is re-derived every time.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The documents directory, looked up once.
///
/// Injectable for tests, and cached because resolving a path happens on the
/// draw of every cell carrying a photograph.
Future<Directory> Function() storedPathRoot = getApplicationDocumentsDirectory;

String? _cachedRoot;

/// Forgets the cached documents directory. Tests that change the root call it.
void resetStoredPathRoot() => _cachedRoot = null;

/// The part of [uri] that belongs to this app rather than to the OS.
///
/// Everything after the last `Documents/` segment, or the bare file name when
/// there is no such segment. Returns null for a path that is already relative,
/// because there is nothing to strip.
String? relativeStoredPath(String uri) {
  const marker = '/Documents/';
  final at = uri.lastIndexOf(marker);
  if (at >= 0) return uri.substring(at + marker.length);
  if (p.isAbsolute(uri)) return p.basename(uri);
  return null;
}

/// The path to read [uri] from, or null when no such file is on this device.
///
/// Tries the stored path first — it is right on every platform whose container
/// does not move, and on iOS until the container does — and then the same file
/// re-rooted under the current documents directory.
///
/// [root] is for a caller that already knows its own documents directory, so
/// one that was handed a directory does not go and ask the platform for a
/// different one.
Future<String?> resolveStoredPath(
  String uri, {
  Future<Directory> Function()? root,
}) async {
  if (uri.isEmpty) return null;

  if (p.isAbsolute(uri) && await File(uri).exists()) return uri;

  final base = root == null
      ? (_cachedRoot ??= (await storedPathRoot()).path)
      : (await root()).path;
  final relative = p.isAbsolute(uri) ? relativeStoredPath(uri) : uri;
  if (relative == null || relative.isEmpty) return null;

  final rerooted = p.join(base, relative);
  if (await File(rerooted).exists()) return rerooted;

  return null;
}
