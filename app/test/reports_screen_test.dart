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

  group('what the screen says before anything else', () {
    testWidgets('that nothing is sent on its own', (tester) async {
      await open(tester);
      expect(
        find.textContaining('never sends anything on its own'),
        findsOneWidget,
      );
    });

    testWidgets('and what a report does and does not carry', (tester) async {
      await open(tester);
      expect(find.textContaining('never carries a name'), findsOneWidget);
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
      expect(find.text('Faults this tablet caught'), findsNothing);
    });

    testWidgets('are listed, and marked unsent', (tester) async {
      await open(tester, waiting: [fault('Bad state: no route')]);
      expect(find.text('Faults this tablet caught'), findsOneWidget);
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

      expect(find.text('Faults this tablet caught'), findsNothing);
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
    testWidgets('shows the payload itself before anything is sent', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'the finder is slow');
      await tester.pump();

      await tester.ensureVisible(find.text('Review and send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and send'));
      await tester.pumpAndSettle();

      // The whole report, as JSON, not a description of it.
      final shown = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;

      expect(shown, contains('"schema": 1'));
      expect(shown, contains('the finder is slow'));
      expect(shown, contains('"rows": 7'));
      expect(shown, contains('"model": "iPad11,1"'));

      // And what it is not: no name, and nothing from the board.
      expect(shown, isNot(contains('Maya')));
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
      expect(find.textContaining('Sent'), findsOneWidget);
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

class _Counting extends http.BaseClient {
  _Counting(this._onSend);

  final VoidCallback _onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    _onSend();
    return http.StreamedResponse(const Stream.empty(), 202);
  }
}
