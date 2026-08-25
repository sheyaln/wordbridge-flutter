import 'dart:convert';

/// Open Board Format 0.1 value types — https://www.openboardformat.org/
///
/// Parsing is deliberately forgiving and emission strict. Files in the wild
/// use the numeric ids the spec forbids, omit optional keys, capitalise
/// `copyright_notice_url` inconsistently (the spec's own examples do both),
/// and carry vendor `ext_` keys. Nothing we write should need that tolerance.
const obfFormat = 'open-board-0.1';

/// Keys we add under the spec's `ext_` extension mechanism.
///
/// Everything here is information OBF has no home for. Other apps ignore it;
/// a wordbridge-to-wordbridge round trip keeps it.
abstract final class WordbridgeExt {
  static const prefix = 'ext_wordbridge_';

  static const partOfSpeech = '${prefix}part_of_speech';
  static const vocabLevel = '${prefix}vocab_level';
  static const hidden = '${prefix}hidden';
  static const system = '${prefix}system';
  static const message = '${prefix}message';
  static const morphemeKind = '${prefix}morpheme_kind';
  static const boardKind = '${prefix}board_kind';
  static const vocabularyName = '${prefix}vocabulary_name';
  static const colourScheme = '${prefix}colour_scheme';
  static const sourceLicense = '${prefix}source_license';

  /// Actions OBF does not define. The spec's guidance for those is `:ext_`
  /// notation, still prefixed by a colon.
  static const backAction = ':ext_wordbridge_back';
  static const morphemeAction = ':ext_wordbridge_morpheme';
  static const noneAction = ':ext_wordbridge_none';
}

class ObfFormatException implements Exception {
  ObfFormatException(this.message);

  final String message;

  @override
  String toString() => 'ObfFormatException: $message';
}

Map<String, Object?> _asMap(Object? v) => v is Map
    ? {for (final e in v.entries) e.key.toString(): e.value}
    : const <String, Object?>{};

List<Object?> _asList(Object? v) => v is List ? v : const <Object?>[];

/// Ids are specified as strings, but numeric ids are common enough that the
/// spec has a section apologising for them.
String? _asId(Object? v) => v?.toString();

String? _asString(Object? v) => switch (v) {
  null => null,
  String s => s,
  _ => v.toString(),
};

int? _asInt(Object? v) => switch (v) {
  num n => n.toInt(),
  String s => int.tryParse(s),
  _ => null,
};

bool? _asBool(Object? v) => switch (v) {
  bool b => b,
  num n => n != 0,
  'true' => true,
  'false' => false,
  _ => null,
};

Map<String, Object?> _extOf(Map<String, Object?> json) => {
  for (final e in json.entries)
    if (e.key.startsWith('ext_')) e.key: e.value,
};

/// Drops null values so emitted files carry only keys that mean something.
Map<String, Object?> _dense(Map<String, Object?> json) => {
  for (final e in json.entries)
    if (e.value != null) e.key: e.value,
};

class ObfLicense {
  const ObfLicense({
    this.type,
    this.copyrightNoticeUrl,
    this.sourceUrl,
    this.authorName,
    this.authorUrl,
    this.authorEmail,
  });

  factory ObfLicense.fromJson(Map<String, Object?> json) => ObfLicense(
    type: _asString(json['type']),
    copyrightNoticeUrl: _asString(
      json['copyright_notice_url'] ?? json['Copyright_notice_url'],
    ),
    sourceUrl: _asString(json['source_url']),
    authorName: _asString(json['author_name']),
    authorUrl: _asString(json['author_url']),
    authorEmail: _asString(json['author_email']),
  );

  final String? type;
  final String? copyrightNoticeUrl;
  final String? sourceUrl;
  final String? authorName;
  final String? authorUrl;
  final String? authorEmail;

  bool get isEmpty =>
      type == null &&
      copyrightNoticeUrl == null &&
      sourceUrl == null &&
      authorName == null &&
      authorUrl == null &&
      authorEmail == null;

