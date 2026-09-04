import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Writes a clean copy of [source] to [destination].
///
/// `VACUUM INTO` through a connection of its own rather than a byte copy. A
/// run killed mid-write leaves a rollback journal beside the database, and the
/// database alone is then a file that needs a rollback nobody copied; opening
/// it is the recovery, so the copy is written by a connection that has already
/// performed one.
void copyDatabaseFile(File source, String destination) {
  final handle = raw.sqlite3.open(source.path);
  try {
    handle.execute('VACUUM INTO ?', [destination]);
  } finally {
    handle.close();
  }
}

/// An executor over [file], for letting drift's own migration run against it.
QueryExecutor openDatabaseFile(File file) => NativeDatabase(file);

/// Whether SQLite can read every page of [file], not just its header.
///
/// `quick_check` is what tells a whole database from the first third of one.
/// Read-only, so a file that turns out to be damaged is not written to on the
/// way to finding out.
bool databaseIsWhole(File file) {
  try {
    final handle = raw.sqlite3.open(file.path, mode: raw.OpenMode.readOnly);
    try {
      final rows = handle.select('PRAGMA quick_check');
      return rows.length == 1 && rows.first.values.first == 'ok';
    } finally {
      handle.close();
    }
  } catch (_) {
    return false;
  }
}
