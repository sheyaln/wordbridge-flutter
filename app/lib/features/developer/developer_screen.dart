import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../speech/neural/neural_engine.dart';
import '../speech/speech_engine.dart';
import '../symbols/symbol_registry.dart';
import '../usage/logger.dart';
import '../usage/usage_queries.dart';
import 'developer_mode.dart';
import 'motor_plan_screen.dart';

/// The switches, and the four things worth reading off a running device.
///
/// Reached only from the settings list, and only while developer mode is on.
/// Everything on it is either a switch that changes what the board draws over
/// itself, or a number that is already being kept somewhere and has never had
/// a screen — the dropped log writes above all, which the logger has counted
/// since it was written and nothing has ever shown.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    required this.developer,
    this.logger,
    this.speech,
    this.registry,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final DeveloperMode developer;
  final UsageLogger? logger;
  final SpeechEngine? speech;
  final SymbolRegistry? registry;

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  int? _recorded;

  @override
  void initState() {
    super.initState();
    _countRecorded();
  }

  Future<void> _countRecorded() async {
    try {
      final recorded = await UsageQueries(widget.db)
          .recordedFor(widget.profileId);
      if (mounted) setState(() => _recorded = recorded);
    } catch (_) {
      // A count that will not come back leaves the row saying so, which is
      // more use than a screen that will not open.
    }
  }

  Future<void> _set(String key, bool value) async {
    await widget.developer.set(key, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final developer = widget.developer;

    return Scaffold(
      appBar: AppBar(title: const Text('Developer')),
      body: ListView(
        children: [
          const _Heading('What the board draws over itself'),
          SwitchListTile(
            value: developer.coordinates,
            title: const Text('Row and column'),
            subtitle: const Text(
              'Counted from zero, as the database counts them.',
            ),
            onChanged: (v) => _set('coordinates', v),
          ),
          SwitchListTile(
            value: developer.cellState,
            title: const Text('Why a location is blank'),
            subtitle: const Text(
              'Free, switched off, above this level, or an ending that does '
              'not apply yet.',
            ),
            isThreeLine: true,
            onChanged: (v) => _set('cellState', v),
          ),
          SwitchListTile(
            value: developer.pictureSource,
            title: const Text('Where each picture came from'),
            subtitle: const Text(
              'Whether somebody chose it for this button, took it off, or it '
              'was matched from the word.',
            ),
            isThreeLine: true,
            onChanged: (v) => _set('pictureSource', v),
          ),
          SwitchListTile(
            value: developer.holdToInspect,
            title: const Text('Hold a location to open it'),
            subtitle: Text(
              'Holding a location for ${DeveloperMode.hold.inMilliseconds} ms '
              'says what is behind it and offers the editor, the picture '
              'picker and both voices. Nothing is added to the tap path: a '
              'press still speaks exactly as fast.',
            ),
            isThreeLine: true,
            onChanged: (v) => _set('holdToInspect', v),
          ),

          const Divider(height: 32),
          const _Heading('The motor plan'),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Check nothing has moved'),
            subtitle: const Text(
              'Records where every word is, and compares a later run against '
              'it. The one invariant this app has, checkable on the device it '
              'has to hold on.',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MotorPlanScreen(
                  db: widget.db,
                  vocabularyId: widget.vocabularyId,
                ),
              ),
            ),
          ),

          const Divider(height: 32),
          const _Heading('The usage log'),
          ..._log(),

          if (widget.speech case final speech?) ...[
            const Divider(height: 32),
            const _Heading('Speech'),
            ..._speechState(speech),
          ],

          if (widget.registry case final registry?) ...[
            const Divider(height: 32),
            const _Heading('Picture sets'),
            for (final set in registry.sets)
              _Fact(set.slug, registry.isSetEnabled(set.slug) ? 'on' : 'off'),
          ],

          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('Turn developer mode off'),
            subtitle: const Text(
              'Takes the overlays and the hold off the board. The switches '
              'above keep their values for the next time.',
            ),
            isThreeLine: true,
            onTap: () async {
              await developer.setEnabled(false);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  /// What the logger is holding, including the part nothing else reports.
  ///
  /// `droppedEvents` has been counted since the logger was written and has
  /// never had a screen, so a device quietly failing every write looks
  /// identical to one nobody is talking on.
  List<Widget> _log() {
    final logger = widget.logger;
    if (logger == null) return const [_Fact('logger', 'not supplied')];

    return [
      _Fact('recording', logger.enabled ? 'on' : 'off'),
      _Fact('waiting to be written', '${logger.pending}'),
      _Fact('dropped', '${logger.droppedEvents}'),
      _Fact(
        'recorded for this profile',
        _recorded == null ? 'counting' : '$_recorded',
      ),
    ];
  }

  /// Which rung of the ladder this device is actually standing on.
  ///
  /// The caregiver screen says how the voice is doing, in the terms a
  /// caregiver decides in. This says what is loaded, what is cached and what
  /// the budget is, which is what somebody chasing a fallback needs and is not
  /// a thing to put in front of a parent.
  List<Widget> _speechState(SpeechEngine speech) {
    if (speech is! NeuralSpeechEngine) {
      return [_Fact('engine', speech.runtimeType.toString())];
    }

    final clips = speech.clips;
    return [
      _Fact('engine', '${speech.runtimeType}'),
      _Fact('falls back to', '${speech.platform.runtimeType}'),
      _Fact('neural voice', speech.isOn ? 'on' : 'off'),
      _Fact('can play a clip', speech.canPlay ? 'yes' : 'no'),
      _Fact('voice', speech.voice.name),
      _Fact('model in memory', speech.isModelLoaded ? 'yes' : 'no'),
      _Fact('clip pack', clips?.packId ?? 'none open'),
      _Fact('clips cached', '${clips?.count ?? 0}'),
      _Fact('budget', '${speech.budget}'),
      _Fact('fell back this session', '${speech.fallbackCount}'),
      for (final fallback in speech.fallbacks.reversed.take(5))
        _Fact('  "${fallback.text}"', fallback.reason),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// One reading, in the shape somebody scans down rather than reads.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
