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

/// Switching the downloaded voice on, and everything that costs.
///
/// Every number a caregiver is shown here is one somebody has to live with:
/// how much disk, how long the bake, how much of the board can be said in the
/// chosen voice yet, and how often the platform voice has had to step in. None
/// of it is inferred and none of it is rounded into reassurance.
class NeuralVoiceScreen extends StatefulWidget {
  const NeuralVoiceScreen({
    super.key,
    required this.speech,
    required this.settings,
    required this.db,
    required this.vocabularyId,
  });

  final NeuralSpeechEngine speech;
  final ProfileSettings settings;
  final WordbridgeDatabase db;
  final String vocabularyId;

  static Future<void> show(
    BuildContext context, {
    required NeuralSpeechEngine speech,
    required ProfileSettings settings,
    required WordbridgeDatabase db,
    required String vocabularyId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NeuralVoiceScreen(
        speech: speech,
        settings: settings,
        db: db,
        vocabularyId: vocabularyId,
      ),
    ),
  );

  @override
  State<NeuralVoiceScreen> createState() => _NeuralVoiceScreenState();
}

class _NeuralVoiceScreenState extends State<NeuralVoiceScreen> {
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
    final words = _words ?? await bakeVocabulary(widget.db, widget.vocabularyId);
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
          'This gives back ${_megabytes(_onDisk)} and the board goes back to '
          'the device\'s own voice. The words already baked are kept, so '
          'downloading it again does not mean baking them again.',
      action: 'Delete',
    );
    if (!agreed) return;

    await _speech.models.deleteModel();
    await _set('neuralVoice', false);
    await _speech.useNeuralVoice(enabled: false);
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
    await _refresh();
  }

  /// Changing the voice makes every clip in the cache wrong, not stale.
  ///
  /// The board keeps speaking throughout — in the platform voice for anything
  /// not yet baked in the new one — which is the honest cost and is said
  /// before it is paid.
  Future<void> _chooseVoice(NeuralVoice voice) async {
    if (voice.id == _settings.neuralVoiceId) return;

    final baked = _speech.clips?.count ?? 0;
    if (baked > 0) {
      final agreed = await _confirm(
        title: 'Change the voice to ${voice.name}?',
        body:
            'The $baked words already baked belong to the old voice, so they '
            'have to be made again — about ${_bakeMinutes(_words?.length ?? 0)} '
            'in the background. Until that finishes, words that have not been '
            'made yet speak in the device\'s own voice.',
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
    await _refresh();
  }

  Future<void> _preview(NeuralVoice voice) async {
    setState(() => _busy = 'Making a sentence in ${voice.name}…');
    final spoke = await _speech.previewVoice(
      voice,
      VoiceScreen.previewSentence,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (!spoke) _say('The voice could not be loaded, so there is nothing to hear.');
  }

  Future<void> _startBake() async {
    setState(() => _busy = 'Starting…');
    final job = await _speech.bakeJob();
    final words = _words ?? const <String>[];
    if (!mounted) return;
    setState(() => _busy = null);

    if (job == null) {
      _say('The voice could not be loaded, so there is nothing to bake with.');
      return;
    }
    _bake?.removeListener(_onBake);
    job.addListener(_onBake);
    setState(() => _bake = job);
    unawaited(job.start(words));
  }

  Future<void> _measure() async {
    setState(() => _busy = 'Timing two sentences on this tablet…');
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

    return Scaffold(
      appBar: AppBar(title: const Text('A voice of their own')),
      body: ListView(
        children: [
          const _PreAlpha(),
          const _Header('What this is'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'A voice that runs on this tablet and never leaves it. It sounds '
              'less like a synthesiser than the device\'s own voice, and it '
              'does not sound like every other AAC user\'s — which is the '
              'thing people who use these devices ask for by name.\n\n'
              'It is one download and then nothing: no account, no connection, '
              'nothing sent anywhere. The tablet works exactly the same in a '
              'car, a playground, and a hospital corridor with no signal.',
            ),
          ),

          if (!_speech.canPlay)
            const ListTile(
              leading: Icon(Icons.error_outline),
              title: Text('This device cannot play a made voice'),
              subtitle: Text(
                'The board keeps the device\'s own voice, which is what it '
                'has always used.',
              ),
            ),

          const _Header('The download'),
          _ModelTile(
            published: _speech.models.published,
            installed: _installed,
            onDisk: _onDisk,
            partial: _partial,
            progress: _progress,
            onInstall: _startInstall,
            onDelete: _deleteModel,
          ),

          if (_installed) ...[
            const Divider(height: 32),
            SwitchListTile(
              value: on,
              title: const Text('Speak with the downloaded voice'),
              subtitle: const Text(
                'Pre-alpha — it may not sound correct. Off, the board speaks '
                'exactly as it does today. On, it uses the voice chosen below '
                'for every word that has been made, and the device\'s own '
                'voice for the rest.',
              ),
              isThreeLine: true,
              onChanged: _speech.canPlay ? _setEnabled : null,
            ),
          ],

          if (_installed && on) ...[
            const _Header('The voice'),
            RadioGroup<String>(
              groupValue: _settings.neuralVoiceId,
              onChanged: (id) {
                if (id != null) unawaited(_chooseVoice(neuralVoiceById(id)));
              },
              child: Column(
                children: [
                  for (final voice in kokoroVoices)
                    RadioListTile<String>(
                      value: voice.id,
                      title: Text(voice.name),
                      subtitle: Text(voice.accent),
                      secondary: IconButton(
                        icon: const Icon(Icons.volume_up_rounded),
                        tooltip: 'Hear ${voice.name}',
                        onPressed: _busy == null ? () => _preview(voice) : null,
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Hearing one takes a couple of seconds — it is being made from '
                'scratch. That is the wait the board exists to avoid, which is '
                'why the words are made in advance instead.\n\n'
                'Two controls do less in this voice than they do in the '
                'device\'s own, and both are measured rather than assumed. '
                'The pitch dial does nothing — this voice has no pitch '
                'control at all, so it applies to the device\'s voice only. '
                'And the "?" key does not make a sentence sound like a '
                'question: it still changes what is written on the bar, and '
                'the device\'s own voice still reads it as a question, but '
                'this voice does not. The speed dial works in both.',
              ),
            ),

            _Header('How much of the board is ready'),
            _BakeTile(
              baked: baked,
              words: words,
              job: _bake,
              busy: _busy,
              onStart: _startBake,
              onPause: () => _bake?.pause(),
            ),

            const _Header('When the device\'s own voice steps in'),
            _FallbackTile(
              count: _speech.fallbackCount,
              recent: _speech.fallbacks,
            ),

            const _Header('How long a sentence may take'),
            ListTile(
              title: Text('${_settings.synthesisBudget}'),
              subtitle: Text(
                _settings.synthesisBudgetMeasured
                    ? 'Measured on this tablet. Pressing speak on a sentence '
                          'that is not yet made waits up to this long for the '
                          'chosen voice, then uses the device\'s own.'
                    : 'The default, which is set for the slowest tablet this '
                          'app supports. Measuring gives this one its own '
                          'number, which on a newer tablet is a good deal '
                          'shorter.',
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
/// it came out wrong — so what is uncertain about it goes above the switch,
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
                  'Pre-alpha — it may not sound correct',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colours.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Words can come out mispronounced, and the "?" key does not '
                  'make this voice sound like it is asking a question. Turning '
                  'it off puts the device\'s own voice back exactly as it was, '
                  'immediately, with nothing to undo.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colours.onTertiaryContainer,
                  ),
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
        subtitle: Text('Using ${_megabytes(onDisk)} on this tablet.'),
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
          ModelPhase.verifying => 'Checking what arrived',
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
              '${running.phase == ModelPhase.downloading ? ' — closing the app does not lose this' : ''}',
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
            ? 'Resume the download — ${_megabytes(partial)} already here'
            : 'Download the voice',
      ),
      subtitle: Text(
        running?.detail ??
            '${_megabytes(published.downloadBytes)} to download, and '
                '${_megabytes(published.installedBytes)} on the tablet '
                'once it is unpacked. It can be deleted again at any time. '
                'Best done on wi-fi and while the tablet is not needed.',
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
          title: Text('$done of $total words ready'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              LinearProgressIndicator(value: share),
              const SizedBox(height: 6),
              Text(switch (running?.state) {
                BakeState.running => 'Making them now. The board works '
                    'throughout — this stops whenever anybody speaks.',
                BakeState.waiting =>
                  'Paused while the board is in use. It picks up again a few '
                      'seconds after the last word.',
                BakeState.paused => 'Stopped. Nothing already made is lost.',
                BakeState.done => 'Every word on this board is ready.',
                BakeState.failed =>
                  running?.failure ??
                      'Something went wrong. Nothing already made is lost.',
                _ =>
                  done >= total
                      ? 'Every word on this board is ready.'
                      : 'About ${_bakeMinutes(total - done)} left. It can be '
                            'stopped and picked up again at any time, and '
                            'nothing already made is lost.',
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
        title: Text('It has not had to, since the app started'),
        subtitle: Text(
          'Everything said so far came out in the chosen voice.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text('$count times since the app started'),
          subtitle: const Text(
            'Each of these came out in the device\'s own voice instead. If it '
            'is happening often, the answer is to finish making the words — '
            'not to allow a longer wait.',
          ),
          isThreeLine: true,
        ),
        for (final fallback in recent.reversed.take(5))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '"${fallback.text}" — ${fallback.reason}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
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
