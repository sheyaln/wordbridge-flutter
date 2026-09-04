/// SQLite against a file nothing has open, for the three moments drift cannot
/// cover.
///
/// Each of these needs the database as a *file* rather than as a connection:
/// the copy taken before a migration runs, the staged upgrade of a snapshot
/// written by an older build, and the check that a downloaded file is a whole
/// database rather than the first third of one. All three are backup and
/// restore, and none of them means anything on a host with no files.
library;

export 'sqlite_file_native.dart'
    if (dart.library.js_interop) 'sqlite_file_web.dart';
