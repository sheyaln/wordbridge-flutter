import 'dart:io';

import 'package:drift/drift.dart';

/// A browser has no file to open and no SQLite of its own to open it with.
///
/// Reached only through backup and restore, which `hostKeepsFiles` already
/// keeps off every screen here. Throwing rather than answering quietly: a
/// backup that reports success without writing anything is the failure the
/// whole feature exists against, and it must not be introduced by a stub.
Never _noFiles() => throw UnsupportedError(
  'The board cannot be copied to a file in a browser.',
);

void copyDatabaseFile(File source, String destination) => _noFiles();

QueryExecutor openDatabaseFile(File file) => _noFiles();

bool databaseIsWhole(File file) => false;
