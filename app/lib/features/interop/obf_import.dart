import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';
import 'obf_model.dart';

/// Imports a single `.obf` board as a new vocabulary and returns its id.
///
/// Any `load_board` links are unresolvable in a standalone file — there is no
/// other board in the package to point at — so those buttons arrive as
/// navigation with no target and are listed in [notes].
Future<String> importObf(
  WordbridgeDatabase db,
  String json, {
  String? vocabularyName,
  List<String>? notes,
}) async {
  final log = notes ?? <String>[];
  final source = _Source(ObfBoard.parse(json));
  return _materialise(
    db,
    sources: [source],
    root: source,
    name: vocabularyName ?? _vocabularyName(source),
    notes: log,
  );
}

/// Imports an `.obz` package as a single vocabulary and returns its id.
///
/// Every `.obf` in the zip is imported, not just those reachable from the
/// root, which the spec recommends and which avoids silently dropping boards
/// whose only inbound link is an external URL.
Future<String> importObz(
  WordbridgeDatabase db,
  List<int> zipBytes, {
  String? vocabularyName,
  List<String>? notes,
}) async {
  final log = notes ?? <String>[];
  final archive = ZipDecoder().decodeBytes(zipBytes);

  ArchiveFile? manifestFile;
  final rawBoards = <String, ArchiveFile>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = _normalise(file.name);
    if (p.url.basename(name) == 'manifest.json') {
      manifestFile ??= file;
    } else if (p.url.extension(name).toLowerCase() == '.obf') {
      rawBoards[name] = file;
    }
  }

  if (rawBoards.isEmpty) {
    throw ObfFormatException('the package contains no .obf files');
  }

  // Some packagers wrap everything in a top-level directory. Paths inside the
  // manifest are relative to the manifest, so rebase on wherever it landed.
  final base = manifestFile == null
      ? ''
      : p.url.dirname(_normalise(manifestFile.name));
  String rebase(String name) {
    if (base.isEmpty || base == '.') return name;
    return name.startsWith('$base/') ? name.substring(base.length + 1) : name;
  }

  final boards = <String, ArchiveFile>{
    for (final e in rawBoards.entries) rebase(e.key): e.value,
  };

  ObzManifest? manifest;
  if (manifestFile != null) {
    manifest = ObzManifest.parse(_text(manifestFile));
  } else if (boards.length > 1) {
    log.add(
      'The package has ${boards.length} boards and no manifest.json, so the '
      'root board was guessed from the file names.',
    );
  }

  final paths = boards.keys.toList()..sort();
  final sources = [
    for (final path in paths) _Source(ObfBoard.parse(_text(boards[path]!)), path),
  ];

  final rootPath = manifest?.root == null ? null : _normalise(manifest!.root!);
  var root = sources.first;
  for (final s in sources) {
    if (s.path == rootPath) root = s;
  }
  if (rootPath != null && root.path != rootPath) {
    log.add(
      'manifest.json names "$rootPath" as the root board but no such file is '
      'in the package; "${root.path}" was used instead.',
    );
  }

  return _materialise(
    db,
    sources: [root, ...sources.where((s) => s != root)],
    root: root,
    name: vocabularyName ?? _vocabularyName(root),
    notes: log,
  );
}

/// One `.obf` on its way into the database.
class _Source {
  _Source(this.obf, [this.path]);

  final ObfBoard obf;

  /// Location within the `.obz`, which is how `load_board` links address it.
  final String? path;

  late final ObfGrid grid;
  late final String boardId;

  String get name =>
      obf.name ??
      (path == null ? null : p.url.basenameWithoutExtension(path!)) ??
      (obf.id.isEmpty ? 'board' : obf.id);
}

String _vocabularyName(_Source root) =>
    readExt<String>(root.obf.ext, WordbridgeExt.vocabularyName) ?? root.name;

String _text(ArchiveFile file) => utf8.decode(file.readBytes() ?? const []);

