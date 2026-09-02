import 'dart:convert';

import 'package:http/http.dart' as http;

import 'report.dart';

/// What happened when somebody pressed send.
///
/// [reference] is what the intake gives back so a caregiver can quote it. A
/// report they cannot refer to afterwards is a report they have to trust went
/// somewhere.
typedef SendOutcome = ({bool sent, String? reference, String? problem});

/// Where a report goes, and the only code in the app that opens a socket
/// because of one (§4.52).
///
/// **Nothing here runs on a timer.** There is no queue, no retry loop and no
/// background upload. `send` is called from a button press and from nowhere
/// else, which is the whole design and not an implementation detail: an AAC
/// app that talks to a server on its own is an AAC app whose privacy claim is
/// about intentions rather than about what the code can do.
class ReportSender {
  ReportSender({http.Client? client, String? url, String? token})
    : _client = client ?? http.Client(),
      url = url ?? intakeUrl,
      token = token ?? intakeToken;

  final http.Client _client;
  final String url;
  final String token;

  /// Compiled in at build time. A build given neither has no reporting, which
  /// is the right state for a fork and for anyone building from source — the
  /// screen says so rather than offering a button that cannot work.
  static const intakeUrl = String.fromEnvironment('WORDBRIDGE_INTAKE_URL');
  static const intakeToken = String.fromEnvironment('WORDBRIDGE_INTAKE_TOKEN');

  bool get configured => url.isNotEmpty && token.isNotEmpty;

  Future<SendOutcome> send(Map<String, Object?> payload) async {
    if (!configured) {
      return (sent: false, reference: null, problem: notConfigured);
    }

    final body = utf8.encode(jsonEncode(payload));
    if (body.length > reportSizeLimit) {
      return (sent: false, reference: null, problem: tooLong);
    }

    try {
      final request = http.Request('POST', Uri.parse(url))
        // A redirect is a way for an intake to be repointed at somewhere
        // nobody agreed to. This one goes where it was built to go or it does
        // not go.
        ..followRedirects = false
        ..headers.addAll({
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        })
        ..bodyBytes = body;

      final response = await http.Response.fromStream(
        await _client.send(request),
      );

      final problem = problemFor(response.statusCode);
      if (problem != null) {
        return (sent: false, reference: null, problem: problem);
      }
      return (sent: true, reference: referenceIn(response.body), problem: null);
    } catch (_) {
      return (sent: false, reference: null, problem: couldNotReach);
    }
  }

  void close() => _client.close();

  static const notConfigured =
      'This build has nowhere to send reports to. Nothing was sent.';
  static const tooLong = 'That report is too long to send. Shorten it.';
  static const couldNotReach =
      'It could not be sent. The report is still here, so you can try again '
      'when this device is online.';
}

/// Why a response means the report did not arrive, or null where it did.
///
/// A closed set of sentences a caregiver reads. Nothing here repeats what the
/// server said: a report screen is not a place to learn about bearer tokens,
/// and a message assembled from a response body is a message somebody else
/// wrote.
String? problemFor(int status) => switch (status) {
  200 || 201 || 202 || 204 => null,
  400 || 422 =>
    'This version of Wordbridge AAC cannot send reports any more. '
        'Update the app and try again.',
  401 || 403 =>
    'This build is not allowed to send reports. Update the app '
        'and try again.',
  413 => ReportSender.tooLong,
  429 =>
    'Too many reports have been sent from here just now. Try again '
        'later.',
  _ => ReportSender.couldNotReach,
};

/// The reference the intake gave back, or null if it gave none.
///
/// A body that is not the JSON this expects is not an error: the report
/// arrived, which is what the status code said, and a missing reference costs
/// a caregiver a quotable string rather than their report.
String? referenceIn(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final reference = json['reference'];
    return reference is String && reference.isNotEmpty ? reference : null;
  } catch (_) {
    return null;
  }
}
