/// What a report contains, and what it may never contain (§4.52).
///
/// Three kinds go to one place, because from a caregiver's side there is one
/// question — "this is wrong, or this is missing" — and asking them to sort it
/// into a category first is asking them to do our triage.
///
/// Everything here is a pure function of its arguments. Nothing reads a clock,
/// a device or a database, so a test can state the whole payload and a change
/// to it is a change somebody has to write down.
library;

import 'scrub.dart';

/// The version of this document's shape. The intake rejects one it does not
/// know rather than guessing, and an old build is told to update rather than
/// being quietly half-understood.
const reportSchema = 1;

/// Kept in step with `pubspec.yaml` by `report_payload_test.dart`, which reads
/// the file. Declared rather than looked up so that no plugin sits between the
/// app and its own version number.
const appVersion = '0.3.1';
const appBuild = '5';

enum ReportKind {
  crash('Something crashed', 'A fault the app caught and recovered from'),
  bug('Something is wrong', 'It does not do what it should'),
  idea('Something is missing', 'A word, a setting, a way of working');

  const ReportKind(this.title, this.description);

  final String title;
  final String description;

  String get wire => name;
}

/// What is known about the tablet. No identifier of any kind.
///
/// The model is a class of hardware shared by millions of devices and is the
/// one field that makes a neural voice timing mean anything: "slow" on an iPad
/// mini 5 and "slow" on this year's iPad are different findings.
typedef DeviceFacts = ({
  String platform,
  String osVersion,
  String? model,
  String locale,
});

/// What the person is looking at when they report. Geometry and level, never
/// content.
typedef BoardFacts = ({int rows, int cols, int level, String engine});

/// The finished report, as the intake receives it.
///
/// [detail] is machine-written and is scrubbed here rather than by the caller,
/// so there is no path that reaches this function with an unscrubbed trace and
/// no way to forget.
Map<String, Object?> reportPayload({
  required ReportKind kind,
  required String note,
  required DeviceFacts device,
  required BoardFacts board,
  String? detail,
  Map<String, Object?>? voice,

  /// When the fault happened, for a crash that is being sent later.
  ///
  /// A crash is recorded at the moment it happens and sent on the next healthy
  /// launch, so the two can be a fortnight apart. Without this the arrival time
  /// is the only time anybody has, and a backlog emptying all at once is
  /// indistinguishable from a device failing over and over right now — which is
  /// what §4.67 was, and it took reading object timestamps out of storage to
  /// tell which.
  DateTime? occurredAt,
}) => {
  'schema': reportSchema,
  'kind': kind.wire,
  'app': {'version': appVersion, 'build': appBuild},
  'device': {
    'platform': device.platform,
    'os': device.osVersion,
    'model': ?device.model,
    'locale': device.locale,
  },
  'board': {
    'rows': board.rows,
    'cols': board.cols,
    'level': board.level,
    'engine': board.engine,
  },
  'occurredAt': ?occurredAt?.toUtc().toIso8601String(),
  'note': note.trim(),
  if (detail != null) 'detail': scrubbed(detail),
  'voice': ?voice,
};

/// The most a report may weigh, matching what the intake accepts.
///
/// Enforced here as well so that a report too large is refused with a sentence
/// on the screen rather than by a 413 from somewhere the caregiver cannot see.
const reportSizeLimit = 64 * 1024;

/// The most a caregiver may type. Generous: somebody describing what went
/// wrong should not be counting characters.
const noteLimit = 4000;

/// What the note box is, said beside the note box (§4.79).
///
/// Everything else in a report is cleaned on the way out: the trace loses
/// quoted text and file paths, and `refusalToSend` stops a report still
/// carrying a profile name. That check reads machine-written text only, on
/// purpose — what somebody typed themselves is theirs to type — which leaves
/// this one field reaching us exactly as written.
///
/// So it carries the reason and not just the instruction. "Do not send personal
/// information" is a warning somebody scrolls past; "this is the only part of
/// the report that can carry a name" is a fact they can act on.
const personalInformationNotice =
    'What you type here is sent exactly as written. Everything else in the '
    'report has names and board words taken out first, so this box is the one '
    'part that can carry them. Please leave out names and anything else '
    'personal.';
