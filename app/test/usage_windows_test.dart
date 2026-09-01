import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/editor/remap_confirm_sheet.dart';
import 'package:wordbridge/features/usage/logger.dart';
import 'package:wordbridge/features/usage/usage_queries.dart';
import 'package:wordbridge/features/usage/usage_summary.dart';

/// Every figure in here is read by somebody making a decision about a
/// person — an SLP writing a funding letter, a caregiver deciding whether a
/// move is safe. A day that is 23 or 25 hours long must not move any of them.
void main() {
  int startOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
  }

  /// Local days on this host that are not 24 hours long. Empty where the
  /// host's timezone never changes offset, which the tests below say plainly
  /// rather than passing on nothing.
  List<DateTime> clockChangeDays() {
    final today = DateTime.now();
    return [
      for (var i = 0; i < 400; i++)
        if (DateTime(today.year, today.month, today.day + i + 1)
                .difference(DateTime(today.year, today.month, today.day + i))
                .inHours !=
            24)
          DateTime(today.year, today.month, today.day + i),
    ];
  }

  /// The axis as absolute 24-hour steps, for comparison only.
  List<DateTime> byDuration(DateTime today, int days) => [
    for (var i = days - 1; i >= 0; i--)
      DateTime(today.year, today.month, today.day).subtract(Duration(days: i)),
  ];

  group('the day axis walks calendar days', () {
    test('a clock change does not knock the axis off midnight', () {
      final changes = clockChangeDays();
      if (changes.isEmpty) {
        markTestSkipped(
          'this host keeps a fixed UTC offset all year, so there is no clock '
          'change here to walk across',
        );
        return;
      }

      final change = changes.first;
      // Two days after the change, so the short or long day sits inside the
      // week rather than on its edge.
      final today = DateTime(change.year, change.month, change.day + 2);
      final axis = calendarDaysEnding(today, 7);

      for (final day in axis) {
        expect(
          [day.hour, day.minute, day.second, day.millisecond],
          [0, 0, 0, 0],
          reason:
              '$day is not local midnight, so no day bucket keyed on a date '
              'can ever match it and the chart shows a zero',
        );
      }

      expect(
        axis.map((d) => (d.month, d.day)),
        contains((change.month, change.day)),
        reason: 'the day the clocks changed dropped out of the week entirely',
      );

      expect(
        axis,
        isNot(byDuration(today, 7)),
        reason:
            'the two are meant to differ across a clock change; if they agree '
            'this host found no real transition and the test proves nothing',
      );
    });

    test('every key is local midnight, one calendar day apart', () {
      // Two years of end dates, which crosses every clock change, month end,
      // year end and leap day this host observes.
      final base = DateTime(2026, 1, 1);
      for (var offset = 0; offset < 730; offset++) {
        final today = DateTime(base.year, base.month, base.day + offset);
        final axis = calendarDaysEnding(today, 7);

        expect(axis, hasLength(7));
        expect(axis.last, DateTime(today.year, today.month, today.day));

        for (var i = 0; i < axis.length; i++) {
          final day = axis[i];
          expect(
            [day.hour, day.minute, day.second, day.millisecond],
            [0, 0, 0, 0],
            reason: '$day is not local midnight',
          );
          if (i > 0) {
            final previous = axis[i - 1];
            expect(
              day,
              DateTime(previous.year, previous.month, previous.day + 1),
              reason: '$previous to $day is not one calendar day',
            );
          }
        }
      }
    });

    test('a month end is a day like any other', () {
      expect(calendarDaysEnding(DateTime(2026, 3, 2), 4), [
        DateTime(2026, 2, 27),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 2),
      ]);
    });

    test('a leap day is not skipped', () {
      expect(
        calendarDaysEnding(DateTime(2028, 3, 1), 3),
        contains(DateTime(2028, 2, 29)),
      );
    });
  });

  group('today means today', () {
    late WordbridgeDatabase db;
    late UsageQueries q;

    setUp(() {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      q = UsageQueries(db);
    });

    tearDown(() async => db.close());

    Future<void> record(String label, int at, {String? utteranceId}) => db
        .into(db.usageEvents)
        .insert(
          UsageEventsCompanion.insert(
            deviceId: 'test',
            profileId: 'p1',
            vocabularyId: 'v1',
            boardId: 'b1',
            cellId: 'c1',
            labelSnapshot: label,
            action: ButtonAction.speak,
            source: UsageSource.touch,
            sessionId: 's1',
            utteranceId: Value(utteranceId),
            occurredAt: at,
          ),
        );

    test('a calendar window starts at midnight', () {
      final n = DateTime.now();
      expect(
        const UsageWindow.calendarDays(1).cutoffMs(),
        DateTime(n.year, n.month, n.day).millisecondsSinceEpoch,
      );
    });

    test('yesterday evening is not part of today', () async {
      await record('eat', nowMs());
      await record('drink', startOfToday() - 1);

      expect(
        await q.totalTaps('p1', window: const UsageWindow.calendarDays(1)),
        1,
        reason: 'a figure labeled today cannot include last night',
      );
      expect(
        await q.numberOfDifferentWords(
          'p1',
          window: const UsageWindow.calendarDays(1),
        ),
        1,
      );

      expect(
        await q.totalTaps('p1', window: const UsageWindow.rollingDays(1)),
        2,
        reason: 'a rolling day is a different question and still answers it',
      );
    });

    test('a sentence from last night is not a sentence from today', () async {
      await record('go', startOfToday() - 2000, utteranceId: 'u1');
      await record('home', startOfToday() - 1000, utteranceId: 'u1');

      expect(
        await q.recentUtterances(
          'p1',
          window: const UsageWindow.calendarDays(1),
        ),
        isEmpty,
        reason: 'a sentence listed under today has to have been said today',
      );
      expect(
        (await q.recentUtterances(
          'p1',
          window: const UsageWindow.rollingDays(7),
        )).map((u) => u.text),
        ['go home'],
      );
    });

    test('a sentence carried over midnight is quoted whole', () async {
      await record('i', startOfToday() - 2000, utteranceId: 'u1');
      await record('want', startOfToday() - 1000, utteranceId: 'u1');
      await record('breakfast', nowMs(), utteranceId: 'u1');

      expect(
        (await q.recentUtterances(
          'p1',
          window: const UsageWindow.calendarDays(1),
        )).map((u) => u.text),
        ['i want breakfast'],
        reason:
            'the words chosen before midnight are part of the sentence that '
            'came out after it, and a quote missing its start is a misquote',
      );
    });

    testWidgets('the summary counts today from midnight', (tester) async {
      await record('eat', nowMs());
      await record('drink', startOfToday() - 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UsageSummary(
              db: db,
              profileId: 'p1',
              logger: UsageLogger(db, deviceId: 'test')..enabled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      expect(
        find.text('2'),
        findsNothing,
        reason: 'only one word was said today; the other was said yesterday',
      );
      expect(find.text('1'), findsWidgets);
    });
  });

  group('activity by day', () {
    late WordbridgeDatabase db;
    late UsageQueries q;

    setUp(() {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      q = UsageQueries(db);
    });

    tearDown(() async => db.close());

    Future<void> record(int at) => db
        .into(db.usageEvents)
        .insert(
          UsageEventsCompanion.insert(
            deviceId: 'test',
            profileId: 'p1',
            vocabularyId: 'v1',
            boardId: 'b1',
            cellId: 'c1',
            labelSnapshot: 'eat',
            action: ButtonAction.speak,
            source: UsageSource.touch,
            sessionId: 's1',
            occurredAt: at,
          ),
        );

    test('a used day is never reported as empty', () async {
      await record(nowMs());
      await record(nowMs());
      await record(startOfToday() - 1);

      final week = await q.activityByDay('p1');

      expect(week, hasLength(7));
      expect(
        week.map((d) => d.day).toList(),
        calendarDaysEnding(DateTime.now(), 7),
        reason: 'the axis has to be the same days the buckets are keyed by',
      );
      expect(week.last.count, 2);
      expect(week[week.length - 2].count, 1);
      expect(week.take(5).map((d) => d.count), everyElement(0));
    });
  });

  group('days since first use', () {
    test('a date change counts, not twenty-four hours', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 10, 23, 0),
          DateTime(2026, 3, 11, 0, 30),
        ),
        1,
        reason: 'ninety minutes spanning midnight is a day ago, not today',
      );
    });

    test('the same day is zero', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 10, 0, 5),
          DateTime(2026, 3, 10, 23, 55),
        ),
        0,
      );
    });

    test('a short or long day still counts as one', () {
      final changes = clockChangeDays();
      if (changes.isEmpty) {
        markTestSkipped(
          'this host keeps a fixed UTC offset all year, so there is no short '
          'or long day here to count',
        );
        return;
      }

      for (final change in changes) {
        expect(
          calendarDaysBetween(
            change,
            DateTime(change.year, change.month, change.day + 3),
          ),
          3,
          reason: 'three days across the change on $change came out wrong',
        );
      }
    });

    testWidgets('the sheet counts calendar days', (tester) async {
      final n = DateTime.now();
      // The last millisecond of yesterday: one calendar day back at every hour
      // of the day, and under twenty-four hours back at all but the last.
      final firstUsed = DateTime.fromMillisecondsSinceEpoch(
        DateTime(n.year, n.month, n.day).millisecondsSinceEpoch - 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemapConfirmSheet(
              impact: (
                label: 'eat',
                taps: 5,
                days: 2,
                firstUsed: firstUsed,
                isLearned: false,
                windowDays: 90,
              ),
              warning: 'Moving "eat" will change its motor pattern.',
              destination: 'row 1, column 1',
            ),
          ),
        ),
      );

      expect(
        find.text('1'),
        findsOneWidget,
        reason: 'first use was yesterday, which is one day ago all day',
      );
    });

    testWidgets('the sheet says how far back the figures look', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemapConfirmSheet(
              impact: (
                label: 'eat',
                taps: 5,
                days: 2,
                firstUsed: DateTime.now(),
                isLearned: false,
                windowDays: 90,
              ),
              warning: 'Moving "eat" will change its motor pattern.',
              destination: 'row 1, column 1',
            ),
          ),
        ),
      );

      expect(find.textContaining('last 90 days'), findsWidgets);
    });
  });

  group('which selections count', () {
    late WordbridgeDatabase db;
    late UsageQueries q;

    setUp(() {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      q = UsageQueries(db);
    });

    tearDown(() async => db.close());

    Future<void> record(
      String label, {
      required UsageSource source,
      String? utteranceId,
      int? at,
    }) => db
        .into(db.usageEvents)
        .insert(
          UsageEventsCompanion.insert(
            deviceId: 'test',
            profileId: 'p1',
            vocabularyId: 'v1',
            boardId: 'b1',
            cellId: 'c1',
            labelSnapshot: label,
            action: ButtonAction.speak,
            source: source,
            sessionId: 's1',
            utteranceId: Value(utteranceId),
            occurredAt: at ?? nowMs(),
          ),
        );

    test('switch scanning is a user reaching a word', () async {
      final now = nowMs();
      await record(
        'i',
        source: UsageSource.switchAccess,
        utteranceId: 'u1',
        at: now - 1000,
      );
      await record(
        'drink',
        source: UsageSource.switchAccess,
        utteranceId: 'u1',
        at: now,
      );
      await record('drink', source: UsageSource.switchAccess, at: now);

      expect(await q.totalTaps('p1'), 3);
      expect(await q.numberOfDifferentWords('p1'), 2);
      expect(
        (await q.mostUsedWords('p1')).map((w) => (w.label, w.count)),
        containsAll([('drink', 2), ('i', 1)]),
      );
      expect((await q.activityByDay('p1')).last.count, 3);
      expect((await q.recentUtterances('p1')).map((u) => u.text), ['i drink']);
      expect(
        (await q.historyForCell('c1')).taps,
        3,
        reason: 'a remap warning has to count a switch user\'s practice too',
      );
    });

    test('a partner modeling reaches no report', () async {
      await record('eat', source: UsageSource.partnerModel, utteranceId: 'u1');

      expect(await q.totalTaps('p1'), 0);
      expect(await q.numberOfDifferentWords('p1'), 0);
      expect(await q.mostUsedWords('p1'), isEmpty);
      expect(await q.recentUtterances('p1'), isEmpty);
      expect((await q.historyForCell('c1')).taps, 0);
    });

    test('a word a partner modeled is not quoted as the user\'s', () async {
      final now = nowMs();
      await record(
        'i',
        source: UsageSource.touch,
        utteranceId: 'u1',
        at: now - 2000,
      );
      await record(
        'like',
        source: UsageSource.partnerModel,
        utteranceId: 'u1',
        at: now - 1000,
      );
      await record(
        'cookie',
        source: UsageSource.prediction,
        utteranceId: 'u1',
        at: now,
      );

      expect(
        (await q.recentUtterances('p1')).map((u) => u.text),
        ['i cookie'],
        reason:
            'a partner demonstrating a word on the device said it, not the '
            'user, so it is not part of what the user is quoted as saying',
      );
    });

    test('a word off the prediction strip is said, not practiced', () async {
      final now = nowMs();
      await record(
        'i',
        source: UsageSource.switchAccess,
        utteranceId: 'u1',
        at: now - 2000,
      );
      await record(
        'want',
        source: UsageSource.touch,
        utteranceId: 'u1',
        at: now - 1000,
      );
      await record(
        'cookie',
        source: UsageSource.prediction,
        utteranceId: 'u1',
        at: now,
      );

      expect((await q.recentUtterances('p1')).map((u) => u.text), [
        'i want cookie',
      ], reason: 'the user said all three words, in that order');
      expect(
        await q.totalTaps('p1'),
        3,
        reason: 'three words came out of the device, and the user chose each',
      );
      expect(await q.numberOfDifferentWords('p1'), 3);
      expect(await q.mostUsedWords('p1'), hasLength(3));
      expect((await q.activityByDay('p1')).last.count, 3);
      expect(
        (await q.historyForCell('c1')).taps,
        2,
        reason:
            'the strip was never reached for, so it is no evidence about the '
            'location and must not inflate a remap warning',
      );
    });
  });
}
