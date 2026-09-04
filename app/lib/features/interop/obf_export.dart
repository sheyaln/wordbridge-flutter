import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../../db/database.dart';
import '../../db/tables.dart';
import '../symbols/custom_upload.dart';
import '../symbols/drawable.dart';
import 'obf_model.dart';

/// Reads whatever a symbol's `local_uri` points at, or null when this device
/// has no bytes behind it.
///
/// Injected so a test can hand an export a picture without a symbol pack, an
/// asset bundle or a download under it.
typedef SymbolImageReader = Future<Uint8List?> Function(String localUri);

/// Which pictures an exported file may carry, by license.
///
/// An allowlist rather than a test for `NC`, because the two mistakes do not
/// cost the same. A permissive license missing from this set costs a recipient
/// a picture they could have had. A restrictive one that happens not to match a
/// pattern costs this project the boundary NOTICE.md commits to, in a file
/// somebody has already emailed to a school.
///
/// ARASAAC is CC BY-NC-SA and is not here, and no non-commercial set ever may
/// be: those images are fetched onto a device because a user chose them, which
/// is not the same as this app passing them on to whoever opens the export.
///
/// `Unicode-3.0` is deliberately absent as well. That is the license of the
/// emoji *index*; the pictures are the operating system's own font, and writing
/// one into a file would be redistributing Apple's or Microsoft's artwork.
const redistributableSymbolLicenses = <String>{
  'CC-BY-SA-4.0',
  'CC-BY-SA',
  'CC-BY-4.0',
  'CC-BY',
  'CC0-1.0',
  customSymbolLicense,
};

/// Exports one board as a standalone `.obf` document.
///
/// Links to other boards are emitted by id and name only. A standalone file has
/// no package for a `path` to address, so an importer can carry the intent
/// forward but cannot resolve it — use [exportObz] when the links matter. What
/// was left unresolvable is written into [notes] rather than left for the
/// recipient to discover.
Future<String> exportObf(
  WordbridgeDatabase db,
  String boardId, {
  List<String>? notes,
  SymbolImageReader? readImage,
}) async {
  final log = notes ?? <String>[];

  // Throws for a removed board rather than shipping one somebody deleted into
  // a file they will hand to a school.
  final board =
      await (db.select(db.boards)
            ..where((b) => b.id.equals(boardId))
            ..where((b) => b.deletedAt.isNull()))
          .getSingle();
  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(board.vocabularyId))).getSingle();

  final names = {
    for (final b in await _boardsOf(db, board.vocabularyId)) b.id: b.name,
  };

  final placed = await _placedOn(db, board.id);
  final pictures = _Pictures(readImage ?? readSymbolImage, asFiles: false);
  await pictures.load(db, _symbolIdsIn([placed]));
  pictures.report(log);

  _noteBoardsLeftOut(
    await _outboundLinks(db, board.vocabularyId),
    included: {board.id},
    names: names,
    notes: log,
  );

  return _toObf(
    board: board,
    vocabulary: vocabulary,
    placed: placed,
    paths: const {},
    names: names,
    pictures: pictures,
  ).encode();
}

