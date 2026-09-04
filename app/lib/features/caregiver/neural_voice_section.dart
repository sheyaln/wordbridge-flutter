import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../profiles/profile_settings.dart';
import 'telemetry_switches.dart';
import '../speech/neural/bake.dart';
import '../speech/neural/bake_vocabulary.dart';
import '../speech/neural/neural_engine.dart';
import '../speech/neural/neural_voice.dart';
import '../speech/neural/voice_model.dart';
import 'voice_screen.dart';

/// The whole body of the voice screen, where there are two voices to choose
/// between.
///
/// The choice heads it, then the settings of whichever voice was chosen, then
/// the other's. Anything else puts a caregiver through a screen of dials before
/// telling them which voice those dials belong to.
///
/// The device controls are handed in by [VoiceScreen] rather than built here,
/// so the half of the screen that a build with no neural engine still shows is
/// written once.
///
/// Every number a caregiver is shown here is one somebody has to live with:
/// how much disk, how long the bake, how much of the board can be said in the
/// chosen voice yet, and how often the device voice has had to step in. None
/// of it is inferred and none of it is rounded into reassurance.
///
/// A section rather than a screen of its own, because "which voice speaks" is
/// one question and it used to be asked on two pages that did not mention each
/// other. Early access is said at the row where the voice is picked: this is
/// the experiment, and a screen that opened on it read as though the experiment
/// were the arrangement.
class NeuralVoiceSection extends StatefulWidget {
  const NeuralVoiceSection({
    super.key,
    required this.speech,
    required this.settings,
    required this.db,
    required this.vocabularyId,
    required this.deviceControls,
    required this.onChanged,
  });

  final NeuralSpeechEngine speech;
  final ProfileSettings settings;
  final WordbridgeDatabase db;
  final String vocabularyId;

  /// The other voice's controls, asked for once the choice is known.
  final DeviceVoiceControls deviceControls;

  /// Told when the voice that speaks changes, so the screen holding this
  /// redraws with it.
  final VoidCallback onChanged;

  @override
  State<NeuralVoiceSection> createState() => _NeuralVoiceSectionState();
}

class _NeuralVoiceSectionState extends State<NeuralVoiceSection> {
  ModelProgress? _progress;
  StreamSubscription<ModelProgress>? _install;

  bool _installed = false;
  int _onDisk = 0;
  int _partial = 0;

  BakeJob? _bake;
  List<String>? _words;

  String? _busy;

  @override
  void initState() {
    super.initState();
    // A download already running is the store's, so this reattaches to it and
    // draws the bar where it got to rather than offering to start again.
    if (_speech.models.isInstalling) {
      _progress = _speech.models.installProgress;
      _watchInstall();
    }
    unawaited(_refresh());
  }

  @override
  void dispose() {
    // Only stops watching. The install belongs to the store, and 305 MB is not
    // thrown away because somebody backed out of a screen.
    _install?.cancel();
    _bake?.removeListener(_onBake);
    super.dispose();
  }

  ProfileSettings get _settings => widget.settings;
  NeuralSpeechEngine get _speech => widget.speech;

