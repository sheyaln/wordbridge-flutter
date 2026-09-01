import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'scrub.dart';

/// A fault that was caught, waiting to be shown to somebody (§4.52).
typedef CrashRecord = ({String id, DateTime at, String detail});

/// Where a caught fault waits until a caregiver has time for it.
///
/// **A crash does not end the session.** `installFallbackBoard` means the user
/// is still holding a tablet that still talks, and interrupting somebody
/// mid-sentence to ask about a stack trace would be the wrong thing at the
/// wrong moment. So the record is written and nothing else happens; the offer
/// to send it appears the next time an adult opens settings.
///
/// **Written on the way down, never sent on the way down.** A process that is
/// failing is not given a network call to finish. It is given one small
/// synchronous file write that cannot throw, and everything else waits for a
/// process that is alive.
class CrashStore {
  CrashStore({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  /// Its own folder, not the backups one. A caregiver looking for a backup
  /// must never find one of these and think they have one.
  static const folder = 'reports';

  /// How many are kept, oldest dropped first.
  ///
  /// A tablet that has crashed two hundred times has a problem the first few
  /// records already describe, and the rest are a folder nobody will read.
  static const keep = 10;

  Directory? _cached;

  Future<Directory> directory() async {
    final directory =
        _cached ??
        Directory(p.join((await _documentsDirectory()).path, folder));
    _cached = directory;
    await directory.create(recursive: true);
    return directory;
  }

  /// Records a fault. Scrubbed before it touches the disk, so there is no
  /// window in which an unscrubbed trace exists as a file.
  ///
  /// Swallows everything. A store that throws while recording a crash turns
  /// one fault into two, and the second one has nowhere to be written.
  Future<void> record(Object error, StackTrace? trace, {DateTime? at}) async {
    try {
      final when = at ?? DateTime.now();
      final folder = await directory();
      final file = File(
        p.join(folder.path, '${when.toUtc().toIso8601String()}.json'),
      );

      await file.writeAsString(
        jsonEncode({
          'at': when.toUtc().toIso8601String(),
          'detail': scrubbed('$error\n${trace ?? ''}'),
        }),
      );

      await _prune(folder);
    } catch (_) {
      // Nothing. See above.
    }
  }

  /// Everything waiting, newest first.
  Future<List<CrashRecord>> waiting() async {
    final directory = await this.directory();
    final records = <CrashRecord>[];

    for (final file in await _files(directory)) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        records.add((
          id: p.basename(file.path),
          at: DateTime.parse(json['at']! as String),
          // Scrubbed again on the way out. A file written by an older build,
          // or edited by hand, is not evidence that it is safe to show.
          detail: scrubbed(json['detail']! as String),
        ));
      } catch (_) {
        // A record that cannot be read is a record nobody can act on.
        await file.delete().catchError((_) => file);
      }
    }

    records.sort((a, b) => b.at.compareTo(a.at));
    return records;
  }

  /// Forgets one, whether it was sent or discarded. Both are the caregiver
  /// deciding they are done with it.
  Future<void> discard(String id) async {
    final file = File(p.join((await directory()).path, id));
    if (await file.exists()) await file.delete();
  }

  Future<void> discardAll() async {
    for (final file in await _files(await directory())) {
      await file.delete().catchError((_) => file);
    }
  }

  Future<List<File>> _files(Directory directory) async {
    if (!await directory.exists()) return const [];
    return [
      for (final entity in await directory.list().toList())
        if (entity is File && entity.path.endsWith('.json')) entity,
    ];
  }

  Future<void> _prune(Directory directory) async {
    final files = await _files(directory)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (var i = 0; i < files.length - keep; i++) {
      await files[i].delete().catchError((_) => files[i]);
    }
  }
}