  /// Flattened for a single text column. One-way: the structure is not
  /// recoverable from the result.
  String get readable {
    final parts = <String>[
      ?type,
      if (authorName != null) 'by $authorName',
      if (authorEmail != null) '<$authorEmail>',
      ?authorUrl,
      if (copyrightNoticeUrl != null) 'licence: $copyrightNoticeUrl',
      if (sourceUrl != null) 'source: $sourceUrl',
    ];
    return parts.join(', ');
  }

  Map<String, Object?> toJson() => _dense({
    'type': type,
    'copyright_notice_url': copyrightNoticeUrl,
    'source_url': sourceUrl,
    'author_name': authorName,
    'author_url': authorUrl,
    'author_email': authorEmail,
  });
}

/// A link from a button to another board.
///
/// Within an `.obz` the [path] is authoritative; [id] and [name] are the
/// fallbacks, and [url] / [dataUrl] point outside the package entirely.
class ObfLoadBoard {
  const ObfLoadBoard({this.id, this.name, this.path, this.url, this.dataUrl});

  factory ObfLoadBoard.fromJson(Map<String, Object?> json) => ObfLoadBoard(
    id: _asId(json['id']),
    name: _asString(json['name']),
    path: _asString(json['path']),
    url: _asString(json['url']),
    dataUrl: _asString(json['data_url']),
  );

  final String? id;
  final String? name;
  final String? path;
  final String? url;
  final String? dataUrl;

  Map<String, Object?> toJson() => _dense({
    'id': id,
    'name': name,
    'path': path,
    'url': url,
    'data_url': dataUrl,
  });
}

class ObfButton {
  const ObfButton({
    required this.id,
    this.label,
    this.vocalization,
    this.imageId,
    this.soundId,
    this.action,
    this.actions = const [],
    this.backgroundColor,
    this.borderColor,
    this.loadBoard,
    this.ext = const {},
  });

  factory ObfButton.fromJson(Map<String, Object?> json) {
    final id = _asId(json['id']);
    if (id == null) throw ObfFormatException('button without an id');
    final loadBoard = json['load_board'];
    return ObfButton(
      id: id,
      label: _asString(json['label']),
      vocalization: _asString(json['vocalization']),
      imageId: _asId(json['image_id']),
      soundId: _asId(json['sound_id']),
      action: _asString(json['action']),
      actions: [for (final a in _asList(json['actions'])) ?_asString(a)],
      backgroundColor: _asString(json['background_color']),
      borderColor: _asString(json['border_color']),
      loadBoard: loadBoard == null
          ? null
          : ObfLoadBoard.fromJson(_asMap(loadBoard)),
      ext: _extOf(json),
    );
  }

  final String id;
  final String? label;
  final String? vocalization;
  final String? imageId;
  final String? soundId;
  final String? action;

  /// Multi-action buttons. The spec requires [action] as a single-action
  /// fallback, so this is only consulted when [action] is absent.
  final List<String> actions;

  final String? backgroundColor;
  final String? borderColor;
  final ObfLoadBoard? loadBoard;
  final Map<String, Object?> ext;

  String? get primaryAction =>
      action ?? (actions.isEmpty ? null : actions.first);

  Map<String, Object?> toJson() => _dense({
    'id': id,
    'label': label,
    'vocalization': vocalization,
    'image_id': imageId,
    'sound_id': soundId,
    'action': action,
    'actions': actions.isEmpty ? null : actions,
    'background_color': backgroundColor,
    'border_color': borderColor,
    'load_board': loadBoard?.toJson(),
    ...ext,
  });
}

/// A reference to a symbol in a proprietary set, where redistributing the
/// image itself would breach its terms.
class ObfSymbolRef {
  const ObfSymbolRef({this.set, this.filename});

  factory ObfSymbolRef.fromJson(Map<String, Object?> json) => ObfSymbolRef(
    set: _asString(json['set']),
    filename: _asString(json['filename']),
  );

  final String? set;
  final String? filename;

  Map<String, Object?> toJson() => _dense({'set': set, 'filename': filename});
}

class ObfImage {
  const ObfImage({
    required this.id,
    this.url,
    this.data,
    this.path,
    this.contentType,
    this.width,
    this.height,
    this.symbol,
    this.license,
  });

