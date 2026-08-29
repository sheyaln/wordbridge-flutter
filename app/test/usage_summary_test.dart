import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/usage/logger.dart';
import 'package:wordbridge/features/usage/usage_summary.dart';

/// Counts reads of the log, which is what the summary screen costs while a
/// caregiver has it open.
class _CountReads extends QueryInterceptor {
  int reads = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('usage_events')) reads++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  late _CountReads counter;
  late WordbridgeDatabase db;
  late UsageLogger logger;

  setUp(() {
    counter = _CountReads();
    db = WordbridgeDatabase.forTesting(
      NativeDatabase.memory().interceptWith(counter),
    );
    logger = UsageLogger(db, deviceId: 'test')..enabled = true;
  });

  tearDown(() async => db.close());

  int daysAgo(int days) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - days, 12).millisecondsSinceEpoch;
  }

  Future<void> record(
    String label,
    int at, {
    String profileId = 'p1',
    String? utteranceId,
  }) => db
      .into(db.usageEvents)
      .insert(
        UsageEventsCompanion.insert(
          deviceId: 'test',
          profileId: profileId,
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

  /// Figures that differ in every window, so a panel showing a stale one is
  /// caught rather than coinciding with the right answer.
  ///
  /// Today: 4 taps, 3 words. Last 7 days: 9 and 5. Last 30: 20 and 6.
  Future<void> seed() async {
    final now = nowMs();
    // Spaced, so the two words of the sentence can only come out in the order
    // they were said.
    await record('i', now - 2000, utteranceId: 'u1');
    await record('want', now - 1000, utteranceId: 'u1');
    await record('eat', now);
    await record('eat', now);

    for (var i = 0; i < 3; i++) {
      await record('go', daysAgo(3));
    }
    for (var i = 0; i < 2; i++) {
      await record('more', daysAgo(3));
    }
    for (var i = 0; i < 11; i++) {
      await record('stop', daysAgo(20));
    }
  }

  Widget screen({String profileId = 'p1'}) => MaterialApp(
    home: Scaffold(
      body: UsageSummary(db: db, profileId: profileId, logger: logger),
    ),
  );

  /// A frame budget rather than the ten-minute default. Every assertion below
  /// turns on the screen running out of work to do, so one that does not should
  /// say so in seconds instead of holding the suite open.
  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );

  group('an open summary reads the log once', () {
    testWidgets('it stops reading once the figures are on screen', (
      tester,
    ) async {
      await seed();

      await tester.pumpWidget(screen());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('9'),
        findsWidgets,
        reason: 'the figures have to be up before idling proves anything',
      );
      final onceLoaded = counter.reads;

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        counter.reads,
        onceLoaded,
        reason:
            'nobody touched the screen, so a caregiver leaving it open must '
            'not keep the database working',
      );
    });

    testWidgets('a rebuild that asks nothing new reads nothing new', (
      tester,
    ) async {
      await seed();

      await tester.pumpWidget(screen());
      await settle(tester);
      final onceLoaded = counter.reads;

      // The screen is rebuilt by things that have no bearing on the figures:
      // the caregiver screen around it calling setState, coming back to the
      // tab, a theme or text-size change.
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        counter.reads,
        onceLoaded,
        reason:
            'the question did not change, so the log should not have been '
            'read again',
      );
      expect(find.text('9'), findsWidgets);
    });

    testWidgets('the tree goes quiet', (tester) async {
      await seed();
      await tester.pumpWidget(screen());

      await settle(tester);

      expect(find.text('9'), findsWidgets);
      expect(find.text('5'), findsWidgets);
    });

    testWidgets('one read answers all three panels', (tester) async {
      await seed();
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        counter.reads,
        4,
        reason:
            'one query per figure and no more: the counts, the sentences and '
            'the most-used list are one snapshot of a log that is still being '
            'written to',
      );
      expect(find.text('i want'), findsOneWidget);
    });
  });

  group('the figures still change when they should', () {
    testWidgets('a different window is a different question', (tester) async {
      await seed();
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.text('9'), findsWidgets, reason: 'seven days is the default');
      expect(find.text('5'), findsWidgets);

      await tester.tap(find.text('Today'));
      await settle(tester);

      expect(
        find.text('9'),
        findsNothing,
        reason: 'a figure labelled today cannot still be the weekly one',
      );
      expect(find.text('4'), findsWidgets);
      expect(find.text('3'), findsWidgets);

      await tester.tap(find.text('30 days'));
      await settle(tester);

      expect(find.text('20'), findsWidgets);
      expect(find.text('6'), findsWidgets);
    });

    testWidgets('deleting the history empties the screen', (tester) async {
      await seed();
      await tester.pumpWidget(screen());
      await settle(tester);

      await tester.scrollUntilVisible(
        find.text('Delete all recorded use'),
        200,
      );
      await tester.tap(find.text('Delete all recorded use'));
      await settle(tester);

      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(
        find.text('9'),
        findsNothing,
        reason: 'a caregiver who deleted the history must see it gone',
      );
      expect(find.text('0'), findsWidgets);
      expect(find.text('i want'), findsNothing);
      expect(find.text('Nothing recorded yet.'), findsNWidgets(2));
    });

    testWidgets('another profile is another person', (tester) async {
      await seed();
      await record('yes', nowMs(), profileId: 'p2');

      await tester.pumpWidget(screen());
      await settle(tester);
      expect(find.text('9'), findsWidgets);

      await tester.pumpWidget(screen(profileId: 'p2'));
      await settle(tester);

      expect(
        find.text('9'),
        findsNothing,
        reason: 'one profile must never be shown another profile\'s figures',
      );
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('recording switched off reads nothing at all', (tester) async {
      await seed();
      logger.enabled = false;

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.text('Word usage is not being tracked'), findsOneWidget);
      expect(
        counter.reads,
        0,
        reason: 'a screen that reports nothing has no business in the log',
      );

      logger.enabled = true;
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.text('9'), findsWidgets);
    });

    testWidgets('switching recording back on asks the database again', (
      tester,
    ) async {
      await seed();

      await tester.pumpWidget(screen());
      await settle(tester);
      expect(find.text('9'), findsWidgets);

      logger.enabled = false;
      await tester.pumpWidget(screen());
      await settle(tester);
      expect(find.text('Word usage is not being tracked'), findsOneWidget);

      // Emptied while nothing was being recorded, as retention pruning or
      // another device of the same profile would.
      await db.delete(db.usageEvents).go();

      logger.enabled = true;
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        find.text('9'),
        findsNothing,
        reason: 'the figures are of a log that is gone',
      );
      expect(find.text('0'), findsWidgets);
    });
  });
}
