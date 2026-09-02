/// The report in the words a caregiver reads, rather than in the shape the
/// intake receives it (§4.52).
///
/// Consent is given while looking at this, so everything the payload carries
/// has a line here. A field this file has no label for is still shown, under
/// its own key: a caregiver who agreed to a report they were shown part of
/// agreed to nothing.
library;

import 'report.dart';

/// One labeled line of a report.
typedef ReportLine = ({String label, String value});

/// The lines that belong together under one heading.
typedef ReportSection = ({String title, List<ReportLine> lines});

/// The whole payload, grouped and labeled.
List<ReportSection> reportSections(Map<String, Object?> payload) {
  final rest = Map<String, Object?>.of(payload);
  final sections = <ReportSection>[];

  void section(String title, List<ReportLine> lines) {
    if (lines.isNotEmpty) sections.add((title: title, lines: lines));
  }

  Map<String, Object?> group(String key) {
    final value = rest.remove(key);
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  final kind = rest.remove('kind');
  final note = rest.remove('note');
  final detail = rest.remove('detail');
  final schema = rest.remove('schema');
  final app = group('app');
  final device = group('device');
  final board = group('board');
  final voice = group('voice');

  section('Report', [
    if (kind != null) (label: 'Kind', value: _kindTitle('$kind')),
    if (note is String && note.trim().isNotEmpty)
      (label: 'What you wrote', value: note.trim()),
    if (detail != null)
      (label: 'What the app recorded', value: _readable(detail)),
  ]);

  section('App', [
    ?_line(app, 'version', 'Version'),
    ?_line(app, 'build', 'Build'),
    if (schema != null) (label: 'Report format', value: _readable(schema)),
    ..._leftover(app),
  ]);

  section('Tablet', [
    ?_line(device, 'platform', 'System'),
    ?_line(device, 'os', 'System version'),
    ?_line(device, 'model', 'Model'),
    ?_line(device, 'locale', 'Language'),
    ..._leftover(device),
  ]);

  final grid = board.containsKey('rows') && board.containsKey('cols')
      ? '${board.remove('rows')} rows by ${board.remove('cols')} columns'
      : null;

  section('Board', [
    if (grid != null) (label: 'Grid', value: grid),
    ?_line(board, 'level', 'Vocabulary level'),
    ?_line(board, 'engine', 'Speech', _engineTitle),
    ..._leftover(board),
  ]);

  final fallbacks = voice.remove('fallbacks');

  section('Voice measurements', [
    ?_line(voice, 'voice_id', 'Voice'),
    ?_line(voice, 'budget_base_ms', 'Time allowed', _milliseconds),
    ?_line(
      voice,
      'budget_per_word_ms',
      'Time allowed for each word',
      _milliseconds,
    ),
    ?_line(voice, 'fallback_count', 'Fell back to the device voice', _howOften),
    for (final fallback in fallbacks is List ? fallbacks : const [])
      (label: 'Fallback', value: _fallback(fallback)),
    ..._leftover(voice),
  ]);

  section('Also included', [..._leftover(rest)]);
  return sections;
}

/// One line of a group, or null where the payload does not carry the field.
/// Taken out of the group so what stays behind is what nothing has labeled.
ReportLine? _line(
  Map<String, Object?> from,
  String key,
  String label, [
  String Function(Object?)? format,
]) {
  if (!from.containsKey(key)) return null;
  final value = from.remove(key);
  return (label: label, value: (format ?? _readable)(value));
}

Iterable<ReportLine> _leftover(Map<String, Object?> from) sync* {
  for (final entry in from.entries) {
    yield (label: labelFor(entry.key), value: _readable(entry.value));
  }
}

/// The words a caregiver reads in place of a payload key.
String labelFor(String key) {
  final words = key
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .trim()
      .toLowerCase();
  if (words.isEmpty) return key;
  return words[0].toUpperCase() + words.substring(1);
}

String _readable(Object? value) => switch (value) {
  null => '',
  bool it => it ? 'Yes' : 'No',
  String it => _looksLikeADate(it) ? readableDate(it) : it,
  List it => it.map(_readable).join(', '),
  Map it => [
    for (final entry in it.entries)
      '${labelFor('${entry.key}')}: ${_readable(entry.value)}',
  ].join(', '),
  _ => '$value',
};

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?');

bool _looksLikeADate(String value) => _isoDate.hasMatch(value);

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A moment as a date, in the reader's own time zone. An intake timestamp is
/// written for a machine and is unreadable at the moment somebody is deciding
/// whether to send it.
String readableDate(String value) {
  final at = DateTime.tryParse(value)?.toLocal();
  if (at == null) return value;

  final day = '${at.day} ${_months[at.month - 1]} ${at.year}';
  final carriesATime = _isoDate.firstMatch(value)?.group(4) != null;
  if (!carriesATime) return day;

  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');
  return '$day at $hour:$minute';
}

String _kindTitle(String wire) {
  for (final kind in ReportKind.values) {
    if (kind.wire == wire) return kind.title;
  }
  return labelFor(wire);
}

String _engineTitle(Object? engine) => switch (engine) {
  'neural' => 'Neural voice',
  'platform' => 'Device voice',
  _ => _readable(engine),
};

String _milliseconds(Object? value) => '${_readable(value)} ms';

String _howOften(Object? value) => switch (value) {
  0 => 'Never',
  1 => 'Once',
  _ => '${_readable(value)} times',
};

/// One fallback, as a sentence. The reason is matched on the wire string
/// rather than on the enum so that nothing in a report drags the speech engine
/// in behind it; `report_summary_test.dart` holds the two in step.
String _fallback(Object? fallback) {
  if (fallback is! Map) return _readable(fallback);

  final rest = Map<String, Object?>.from(fallback);
  final reason = rest.remove('reason');
  final words = rest.remove('words');

  return [
    if (reason != null) fallbackReason('$reason'),
    if (words != null) '${_readable(words)} ${words == 1 ? 'word' : 'words'}',
    for (final line in _leftover(rest)) '${line.label}: ${line.value}',
  ].join(', ');
}

/// Why the device voice spoke instead, in a sentence.
String fallbackReason(String wire) => switch (wire) {
  'voiceUnavailable' => 'The voice was not available',
  'overBudget' => 'Ran over the time allowed',
  'failed' => 'The voice failed',
  'other' => 'Another reason',
  _ => labelFor(wire),
};