  factory ObfImage.fromJson(Map<String, Object?> json) {
    final id = _asId(json['id']);
    if (id == null) throw ObfFormatException('image without an id');
    final symbol = json['symbol'];
    final license = json['license'];
    return ObfImage(
      id: id,
      url: _asString(json['url']),
      data: _asString(json['data']),
      path: _asString(json['path']),
      contentType: _asString(json['content_type']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      symbol: symbol == null ? null : ObfSymbolRef.fromJson(_asMap(symbol)),
      license: license == null ? null : ObfLicense.fromJson(_asMap(license)),
    );
  }

  final String id;
  final String? url;
  final String? data;
  final String? path;
  final String? contentType;
  final int? width;
  final int? height;
  final ObfSymbolRef? symbol;
  final ObfLicense? license;

  Map<String, Object?> toJson() => _dense({
    'id': id,
    'url': url,
    'data': data,
    'path': path,
    'content_type': contentType,
    'width': width,
    'height': height,
    'symbol': symbol?.toJson(),
    'license': license?.toJson(),
  });
}

class ObfSound {
  const ObfSound({
    required this.id,
    this.url,
    this.data,
    this.path,
    this.contentType,
    this.duration,
    this.license,
  });

  factory ObfSound.fromJson(Map<String, Object?> json) {
    final id = _asId(json['id']);
    if (id == null) throw ObfFormatException('sound without an id');
    final license = json['license'];
    return ObfSound(
      id: id,
      url: _asString(json['url']),
      data: _asString(json['data']),
      path: _asString(json['path']),
      contentType: _asString(json['content_type']),
      duration: _asInt(json['duration']),
      license: license == null ? null : ObfLicense.fromJson(_asMap(license)),
    );
  }

  final String id;
  final String? url;
  final String? data;
  final String? path;
  final String? contentType;
  final int? duration;
  final ObfLicense? license;

  Map<String, Object?> toJson() => _dense({
    'id': id,
    'url': url,
    'data': data,
    'path': path,
    'content_type': contentType,
    'duration': duration,
    'license': license?.toJson(),
  });
}

/// A 2D map of button ids onto grid locations. `null` is a location that
/// exists and holds nothing — a reserved cell, not a missing one.
class ObfGrid {
  const ObfGrid({
    required this.rows,
    required this.columns,
    required this.order,
  });

  factory ObfGrid.fromJson(Map<String, Object?> json) {
    final order = [
      for (final r in _asList(json['order']))
        [for (final c in _asList(r)) _asId(c)],
    ];
    // Declared dimensions and the actual array disagree often enough that
    // trusting either alone truncates boards. Take whichever is larger.
    final widest = order.fold(0, (m, r) => r.length > m ? r.length : m);
    return ObfGrid(
      rows: _max(_asInt(json['rows']) ?? 0, order.length),
      columns: _max(_asInt(json['columns']) ?? 0, widest),
      order: order,
    );
  }

  final int rows;
  final int columns;
  final List<List<String?>> order;

  Map<String, Object?> toJson() => {
    'rows': rows,
    'columns': columns,
    'order': order,
  };
}

int _max(int a, int b) => a > b ? a : b;

class ObfBoard {
  const ObfBoard({
    required this.id,
    this.format = obfFormat,
    this.locale,
    this.name,
    this.descriptionHtml,
    this.url,
    this.dataUrl,
    this.buttons = const [],
    this.grid,
    this.images = const [],
    this.sounds = const [],
    this.strings = const {},
    this.license,
    this.ext = const {},
  });

