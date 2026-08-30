import 'dart:io';

import 'package:path/path.dart' as p;

/// A copy of the board as it stood at one moment, sitting on this tablet.
///
/// It never leaves the device. There is no upload, no account, and no
/// synchronisation anywhere in this feature — the usage log inside a snapshot
/// is a record of a disabled person's private speech, and the only place it is
/// safe is the tablet it was said on. A caregiver who wants a copy elsewhere
/// has to move the file themselves, deliberately.
///
/// [schemaVersion] is read out of the file rather than taken from its name, so
/// a snapshot cannot claim to be readable by lying about what wrote it.
typedef Snapshot = ({
  String path,
  DateTime takenAt,
  int bytes,
  int schemaVersion,
});

const _prefix = 'wordbridge-';
const _extension = '.db';

/// Names a snapshot after the instant it was taken, in UTC.
///
/// The instant lives in the name rather than in the file's modification time
/// because copying a folder off a tablet and back rewrites modification times,
/// and a caregiver restoring after a bad update is choosing by date. A name
/// that survives a round trip through a file manager is the only version of
/// that date worth showing them.
///
/// Compact ISO-8601, so the names sort into chronological order and the
/// oldest can be found without opening anything. Colons are omitted because
/// they are not legal in a filename on every platform this runs on.
String snapshotFileName(DateTime takenAt) {
  final t = takenAt.toUtc();
  String pad(int value, int width) => value.toString().padLeft(width, '0');

  return '$_prefix'
      '${pad(t.year, 4)}${pad(t.month, 2)}${pad(t.day, 2)}'
      'T'
      '${pad(t.hour, 2)}${pad(t.minute, 2)}${pad(t.second, 2)}'
      '${pad(t.millisecond, 3)}'
      'Z$_extension';
}

/// The instant in a snapshot's name, or null if the name is not one of ours.
///
/// Returning null rather than guessing keeps anything else a caregiver has put
/// in the folder out of the list they are offered to restore from.
DateTime? snapshotTakenAt(String fileName) {
  final name = p.basename(fileName);
  if (!name.startsWith(_prefix) || !name.endsWith(_extension)) return null;

  final stamp = name.substring(_prefix.length, name.length - _extension.length);
  if (stamp.length != 19 || stamp[8] != 'T' || stamp[18] != 'Z') return null;

  int? at(int start, int end) => int.tryParse(stamp.substring(start, end));

  final year = at(0, 4);
  final month = at(4, 6);
  final day = at(6, 8);
  final hour = at(9, 11);
  final minute = at(11, 13);
  final second = at(13, 15);
  final millisecond = at(15, 18);

  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null ||
      second == null ||
      millisecond == null) {
    return null;
  }

  return DateTime.utc(year, month, day, hour, minute, second, millisecond);
}

/// The schema version SQLite recorded in the file, or null if it is not a
/// SQLite database.
///
/// Read straight out of the 100-byte header instead of by opening a
/// connection. Listing what a caregiver can restore from must not depend on
/// every file in the folder being openable: one truncated snapshot would
/// otherwise take the whole list with it, at the moment the list is the only
/// way back.
Future<int?> snapshotSchemaVersion(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final header = await handle.read(64);
    if (header.length < 64) return null;

    // Anything else in this folder is not a snapshot, whatever it has been
    // named, and the four bytes at offset 60 would be somebody's holiday photo
    // rather than a schema version.
    const magic = 'SQLite format 3\x00';
    for (var i = 0; i < magic.length; i++) {
      if (header[i] != magic.codeUnitAt(i)) return null;
    }

    // user_version: four bytes, big-endian, at offset 60. Drift writes the
    // schema version there, so it is the one number that says whether this
    // file can be read by the code holding it.
    return (header[60] << 24) |
        (header[61] << 16) |
        (header[62] << 8) |
        header[63];
  } on FileSystemException {
    return null;
  } finally {
    await handle?.close();
  }
}
