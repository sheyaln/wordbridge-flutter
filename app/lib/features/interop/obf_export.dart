import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import 'obf_model.dart';

/// Exports one board as a standalone `.obf` document.
///
/// Links to other boards are emitted by id and name only. A standalone file
/// has no package for a `path` to address, so an importer can carry the intent
/// forward but cannot resolve it — use [exportObz] when the links matter.
Future<String> exportObf(WordbridgeDatabase db, String boardId) async {
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

  final obf = await _toObf(
    db,
    board: board,
    vocabulary: vocabulary,
    paths: const {},
    names: names,
  );
  return obf.encode();
}

/// Exports every board in a vocabulary as an `.obz` package.
Future<List<int>> exportObz(WordbridgeDatabase db, String vocabularyId) async {
  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingle();

  final boards = await _boardsOf(db, vocabularyId);
  if (boards.isEmpty) {
    throw StateError('vocabulary $vocabularyId has no boards to export');
  }

  final rootId = vocabulary.rootBoardId ?? boards.first.id;
  final ordered = [
    ...boards.where((b) => b.id == rootId),
    ...boards.where((b) => b.id != rootId),
  ];

  final paths = <String, String>{
    for (var i = 0; i < ordered.length; i++)
      ordered[i].id: 'boards/${i + 1}.obf',
  };
  final names = {for (final b in ordered) b.id: b.name};

  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'manifest.json',
        ObzManifest(root: paths[rootId], boards: paths).encode(),
      ),
    );

  for (final board in ordered) {
    final obf = await _toObf(
      db,
      board: board,
      vocabulary: vocabulary,
      paths: paths,
      names: names,
    );
    archive.add(ArchiveFile.string(paths[board.id]!, obf.encode()));
  }

  return ZipEncoder().encodeBytes(archive);
}

Future<List<Board>> _boardsOf(WordbridgeDatabase db, String vocabularyId) =>
    (db.select(db.boards)
          ..where((b) => b.vocabularyId.equals(vocabularyId))
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([(b) => OrderingTerm(expression: b.id)]))
        .get();

Future<ObfBoard> _toObf(
  WordbridgeDatabase db, {
  required Board board,
  required Vocabulary vocabulary,
  required Map<String, String> paths,
  required Map<String, String> names,
}) async {
  final query = db.select(db.cells).join([
    leftOuterJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
  ])..where(db.cells.boardId.equals(board.id));

  final placed =
      [
        for (final row in await query.get())
          (
            cell: row.readTable(db.cells),
            button: row.readTableOrNull(db.buttons),
          ),
      ]..sort((a, b) {
        final byRow = a.cell.row.compareTo(b.cell.row);
        return byRow != 0 ? byRow : a.cell.col.compareTo(b.cell.col);
      });

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

    final image = await _imageFor(db, button.symbolId);
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
    ext: {
      WordbridgeExt.boardKind: board.kind.name,
      WordbridgeExt.vocabularyName: vocabulary.name,
      WordbridgeExt.colourScheme: vocabulary.colourScheme.name,
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

/// Emits a symbol only when there is something a recipient can actually
/// resolve. A path into this device's cache would dangle in their copy, which
/// is worse than shipping the button without an image.
Future<ObfImage?> _imageFor(WordbridgeDatabase db, String? symbolId) async {
  if (symbolId == null) return null;

  final symbol = await (db.select(
    db.symbols,
  )..where((s) => s.id.equals(symbolId))).getSingleOrNull();
  if (symbol == null) return null;

  final uri = symbol.localUri;
  final remote =
      uri != null && (uri.startsWith('http://') || uri.startsWith('https://'));
  final ref = symbol.packId != null && symbol.externalId != null
      ? ObfSymbolRef(set: symbol.packId, filename: symbol.externalId)
      : null;
  if (!remote && ref == null) return null;

  return ObfImage(
    id: symbol.id,
    url: remote ? uri : null,
    symbol: ref,
    width: symbol.width,
    height: symbol.height,
    license: ObfLicense(
      type: symbol.license.isEmpty ? null : symbol.license,
      authorName: symbol.attribution.isEmpty ? null : symbol.attribution,
    ),
  );
}
