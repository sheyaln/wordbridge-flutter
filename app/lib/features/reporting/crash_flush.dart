import 'crash_store.dart';
import 'device_facts.dart';
import 'report.dart';
import 'report_sender.dart';
import 'scrub.dart';

/// Sends the faults this tablet caught last time (§4.59).
///
/// **On the next launch, never during the crash.** `recordCaughtFaults`
/// installs before the app does: it holds no database and no profile, and the
/// fault it is handling may be the database. Putting a network call inside an
/// error handler on a device that has just failed is how one fault becomes
/// two. So a fault is written where it happens and sent from here, once the
/// app is up, the setting is readable and nobody is mid sentence.
///
/// Every failure ends quietly. A record that cannot be sent is kept for the
/// next launch or for somebody to send by hand from the reports screen; a
/// record the intake accepted is discarded so it cannot go twice. Nothing here
/// may throw into app startup.
Future<CrashFlushResult> flushCaughtFaults({
  required CrashStore store,
  required ReportSender sender,
  required bool enabled,
  required BoardFacts board,
  DeviceModel? models,
  Iterable<String> names = const [],
}) async {
  if (!enabled || !sender.configured) {
    return (attempted: 0, sent: 0);
  }

  final List<CrashRecord> waiting;
  try {
    waiting = await store.waiting();
  } catch (_) {
    return (attempted: 0, sent: 0);
  }
  if (waiting.isEmpty) return (attempted: 0, sent: 0);

  final device = await deviceFacts(models: models);
  var sent = 0;

  for (final record in waiting) {
    final payload = reportPayload(
      kind: ReportKind.crash,
      note: '',
      device: device,
      board: board,
      detail: record.detail,
    );

    // The same last check the reports screen makes before the network. A
    // trace is assembled from whatever threw, and this codebase throws
    // messages that quote board names and words on purpose.
    if (refusalToSend(payload['detail'] as String?, names: names) != null) {
      continue;
    }

    try {
      final outcome = await sender.send(payload);
      if (outcome.sent) {
        await store.discard(record.id);
        sent++;
      }
    } catch (_) {
      // Kept for next time. A fault that cannot be reported is not a reason
      // to fail the launch that was going to report it.
    }
  }

  return (attempted: waiting.length, sent: sent);
}

/// What one flush did, for a test to read. Nothing displays this.
typedef CrashFlushResult = ({int attempted, int sent});
