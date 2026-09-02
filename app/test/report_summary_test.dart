import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/reporting/report.dart';
import 'package:wordbridge/features/reporting/report_summary.dart';
import 'package:wordbridge/features/reporting/voice_measurements.dart';

/// §4.52. The report as the person agreeing to send it reads it.
///
/// Consent is given while looking at this, so the test the whole file is
/// making is that everything in the payload is on the screen and none of it is
/// in the shape a server wants it in.
void main() {
  const device = (
    platform: 'ios',
    osVersion: 'Version 18.5 (Build 22F76)',
    model: 'iPad11,1',
    locale: 'en_GB',
  );
  const board = (rows: 7, cols: 12, level: 2, engine: 'neural');

  final voice = voicePayload((
    voiceId: 'af_heart',
    budgetBaseMs: 900,
    budgetPerWordMs: 120,
    fallbackCount: 2,
    fallbacks: const [
      (reason: FallbackReason.overBudget, words: 5),
      (reason: FallbackReason.failed, words: 1),
    ],
  ));

  List<ReportSection> read({
    ReportKind kind = ReportKind.bug,
    String note = 'the finder is slow',
    String? detail,
    Map<String, Object?>? measurements,
  }) => reportSections(
    reportPayload(
      kind: kind,
      note: note,
      device: device,
      board: board,
      detail: detail,
      voice: measurements,
    ),
  );

  ReportSection titled(List<ReportSection> sections, String title) =>
      sections.firstWhere(
        (s) => s.title == title,
        orElse: () => fail('no section titled "$title"'),
      );

  String? valueOf(List<ReportSection> sections, String label) {
    for (final section in sections) {
      for (final line in section.lines) {
        if (line.label == label) return line.value;
      }
    }
    return null;
  }

  group('the report', () {
    test('says what kind it is in words, not in the wire spelling', () {
      expect(valueOf(read(), 'Kind'), 'Something is wrong');
      expect(
        valueOf(read(kind: ReportKind.idea), 'Kind'),
        'Something is missing',
      );
      expect(
        valueOf(read(kind: ReportKind.crash), 'Kind'),
        'Something crashed',
      );
    });

    test('carries what was typed, as it was typed', () {
      expect(
        valueOf(read(note: 'it stopped speaking'), 'What you wrote'),
        'it stopped speaking',
      );
    });

    test('and no empty line where nothing was typed', () {
      expect(valueOf(read(note: '   '), 'What you wrote'), isNull);
    });

    test('a recorded fault is shown, scrubbed as it will be sent', () {
      final shown = valueOf(
        read(detail: 'Bad state: Row 3 of "Maya\'s words" is full'),
        'What the app recorded',
      );

      expect(shown, contains('Bad state'));
      expect(shown, isNot(contains('Maya')));
    });
  });

  group('the app', () {
    test('is a version, a build and the format of the report', () {
      final app = titled(read(), 'App');
      expect(app.lines, [
        (label: 'Version', value: appVersion),
        (label: 'Build', value: appBuild),
        (label: 'Report format', value: '$reportSchema'),
      ]);
    });
  });

  group('the tablet', () {
    test('is named the way somebody would read it out', () {
      final sections = read();
      expect(valueOf(sections, 'System'), 'ios');
      expect(valueOf(sections, 'System version'), 'Version 18.5 (Build 22F76)');
      expect(valueOf(sections, 'Model'), 'iPad11,1');
      expect(valueOf(sections, 'Language'), 'en_GB');
    });
  });

  group('the board', () {
    test('is a grid in words, a level, and which voice speaks', () {
      final sections = read();
      expect(valueOf(sections, 'Grid'), '7 rows by 12 columns');
      expect(valueOf(sections, 'Vocabulary level'), '2');
      expect(valueOf(sections, 'Speech'), 'Neural voice');
    });

    test('and the device voice says so', () {
      final sections = reportSections(
        reportPayload(
          kind: ReportKind.bug,
          note: 'x',
          device: device,
          board: (rows: 4, cols: 6, level: 1, engine: 'platform'),
        ),
      );

      expect(valueOf(sections, 'Speech'), 'Device voice');
      expect(valueOf(sections, 'Grid'), '4 rows by 6 columns');
    });
  });

  group('the voice measurements', () {
    test('are only there where consent turned them on', () {
      expect(read().where((s) => s.title == 'Voice measurements'), isEmpty);
    });

    test(
      'and read as timings and counts, never as milliseconds of nothing',
      () {
        final sections = read(measurements: voice);
        expect(valueOf(sections, 'Voice'), 'af_heart');
        expect(valueOf(sections, 'Time allowed'), '900 ms');
        expect(valueOf(sections, 'Time allowed for each word'), '120 ms');
        expect(valueOf(sections, 'Fell back to the device voice'), '2 times');
      },
    );

    test('each fallback is a sentence about the shape of the failure', () {
      final lines = titled(
        read(measurements: voice),
        'Voice measurements',
      ).lines.where((l) => l.label == 'Fallback').map((l) => l.value).toList();

      expect(lines, [
        'Ran over the time allowed, 5 words',
        'The voice failed, 1 word',
      ]);
    });

    test('having never fallen back is said, not left as a zero', () {
      final sections = read(
        measurements: voicePayload((
          voiceId: 'af_heart',
          budgetBaseMs: 900,
          budgetPerWordMs: 120,
          fallbackCount: 0,
          fallbacks: const [],
        )),
      );

      expect(valueOf(sections, 'Fell back to the device voice'), 'Never');
    });

    test('and every reason the engine can give has a sentence here', () {
      // The wire spellings are matched as strings so that a report does not
      // drag the speech engine in behind it. This is what holds the two
      // together: a reason added to the enum arrives here as its own key and
      // fails.
      for (final reason in FallbackReason.values) {
        expect(
          fallbackReason(reason.wire),
          isNot(labelFor(reason.wire)),
          reason: '${reason.wire} has no sentence',
        );
      }
    });
  });

  group('nothing is left out', () {
    test('a field nothing here has a label for is still shown', () {
      // A payload that grows a field must not quietly leave the screen it is
      // consented on.
      final sections = reportSections({'kind': 'bug', 'battery': 41});
      expect(valueOf(sections, 'Battery'), '41');
    });

    test('and so is one that grew inside a group', () {
      final sections = reportSections({
        'device': {'platform': 'ios', 'screenInches': 10.2},
      });

      expect(valueOf(sections, 'System'), 'ios');
      expect(valueOf(sections, 'Screen inches'), '10.2');
    });

    test('a moment is a date, not a machine timestamp', () {
      expect(
        valueOf(reportSections({'at': '2026-08-31T20:15:00'}), 'At'),
        '31 August 2026 at 20:15',
      );
      expect(
        valueOf(reportSections({'at': '2026-08-31'}), 'At'),
        '31 August 2026',
      );
    });

    test('and something that only looks like one is left alone', () {
      expect(
        valueOf(reportSections({'at': 'later today'}), 'At'),
        'later today',
      );
    });
  });

  group('what a caregiver never sees', () {
    test('is JSON', () {
      for (final section in read(
        detail: 'Bad state: no route',
        measurements: voice,
      )) {
        for (final line in section.lines) {
          expect(line.value, isNot(contains('{')));
          expect(line.value, isNot(contains('": ')));
        }
      }
    });

    test('or a key from the payload', () {
      for (final section in read(measurements: voice)) {
        expect(section.title, isNot(contains('_')));
        for (final line in section.lines) {
          expect(line.label, isNot(contains('_')));
        }
      }
    });

    test('or a dash, between words or inside one', () {
      // §4.50. The values belong to the tablet and to whoever typed them. The
      // labels and headings are ours, and the house style is ours to keep.
      for (final section in read(measurements: voice)) {
        for (final text in [
          section.title,
          ...section.lines.map((l) => l.label),
        ]) {
          expect(
            text.contains('-') || text.contains('—') || text.contains('–'),
            isFalse,
            reason: '"$text" carries a dash or a hyphen',
          );
        }
      }
    });
  });
}
