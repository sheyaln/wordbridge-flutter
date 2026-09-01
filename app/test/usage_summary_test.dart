import 'dart:async';

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
/// caregiver has it open, and breaks the ones a test asks it to.
class _CountReads extends QueryInterceptor {
  int reads = 0;

  /// Statement fragment whose read fails, as a locked or corrupt database
  /// would fail it. One fragment per panel, so a test can break one figure and
  /// leave the rest of the log readable.
  String? failOn;

  /// Statement fragment whose read is accepted and then never answered, which
  /// is the shape of a wedged database rather than a failing one.
  String? hangOn;

  final _stuck = <Completer<List<Map<String, Object?>>>>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('usage_events')) reads++;

    final hang = hangOn;
    if (hang != null && statement.contains(hang)) {
      final stuck = Completer<List<Map<String, Object?>>>();
      _stuck.add(stuck);
      return stuck.future;
    }

    final fail = failOn;
    if (fail != null && statement.contains(fail)) {
      return Future.error(StateError('the usage log could not be read'));
    }

    return executor.runSelect(statement, args);
  }

  /// Answers everything left hanging, so the database can be closed.
  void release() {
    for (final stuck in _stuck) {
      if (!stuck.isCompleted) stuck.complete(const []);
    }
    _stuck.clear();
  }
}

