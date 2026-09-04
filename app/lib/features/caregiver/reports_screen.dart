import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../profiles/profile_settings.dart';
import '../reporting/crash_store.dart';
import '../reporting/device_facts.dart';
import '../reporting/report.dart';
import '../reporting/report_sender.dart';
import '../reporting/report_summary.dart';
import '../reporting/scrub.dart';
import '../reporting/voice_measurements.dart';
import '../speech/neural/neural_engine.dart';
import '../speech/speech_engine.dart';

/// Telling us something is wrong, or missing (§4.52).
///
/// **Nothing on this screen happens on its own.** There is no queue, no retry
/// and no background upload. A report leaves because somebody read what was in
/// it and pressed send, and what they read is every field of it, labeled.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    this.settings,
    this.speech,
    this.crashes,
    this.sender,
    this.models,
    this.userName,
    this.profileName,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final ProfileSettings? settings;
  final SpeechEngine? speech;

  /// Built by existing when nothing supplies one. A widget test gives it a
  /// store that answers without touching the documents directory: a fake clock
  /// never lets real platform file I/O finish, and the suite hangs at teardown.
  final CrashStore? crashes;
  final ReportSender? sender;

  /// Which hardware this is. Injected for the same reason as the two above,
  /// and the sharpest case of it: an unanswered method channel under the test
  /// binding does not fail, it never returns, and the screen sits for ever on
  /// an await nobody can see.
  final DeviceModel? models;

  final String? userName;
  final String? profileName;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final CrashStore _crashes = widget.crashes ?? CrashStore();
  late final ReportSender _sender = widget.sender ?? ReportSender();

  final _note = TextEditingController();
  final _scroll = ScrollController();
  ReportKind _kind = ReportKind.bug;
  List<CrashRecord> _waiting = const [];
  SendOutcome? _outcome;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final waiting = await _crashes.waiting();
    if (mounted) setState(() => _waiting = waiting);
  }

  Future<Map<String, Object?>> _payload({String? detail}) async {
    final vocabulary = await (widget.db.select(
      widget.db.vocabularies,
    )..where((v) => v.id.equals(widget.vocabularyId))).getSingleOrNull();
    final profile = await (widget.db.select(
      widget.db.profiles,
    )..where((p) => p.id.equals(widget.profileId))).getSingleOrNull();

    final speech = widget.speech;
    final voice =
        speech is NeuralSpeechEngine &&
            (widget.settings?.voiceMeasurements ?? false)
        ? voicePayload(voiceMeasurements(speech))
        : null;

    return reportPayload(
      kind: detail == null ? _kind : ReportKind.crash,
      note: _note.text,
      device: await deviceFacts(models: widget.models),
      board: (
        rows: vocabulary?.gridRows ?? 0,
        cols: vocabulary?.gridCols ?? 0,
        level: profile?.vocabLevel ?? 0,
        engine: speech is NeuralSpeechEngine ? 'neural' : 'platform',
      ),
      detail: detail,
      voice: voice,
    );
  }

  /// The names that must not appear in machine-written text.
  Iterable<String> get _names =>
      [widget.userName, widget.profileName].whereType<String>();

  Future<void> _send({String? detail, String? crashId}) async {
    setState(() {
      _busy = true;
      _outcome = null;
    });

    final payload = await _payload(detail: detail);

    // The last check before the network, and deliberately not the only one.
    final refusal = refusalToSend(payload['detail'] as String?, names: _names);
    if (refusal != null) {
      if (mounted) {
        _finish((sent: false, reference: null, problem: refusal));
      }
      return;
    }

    final outcome = await _sender.send(payload);
    if (!mounted) return;

    if (outcome.sent && crashId != null) await _crashes.discard(crashId);
    if (outcome.sent) _note.clear();
    await _load();

    if (!mounted) return;
    _finish(outcome);
  }

  /// Puts the result on the screen, and the screen where the result is.
  ///
  /// Send is the last thing in the list, so on a short tablet the answer to
  /// pressing it lands below the fold. Scrolled after the frame that builds it,
  /// because until then the list does not know it grew.
  void _finish(SendOutcome outcome) {
    setState(() {
      _busy = false;
      _outcome = outcome;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _WhatThisIsFor(),
          if (!_sender.configured) const _NoIntake(),
          if (_waiting.isNotEmpty) ...[
            const _Heading('Faults this device caught'),
            for (final record in _waiting)
              _CrashTile(
                record: record,
                busy: _busy,
                onSend: () => _send(detail: record.detail, crashId: record.id),
                onDiscard: () async {
                  await _crashes.discard(record.id);
                  await _load();
                },
              ),
          ],
          const _Heading('Tell us something'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ReportKind>(
              segments: [
                for (final kind in [ReportKind.bug, ReportKind.idea])
                  ButtonSegment(value: kind, label: Text(kind.title)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _note,
              maxLines: 6,
              maxLength: noteLimit,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _kind.title,
                helperText: _kind.description,
              ),
            ),
          ),
          // Under the box rather than in the helper line. A helper line is
          // small, grey, and one line tall, which is the right size for
          // "It does not do what it should" and the wrong size for the only
          // sentence here that changes what somebody types.
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              personalInformationNotice,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ),
          // The measurement switch is deliberately not here. It is on the
          // voice screen, where somebody is deciding about the voice, and
          // under Settings, which is the inventory of what the app can do.
          // A third copy on the page where a person is writing a sentence to
          // a human being asked them to make an unrelated decision mid-report
          // — and three places to change one setting is three places to
          // wonder which one is the real one.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: _busy || _note.text.trim().isEmpty
                  ? null
                  : () => _review(),
              child: const Text('Review and send'),
            ),
          ),
          if (_outcome != null) _Outcome(outcome: _outcome!),
        ],
      ),
    );
  }

  Future<void> _review() async {
    final payload = await _payload();
    if (!mounted) return;

    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _Review(payload: payload),
    );

    if (send ?? false) await _send();
  }
}

