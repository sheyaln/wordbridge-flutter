import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/reporting/report.dart';
import 'package:wordbridge/features/reporting/report_sender.dart';

/// §4.52. What a report contains, stated once so a change to it is a change
/// somebody has to write down.
void main() {
  const device = (
    platform: 'ios',
    osVersion: 'Version 18.5 (Build 22F76)',
    model: 'iPad11,1',
    locale: 'en_GB',
  );
  const board = (rows: 7, cols: 12, level: 2, engine: 'neural');

  Map<String, Object?> payload({
    ReportKind kind = ReportKind.bug,
    String note = 'the finder does not find "cook"',
    String? detail,
    Map<String, Object?>? voice,
  }) => reportPayload(
    kind: kind,
    note: note,
    device: device,
    board: board,
    detail: detail,
    voice: voice,
  );

  group('the shape', () {
    test('is the whole of it, and nothing else', () {
      expect(payload().keys, [
        'schema',
        'kind',
        'app',
        'device',
        'board',
        'note',
      ]);
    });

    test(
      'and names its version, so an old build is told rather than guessed at',
      () {
        expect(payload()['schema'], reportSchema);
      },
    );

    test('the kind travels as a stable string, not an ordinal', () {
      // An index would silently change meaning the moment a kind is added in
      // the middle of the enum, and the intake would file crashes as ideas.
      expect(payload(kind: ReportKind.crash)['kind'], 'crash');
      expect(payload(kind: ReportKind.idea)['kind'], 'idea');
    });

    test('the note is carried as typed, trimmed', () {
      expect(
        payload(note: '  it stopped speaking  ')['note'],
        'it stopped speaking',
      );
    });

    test('detail appears only where there is one', () {
      expect(payload().containsKey('detail'), isFalse);
      expect(payload(detail: 'Bad state: no')['detail'], contains('Bad state'));
    });

    test('and voice only where consent turned it on', () {
      expect(payload().containsKey('voice'), isFalse);
      expect(payload(voice: {'voice_id': 'af_heart'})['voice'], isNotNull);
    });
  });

  group('the tablet', () {
    test('is described by class, never by identity', () {
      final facts = payload()['device']! as Map<String, Object?>;
      expect(facts.keys, ['platform', 'os', 'model', 'locale']);
      expect(facts['model'], 'iPad11,1');
    });

    test('and a platform that will not say which model still reports', () {
      final quiet = reportPayload(
        kind: ReportKind.bug,
        note: 'x',
        device: (
          platform: 'android',
          osVersion: '15',
          model: null,
          locale: 'en_GB',
        ),
        board: board,
      );

      final facts = quiet['device']! as Map<String, Object?>;
      expect(facts.containsKey('model'), isFalse);
      expect(facts['platform'], 'android');
    });
  });

  group('the board', () {
    test('is geometry and level, never content', () {
      final facts = payload()['board']! as Map<String, Object?>;
      expect(facts, {'rows': 7, 'cols': 12, 'level': 2, 'engine': 'neural'});
    });
  });

  group('detail is scrubbed here, not by whoever calls', () {
    test('so there is no path that sends an unscrubbed trace', () {
      // The scrubber is not optional and not the caller's job to remember.
      final out = payload(
        detail: 'Bad state: Row 3 of "Maya\'s words" already holds 4 words.',
      );
      expect(out['detail'], isNot(contains('Maya')));
    });
  });

  group('the version', () {
    test('matches pubspec.yaml', () {
      // Declared in Dart so no plugin sits between the app and its own version
      // number, and checked here so the two cannot drift.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final line = RegExp(
        r'^version:\s*(\S+)\+(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(line, isNotNull, reason: 'pubspec.yaml has no version line');
      expect(line!.group(1), appVersion);
      expect(line.group(2), appBuild);
    });
  });

  group('size', () {
    test('a report that would be refused by the intake is refused here', () {
      // So a caregiver reads a sentence on the screen rather than meeting a
      // 413 from somewhere they cannot see.
      final huge = payload(note: 'x' * (reportSizeLimit + 1));
      expect(
        utf8.encode(jsonEncode(huge)).length,
        greaterThan(reportSizeLimit),
      );

      expect(
        ReportSender(url: 'https://example.invalid', token: 't').send(huge),
        completion(
          (SendOutcome o) => !o.sent && o.problem == ReportSender.tooLong,
        ),
      );
    });
  });
}
