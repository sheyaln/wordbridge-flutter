import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../profiles/profile_settings.dart';
import '../speech/neural/bake.dart';
import '../speech/neural/bake_vocabulary.dart';
import '../speech/neural/neural_engine.dart';
import '../speech/neural/neural_voice.dart';
import '../speech/neural/voice_model.dart';
import 'voice_screen.dart';

/// The neural voice, and everything it costs, below the device's own voice.
///
/// Every number a caregiver is shown here is one somebody has to live with:
/// how much disk, how long the bake, how much of the board can be said in the
/// chosen voice yet, and how often the device voice has had to step in. None
/// of it is inferred and none of it is rounded into reassurance.
///
/// A section rather than a screen of its own, because "which voice speaks" is
/// one question and it used to be asked on two pages that did not mention each
/// other. It sits **below** the device voice under [VoiceScreen], and is
/// labelled pre-alpha where it sits: this is the experiment, and a screen that
/// opened on it read as though the experiment were the arrangement.
class NeuralVoiceSection extends StatefulWidget {
  const NeuralVoiceSection({
    super.key,
    required this.speech,
    required this.settings,
    required this.db,
    required this.vocabularyId,
    required this.onChanged,
  });

  final NeuralSpeechEngine speech;
  final ProfileSettings settings;
  final WordbridgeDatabase db;
  final String vocabularyId;

  /// Told when the voice that speaks changes, so the device half below can say
  /// whether it is the voice or the fallback.
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
    unawaited(_refresh());
  }

  @override
  void dispose() {
    // The install keeps running: 305 MB is not something to throw away because
    // somebody backed out of a screen. It is the store's, not this widget's.
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
    _install?.cancel();
    _install = _speech.models.install().listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.phase == ModelPhase.installed || p.phase == ModelPhase.failed) {
        unawaited(_refresh());
      }
    });
  }

  Future<void> _deleteModel() async {
    final agreed = await _confirm(
      title: 'Delete the downloaded voice?',
      body:
          'This frees ${_megabytes(_onDisk)} and the board returns to the '
          'device voice. Words already synthesised are kept, so downloading '
          'again will not mean synthesising them again.',
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
            'The $baked words already made are in the old voice, so they have '
            'to be synthesised again, about '
            '${_bakeMinutes(_words?.length ?? 0)} in the background. Until '
            'then, words that are not ready speak in the device voice.',
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
    _say('This tablet: $budget.');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
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

  @override
  Widget build(BuildContext context) {
    final on = _settings.neuralVoice;
    final words = _words?.length ?? 0;
    final baked = _speech.clips?.count ?? 0;

    // Nothing to choose between until there is a second voice on the tablet,
    // and nothing to choose at all where a buffer cannot be played back.
    final chooseable = _installed && _speech.canPlay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VoiceHeader('Neural voice, early access'),
        const _PreAlpha(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'A neural voice runs on this tablet. It sounds closer to a human '
            'speaker than text to speech, and it does not sound like every '
            'other AAC user.\n\n'
            'One download and no account. It runs entirely on the tablet, so '
            'it works the same with no signal.',
          ),
        ),

        if (!_speech.canPlay)
          const ListTile(
            leading: Icon(Icons.error_outline),
            title: Text('This tablet cannot play a neural voice'),
            subtitle: Text('The board continues to use text to speech.'),
          ),

        // The choice, and it is a choice rather than a switch. "Use the neural
        // voice", off, names one of the two voices and leaves the other
        // unnamed — and the unnamed one is the one that is speaking.
        if (chooseable) ...[
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
                    _settings.voiceName == null
                        ? 'Text to speech, configured above. Used unless a '
                              'neural voice is selected.'
                        : '${_settings.voiceName}, configured above. Used '
                              'unless a neural voice is selected.',
                  ),
                  isThreeLine: true,
                ),
                RadioListTile<bool>(
                  value: true,
                  title: const Text('Neural voice, early access'),
                  subtitle: Text(
                    '${neuralVoiceById(_settings.neuralVoiceId).name}. Words '
                    'synthesised in advance play instantly. Anything else is '
                    'synthesised on selection.',
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
          ),
        ],

        const VoiceHeader('Downloading the neural voice'),
        _ModelTile(
          published: _speech.models.published,
          installed: _installed,
          onDisk: _onDisk,
          partial: _partial,
          progress: _progress,
          onInstall: _startInstall,
          onDelete: _deleteModel,
        ),

        if (_installed && on) ...[
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
          _FallbackTile(
            count: _speech.fallbackCount,
            recent: _speech.fallbacks,
          ),

          const VoiceHeader('How long synthesis may take'),
          ListTile(
            title: Text('${_settings.synthesisBudget}'),
            subtitle: Text(
              _settings.synthesisBudgetMeasured
                  ? 'Measured on this tablet. Anything not synthesised in '
                        'advance is synthesised on selection, falling back to '
                        'the device voice only if it exceeds this.'
                  : 'A safe default for the slowest supported tablet. Measure '
                        'to get this tablet\'s own figure, usually lower.',
            ),
            isThreeLine: true,
            trailing: FilledButton.tonal(
              onPressed: _busy == null ? _measure : null,
              child: const Text('Measure'),
            ),
          ),
        ],

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
              'Select the speaker to hear a voice. It takes a second or two, '
              'as the sentence is synthesised while you listen.',
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
            'Rate applies to these voices. Pitch does not, as they offer no '
            'pitch control, so it affects the device voice only.',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Says what this is before anything on the screen is touched.
///
/// Not a disclaimer in small print at the bottom. A caregiver is deciding how
/// somebody else will sound, and the person it is for may not be able to say
/// it came out wrong — so what is uncertain about it goes above the choice,
/// not below it.
class _PreAlpha extends StatelessWidget {
  const _PreAlpha();

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colours.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: colours.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Early access. It may not sound correct',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colours.onTertiaryContainer),
                ),
                const SizedBox(height: 6),
                Text(
                  'Words can be mispronounced, and the question mark key does '
                  'not give this voice a rising intonation. Turning it off '
                  'restores text to speech exactly as it was, immediately, '
                  'with nothing to undo.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colours.onTertiaryContainer),
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
        subtitle: Text('${_megabytes(onDisk)} on this tablet.'),
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
              '${running.phase == ModelPhase.downloading ? '. Safe to close the app' : ''}',
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
                'over wifi. You can delete it at any time.',
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
          title: Text('$done of $total words synthesised'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              LinearProgressIndicator(value: share),
              const SizedBox(height: 6),
              Text(switch (running?.state) {
                BakeState.running =>
                  'Synthesising now. The board still works: this pauses for '
                      'each word spoken and resumes immediately after.',
                BakeState.waiting =>
                  'Paused while the board is in use. It carries on a few '
                      'seconds after the last word.',
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
                  child: Text(done == 0 ? 'Make the words' : 'Carry on'),
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
        title: Text('None since the app started'),
        subtitle: Text('Everything so far came out in the chosen voice.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text('$count since the app started'),
          subtitle: const Text(
            'If this happens often, finish synthesising the words rather than '
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