  Future<void> _refresh() async {
    final installed = await _speech.models.isInstalled();
    final onDisk = await _speech.models.bytesOnDisk();
    final partial = await _speech.models.downloadedBytes();
    final words =
        _words ?? await bakeVocabulary(widget.db, widget.vocabularyId);
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _onDisk = onDisk;
      _partial = partial;
      _words = words;
    });
  }

  void _onBake() {
    if (mounted) setState(() {});
  }

  Future<void> _set(String key, Object? value) async {
    await _settings.set(key, value);
    if (mounted) setState(() {});
  }

  Future<void> _startInstall() async {
    setState(() => _progress = null);
    _watchInstall();
  }

  /// Starts the install, or attaches to the one already running.
  ///
  /// The store decides which: asking twice hands back the same work rather
  /// than starting a second download onto the same partial file.
  void _watchInstall() {
    _install?.cancel();
    _install = _speech.models.install().listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.phase == ModelPhase.installed) {
        unawaited(_afterInstall());
      } else if (p.phase == ModelPhase.failed) {
        unawaited(_refresh());
      }
    });
  }

  /// A voice that has finished downloading has nothing left to wait for.
  ///
  /// Somebody who switched the voice on before the download existed asked for
  /// this to happen; making them come back and press two more buttons is how
  /// §4.62 describes the whole of this feature.
  Future<void> _afterInstall() async {
    await _refresh();
    if (mounted && _settings.neuralVoice) await _getGoing();
  }

  Future<void> _deleteModel() async {
    final agreed = await _confirm(
      title: 'Delete the downloaded voice?',
      body:
          'Frees ${_megabytes(_onDisk)} and the board returns to the device '
          'voice. Words already synthesized are kept, so downloading again '
          'does not mean making them again.',
      action: 'Delete',
    );
    if (!agreed) return;

    await _speech.models.deleteModel();
    await _setEnabled(false);
    await _refresh();
  }

  /// Turning it on is free; it opens an index file and loads no model.
  Future<void> _setEnabled(bool on) async {
    await _set('neuralVoice', on);
    await _speech.useNeuralVoice(
      enabled: on,
      voiceId: _settings.neuralVoiceId,
      speed: _settings.speechRate,
    );
    if (mounted) setState(() => _bake = null);
    widget.onChanged();
    await _refresh();

    if (on && mounted) await _getGoing();
  }

  /// Measures this tablet, then starts filling the pack — without being asked.
  ///
  /// §4.62. Both of these were buttons on this screen, which meant a caregiver
  /// who switched the voice on and walked away got a board that fell back on
  /// every word indefinitely, with nothing on it to suggest why.
  ///
  /// The measurement goes first because the bake is what it governs: until
  /// this tablet has its own figure, the budget is the floor device's, and
  /// every word is given three times longer than it needs before the device
  /// voice takes over.
  Future<void> _getGoing() async {
    if (!_installed) return;

    if (!_settings.synthesisBudgetMeasured) await _measure();
    if (!mounted) return;

    final words = _words ?? const <String>[];
    if (!_speech.needsBaking(words)) return;
    await _startBake();
  }

  /// Changing the voice makes every clip in the cache wrong, not stale.
  ///
  /// The board keeps speaking throughout — in the device voice for anything
  /// not yet baked in the new one — which is the honest cost and is said
  /// before it is paid.
  Future<void> _chooseVoice(NeuralVoice voice) async {
    if (voice.id == _settings.neuralVoiceId) return;

    final baked = _speech.clips?.count ?? 0;
    if (baked > 0) {
      final agreed = await _confirm(
        title: 'Change to ${voice.name}?',
        body:
            'The $baked words already made are in the old voice and have to '
            'be synthesized again, about '
            '${_bakeMinutes(_words?.length ?? 0)} in the background. Until '
            'then, anything not ready speaks in the device voice.',
        action: 'Change',
      );
      if (!agreed) return;
    }

    await _set('neuralVoiceId', voice.id);
    await _speech.useNeuralVoice(
      enabled: _settings.neuralVoice,
      voiceId: voice.id,
      speed: _settings.speechRate,
    );
    await _speech.pruneOtherVoices();
    if (mounted) setState(() => _bake = null);
    widget.onChanged();
    await _refresh();

    // The new voice's pack is empty, so this is the same situation as
    // switching the voice on and gets the same answer.
    if (mounted) await _getGoing();
  }

  /// The Speed dial, let go of.
  ///
  /// Speed is not a playback rate here. Kokoro is *given* it at generation, so
  /// every clip in a pack was made at one speed and a different speed is a
  /// different pack. Moving this dial is therefore the same event as changing
  /// the voice, and it gets the same answer: said before it is paid for.
  ///
  /// It used not to be. The dial wrote `speechRate` and stopped there —
  /// nothing re-pointed the engine, so the board went on speaking out of the
  /// old pack for the rest of the session while the screen said speed "applies
  /// to both". The next launch asked for the pack at the new speed, found an
  /// empty one, and fell back to the device voice on every word; choosing a
  /// voice after that ran `pruneOtherVoices`, which deleted the only copy. An
  /// hour of synthesis thrown away by a slider, with nothing anywhere having
  /// said it would be.
  Future<void> _speedSettled() async {
    if (!_settings.neuralVoice) return;

    // Rounded into the pack name, so a thumb that moved a thousandth has not
    // changed anything and must not be made to look as though it had.
    final was = _speech.speed;
    final now = _settings.speechRate;
    if (_speech.packIdAt(now) == _speech.packIdAt(was)) return;

    final baked = _speech.clips?.count ?? 0;
    if (baked > 0) {
      final agreed = await _confirm(
        title: 'Speak at the new speed?',
        body:
            'Speed is made into each word rather than applied when it plays, '
            'so the $baked words already made are at the old speed and will '
            'not be used at the new one. Making them again takes about '
            '${_bakeMinutes(_words?.length ?? 0)} in the background, and '
            'until then anything not ready speaks in the device voice. The '
            'old ones are kept, so going back to that speed brings them back.',
        action: 'Change',
        dismiss: 'Keep the old speed',
      );
      if (!agreed) {
        // One speed, both voices — which is what the screen says. Refusing the
        // re-bake puts the dial back rather than leaving the device voice at
        // the new speed and the neural voice at the old one.
        await _set('speechRate', was);
        widget.onChanged();
        return;
      }
    }

    await _speech.useNeuralVoice(
      enabled: true,
      voiceId: _settings.neuralVoiceId,
      speed: now,
    );
    // Deliberately no `pruneOtherVoices` here, unlike a voice change. A speed
    // is a dial somebody nudges and reconsiders, and the pack it moved off is
    // the whole of what they would be reconsidering — leaving it on disk makes
    // going back instant and is the only reason the question above can promise
    // it. A voice change is the discrete decision that clears them out.
    if (mounted) setState(() => _bake = null);
    widget.onChanged();
    await _refresh();

    // Either a pack with nothing in it, or the one they came from. Both want
    // the same answer: fill whatever is missing.
    if (mounted) await _getGoing();
  }

  /// The voices, on a page of their own.
  ///
  /// A dozen radio rows above the sections that say how much is ready and how
  /// long a sentence takes pushed both off the screen. The list is read once,
  /// when a voice is chosen; the two below it are read every time somebody
  /// comes back to check on it.
  Future<void> _openVoicePicker() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _VoicePicker(
          chosen: _settings.neuralVoiceId,
          onChoose: _chooseVoice,
          onPreview: _preview,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _preview(NeuralVoice voice) async {
    setState(() => _busy = 'Making a sentence in ${voice.name}…');
    final spoke = await _speech.previewVoice(
      voice,
      VoiceScreen.previewSentence,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (!spoke) _say('That voice could not be loaded.');
  }

  Future<void> _startBake() async {
    setState(() => _busy = 'Starting…');
    final job = await _speech.bakeJob();
    final words = _words ?? const <String>[];
    if (!mounted) return;
    setState(() => _busy = null);

    if (job == null) {
      _say(
        'The voice could not be loaded, so there is nothing to make words with.',
      );
      return;
    }
    _bake?.removeListener(_onBake);
    job.addListener(_onBake);
    setState(() => _bake = job);
    unawaited(job.start(words));
  }

  Future<void> _measure() async {
    setState(() => _busy = 'Timing two sentences…');
    final budget = await _speech.measureBudget();
    if (!mounted) return;
    setState(() => _busy = null);

    if (budget == null) {
      _say('The voice could not be loaded, so nothing was measured.');
      return;
    }
    await _settings.setSynthesisBudget(budget);
    _speech.budget = budget;
    if (mounted) setState(() {});
    _say('This device: $budget.');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// [dismiss] names the other answer where "Cancel" would be wrong. A
  /// question offering Cancel reads as one that can be escaped without
  /// answering, and this one is answered either way.
  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    String dismiss = 'Cancel',
  }) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(dismiss),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return agreed ?? false;
  }

  /// What the neural row says about itself, including whatever is in its way.
  ///
  /// A row that cannot be picked and does not say why reads as a feature that
  /// was withdrawn. And a profile restored onto a tablet with no model carries
  /// the setting without anything behind it, so that row has to admit that the
  /// device voice is doing the talking.
  String _neuralLine({required bool on}) {
    final name = neuralVoiceById(_settings.neuralVoiceId).name;
    if (!_speech.canPlay) {
      return '$name. This device cannot play one, so the board goes on '
          'speaking with the device voice.';
    }
    if (!_installed) {
      return on
          ? '$name. Not downloaded, so the board is speaking with the device '
                'voice until it is.'
          : '$name. Not downloaded yet — '
                '${_megabytes(_speech.models.published.downloadBytes)} below.';
    }
    return '$name. Closer to a human speaker than text to speech. Words made '
        'in advance play instantly; anything else is synthesized as it is '
        'chosen.';
  }

  @override
  Widget build(BuildContext context) {
    final on = _settings.neuralVoice;
    final words = _words?.length ?? 0;
    final baked = _speech.clips?.count ?? 0;

    // Nothing to pick until there is a second voice on the tablet, and nothing
    // to pick at all where a buffer cannot be played back. The row stays on
    // screen either way and says which of the two it is.
    final chooseable = _installed && _speech.canPlay;

    // What the neural voice has to show for itself, as against what a profile
    // merely asked for.
    final speaking = on && _installed;

    final neuralBlock = <Widget>[
      const VoiceHeader('Neural voice'),
      if (speaking) ...[
        ListTile(
          leading: const Icon(Icons.graphic_eq_outlined),
          title: const Text('Which voice'),
          subtitle: Text(
            '${neuralVoiceById(_settings.neuralVoiceId).name} · '
            '${neuralVoiceById(_settings.neuralVoiceId).accent} · '
            '${kokoroVoices.length} to choose from',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openVoicePicker,
        ),
        const VoiceNote(
          'Speed is set with the device voice below and applies to both — but '
          'this voice has it made into each word, so changing it means making '
          'them all again. Pitch, volume and tone do not reach this one.',
        ),

        const VoiceHeader('Words made in advance'),
        _BakeTile(
          baked: baked,
          words: words,
          job: _bake,
          busy: _busy,
          onStart: _startBake,
          onPause: () => _bake?.pause(),
        ),

        const VoiceHeader('Times the device voice was used instead'),
        _FallbackTile(count: _speech.fallbackCount, recent: _speech.fallbacks),

        const VoiceHeader('How long synthesis may take'),
        ListTile(
          title: Text('${_settings.synthesisBudget}'),
          subtitle: Text(
            _settings.synthesisBudgetMeasured
                ? 'Measured on this device. Anything slower than this falls '
                      'back to the device voice.'
                : 'A safe default for the slowest supported device. Measure '
                      'for this device\'s own figure, usually lower.',
          ),
          isThreeLine: true,
          trailing: FilledButton.tonal(
            onPressed: _busy == null ? _measure : null,
            child: const Text('Measure'),
          ),
        ),

        const VoiceHeader('The download'),
      ],
      _ModelTile(
        published: _speech.models.published,
        installed: _installed,
        onDisk: _onDisk,
        partial: _partial,
        progress: _progress,
        onInstall: _startInstall,
        onDelete: _deleteModel,
      ),

      // The same switch that appears under Reports, not a second copy of it
      // (§4.59). Disabled while the device voice is speaking, because there
      // are no neural timings to send.
      if (chooseable)
        VoiceMeasurementSwitch(
          settings: _settings,
          available: on,
          onChanged: () => setState(() {}),
        ),
    ];

    final deviceBlock = <Widget>[
      const VoiceHeader('Device voice'),
      if (on)
        const VoiceNote(
          'Speaks any word the neural voice has not made yet, and anything it '
          'cannot make in time.',
        ),
      ...widget.deviceControls(neuralOn: on, onSpeedSettled: _speedSettled),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The choice, at the top, and it is a choice rather than a switch.
        // "Use the neural voice", off, names one of the two voices and leaves
        // the other unnamed — and the unnamed one is the one that is speaking.
        // It heads the screen because everything under it belongs to one voice
        // or the other, and below the dials it let a caregiver configure a
        // voice for two screens before finding out which one was talking.
        const VoiceHeader('Which voice speaks'),
        RadioGroup<bool>(
          groupValue: on,
          onChanged: (chosen) {
            if (chosen != null && chosen != on) {
              unawaited(_setEnabled(chosen));
            }
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                value: false,
                title: const Text('Device voice'),
                subtitle: Text(
                  deviceVoiceLine(_settings.voiceName, _settings.voiceLocale),
                ),
              ),
              RadioListTile<bool>(
                value: true,
                // Named even where it cannot be picked, so the screen never
                // carries a voice with no name on it. What stands in the way
                // rides the row rather than a tile somewhere under it.
                enabled: chooseable,
                title: const Text('Neural voice'),
                subtitle: Text(_neuralLine(on: on)),
                isThreeLine: true,
              ),
            ],
          ),
        ),
        const _PreAlpha(),

        // The chosen voice's own settings first. Somebody has just been asked
        // which voice speaks, and the next thing under the answer has to be
        // the voice they answered with.
        ...(on
            ? [...neuralBlock, ...deviceBlock]
            : [...deviceBlock, ...neuralBlock]),

        if (_busy != null)
          ListTile(
            leading: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text(_busy!),
          ),
      ],
    );
  }
}