/// Exports the boards of a vocabulary as an `.obz` package.
///
/// [boardIds] narrows the package to a subset — one category and the pages it
/// opens, say. Boards outside it are still named on the links that point at
/// them, so a recipient is told a page is missing rather than handed keys that
/// quietly do nothing; [notes] says which, and the screen shows it.
Future<List<int>> exportObz(
  WordbridgeDatabase db,
  String vocabularyId, {
  Iterable<String>? boardIds,
  String? rootBoardId,
  List<String>? notes,
  SymbolImageReader? readImage,
}) async {
  final log = notes ?? <String>[];

  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingle();

  final all = await _boardsOf(db, vocabularyId);
  final wanted = boardIds?.toSet();
  final boards = wanted == null
      ? all
      : [
          for (final b in all)
            if (wanted.contains(b.id)) b,
        ];
  if (boards.isEmpty) {
    throw StateError('vocabulary $vocabularyId has no boards to export');
  }

  final ids = {for (final b in boards) b.id};
  final rootId = ids.contains(rootBoardId)
      ? rootBoardId!
      : ids.contains(vocabulary.rootBoardId)
      ? vocabulary.rootBoardId!
      : boards.first.id;
  final ordered = [
    ...boards.where((b) => b.id == rootId),
    ...boards.where((b) => b.id != rootId),
  ];

  final paths = <String, String>{
    for (var i = 0; i < ordered.length; i++)
      ordered[i].id: 'boards/${i + 1}.obf',
  };
  // Every board in the vocabulary, not just the exported ones: a link out of
  // the package keeps the name of what it opened, which is the difference
  // between "the Food page is missing" and a dead key.
  final names = {for (final b in all) b.id: b.name};

  final placed = {for (final b in ordered) b.id: await _placedOn(db, b.id)};
  final pictures = _Pictures(readImage ?? readSymbolImage, asFiles: true);
  await pictures.load(db, _symbolIdsIn(placed.values));
  pictures.assignPaths();
  pictures.report(log);

  _noteBoardsLeftOut(
    await _outboundLinks(db, vocabularyId),
    included: ids,
    names: names,
    notes: log,
  );

  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'manifest.json',
        ObzManifest(
          root: paths[rootId],
          boards: paths,
          images: pictures.manifestPaths,
        ).encode(),
      ),
    );

  for (final board in ordered) {
    final obf = _toObf(
      board: board,
      vocabulary: vocabulary,
      placed: placed[board.id]!,
      paths: paths,
      names: names,
      pictures: pictures,
    );
    archive.add(ArchiveFile.string(paths[board.id]!, obf.encode()));
  }
  for (final entry in pictures.files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }

  return ZipEncoder().encodeBytes(archive);
}

/// [boardId] and every board reachable from it by following its keys.
///
/// This is what a "category" is on a board set: the category board plus the
/// pages its keys open, and the pages those open. Reachability is followed
/// rather than any recorded parentage, because a key that opens a board is the
/// only thing that makes it reachable at all.
Future<Set<String>> linkedBoardIds(
  WordbridgeDatabase db,
  String boardId,
) async {
  final board = await (db.select(
    db.boards,
  )..where((b) => b.id.equals(boardId))).getSingle();

  final alive = {for (final b in await _boardsOf(db, board.vocabularyId)) b.id};
  final links = <String, Set<String>>{};
  for (final link in await _outboundLinks(db, board.vocabularyId)) {
    if (!alive.contains(link.to)) continue;
    links.putIfAbsent(link.from, () => <String>{}).add(link.to);
  }

  final reached = <String>{boardId};
  final pending = <String>[boardId];
  while (pending.isNotEmpty) {
    for (final next in links[pending.removeLast()] ?? const <String>{}) {
      if (reached.add(next)) pending.add(next);
    }
  }
  return reached;
}

/// Reads a picture off this device.
///
/// A pack's `resolve` answers with an asset key, an absolute path, or — for the
/// system emoji — the characters to draw. Only the first two name bytes.
/// Nothing here rasterizes anything: a glyph is the platform's own font and
/// turning one into a file is the line NOTICE.md draws.
Future<Uint8List?> readSymbolImage(String localUri) async {
  try {
    if (localUri.startsWith('assets/')) {
      return (await rootBundle.load(localUri)).buffer.asUint8List();
    }
    if (p.isAbsolute(localUri)) {
      final file = File(localUri);
      return await file.exists() ? await file.readAsBytes() : null;
    }
  } catch (_) {
    // A picture that will not read costs the recipient one image. Failing the
    // export would cost them the board.
  }
  return null;
}