  factory ObfBoard.fromJson(Map<String, Object?> json) {
    final grid = json['grid'];
    final license = json['license'];
    return ObfBoard(
      format: _asString(json['format']) ?? obfFormat,
      id: _asId(json['id']) ?? '',
      locale: _asString(json['locale']),
      name: _asString(json['name']),
      descriptionHtml: _asString(json['description_html']),
      url: _asString(json['url']),
      dataUrl: _asString(json['data_url']),
      buttons: [
        for (final b in _asList(json['buttons'])) ObfButton.fromJson(_asMap(b)),
      ],
      grid: grid == null ? null : ObfGrid.fromJson(_asMap(grid)),
      images: [
        for (final i in _asList(json['images'])) ObfImage.fromJson(_asMap(i)),
      ],
      sounds: [
        for (final s in _asList(json['sounds'])) ObfSound.fromJson(_asMap(s)),
      ],
      strings: {
        for (final e in _asMap(json['strings']).entries)
          e.key: {
            for (final t in _asMap(e.value).entries) t.key: ?_asString(t.value),
          },
      },
      license: license == null ? null : ObfLicense.fromJson(_asMap(license)),
      ext: _extOf(json),
    );
  }

  factory ObfBoard.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ObfFormatException('not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw ObfFormatException('expected a JSON object at the root');
    }
    return ObfBoard.fromJson(_asMap(decoded));
  }

  final String format;
  final String id;
  final String? locale;
  final String? name;
  final String? descriptionHtml;
  final String? url;
  final String? dataUrl;
  final List<ObfButton> buttons;
  final ObfGrid? grid;
  final List<ObfImage> images;
  final List<ObfSound> sounds;

  /// Per-locale translations, keyed by the raw `label` / `vocalization` value.
  final Map<String, Map<String, String>> strings;

  final ObfLicense? license;
  final Map<String, Object?> ext;

  Map<String, Object?> toJson() => _dense({
    'format': format,
    'id': id,
    'locale': locale,
    'name': name,
    'description_html': descriptionHtml,
    'url': url,
    'data_url': dataUrl,
    'buttons': [for (final b in buttons) b.toJson()],
    'grid': grid?.toJson(),
    'images': [for (final i in images) i.toJson()],
    'sounds': [for (final s in sounds) s.toJson()],
    'strings': strings.isEmpty ? null : strings,
    'license': (license?.isEmpty ?? true) ? null : license!.toJson(),
    ...ext,
  });

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// The `.obz` table of contents. Required whenever the package holds more
/// than one board.
class ObzManifest {
  const ObzManifest({
    this.format = obfFormat,
    this.root,
    this.boards = const {},
    this.images = const {},
    this.sounds = const {},
  });

  factory ObzManifest.fromJson(Map<String, Object?> json) {
    Map<String, String> paths(String key) => {
      for (final e in _asMap(_asMap(json['paths'])[key]).entries)
        e.key: ?_asString(e.value),
    };
    return ObzManifest(
      format: _asString(json['format']) ?? obfFormat,
      root: _asString(json['root']),
      boards: paths('boards'),
      images: paths('images'),
      sounds: paths('sounds'),
    );
  }

  factory ObzManifest.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ObfFormatException('manifest.json is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw ObfFormatException('manifest.json must be a JSON object');
    }
    return ObzManifest.fromJson(_asMap(decoded));
  }

  final String format;

  /// Path within the zip of the board the user lands on.
  final String? root;

  /// Board id to path within the zip.
  final Map<String, String> boards;
  final Map<String, String> images;
  final Map<String, String> sounds;

  Map<String, Object?> toJson() => _dense({
    'format': format,
    'root': root,
    'paths': {'boards': boards, 'images': images, 'sounds': sounds},
  });

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Resolves a `label` or `vocalization` through the board's string lists.
///
/// Falls back to the bare language subtag, then to the value as written —
/// which the spec explicitly permits, and which is why untranslated proper
/// nouns need no entry at all.
String? resolveObfString(
  Map<String, Map<String, String>> strings,
  String? locale,
  String? value,
) {
  if (value == null || locale == null || strings.isEmpty) return value;
  final exact = strings[locale]?[value];
  if (exact != null) return exact;
  final language = locale.split(RegExp('[-_]')).first;
  return strings[language]?[value] ?? value;
}

/// Reads a wordbridge extension key that may have survived a trip through
/// another app's exporter as a string.
T? readExt<T extends Object>(Map<String, Object?> ext, String key) {
  final raw = ext[key];
  if (raw == null) return null;
  return switch (T) {
    const (int) => _asInt(raw) as T?,
    const (bool) => _asBool(raw) as T?,
    _ => _asString(raw) as T?,
  };
}