/// Choosing which neural voice, and hearing one before choosing it.
///
/// Its own page so the sections that report on the voice already chosen are not
/// pushed below a list nobody needs after the first visit.
class _VoicePicker extends StatefulWidget {
  const _VoicePicker({
    required this.chosen,
    required this.onChoose,
    required this.onPreview,
  });

  final String chosen;
  final Future<void> Function(NeuralVoice) onChoose;
  final Future<void> Function(NeuralVoice) onPreview;

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  late String _chosen = widget.chosen;
  NeuralVoice? _playing;

  Future<void> _hear(NeuralVoice voice) async {
    setState(() => _playing = voice);
    await widget.onPreview(voice);
    if (mounted) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neural voice')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Select the speaker to hear a voice. It takes a second or two '
              'to synthesize.',
            ),
          ),
          RadioGroup<String>(
            groupValue: _chosen,
            onChanged: (id) async {
              if (id == null) return;
              setState(() => _chosen = id);
              await widget.onChoose(neuralVoiceById(id));
              if (mounted) setState(() {});
            },
            child: Column(
              children: [
                for (final voice in kokoroVoices)
                  RadioListTile<String>(
                    value: voice.id,
                    title: Text(voice.name),
                    subtitle: Text(voice.accent),
                    secondary: IconButton(
                      icon: _playing == voice
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volume_up_rounded),
                      tooltip: 'Hear ${voice.name}',
                      onPressed: _playing == null ? () => _hear(voice) : null,
                    ),
                  ),
              ],
            ),
          ),
          const VoiceNote(
            'Rate applies to these voices. Pitch does not: it affects the '
            'device voice only.',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Says what this is, against the row where it is picked.
///
/// Not a disclaimer in small print at the bottom: a caregiver is deciding how
/// somebody else will sound, and the person it is for may not be able to say
/// it came out wrong. Not a banner over the whole screen either, now that the
/// choice heads it — somebody who has settled on the device voice would read
/// that as the arrangement being the experiment.
class _PreAlpha extends StatelessWidget {
  const _PreAlpha();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: colors.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Early access. It may not sound correct',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colors.onTertiaryContainer),
                ),
                const SizedBox(height: 6),
                Text(
                  'Words may be mispronounced, and sentences may lack '
                  'appropriate intonation.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.published,
    required this.installed,
    required this.onDisk,
    required this.partial,
    required this.progress,
    required this.onInstall,
    required this.onDelete,
  });

  final PublishedModel published;
  final bool installed;
  final int onDisk;
  final int partial;
  final ModelProgress? progress;
  final VoidCallback onInstall;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final running = progress;

    if (installed) {
      return ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: const Text('Downloaded'),
        subtitle: Text('${_megabytes(onDisk)} on this device.'),
        trailing: TextButton(onPressed: onDelete, child: const Text('Delete')),
      );
    }

    if (running != null &&
        running.phase != ModelPhase.failed &&
        running.phase != ModelPhase.installed) {
      final share = running.totalBytes == 0
          ? null
          : running.bytes / running.totalBytes;
      return ListTile(
        title: Text(switch (running.phase) {
          ModelPhase.downloading => 'Downloading',
          ModelPhase.verifying => 'Verifying download',
          ModelPhase.unpacking => 'Unpacking',
          _ => 'Working',
        }),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(value: share),
            const SizedBox(height: 6),
            Text(
              '${_megabytes(running.bytes)} of '
              '${_megabytes(running.totalBytes)}'
              '${running.phase == ModelPhase.downloading ? '. Continues if you leave this screen' : ''}',
            ),
          ],
        ),
        isThreeLine: true,
      );
    }

    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(
        partial > 0
            ? 'Resume. ${_megabytes(partial)} already downloaded'
            : 'Download the voice',
      ),
      subtitle: Text(
        running?.detail ??
            '${_megabytes(published.downloadBytes)} to download, '
                '${_megabytes(published.installedBytes)} once unpacked. Best '
                'over wifi.',
      ),
      isThreeLine: true,
      trailing: FilledButton(
        onPressed: onInstall,
        child: Text(partial > 0 ? 'Resume' : 'Download'),
      ),
    );
  }
}

