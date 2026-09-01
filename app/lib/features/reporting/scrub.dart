/// Taking the private parts out of a stack trace before anybody sees it.
///
/// A trace is assembled from whatever threw, and this codebase throws messages
/// that quote board and word names on purpose — `refusalToMoveRow` names the
/// board, `moveRow` rethrows it, `refusalToPin` names the word. Those messages
/// are good messages. They are written for a caregiver reading a refusal on the
/// screen in front of them, and they are exactly the wrong thing to put in a
/// report that leaves the tablet.
///
/// So a trace is never trusted. What survives is the shape of the failure: the
/// exception type, the frames, the package paths. What goes is anything quoted
/// and anything that looks like a filesystem path.
///
/// This runs before a report is **shown**, not only before it is sent, so what
/// a caregiver reviews is exactly what would leave (§4.52).
library;

/// What a redacted run is replaced with. Visible on purpose: a caregiver
/// reading the report should be able to see that something was taken out.
const redacted = '…';

/// Anything in quotes. Single line only, so an unbalanced quote takes out the
/// rest of one line rather than the rest of the trace.
final _quoted = RegExp(
  '"[^"\n]*"'
  r"|'[^'\n]*'",
);

/// A path into somebody's account or their app container. The account name is
/// in it, and on iOS so is the container UUID.
final _paths = RegExp(
  r'(?:file://)?/(?:Users|home|var|private|data|storage)/[^\s,)\]"'
  "'"
  r']*',
);

/// The most of a trace worth carrying. Past this it is stack frames from the
/// framework, which say nothing the first thirty did not.
const traceLimit = 4000;

/// A stack trace or exception message with the private parts taken out.
String scrubbed(String detail, {int limit = traceLimit}) {
  var out = detail
      .replaceAll(_paths, '<path>')
      .replaceAll(_quoted, '"$redacted"');

  if (out.length > limit) {
    out = '${out.substring(0, limit)}\n$redacted truncated';
  }
  return out;
}

/// Why this report must not be sent, in the sentence somebody reads.
///
/// The last check before the network, and deliberately not the only one: the
/// screen shows the payload, the scrubber has already run over it, and this
/// runs anyway. A rule enforced only where it is displayed is a rule with a way
/// round it.
///
/// [names] is the handful of strings that identify a person — the profile's
/// name and the user's own. Not the board's words: "go" and "more" are
/// vocabulary, and a report refused because it contains the word "go" is a
/// report nobody can ever send.
///
/// Checked against machine-written text only. What a caregiver typed
/// themselves is theirs to type.
String? refusalToSend(String? detail, {required Iterable<String> names}) {
  if (detail == null) return null;
  final haystack = detail.toLowerCase();

  for (final name in names) {
    final needle = name.trim().toLowerCase();
    // Two characters is a fragment, not a name, and would match everywhere.
    if (needle.length < 3) continue;
    if (haystack.contains(needle)) {
      return 'This report still contains a name from this profile, so it has '
          'not been sent. Report it in your own words instead.';
    }
  }
  return null;
}