String _normalise(String path) {
  var value = path.replaceAll(r'\', '/');
  while (value.startsWith('./')) {
    value = value.substring(2);
  }
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  return p.url.normalize(value);
}

/// Builds the vocabulary, its boards, and its buttons.
///
/// Boards are created before any button is placed because a `load_board` link
/// may point at a board defined later in the package.
Future<String> _materialise(
  WordbridgeDatabase db, {
  required List<_Source> sources,
  required _Source root,
  required String name,
  required List<String> notes,
}) async {
  if (sources.isEmpty) {
    throw ObfFormatException('nothing to import');
  }

  var rows = 0;
  var cols = 0;
  for (final source in sources) {
    source.grid = _gridFor(source, notes);
    rows = math.max(rows, source.grid.rows);
    cols = math.max(cols, source.grid.columns);
  }

  // ADR-0003: geometry is a property of the vocabulary, and reflowing a board
  // to fit a smaller one would move words that someone has already learned.
  // The largest grid found wins and the short boards keep reserved cells
  // along their bottom and right edges.
  final mismatched = sources
      .where((s) => s.grid.rows != rows || s.grid.columns != cols)
      .toList();
  if (mismatched.isNotEmpty) {
    notes.add(
      'Boards in this package declare different grid sizes. The vocabulary is '
      '$rows×$cols, the largest found, and every button kept its original '
      'coordinates; ${mismatched.length} board(s) '
      '(${mismatched.map((s) => '"${s.name}" ${s.grid.rows}×${s.grid.columns}').join(', ')}) '
      'gained reserved cells rather than being reflowed.',
    );
  }

  return db.transaction(() async {
    final vocabId = newId();
    final ts = nowMs();

    await db
        .into(db.vocabularies)
        .insert(
          VocabulariesCompanion.insert(
            id: vocabId,
            name: name,
            locale: Value(root.obf.locale ?? 'en-US'),
            gridRows: rows,
            gridCols: cols,
            colourScheme: Value(_colourScheme(root.obf)),
            sourceLicense: Value(_licenceText(sources)),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    for (final source in sources) {
      source.boardId = await materialiseBoard(
        db,
        vocabularyId: vocabId,
        name: source.name,
        kind: _boardKind(source, root),
      );
    }

    await (db.update(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabId))).write(
      VocabulariesCompanion(rootBoardId: Value(root.boardId)),
    );

    final links = _LinkTable(sources);

    for (final source in sources) {
      final byId = {for (final b in source.obf.buttons) b.id: b};
      final placed = <String>{};

      for (var row = 0; row < source.grid.order.length; row++) {
        final line = source.grid.order[row];
        for (var col = 0; col < line.length; col++) {
          final id = line[col];
          // A null entry is a location deliberately held open. The cell was
          // materialised with the board and stays reserved.
          if (id == null) continue;

          final button = byId[id];
          if (button == null) {
            notes.add(
              'Grid of "${source.name}" references button "$id" at $row,$col '
              'but no such button is defined; the location stays reserved.',
            );
            continue;
          }
          if (!placed.add(id)) {
            // Repeating an id across cells is how some exporters encode a
            // merged cell. We have no span information to recover, so the
            // first location wins.
            notes.add(
              'Button "$id" on "${source.name}" appears more than once in the '
              'grid; only its first location was used.',
            );
            continue;
          }

          final cell = await cellAt(
            db,
            boardId: source.boardId,
            row: row,
            col: col,
          );
          await _place(
            db,
            vocabId: vocabId,
            source: source,
            button: button,
            cellId: cell.id,
            links: links,
            notes: notes,
          );
        }
      }

      for (final button in source.obf.buttons) {
        if (placed.contains(button.id)) continue;
        await _tray(
          db,
          vocabId: vocabId,
          source: source,
          button: button,
          links: links,
          notes: notes,
        );
        notes.add(
          'Button "${button.label ?? button.id}" on "${source.name}" is not in '
          'the grid; it was imported unplaced rather than given a location we '
          'invented for it.',
        );
      }
    }

    await _recordSystemCells(db, vocabId, root.boardId);
    await _recordImport(db, vocabId, rows, cols, notes);

    return vocabId;
  });
}

/// A board with no grid has no positions to preserve, so any layout is as
/// faithful as any other; a near-square one at least stays on screen.
ObfGrid _gridFor(_Source source, List<String> notes) {
  final grid = source.obf.grid;
  if (grid != null && grid.order.isNotEmpty) return grid;

  final count = source.obf.buttons.length;
  final columns = count == 0 ? 1 : math.sqrt(count).ceil();
  final rows = count == 0 ? 1 : (count / columns).ceil();
  notes.add(
    '"${source.name}" declares no grid; its $count button(s) were laid out '
    '$rows×$columns in file order.',
  );
  return ObfGrid(
    rows: rows,
    columns: columns,
    order: List.generate(
      rows,
      (r) => List<String?>.generate(columns, (c) {
        final i = r * columns + c;
        return i < count ? source.obf.buttons[i].id : null;
      }),
    ),
  );
}

/// Resolves `load_board` links to board ids, preferring the addressing modes
/// the spec calls authoritative.
class _LinkTable {
  _LinkTable(List<_Source> sources) {
    for (final source in sources) {
      final path = source.path;
      if (path != null) {
        _byPath[path] = source.boardId;
        final base = p.url.basename(path);
        // Two boards with the same file name in different directories cannot
        // be told apart by base name, so refuse to guess.
        _byBasename.update(
          base,
          (_) => null,
          ifAbsent: () => source.boardId,
        );
      }
      if (source.obf.id.isNotEmpty) {
        _byObfId.putIfAbsent(source.obf.id, () => source.boardId);
      }
      _byName.putIfAbsent(source.name, () => source.boardId);
    }
  }

  final _byPath = <String, String>{};
  final _byBasename = <String, String?>{};
  final _byObfId = <String, String>{};
  final _byName = <String, String>{};

  String? resolve(ObfLoadBoard? link) {
    if (link == null) return null;
    final path = link.path;
    if (path != null) {
      final direct = _byPath[_normalise(path)];
      if (direct != null) return direct;
      final base = _byBasename[p.url.basename(_normalise(path))];
      if (base != null) return base;
    }
    final id = link.id;
    if (id != null && _byObfId[id] != null) return _byObfId[id];
    final name = link.name;
    if (name != null && _byName[name] != null) return _byName[name];
    return null;
  }
}

Future<void> _place(
  WordbridgeDatabase db, {
  required String vocabId,
  required _Source source,
  required ObfButton button,
  required String cellId,
  required _LinkTable links,
  required List<String> notes,
}) async {
  final content = _Content(source, button, links, notes);

  final buttonId = await placeButton(
    db,
    vocabularyId: vocabId,
    cellId: cellId,
    label: content.label,
    message: content.message,
    action: content.action,
    targetBoardId: content.targetBoardId,
    partOfSpeech: content.partOfSpeech,
    vocabLevel: content.vocabLevel,
    hidden: content.hidden,
    isSystem: content.isSystem,
  );

  if (content.hasExtras) {
    await (db.update(db.buttons)..where((b) => b.id.equals(buttonId))).write(
      ButtonsCompanion(
        speakText: Value(content.speakText),
        backgroundColor: Value(button.backgroundColor),
        borderColor: Value(button.borderColor),
        morphemeKind: Value(content.morphemeKind),
      ),
    );
  }
}

/// Imports a button the grid never references.
///
/// ADR-0003 keeps `buttons.cell_id` nullable so a bulk import can land in the
/// editor's unplaced tray. Dropping the word would lose vocabulary; putting it
/// in the first free cell would be a position we made up.
Future<void> _tray(
  WordbridgeDatabase db, {
  required String vocabId,
  required _Source source,
  required ObfButton button,
  required _LinkTable links,
  required List<String> notes,
}) async {
  final content = _Content(source, button, links, notes);
  final ts = nowMs();

  await db
      .into(db.buttons)
      .insert(
        ButtonsCompanion.insert(
          id: newId(),
          vocabularyId: vocabId,
          label: content.label,
          message: content.message,
          action: content.action,
          targetBoardId: Value(content.targetBoardId),
          speakText: Value(content.speakText),
          morphemeKind: Value(content.morphemeKind),
          backgroundColor: Value(button.backgroundColor),
          borderColor: Value(button.borderColor),
          partOfSpeech: Value(content.partOfSpeech),
          vocabLevel: Value(content.vocabLevel),
          hidden: Value(content.hidden),
          isSystem: Value(content.isSystem),
          createdAt: ts,
          updatedAt: ts,
        ),
      );
}

/// An OBF button translated into our columns.
class _Content {
  factory _Content(
    _Source source,
    ObfButton button,
    _LinkTable links,
    List<String> notes,
  ) {
    final strings = source.obf.strings;
    final locale = source.obf.locale;
    final label = resolveObfString(strings, locale, button.label) ?? '';
    final spoken = resolveObfString(strings, locale, button.vocalization);

    final action = _actionFor(button);
    String? target;
    if (action == ButtonAction.navigate) {
      target = links.resolve(button.loadBoard);
      if (target == null) {
        notes.add(
          'Button "${label.isEmpty ? button.id : label}" on "${source.name}" '
          'links to a board outside this package; it was imported as '
          'navigation with no destination.',
        );
      }
    }

    if (button.imageId != null) {
      notes.add(
        'Symbol "${button.imageId}" on "${source.name}" was not imported; '
        'symbol handling is not wired up yet.',
      );
    }

    return _Content._(
      label: label,
      message:
          readExt<String>(button.ext, WordbridgeExt.message) ??
          (action == ButtonAction.speak ? label : ''),
      speakText: spoken == null || spoken == label ? null : spoken,
      action: action,
      targetBoardId: target,
      morphemeKind: _enumByName(
        MorphemeKind.values,
        readExt<String>(button.ext, WordbridgeExt.morphemeKind),
      ),
      partOfSpeech: _enumByName(
        PartOfSpeech.values,
        readExt<String>(button.ext, WordbridgeExt.partOfSpeech),
      ),
      vocabLevel: readExt<int>(button.ext, WordbridgeExt.vocabLevel) ?? 1,
      hidden: readExt<bool>(button.ext, WordbridgeExt.hidden) ?? false,
      isSystem:
          readExt<bool>(button.ext, WordbridgeExt.system) ??
          _systemActions.contains(action),
    );
  }

  _Content._({
    required this.label,
    required this.message,
    required this.speakText,
    required this.action,
    required this.targetBoardId,
    required this.morphemeKind,
    required this.partOfSpeech,
    required this.vocabLevel,
    required this.hidden,
    required this.isSystem,
  });

  final String label;
  final String message;
  final String? speakText;
  final ButtonAction action;
  final String? targetBoardId;
  final MorphemeKind? morphemeKind;
  final PartOfSpeech? partOfSpeech;
  final int vocabLevel;
  final bool hidden;
  final bool isSystem;

  /// Columns [placeButton] does not take, so they need a follow-up write.
  bool get hasExtras => speakText != null || morphemeKind != null;
}

const _systemActions = {
  ButtonAction.home,
  ButtonAction.back,
  ButtonAction.clear,
  ButtonAction.backspace,
  ButtonAction.speakBar,
};

/// Named actions win over `load_board`: a button that both links and declares
/// `:home` is a home button that happens to name its destination.
///
/// Everything unrecognised — including the `+letter` spelling actions, which
/// we have no keyboard for yet — falls through to speak, so the word is at
/// least present and in the right place.
ButtonAction _actionFor(ObfButton button) {
  switch (button.primaryAction) {
    case ':home':
      return ButtonAction.home;
    case ':clear':
      return ButtonAction.clear;
    case ':backspace':
      return ButtonAction.backspace;
    case ':speak':
      return ButtonAction.speakBar;
    case ':back':
    case WordbridgeExt.backAction:
      return ButtonAction.back;
    case WordbridgeExt.morphemeAction:
      return ButtonAction.morpheme;
    case WordbridgeExt.noneAction:
      return ButtonAction.none;
  }
  if (button.loadBoard != null) return ButtonAction.navigate;
  return ButtonAction.speak;
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

ColourScheme _colourScheme(ObfBoard board) =>
    _enumByName(
      ColourScheme.values,
      readExt<String>(board.ext, WordbridgeExt.colourScheme),
    ) ??
    ColourScheme.modifiedFitzgerald;

BoardKind _boardKind(_Source source, _Source root) {
  if (identical(source, root)) return BoardKind.root;
  return _enumByName(
        BoardKind.values,
        readExt<String>(source.obf.ext, WordbridgeExt.boardKind),
      ) ??
      BoardKind.category;
}

/// The spec is explicit that an undeclared licence means all rights reserved,
/// so say so rather than leaving the column null and implying it is free.
String _licenceText(List<_Source> sources) {
  final seen = <String>{};
  for (final source in sources) {
    final licence = source.obf.license;
    if (licence != null && !licence.isEmpty) seen.add(licence.readable);
    final carried = readExt<String>(source.obf.ext, WordbridgeExt.sourceLicense);
    if (carried != null && carried.isNotEmpty) seen.add(carried);
  }
  return seen.isEmpty
      ? 'No licence declared in the source file. Treat as all rights reserved.'
      : seen.join('\n');
}

/// Records where the fixed system buttons landed so every board can be checked
/// against them later.
Future<void> _recordSystemCells(
  WordbridgeDatabase db,
  String vocabId,
  String rootBoardId,
) async {
  final query = db.select(db.buttons).join([
    innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
  ])..where(db.cells.boardId.equals(rootBoardId));

  const names = {
    ButtonAction.home: 'home',
    ButtonAction.back: 'back',
    ButtonAction.clear: 'clear',
    ButtonAction.backspace: 'backspace',
    ButtonAction.speakBar: 'speak',
  };

  final map = <String, List<int>>{};
  for (final row in await query.get()) {
    final name = names[row.readTable(db.buttons).action];
    if (name == null) continue;
    final cell = row.readTable(db.cells);
    map.putIfAbsent(name, () => [cell.row, cell.col]);
  }
  if (map.isEmpty) return;

  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId))).write(
    VocabulariesCompanion(systemCellMap: Value(jsonEncode(map))),
  );
}

/// Leaves an audit row for every judgement call the import made, chiefly the
/// grid size chosen when boards disagreed.
Future<void> _recordImport(
  WordbridgeDatabase db,
  String vocabId,
  int rows,
  int cols,
  List<String> notes,
) async {
  await db
      .into(db.editEvents)
      .insert(
        EditEventsCompanion.insert(
          id: newId(),
          vocabularyId: vocabId,
          kind: EditKind.gridResize,
          afterJson: Value(
            jsonEncode({
              'source': 'obf-import',
              'gridRows': rows,
              'gridCols': cols,
              'notes': notes,
            }),
          ),
          changedAt: nowMs(),
        ),
      );
}
