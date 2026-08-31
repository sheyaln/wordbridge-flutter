import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../profiles/profile_settings.dart';
import 'obf_export.dart';
import 'obf_import.dart';
import 'obf_model.dart';

/// A board file sitting in the folder, ready to be taken away or brought in.
typedef BoardFile = ({String path, String name, int bytes, DateTime at});

/// What an import did, or why it did nothing.
///
/// [notes] is what the format could not carry across — an unresolvable link, a
/// board of a different size — and it is shown rather than logged. A caregiver
/// who has just imported a board needs to know what is missing from it before
/// they hand the tablet to somebody.
typedef ImportOutcome = ({
  String? profileId,
  String? problem,
  List<String> notes,
});

/// Getting a board set out of wordbridge, and getting one in.
///
/// **This is not a backup and must never be offered as one.** OBF carries
/// buttons, labels, pictures and links; it does not carry which locations are
/// reserved and empty, what level a word is drawn at, what is hidden, or which
/// band owns which line — which is exactly the metadata that makes this a
/// motor-planning board rather than a grid of pictures. `BackupService` copies
/// the database and is the thing to reach for when the question is "do not
/// lose this". The two live in different sections of the caregiver screen and
/// say so.
///
/// What this is for is leaving. Being able to take a board somewhere else is
/// the argument for the format existing at all, and lock-in is itself an
/// abandonment mechanism — a prescribed system that a school cannot open is
/// one a family stops using.
class BoardFileStore {
  BoardFileStore(this._db, {Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final WordbridgeDatabase _db;
  final Future<Directory> Function() _documentsDirectory;

  /// Where board files live, under the application documents directory.
  ///
  /// Beside the backups and deliberately not among them. A caregiver hunting
  /// for a backup must not find an export and think they have one.
  static const folder = 'boards';

  /// What this reads and writes. `.obf` is one board, `.obz` is a package of
  /// them, and only the second can carry the links between boards.
  static const extensions = {'.obf', '.obz'};

  Future<Directory> directory() async {
    final directory = Directory(
      p.join((await _documentsDirectory()).path, folder),
    );
    await directory.create(recursive: true);
    return directory;
  }

  /// Every board file in the folder, newest first.
  ///
  /// Anything else in there is ignored rather than reported. The folder is
  /// open to the outside — that is the point of it — and a screen that
  /// complained about a stray file somebody dropped in would be complaining
  /// about the feature working.
  Future<List<BoardFile>> files() async {
    final where = await directory();
    final found = <BoardFile>[];

    await for (final entity in where.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!extensions.contains(p.extension(name).toLowerCase())) continue;

      final stat = await entity.stat();
      found.add((
        path: entity.path,
        name: name,
        bytes: stat.size,
        at: stat.modified,
      ));
    }

    found.sort((a, b) => b.at.compareTo(a.at));
    return found;
  }

  /// Writes a whole board set out as one `.obz`.
  ///
  /// A package rather than a single board, because the links between boards are
  /// most of what a board set is and a lone `.obf` cannot carry them.
  Future<BoardFile> exportVocabulary(
    String vocabularyId, {
    DateTime? at,
  }) async {
    final vocabulary = await (_db.select(
      _db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();

    final bytes = await exportObz(_db, vocabularyId);
    final file = File(
      p.join(
        (await directory()).path,
        exportFileName(vocabulary.name, at ?? DateTime.now()),
      ),
    );
    await file.writeAsBytes(bytes, flush: true);

    final stat = await file.stat();
    return (
      path: file.path,
      name: p.basename(file.path),
      bytes: stat.size,
      at: stat.modified,
    );
  }

  Future<void> remove(BoardFile file) async {
    final handle = File(file.path);
    if (await handle.exists()) await handle.delete();
  }

  /// Brings a file in as a board set of its own, under a new person.
  ///
  /// Never over the top of somebody's board. Import writes a new vocabulary
  /// and hangs a new profile off it, so no location anybody has learned moves
  /// and the tablet keeps speaking exactly as it did until a caregiver
  /// deliberately switches to the new person.
  Future<ImportOutcome> import(BoardFile file, {String? displayName}) async {
    final handle = File(file.path);
    if (!await handle.exists()) {
      return (
        profileId: null,
        problem: 'That file is no longer in the folder.',
        notes: const <String>[],
      );
    }

    return importBoardFile(
      _db,
      name: file.name,
      bytes: await handle.readAsBytes(),
      displayName: displayName ?? nameFromFile(file.name),
    );
  }
}

/// What an exported package is called.
///
/// The board set's own name and the day, so a folder holding four of them can
/// be read without opening any. Anything a file system objects to is replaced
/// rather than dropped, because a name with the punctuation silently removed
/// is a different name.
String exportFileName(String vocabularyName, DateTime at) {
  final stem = vocabularyName.trim().isEmpty ? 'board' : vocabularyName.trim();
  final safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '-');
  final day =
      '${at.year}-${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
  return '$safe $day.obz';
}

/// The person a file is imported as, before anybody renames them.
String nameFromFile(String fileName) {
  final stem = p.basenameWithoutExtension(fileName).trim();
  return stem.isEmpty ? 'Imported board' : stem;
}

/// Reads a board file in and gives it somebody to belong to.
///
/// A named function rather than a line inside the screen, because everything
/// interesting about importing is here: which reader the extension chooses,
/// what a malformed file does, and the fact that a new profile is created
/// instead of an existing one being overwritten.
///
/// Nothing here throws. A caregiver holding a file that will not open needs a
/// sentence they can act on, not a crash on the one screen that could have
/// told them what was wrong with it.
Future<ImportOutcome> importBoardFile(
  WordbridgeDatabase db, {
  required String name,
  required List<int> bytes,
  required String displayName,
}) async {
  final notes = <String>[];

  try {
    final vocabularyId = p.extension(name).toLowerCase() == '.obz'
        ? await importObz(db, bytes, vocabularyName: displayName, notes: notes)
        : await importObf(
            db,
            utf8.decode(bytes),
            vocabularyName: displayName,
            notes: notes,
          );

    final profileId = await _attach(db, vocabularyId, displayName);
    return (profileId: profileId, problem: null, notes: notes);
  } on ObfFormatException catch (e) {
    return (
      profileId: null,
      problem: 'That file is not a board this app can read: ${e.message}',
      notes: notes,
    );
  } catch (e) {
    return (
      profileId: null,
      problem: 'That file could not be read: $e',
      notes: notes,
    );
  }
}

/// Hangs a new person off a freshly imported vocabulary.
///
/// Drawn at level 3, which is everything. An imported file carries no notion
/// of how much of itself to show — the levels are a wordbridge idea, and a
/// board from another program arrives with every button at level 1 — so
/// anything less would hide words the file plainly contains.
Future<String> _attach(
  WordbridgeDatabase db,
  String vocabularyId,
  String displayName,
) async {
  final profileId = newId();
  final ts = nowMs();

  await db.transaction(() async {
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: displayName,
            activeVocabularyId: Value(vocabularyId),
            vocabLevel: const Value(3),
            settingsJson: Value(
              jsonEncode({
                'prediction': ProfileSettings.predictionForNewProfiles,
                'breadcrumbs': ProfileSettings.breadcrumbsForNewProfiles,
                // Nobody was asked, and an import is not the moment to ask.
                'usageTracking': false,
              }),
            ),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    await (db.update(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).write(
      VocabulariesCompanion(profileId: Value(profileId), updatedAt: Value(ts)),
    );
  });

  return profileId;
}