class _BakeTile extends StatelessWidget {
  const _BakeTile({
    required this.baked,
    required this.words,
    required this.job,
    required this.busy,
    required this.onStart,
    required this.onPause,
  });

  final int baked;
  final int words;
  final BakeJob? job;
  final String? busy;
  final VoidCallback onStart;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final running = job;
    final done = running?.done ?? baked;
    final total = running?.total ?? words;
    final share = total == 0 ? 1.0 : done / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text('$done of $total words synthesized'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              LinearProgressIndicator(value: share),
              const SizedBox(height: 6),
              Text(switch (running?.state) {
                BakeState.running =>
                  'Synthesizing now. The board still works, pausing for each '
                      'word spoken.',
                BakeState.waiting =>
                  'Paused while the board is in use. Carries on a few seconds '
                      'after the last word.',
                BakeState.paused => 'Stopped. Nothing made so far is lost.',
                BakeState.done => 'Every word is ready.',
                BakeState.failed =>
                  running?.failure ??
                      'Something went wrong. Nothing made so far is lost.',
                _ =>
                  done >= total
                      ? 'Every word is ready.'
                      : 'About ${_bakeMinutes(total - done)} remaining. You '
                            'can stop and resume at any time.',
              }),
            ],
          ),
          isThreeLine: true,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (running?.isRunning ?? false)
                OutlinedButton(
                  onPressed: onPause,
                  child: const Text('Stop for now'),
                )
              else if (done < total)
                FilledButton(
                  onPressed: busy == null ? onStart : null,
                  child: Text(done == 0 ? 'Make the words' : 'Continue'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FallbackTile extends StatelessWidget {
  const _FallbackTile({required this.count, required this.recent});

  final int count;
  final List<Fallback> recent;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return const ListTile(
        title: Text('The neural voice has not timed out yet'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text('$count since the app started'),
          subtitle: const Text(
            'If this happens often, finish synthesizing the words rather than '
            'allowing a longer wait.',
          ),
          isThreeLine: true,
        ),
        for (final fallback in recent.reversed.take(5))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '"${fallback.text}": ${fallback.reason}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

String _megabytes(int bytes) => '${(bytes / 1000000).round()} MB';

/// At the measured 1.3 s a word on the floor device.
///
/// Stated in minutes rather than as a bar filling, because the question a
/// caregiver is actually asking is whether to start it now or tonight.
String _bakeMinutes(int words) {
  final minutes = (words * 1.3 / 60).round();
  if (minutes < 1) return 'under a minute';
  if (minutes == 1) return 'a minute';
  return '$minutes minutes';
}
