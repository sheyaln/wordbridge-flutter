import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wordbridge/features/reporting/report_sender.dart';

/// §4.52. The only code in the app that opens a socket because of a report.
///
/// There is no queue, no retry loop and no background upload, which is the
/// design and not an omission: an AAC app that talks to a server on its own is
/// an AAC app whose privacy claim is about intentions rather than about what
/// the code can do.
void main() {
  /// Answers every request the same way, and keeps what it was asked.
  http.Client answering(
    int status, {
    String body = '{}',
    void Function(http.BaseRequest request)? onRequest,
  }) => _FakeClient((request) {
    onRequest?.call(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
    );
  });

  ReportSender sender(http.Client client) =>
      ReportSender(client: client, url: 'https://intake.invalid/v1', token: 't');

  group('what a status code means to a caregiver', () {
    test('accepted', () => expect(problemFor(202), isNull));
    test('and every other success shape', () {
      for (final ok in [200, 201, 204]) {
        expect(problemFor(ok), isNull, reason: '$ok');
      }
    });

    test('a schema the intake will not take says to update', () {
      expect(problemFor(400), contains('Update the app'));
      expect(problemFor(422), contains('Update the app'));
    });

    test('a rejected token says the same, and nothing about tokens', () {
      // A report screen is not a place to learn about bearer tokens, and there
      // is nothing a caregiver could do with the real reason.
      expect(problemFor(401), contains('Update the app'));
      expect(problemFor(401), isNot(contains('token')));
    });

    test('too large, and too many', () {
      expect(problemFor(413), ReportSender.tooLong);
      expect(problemFor(429), contains('Too many'));
    });

    test('and anything unexpected keeps the report rather than losing it', () {
      expect(problemFor(500), ReportSender.couldNotReach);
      expect(problemFor(302), ReportSender.couldNotReach);
    });
  });

  group('the reference the intake gives back', () {
    test('is read out so a caregiver can quote it', () {
      expect(referenceIn('{"reference":"WB-3K9F"}'), 'WB-3K9F');
    });

    test('and a body without one costs nothing', () {
      // The status code already said it arrived. A missing reference costs a
      // quotable string, not somebody's report.
      expect(referenceIn('{}'), isNull);
      expect(referenceIn('not json at all'), isNull);
      expect(referenceIn('{"reference":""}'), isNull);
      expect(referenceIn('[]'), isNull);
    });
  });

  group('sending', () {
    test('reports the reference on success', () async {
      final outcome = await sender(
        answering(202, body: '{"reference":"WB-1"}'),
      ).send({'schema': 1});

      expect(outcome.sent, isTrue);
      expect(outcome.reference, 'WB-1');
      expect(outcome.problem, isNull);
    });

    test('and never claims to have sent one it did not', () async {
      final outcome = await sender(answering(500)).send({'schema': 1});
      expect(outcome.sent, isFalse);
      expect(outcome.problem, ReportSender.couldNotReach);
    });

    test('a build with no intake says so instead of failing quietly', () {
      // The right state for a fork and for anyone building from source.
      final blank = ReportSender(url: '', token: '');
      expect(blank.configured, isFalse);
      expect(
        blank.send({'schema': 1}),
        completion(
          (SendOutcome o) => o.problem == ReportSender.notConfigured && !o.sent,
        ),
      );
    });

    test('and a token without a URL is not configured either', () {
      expect(ReportSender(url: '', token: 't').configured, isFalse);
      expect(ReportSender(url: 'https://x.invalid', token: '').configured,
          isFalse);
    });

    test('carries the token and the JSON content type', () async {
      http.BaseRequest? seen;
      await sender(
        answering(202, onRequest: (r) => seen = r),
      ).send({'schema': 1});

      expect(seen!.headers['authorization'], 'Bearer t');
      expect(seen!.headers['content-type'], 'application/json');
      expect(seen!.method, 'POST');
    });

    test('and does not follow a redirect', () async {
      // A redirect is a way for an intake to be repointed at somewhere nobody
      // agreed to. This one goes where it was built to go or it does not go.
      http.BaseRequest? seen;
      await sender(
        answering(202, onRequest: (r) => seen = r),
      ).send({'schema': 1});

      expect(seen!.followRedirects, isFalse);
    });

    test('a network that is not there is not an exception a caregiver sees',
        () async {
      final outcome = await sender(
        _FakeClient((_) => throw const SocketFailure()),
      ).send({'schema': 1});

      expect(outcome.sent, isFalse);
      expect(outcome.problem, ReportSender.couldNotReach);
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this._answer);

  final http.StreamedResponse Function(http.BaseRequest request) _answer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Read the body first, the way a real client would, so a test can assert
    // on what was actually going to be written.
    await request.finalize().toBytes();
    return _answer(request);
  }
}