/// Whether a stored `local_uri` names bytes at all, as opposed to characters
/// the device draws for itself or a URL that stays a URL.
bool _namesLocalBytes(String uri) =>
    uri.startsWith('assets/') || p.isAbsolute(uri);

typedef _Placed = ({Cell cell, Button? button});

/// A key that opens another board, and where it opens it from.
typedef _Link = ({String from, String to, String label});

Future<List<Board>> _boardsOf(WordbridgeDatabase db, String vocabularyId) =>
    (db.select(db.boards)
          ..where((b) => b.vocabularyId.equals(vocabularyId))
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([(b) => OrderingTerm(expression: b.id)]))
        .get();

Future<List<_Placed>> _placedOn(WordbridgeDatabase db, String boardId) async {
  final query = db.select(db.cells).join([
    leftOuterJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
  ])..where(db.cells.boardId.equals(boardId));

  return [
    for (final row in await query.get())
      (cell: row.readTable(db.cells), button: row.readTableOrNull(db.buttons)),
  ]..sort((a, b) {
    final byRow = a.cell.row.compareTo(b.cell.row);
    return byRow != 0 ? byRow : a.cell.col.compareTo(b.cell.col);
  });
}

/// Every key in the vocabulary that opens a board, joined through its cell so
/// the board it sits on is known.
///
/// A button with no cell is in the unplaced tray and opens nothing anybody can
/// reach, so the inner join is the filter.
Future<List<_Link>> _outboundLinks(
  WordbridgeDatabase db,
  String vocabularyId,
) async {
  final query =
      db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(
        db.buttons.vocabularyId.equals(vocabularyId) &
            db.buttons.targetBoardId.isNotNull(),
      );

  return [
    for (final row in await query.get())
      (
        from: row.readTable(db.cells).boardId,
        to: row.readTable(db.buttons).targetBoardId!,
        label: row.readTable(db.buttons).label,
      ),
  ];
}

Set<String> _symbolIdsIn(Iterable<List<_Placed>> boards) => {
  for (final placed in boards)
    for (final entry in placed) ?entry.button?.symbolId,
};

/// Says which boards the file points at but does not contain.
///
/// The alternative was dropping those links, and it is worse: a key with its
/// destination removed is a key that looks like every other key and does
/// nothing, on a device whose user cannot report it. Keeping the name means
/// the importer can name the missing page — wordbridge's own does — and means
/// the person exporting is told here, before they hand the file over.
void _noteBoardsLeftOut(
  List<_Link> links, {
  required Set<String> included,
  required Map<String, String> names,
  required List<String> notes,
}) {
  final missing = <String, int>{};
  for (final link in links) {
    if (!included.contains(link.from) || included.contains(link.to)) continue;
    missing.update(link.to, (n) => n + 1, ifAbsent: () => 1);
  }
  if (missing.isEmpty) return;

  final keys = missing.values.reduce((a, b) => a + b);
  final boards = [for (final id in missing.keys) '"${names[id] ?? id}"']
    ..sort();

  notes.add(
    '${boards.join(', ')} ${boards.length == 1 ? 'is' : 'are'} not in this '
    'file. The $keys key(s) that open ${boards.length == 1 ? 'it' : 'them'} '
    'were written with that name and nothing to open, so importing this '
    'reports the missing page rather than leaving a key that does nothing.',
  );
}

/// The pictures an export refers to, and which of them the file may carry.
///
/// One place, consulted by both writers, because the licensing decision must
/// not be able to differ between `.obf` and `.obz`.
class _Pictures {
  _Pictures(this._read, {required this.asFiles});

  final SymbolImageReader _read;

  /// True for an `.obz`, which carries a picture as a file in the zip; false
  /// for a standalone `.obf`, whose only place to put one is a data URI.
  final bool asFiles;

  final _rows = <String, Symbol>{};
  final _bytes = <String, Uint8List>{};
  final _types = <String, String>{};
  final _paths = <String, String>{};

  /// Licenses under which a picture was found on this device and left behind,
  /// against how many pictures.
  final _withheld = <String, int>{};