/// The reads behind the screen, by a fragment of the SQL each one emits.
const _differentWords = 'COUNT(DISTINCT';
const _sentences = 'utterance_id" IN (SELECT';
const _mostUsed = 'GROUP BY "usage_events"."label_snapshot"';

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

  tearDown(() async {
    counter.release();
    await db.close();
  });

  int daysAgo(int days) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - days, 12).millisecondsSinceEpoch;
  }

  Future<void> record(
    String label,
    int at, {
    String profileId = 'p1',
    String? utteranceId,
    UsageSource source = UsageSource.touch,
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
          source: source,
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
        reason: 'a figure labeled today cannot still be the weekly one',
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
      expect(
        find.text('Nothing recorded in the last 7 days.'),
        findsNWidgets(2),
      );
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

    testWidgets('a window is a window on the sentences too', (tester) async {
      final now = nowMs();
      await record('go', daysAgo(20), utteranceId: 'u2');
      await record('home', daysAgo(20) + 1000, utteranceId: 'u2');
      await record('i', now - 1000, utteranceId: 'u1');
      await record('want', now, utteranceId: 'u1');

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.text('i want'), findsOneWidget);
      expect(
        find.text('go home'),
        findsNothing,
        reason: 'three weeks ago is not the last seven days',
      );

      await tester.tap(find.text('Today'));
      await settle(tester);

      expect(find.text('i want'), findsOneWidget);
      expect(
        find.text('go home'),
        findsNothing,
        reason:
            'the sentences sit under a control that says today, so a sentence '
            'from three weeks ago there is a lie about when it was said',
      );
      expect(find.text('2'), findsWidgets, reason: 'two words spoken today');

      await tester.tap(find.text('30 days'));
      await settle(tester);

      expect(find.text('go home'), findsOneWidget);
      expect(find.text('i want'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
    });

    testWidgets('an empty window says which window is empty', (tester) async {
      await record('go', daysAgo(20), utteranceId: 'u2');
      await record('home', daysAgo(20) + 1000, utteranceId: 'u2');

      await tester.pumpWidget(screen());
      await settle(tester);

      await tester.tap(find.text('Today'));
      await settle(tester);

      expect(find.text('go home'), findsNothing);
      expect(find.text('0'), findsWidgets);
      expect(
        find.text('Nothing recorded today.'),
        findsNWidgets(2),
        reason:
            'the log is not empty, only today is, and a caregiver reading '
            '"nothing recorded" has to know which of those they are looking at',
      );
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

  group('however the user reaches the board', () {
    /// Six selections by switch scanning, three of them one sentence.
    Future<void> seedSwitchAccess() async {
      final now = nowMs();
      for (final (i, word) in ['i', 'want', 'more'].indexed) {
        await record(
          word,
          now - 3000 + i * 1000,
          utteranceId: 'u1',
          source: UsageSource.switchAccess,
        );
      }
      for (var i = 0; i < 3; i++) {
        await record('more', now, source: UsageSource.switchAccess);
      }
    }

    testWidgets('a switch user gets a report, not a blank page', (
      tester,
    ) async {
      await seedSwitchAccess();

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        find.text('6'),
        findsWidgets,
        reason:
            'six words were spoken by switch scanning, and this figure goes '
            'to a funder as evidence that the device is used',
      );
      expect(find.text('3'), findsWidgets, reason: 'three different words');
      expect(find.text('i want more'), findsOneWidget);
      expect(
        find.text('want'),
        findsOneWidget,
        reason: 'the most-used list is as much theirs as anyone else\'s',
      );
      expect(find.text('4'), findsOneWidget, reason: '"more" four times');
      expect(find.textContaining('Nothing recorded'), findsNothing);
    });

    testWidgets('a word off the prediction strip stays in the sentence', (
      tester,
    ) async {
      final now = nowMs();
      await record(
        'i',
        now - 2000,
        utteranceId: 'u1',
        source: UsageSource.switchAccess,
      );
      await record('want', now - 1000, utteranceId: 'u1');
      await record(
        'cookie',
        now,
        utteranceId: 'u1',
        source: UsageSource.prediction,
      );

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        find.text('i want cookie'),
        findsOneWidget,
        reason: 'a sentence quoted without its last word is a misquote',
      );
      expect(
        find.text('3'),
        findsNWidgets(2),
        reason:
            'three words were spoken and three were different; a report of '
            'how much language came out cannot drop one of them',
      );
      expect(
        find.text('cookie'),
        findsOneWidget,
        reason:
            'a word the user picked and the device said belongs in the '
            'most-used list like any other',
      );
    });

    testWidgets('a partner modelling is not the user talking', (tester) async {
      final now = nowMs();
      await record(
        'i',
        now - 1000,
        utteranceId: 'u1',
        source: UsageSource.partnerModel,
      );
      await record(
        'want',
        now,
        utteranceId: 'u1',
        source: UsageSource.partnerModel,
      );

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        find.text('i want'),
        findsNothing,
        reason: 'what a partner demonstrated is not what the user said',
      );
      expect(find.text('0'), findsWidgets);
      expect(
        find.text('Nothing recorded in the last 7 days.'),
        findsNWidgets(2),
      );
    });
  });

  group('when the log cannot be read', () {
    testWidgets('a figure that failed does not take the others with it', (
      tester,
    ) async {
      await seed();
      counter.failOn = _differentWords;

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        find.textContaining('Could not read the counts'),
        findsOneWidget,
        reason: 'the panel that failed has to say which figures are missing',
      );
      expect(
        find.text('i want'),
        findsOneWidget,
        reason: 'the sentences read fine and a parent came here to see them',
      );
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the most-used list read fine',
      );
      expect(
        find.text('9'),
        findsNothing,
        reason: 'the counts are the panel that failed',
      );
      expect(
        find.text('—'),
        findsNothing,
        reason: 'a dash where a number should be explains nothing',
      );
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'nothing is still loading, so nothing may still say it is',
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a list that failed is not a list with nothing in it', (
      tester,
    ) async {
      await seed();
      counter.failOn = _sentences;

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        find.textContaining('Could not read the recent sentences'),
        findsOneWidget,
      );
      expect(find.text('i want'), findsNothing);
      expect(
        find.textContaining('Nothing recorded'),
        findsNothing,
        reason:
            'a week the device could not read is not a week in which nothing '
            'was said, and an SLP reading the second would conclude the user '
            'had stopped talking',
      );
      expect(find.text('9'), findsWidgets, reason: 'the counts read fine');
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('the retry asks the database again', (tester) async {
      await seed();
      counter.failOn = _mostUsed;

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(
        find.textContaining('Could not read the most-used words'),
        findsOneWidget,
      );
      expect(find.text('9'), findsWidgets, reason: 'the counts read fine');
      expect(find.text('i want'), findsOneWidget);

      counter.failOn = null;
      final beforeRetry = counter.reads;

      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(
        counter.reads,
        beforeRetry + 1,
        reason:
            'a retry that does not go back to the database is a button that '
            'does nothing',
      );
      expect(
        find.textContaining('Could not read the most-used words'),
        findsNothing,
      );
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the panel a caregiver retried has to fill in',
      );
      expect(
        find.text('9'),
        findsWidgets,
        reason: 'retrying one panel must not throw away the other two',
      );
    });

    testWidgets('a screen that cannot read anything says so three times', (
      tester,
    ) async {
      await seed();
      counter.failOn = 'usage_events';

      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.textContaining('Could not read the counts'), findsOneWidget);
      expect(
        find.textContaining('Could not read the recent sentences'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Could not read the most-used words'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNWidgets(3));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('—'), findsNothing);
      expect(
        find.textContaining('Nothing recorded'),
        findsNothing,
        reason:
            'a log that could not be read is not a log with nothing in it, '
            'and a caregiver must never be shown the second for the first',
      );
    });

    testWidgets('a read that never answers gives up rather than spinning', (
      tester,
    ) async {
      await seed();
      counter.hangOn = 'usage_events';

      await tester.pumpWidget(screen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(
        find.byType(LinearProgressIndicator),
        findsWidgets,
        reason: 'five seconds in, a read still on its way is fair enough',
      );

      await tester.pump(const Duration(seconds: 6));

      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason:
            'a bar that keeps moving over a read that will never land tells a '
            'caregiver the opposite of what is happening',
      );
      expect(find.text('—'), findsNothing);
      expect(find.text('Try again'), findsNWidgets(3));

      counter.release();
      await tester.pump();
    });
  });

  group('switching recording is noticed at once', () {
    testWidgets('switching it off empties a screen that is already open', (
      tester,
    ) async {
      await seed();

      await tester.pumpWidget(screen());
      await settle(tester);
      expect(find.text('9'), findsWidgets);

      // No rebuild from anywhere else: the switch is the only thing that moved.
      logger.enabled = false;
      await settle(tester);

      expect(
        find.text('Word usage is not being tracked'),
        findsOneWidget,
        reason:
            'a screen still showing figures after recording was switched off '
            'says the log is being written when it is not',
      );
      expect(find.text('9'), findsNothing);
    });

    testWidgets('switching it on fills a screen that is already open', (
      tester,
    ) async {
      await seed();
      logger.enabled = false;

      await tester.pumpWidget(screen());
      await settle(tester);
      expect(find.text('Word usage is not being tracked'), findsOneWidget);
      expect(counter.reads, 0);

      logger.enabled = true;
      await settle(tester);

      expect(
        find.text('9'),
        findsWidgets,
        reason:
            'the figures have to arrive on the switch, not on some later '
            'unrelated rebuild',
      );
      expect(find.text('i want'), findsOneWidget);
    });

    testWidgets('setting it to what it already is changes nothing', (
      tester,
    ) async {
      await seed();

      await tester.pumpWidget(screen());
      await settle(tester);
      final onceLoaded = counter.reads;

      logger.enabled = true;
      await settle(tester);

      expect(
        counter.reads,
        onceLoaded,
        reason: 'nothing changed, so nothing should have been re-read',
      );
      expect(find.text('9'), findsWidgets);
    });
  });
}
