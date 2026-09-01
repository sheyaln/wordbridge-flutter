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
const appVersion = '0.1.0';
const appBuild = '1';

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