/// What the screen is for, in the one line it takes to say it.
///
/// The contents of a report used to be described here, in the abstract, before
/// a report existed. The review sheet now lists every field of the real one
/// under "What will be sent", which is the same information at the moment it
/// can actually be acted on. Saying it twice made the first telling a promise
/// and the second one the proof, and only the proof is worth keeping.
class _WhatThisIsFor extends StatelessWidget {
  const _WhatThisIsFor();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Text(
      'Tell us something is wrong or missing, and send faults this device '
      'caught. You read every report before it goes.',
      style: TextStyle(fontSize: 14, height: 1.45),
    ),
  );
}

class _NoIntake extends StatelessWidget {
  const _NoIntake();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.amber.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.amber.shade200),
    ),
    child: const Text(
      'This build has nowhere to send reports to, so nothing here can be '
      'sent. You can still read what a fault recorded.',
      style: TextStyle(fontSize: 13, height: 1.4),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

class _CrashTile extends StatelessWidget {
  const _CrashTile({
    required this.record,
    required this.busy,
    required this.onSend,
    required this.onDiscard,
  });

  final CrashRecord record;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: ExpansionTile(
      title: Text(whenItHappened(record.at)),
      subtitle: const Text('Not sent'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        _Payload(text: record.detail),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: busy ? null : onDiscard,
              child: const Text('Discard'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy ? null : onSend,
              child: const Text('Send'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// When a fault happened, in the words somebody would use out loud.
String whenItHappened(DateTime at, {DateTime? now}) {
  final since = (now ?? DateTime.now()).difference(at);
  if (since.inMinutes < 1) return 'Just now';
  if (since.inHours < 1) return '${since.inMinutes} minutes ago';
  if (since.inHours < 24) {
    return since.inHours == 1 ? 'An hour ago' : '${since.inHours} hours ago';
  }
  return since.inDays == 1 ? 'Yesterday' : '${since.inDays} days ago';
}

/// The heading over the result of pressing send.
String outcomeTitle(SendOutcome outcome) =>
    outcome.sent ? 'Report sent' : 'Not sent';

/// What the result says underneath.
///
/// The reference is the whole point of the sent case: a report nobody can
/// quote afterwards is one they have to take on trust.
String outcomeMessage(SendOutcome outcome) {
  if (!outcome.sent) return outcome.problem ?? ReportSender.couldNotReach;

  final reference = outcome.reference;
  return reference == null
      ? 'Thank you.'
      : 'Reference $reference. Quote it if you get in touch about this report.';
}

/// What pressing send did, where the person who pressed it is looking.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.outcome});

  final SendOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final sent = outcome.sent;
    final tint = sent ? Colors.green : Colors.amber;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            sent ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: tint.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  outcomeTitle(outcome),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                // Selectable so the reference can be copied into whatever the
                // caregiver writes to us in.
                SelectableText(
                  outcomeMessage(outcome),
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Payload extends StatelessWidget {
  const _Payload({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(6),
    ),
    child: SelectableText(
      text,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
    ),
  );
}

/// Everything the report carries, before it carries it anywhere.
class _Review extends StatelessWidget {
  const _Review({required this.payload});

  final Map<String, Object?> payload;

  /// The payload scrolls. The two buttons do not.
  ///
  /// They were at the end of the scroll, which put them past the bottom of the
  /// screen on anything short — a report long enough to be worth reviewing was
  /// a report whose send button a caregiver had to go looking for. Pinned, so
  /// what varies with the length of the report is how much of it is visible,
  /// never whether the decision can be made.
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.8,
    builder: (context, controller) => Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'What will be sent',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final section in reportSections(payload))
                _Section(section: section),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Send this'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One group of the report, under its heading.
class _Section extends StatelessWidget {
  const _Section({required this.section});

  final ReportSection section;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const Divider(height: 12),
        for (final line in section.lines) _Line(line: line),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.line});

  final ReportLine line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            line.label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            line.value,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        ),
      ],
    ),
  );
}