  Future<void> load(WordbridgeDatabase db, Set<String> symbolIds) async {
    for (final id in symbolIds) {
      final symbol = await (db.select(
        db.symbols,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      if (symbol == null) continue;
      _rows[id] = symbol;

      final uri = symbol.localUri;
      if (uri == null || !_namesLocalBytes(uri)) continue;

      // The one gate. A picture only becomes bytes in a file that leaves this
      // device when its license says it may — and the same check is why an
      // embedded picture always has a license to travel with it.
      if (!redistributableSymbolLicenses.contains(symbol.license)) {
        _withheld.update(
          symbol.license.isEmpty ? 'an undeclared license' : symbol.license,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
        continue;
      }

      final bytes = await _read(uri);
      if (bytes == null) continue;
      final type = imageContentType(bytes);
      // A file we cannot name the type of is one the recipient's decoder would
      // have to guess at. Reference it instead.
      if (type == null) continue;

      _bytes[id] = bytes;
      _types[id] = type;
    }
  }

  void assignPaths() {
    var n = 0;
    for (final id in _bytes.keys) {
      _paths[id] = 'images/${++n}${_extensionFor(_types[id]!)}';
    }
  }

  /// Zip entries for the pictures the package carries.
  Map<String, Uint8List> get files => {
    for (final entry in _paths.entries) entry.value: _bytes[entry.key]!,
  };

  /// Image id to path within the zip, for `manifest.json`.
  Map<String, String> get manifestPaths => Map.of(_paths);

  void report(List<String> notes) {
    if (_withheld.isEmpty) return;
    final total = _withheld.values.reduce((a, b) => a + b);
    final licenses = _withheld.keys.toList()..sort();
    notes.add(
      '$total picture(s) are named and credited in this file but not copied '
      'into it: ${licenses.join(', ')} does not permit this app to pass the '
      'images on. Whoever opens it can fetch them from the source named '
      'beside each one.',
    );
  }

  /// Emits a symbol only when there is something a recipient can actually
  /// resolve — bytes we carried, a URL, or a set and filename they could look
  /// up. A path into this device's cache would dangle in their copy, which is
  /// worse than shipping the button without an image.
  ObfImage? imageFor(String? symbolId) {
    if (symbolId == null) return null;
    final symbol = _rows[symbolId];
    if (symbol == null) return null;

    final uri = symbol.localUri;
    final remote =
        uri != null &&
        (uri.startsWith('http://') || uri.startsWith('https://'));
    final ref = symbol.packId != null && symbol.externalId != null
        ? ObfSymbolRef(set: symbol.packId, filename: symbol.externalId)
        : null;
    final bytes = _bytes[symbolId];
    if (!remote && ref == null && bytes == null) return null;

    return ObfImage(
      id: symbol.id,
      url: remote ? uri : null,
      data: bytes == null || asFiles
          ? null
          : 'data:${_types[symbolId]};base64,${base64Encode(bytes)}',
      path: asFiles ? _paths[symbolId] : null,
      contentType: bytes == null ? null : _types[symbolId],
      symbol: ref,
      width: symbol.width,
      height: symbol.height,
      license: ObfLicense(
        type: symbol.license.isEmpty ? null : symbol.license,
        authorName: symbol.attribution.isEmpty ? null : symbol.attribution,
      ),
    );
  }
}

String _extensionFor(String contentType) => switch (contentType) {
  'image/png' => '.png',
  'image/jpeg' => '.jpg',
  'image/gif' => '.gif',
  'image/bmp' => '.bmp',
  'image/webp' => '.webp',
  'image/svg+xml' => '.svg',
  _ => '.bin',
};

ObfBoard _toObf({
  required Board board,
  required Vocabulary vocabulary,
  required List<_Placed> placed,
  required Map<String, String> paths,
  required Map<String, String> names,
  required _Pictures pictures,
}) {
  // Geometry is the vocabulary's, but never emit a grid too small to hold a
  // cell that exists: truncating the order array would delete a word.
  var rows = vocabulary.gridRows;
  var cols = vocabulary.gridCols;
  for (final entry in placed) {
    rows = math.max(rows, entry.cell.row + 1);
    cols = math.max(cols, entry.cell.col + 1);
  }

  final order = List.generate(rows, (_) => List<String?>.filled(cols, null));
  final buttons = <ObfButton>[];
  final images = <String, ObfImage>{};

  for (final entry in placed) {
    final button = entry.button;
    if (button == null) continue;

    // A merged cell occupies several locations but OBF's grid has no span, so
    // only the origin carries the id and the covered locations stay null.
    order[entry.cell.row][entry.cell.col] = button.id;

    final image = pictures.imageFor(button.symbolId);
    if (image != null) images[image.id] = image;
    buttons.add(_toObfButton(button, image?.id, paths, names));
  }

  return ObfBoard(
    id: board.id,
    locale: vocabulary.locale,
    name: board.name,
    buttons: buttons,
    grid: ObfGrid(rows: rows, columns: cols, order: order),
    images: images.values.toList(),
    // No board-level `license`. What is recorded about where a board set came
    // from is a sentence of provenance, and OBF's `license.type` is a license
    // identifier that other programs display as one — a paragraph there reads
    // as a license nobody granted. It travels under the spec's own extension
    // mechanism instead, which our importer reads alongside `license`.
    //
    // The per-image licenses are a different matter and are emitted in full:
    // those are what permit a picture's bytes to be in the file at all.
    ext: {
      WordbridgeExt.boardKind: board.kind.name,
      WordbridgeExt.vocabularyName: vocabulary.name,
      WordbridgeExt.colorConvention: vocabulary.colorConvention.name,
      WordbridgeExt.sourceLicense: ?vocabulary.sourceLicense,
    },
  );
}

ObfButton _toObfButton(
  Button button,
  String? imageId,
  Map<String, String> paths,
  Map<String, String> names,
) {
  final action = _obfAction(button.action);
  final target = button.targetBoardId;

  // What an importer would infer from label and action alone. Only carry the
  // message when it would not survive that inference.
  final implied = button.action == ButtonAction.speak ? button.label : '';

  return ObfButton(
    id: button.id,
    label: button.label,
    vocalization: button.speakText,
    imageId: imageId,
    action: action,
    backgroundColor: button.backgroundColor,
    borderColor: button.borderColor,
    loadBoard: target == null
        ? null
        : ObfLoadBoard(id: target, name: names[target], path: paths[target]),
    ext: {
      if (button.message != implied) WordbridgeExt.message: button.message,
      if (button.partOfSpeech case final pos?)
        WordbridgeExt.partOfSpeech: pos.name,
      if (button.morphemeKind case final kind?)
        WordbridgeExt.morphemeKind: kind.name,
      if (button.vocabLevel != 1) WordbridgeExt.vocabLevel: button.vocabLevel,
      if (button.hidden) WordbridgeExt.hidden: true,
      if (button.isSystem) WordbridgeExt.system: true,
    },
  );
}

String? _obfAction(ButtonAction action) => switch (action) {
  ButtonAction.home => ':home',
  ButtonAction.clear => ':clear',
  ButtonAction.backspace => ':backspace',
  ButtonAction.speakBar => ':speak',
  ButtonAction.back => WordbridgeExt.backAction,
  ButtonAction.morpheme => WordbridgeExt.morphemeAction,
  ButtonAction.punctuate => WordbridgeExt.punctuateAction,
  ButtonAction.cycleCategories => WordbridgeExt.cycleCategoriesAction,
  ButtonAction.none => WordbridgeExt.noneAction,
  // Speaking is the default and a link is described by load_board.
  ButtonAction.speak || ButtonAction.navigate => null,
};
