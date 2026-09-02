import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wordbridge/features/reporting/crash_flush.dart';
import 'package:wordbridge/features/reporting/crash_store.dart';
import 'package:wordbridge/features/reporting/report_sender.dart';

/// Sending what crashed last time, which is what the crash toggle governs.
///
/// The switch says "send crash reports". §4.57 spent a sweep deleting text that
/// promised behavior the code did not have, so the thing worth testing here is
/// not that a flag is stored but that turning it on sends and turning it off
/// does not.
void main() {
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('wordbridge-flush');
  });
  tearDown(() async => documents.delete(recursive: true));

  CrashStore storeIn(Directory dir) =>
      CrashStore(documentsDirectory: () async => dir);

  /// Records what it was asked to send, and answers however it was told to.
  ({ReportSender sender, List<Map<String, Object?>> sent}) senderThat({
    int status = 202,
    String body = '{"reference":"WB-TEST"}',
  }) {
    final sent = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      sent.add(json.decode(request.body) as Map<String, Object?>);
      return http.Response(body, status);
    });
    return (
      sender: ReportSender(
        client: client,
        url: 'https://intake.test/v1/reports',
        token: 't',
      ),
      sent: sent,
    );
  }

  const board = (rows: 7, cols: 12, level: 2, engine: 'platform');

  test('a fault waiting from last time is sent', () async {
    final store = storeIn(documents);
    await store.record(
      StateError('the board would not draw'),
      StackTrace.current,
    );

    final s = senderThat();
    final result = await flushCaughtFaults(
      store: store,
      sender: s.sender,
      enabled: true,
      board: board,
    );

    expect(result.attempted, 1);
    expect(result.sent, 1);
    expect(s.sent, hasLength(1));
    expect(s.sent.single['kind'], 'crash');
  });

  test('and is discarded, so it cannot go twice', () async {
    // Two launches in a row must not report one crash twice. The record is
    // removed only once the intake has accepted it.
    final store = storeIn(documents);
    await store.record(StateError('once'), StackTrace.current);

    final first = senderThat();
    await flushCaughtFaults(
      store: store,
      sender: first.sender,
      enabled: true,
      board: board,
    );
    expect(await store.waiting(), isEmpty);

    final second = senderThat();
    final again = await flushCaughtFaults(
      store: store,
      sender: second.sender,
      enabled: true,
      board: board,
    );
    expect(again.sent, 0);
    expect(second.sent, isEmpty);
  });

  test('switched off, nothing is sent and nothing is thrown away', () async {
    // The half that makes the switch true. A record kept is one somebody can
    // still send by hand from the reports screen.
    final store = storeIn(documents);
    await store.record(StateError('kept'), StackTrace.current);

    final s = senderThat();
    final result = await flushCaughtFaults(
      store: store,
      sender: s.sender,
      enabled: false,
      board: board,
    );

    expect(result.attempted, 0);
    expect(s.sent, isEmpty);
    expect(await store.waiting(), hasLength(1));
  });

  test('a build with no intake sends nothing', () async {
    final store = storeIn(documents);
    await store.record(StateError('nowhere to go'), StackTrace.current);

    final result = await flushCaughtFaults(
      store: store,
      sender: ReportSender(url: '', token: ''),
      enabled: true,
      board: board,
    );

    expect(result.attempted, 0);
    expect(await store.waiting(), hasLength(1));
  });

  test('an intake that refuses keeps the record for next time', () async {
    // 503 is what the intake answers when storage is down, and the whole point
    // of that status is that the report is not lost.
    final store = storeIn(documents);
    await store.record(StateError('try again'), StackTrace.current);

    final s = senderThat(status: 503, body: 'no');
    final result = await flushCaughtFaults(
      store: store,
      sender: s.sender,
      enabled: true,
      board: board,
    );

    expect(result.attempted, 1);
    expect(result.sent, 0);
    expect(
      await store.waiting(),
      hasLength(1),
      reason: 'a refused report must survive to be sent again',
    );
  });

  test('a quoted name is scrubbed out, and the report still goes', () async {
    // This codebase throws messages that quote board names on purpose, and the
    // scrubber takes quoted runs out before anything else looks at the trace.
    // So this one sends — with the name already gone, which is the point.
    final store = storeIn(documents);
    await store.record(
      StateError('Row 3 of "Maya’s favorites" already holds 4 words.'),
      StackTrace.current,
    );

    final s = senderThat();
    final result = await flushCaughtFaults(
      store: store,
      sender: s.sender,
      enabled: true,
      board: board,
      names: const ['Maya'],
    );

    expect(result.sent, 1);
    expect(
      json.encode(s.sent.single),
      isNot(contains('Maya')),
      reason: 'the name must not reach the intake by any field',
    );
  });

  test('a name the scrubber cannot see stops the report entirely', () async {
    // Unquoted, so there is no quoted run to strip and the trace reaches the
    // name check with the name still in it. That check is the backstop, and
    // its answer is to send nothing rather than to send a redacted guess.
    final store = storeIn(documents);
    await store.record(
      StateError('Maya has no cell at 3,4'),
      StackTrace.current,
    );

    final s = senderThat();
    final result = await flushCaughtFaults(
      store: store,
      sender: s.sender,
      enabled: true,
      board: board,
      names: const ['Maya'],
    );

    expect(result.sent, 0);
    expect(s.sent, isEmpty, reason: 'a name must not reach the intake');
    expect(
      await store.waiting(),
      hasLength(1),
      reason: 'kept, so somebody can report it in their own words',
    );
  });

  test('nothing waiting is not an error', () async {
    final s = senderThat();
    final result = await flushCaughtFaults(
      store: storeIn(documents),
      sender: s.sender,
      enabled: true,
      board: board,
    );
    expect(result, (attempted: 0, sent: 0));
    expect(s.sent, isEmpty);
  });

  test('a store that cannot be read fails quietly', () async {
    // This runs inside app startup. Whatever it hits, the launch continues.
    final missing = Directory('${documents.path}/gone');
    final s = senderThat();

    final result = await flushCaughtFaults(
      store: storeIn(missing),
      sender: s.sender,
      enabled: true,
      board: board,
    );

    expect(result, (attempted: 0, sent: 0));
  });
}
