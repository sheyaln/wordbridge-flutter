import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/caregiver/reports_screen.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/reporting/crash_store.dart';
import 'package:wordbridge/features/reporting/device_facts.dart';
import 'package:wordbridge/features/reporting/report_sender.dart';

/// §4.52. Nothing leaves this tablet without somebody reading it first.
///
/// The screen's whole job is that sentence being true, so these are tests
/// about what is on it and what pressing things does, not about the network.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late String profileId;
  late ProfileSettings settings;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabularyId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    profileId = (await db.select(db.profiles).getSingle()).id;
    settings = ProfileSettings(db, profileId);
    await settings.load();
  });

  tearDown(() async => db.close());

  Future<void> open(
    WidgetTester tester, {
    List<CrashRecord> waiting = const [],
    http.Client? client,
    String url = 'https://intake.invalid/v1',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportsScreen(
          db: db,
          vocabularyId: vocabularyId,
          profileId: profileId,
          settings: settings,
          crashes: _Waiting(waiting),
          models: _NoModel(),
          sender: ReportSender(
            client: client ?? _Never(),
            url: url,
            token: url.isEmpty ? '' : 't',
          ),
          userName: 'Maya',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  CrashRecord fault(String detail) =>
      (id: 'one.json', at: DateTime.now(), detail: detail);

  /// Writes a note and opens the sheet that shows what would be sent.
  Future<void> review(
    WidgetTester tester, {
    String note = 'the finder is slow',
  }) async {
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), note);
    await tester.pump();

    await tester.ensureVisible(find.text('Review and send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review and send'));
    await tester.pumpAndSettle();
  }

  /// Only what the sheet says. The screen underneath carries some of the same
  /// words, in the field labels a report is written in.
  Finder inTheSheet(Finder matching) => find.descendant(
    of: find.byType(DraggableScrollableSheet),
    matching: matching,
  );

  group('what the screen says before anything else', () {
    testWidgets('what the screen is for', (tester) async {
      await open(tester);
      expect(
        find.textContaining('Tell us something is wrong or missing'),
        findsOneWidget,
      );
    });

    // What a report carries is no longer described here in the abstract. The
    // review sheet lists every field of the real one, which is the same
    // information where it can be acted on, and `every field in words` below
    // is what holds that. This asserts the description did not come back:
    // stated twice, the first telling is a promise and only the second is
    // evidence.
    testWidgets('and does not promise it in the abstract first', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('never carries'), findsNothing);
      expect(find.textContaining('never sends'), findsNothing);
    });

    testWidgets('a build with no intake says so rather than pretending', (
      tester,
    ) async {
      await open(tester, url: '');
      expect(find.textContaining('nowhere to send reports'), findsOneWidget);
    });
  });

  group('faults this tablet caught', () {
    testWidgets('are not shown when there are none', (tester) async {
      await open(tester);
      expect(find.text('Faults this device caught'), findsNothing);
    });

    testWidgets('are listed, and marked unsent', (tester) async {
      await open(tester, waiting: [fault('Bad state: no route')]);
      expect(find.text('Faults this device caught'), findsOneWidget);
      expect(find.text('Not sent'), findsOneWidget);
    });

    testWidgets('and open onto the whole thing, not a summary', (tester) async {
      await open(tester, waiting: [fault('Bad state: no route')]);
      await tester.tap(find.text('Just now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Bad state: no route'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('discarding one takes it off the screen', (tester) async {
      await open(tester, waiting: [fault('Bad state: no route')]);
      await tester.tap(find.text('Just now'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Faults this device caught'), findsNothing);
    });
  });

  group('writing one', () {
    testWidgets('send is refused until something has been written', (
      tester,
    ) async {
      await open(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Review and send'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('and offered once it has', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'the finder is slow');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Review and send'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('whitespace is not something written', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review and send'),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('review', () {
    testWidgets('says what the sheet is', (tester) async {
      await open(tester);
      await review(tester);

      expect(find.text('What will be sent'), findsOneWidget);
    });

    testWidgets('shows every field of the report, in words', (tester) async {
      await open(tester);
      await review(tester);

      // Grouped and labeled, and all of it: this is where consent is given, so
      // a field missing from the sheet is a field nobody agreed to.
      expect(inTheSheet(find.text('Kind')), findsOneWidget);
      expect(inTheSheet(find.text('Something is wrong')), findsOneWidget);
      expect(inTheSheet(find.text('the finder is slow')), findsOneWidget);
      expect(inTheSheet(find.text('0.1.0')), findsOneWidget);
      expect(inTheSheet(find.text('iPad11,1')), findsOneWidget);

      await tester.scrollUntilVisible(
        inTheSheet(find.text('7 rows by 12 columns')),
        120,
        scrollable: inTheSheet(find.byType(Scrollable)).first,
      );
      expect(inTheSheet(find.text('7 rows by 12 columns')), findsOneWidget);
      expect(inTheSheet(find.text('Vocabulary level')), findsOneWidget);
    });

    testWidgets('and none of it as JSON', (tester) async {
      await open(tester);
      await review(tester);

      expect(inTheSheet(find.textContaining('{')), findsNothing);
      expect(inTheSheet(find.textContaining('"schema"')), findsNothing);

      // And what a report never carries, however it is laid out.
      expect(inTheSheet(find.textContaining('Maya')), findsNothing);
    });

    testWidgets('and backing out sends nothing', (tester) async {
      var sent = 0;
      await open(tester, client: _Counting(() => sent++));
      await tester.enterText(find.byType(TextField), 'x marks it');
      await tester.pump();

      await tester.ensureVisible(find.text('Review and send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(sent, 0);
    });

    testWidgets('pressing send is what sends it', (tester) async {
      var sent = 0;
      await open(tester, client: _Counting(() => sent++));
      await tester.enterText(find.byType(TextField), 'x marks it');
      await tester.pump();

      await tester.ensureVisible(find.text('Review and send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send this'));
      await tester.pumpAndSettle();

      expect(sent, 1);
      expect(find.text('Report sent'), findsOneWidget);
    });
  });

  group('once it has gone', () {
    Future<void> send(WidgetTester tester) async {
      await review(tester, note: 'the finder is slow');
      await tester.tap(find.text('Send this'));
      await tester.pumpAndSettle();
    }

    testWidgets('the screen says so', (tester) async {
      await open(tester, client: _Answering(body: '{"reference":"WB-7QK2"}'));
      await send(tester);

      expect(find.text('Report sent'), findsOneWidget);
    });

    testWidgets('and gives back the reference to quote', (tester) async {
      // A report nobody can refer to afterwards is one they have to trust went
      // somewhere.
      await open(tester, client: _Answering(body: '{"reference":"WB-7QK2"}'));
      await send(tester);

      expect(find.textContaining('WB-7QK2'), findsOneWidget);
    });

    testWidgets('or thanks them where the intake gave no reference', (
      tester,
    ) async {
      await open(tester, client: _Answering());
      await send(tester);

      expect(find.text('Report sent'), findsOneWidget);
      expect(find.text('Thank you.'), findsOneWidget);
    });

    testWidgets('the note is cleared, so the same report is not sent twice', (
      tester,
    ) async {
      await open(tester, client: _Answering());
      await send(tester);

      expect(find.text('the finder is slow'), findsNothing);
    });

    testWidgets('and the confirmation is on the screen of a short tablet', (
      tester,
    ) async {
      // Send is the last thing in the list, so on a short tablet the answer to
      // pressing it lands below the fold and reads as nothing having happened.
      tester.view.physicalSize = const Size(800, 460);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await open(tester, client: _Answering());
      await send(tester);

      expect(find.text('Report sent'), findsOneWidget);
      expect(tester.getRect(find.text('Report sent')).bottom, lessThan(460));
    });
  });

  group('when it did not go', () {
    testWidgets('it says so rather than thanking anybody', (tester) async {
      await open(tester, client: _Answering(status: 500));
      await review(tester, note: 'the finder is slow');
      await tester.tap(find.text('Send this'));
      await tester.pumpAndSettle();

      expect(find.text('Not sent'), findsOneWidget);
      expect(find.text('Report sent'), findsNothing);
      expect(find.textContaining('could not be sent'), findsOneWidget);
    });

    testWidgets('and the report is still there to try again with', (
      tester,
    ) async {
      await open(tester, client: _Answering(status: 500));
      await review(tester, note: 'the finder is slow');
      await tester.tap(find.text('Send this'));
      await tester.pumpAndSettle();

      expect(find.text('the finder is slow'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review and send'),
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  group('a short screen', () {
    testWidgets('still puts the decision in reach', (tester) async {
      // The buttons used to sit at the end of the sheet's scroll, so a report
      // long enough to be worth reviewing was one whose send button was below
      // the bottom of the screen. It passed on a tall surface and failed on a
      // short one, which is how CI found it.
      tester.view.physicalSize = const Size(800, 460);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _Counting(() {});
      await open(tester, client: client);

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'a note');
      await tester.pump();

      await tester.ensureVisible(find.text('Review and send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and send'));
      await tester.pumpAndSettle();

      // No scrolling to find it. Pinned means visible.
      expect(find.text('Send this'), findsOneWidget);
      await tester.tap(find.text('Send this'));
      await tester.pumpAndSettle();

      expect(client.sent, 1);
    });
  });

  group('when a fault happened', () {
    // In the words somebody would use out loud. A caregiver deciding whether a
    // fault is worth reporting is asking "was that the thing I just saw?", and
    // an ISO timestamp does not answer it.
    final now = DateTime(2026, 8, 31, 20);

    test('just now', () {
      expect(
        whenItHappened(now.subtract(const Duration(seconds: 20)), now: now),
        'Just now',
      );
    });

    test('minutes', () {
      expect(
        whenItHappened(now.subtract(const Duration(minutes: 12)), now: now),
        '12 minutes ago',
      );
    });

    test('an hour is not "1 hours"', () {
      expect(
        whenItHappened(now.subtract(const Duration(hours: 1)), now: now),
        'An hour ago',
      );
    });

    test('hours', () {
      expect(
        whenItHappened(now.subtract(const Duration(hours: 5)), now: now),
        '5 hours ago',
      );
    });

    test('yesterday is not "1 days"', () {
      expect(
        whenItHappened(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
    });

    test('and days', () {
      expect(
        whenItHappened(now.subtract(const Duration(days: 4)), now: now),
        '4 days ago',
      );
    });
  });

  group('the voice measurement switch', () {
    testWidgets('is not offered where nothing neural is speaking', (
      tester,
    ) async {
      // The platform voice has no budget, no fallbacks and nothing to measure.
      await open(tester);
      expect(
        find.textContaining('how the neural voice is performing'),
        findsNothing,
      );
    });
  });
}

/// Faults without a folder. A real directory read started inside a widget test
/// never comes back under the fake clock.
class _Waiting extends CrashStore {
  _Waiting(this._records);

  List<CrashRecord> _records;

  @override
  Future<List<CrashRecord>> waiting() async => _records;

  @override
  Future<void> discard(String id) async => _records = [
    for (final r in _records)
      if (r.id != id) r,
  ];
}

/// The hardware identifier, without the platform. An unanswered method
/// channel under the test binding never returns at all.
class _NoModel extends DeviceModel {
  @override
  Future<String?> model() async => 'iPad11,1';
}

class _Never extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw StateError('nothing on this screen may reach the network');
}

/// An intake that answers, so what the screen says afterwards can be read.
class _Answering extends http.BaseClient {
  _Answering({this.status = 202, this.body = ''});

  final int status;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }
}

class _Counting extends http.BaseClient {
  _Counting(this._onSend);

  final VoidCallback _onSend;
  int sent = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    sent++;
    _onSend();
    return http.StreamedResponse(const Stream.empty(), 202);
  }
}
