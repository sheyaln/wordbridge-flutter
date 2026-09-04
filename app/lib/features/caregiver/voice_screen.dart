import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../profiles/profile_settings.dart';
import '../speech/neural/neural_engine.dart';
import '../speech/speech_engine.dart';
import '../speech/tone.dart';
import '../speech/voice_setup.dart';
import 'neural_voice_section.dart';

/// Whether the neural half of the voice screen has everything it needs.
///
/// A build without the engine, or a caller that did not pass the board the
/// bake would read its words from, gets the device's own voice and nothing
/// else — which is all such a build has anyway.
bool showsNeuralVoice(
  SpeechEngine speech, {
  WordbridgeDatabase? db,
  String? vocabularyId,
}) => speech is NeuralSpeechEngine && db != null && vocabularyId != null;

/// The engine the device-voice controls are previewed through.
///
/// The platform engine directly, never the neural one wrapping it. A caregiver
/// dragging the pitch dial with the neural voice on would otherwise hear a
/// synthesized sentence that pitch does nothing to, and conclude the dial is
/// broken. It is not — it belongs to the other voice.
SpeechEngine deviceVoiceEngine(SpeechEngine speech) =>
    speech is NeuralSpeechEngine ? speech.platform : speech;

/// What the device-voice row says, so the list does not have to be opened to
/// find out which voice is set.
String deviceVoiceLine(String? name, String? locale) {
  if (name == null) return 'Whatever this device uses';
  return locale == null ? name : '$name · $locale';
}

/// The device voice's controls, worded for whichever voice is speaking.
///
/// A builder rather than a list, because half of what these say is which of the
/// two voices hears them, and [NeuralVoiceSection] is what knows.
typedef DeviceVoiceControls = List<Widget> Function({required bool neuralOn});

/// How this profile sounds — both voices, on one screen.
///
/// One question is being answered here: what does this person sound like. It
/// used to be two screens, neither of which said the other existed, and the
/// device voice was filed under the one you reached by turning the neural
/// voice off — as though it were the alternative rather than what the neural
/// voice falls back to for every word not yet made (§4.5). Configuring it is
/// never irrelevant, so it is never hidden.
///
/// The choice between the two voices heads the screen and the settings for
/// whichever one was chosen come first under it. It used to sit two screens of
/// dials down, so a caregiver configured a voice at length before finding out
/// which one was doing the talking.
///
/// Every control previews itself the moment it moves. A caregiver setting a
/// voice for someone else cannot judge it from a number, and the person it is
/// for may not be able to tell them it is wrong.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.speech,
    required this.settings,
    this.db,
    this.vocabularyId,
    this.locale = 'en',
  });

  final SpeechEngine speech;
  final ProfileSettings settings;

  /// Where the words the neural voice would make in advance are read from.
  ///
  /// Without them the screen is the device's own voice and nothing else, which
  /// is what a build with no neural engine has anyway.
  final WordbridgeDatabase? db;
  final String? vocabularyId;

  final String locale;

  static Future<void> show(
    BuildContext context, {
    required SpeechEngine speech,
    required ProfileSettings settings,
    WordbridgeDatabase? db,
    String? vocabularyId,
    String locale = 'en',
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VoiceScreen(
        speech: speech,
        settings: settings,
        db: db,
        vocabularyId: vocabularyId,
        locale: locale,
      ),
    ),
  );

  /// What the preview says.
  ///
  /// A whole sentence rather than a word, because rate and tone are properties
  /// of a sentence and cannot be heard in one syllable. A greeting rather than
  /// a request: it is the sentence somebody hears first, and a caregiver
  /// comparing voices is choosing how this person will say hello.
  static const previewSentence = 'Hello, how are you?';

  /// The travel of each dial.
  ///
  /// Named rather than inline because a tone multiplies these and [applyTone]
  /// clamps the product, so where a bound lands decides whether the top of a
  /// slider does anything.
  static const speedMin = 0.4;
  static const speedMax = 1.8;
  static const pitchMin = 0.6;
  static const pitchMax = 1.6;
  static const volumeMin = 0.1;
  static const volumeMax = 1.0;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  ProfileSettings get _settings => widget.settings;

  /// The neural half of the screen, or null where there is none to show.
  NeuralSpeechEngine? get _neural =>
      showsNeuralVoice(
        widget.speech,
        db: widget.db,
        vocabularyId: widget.vocabularyId,
      )
      ? widget.speech as NeuralSpeechEngine
      : null;

  SpeechEngine get _device => deviceVoiceEngine(widget.speech);

  late final _setup = VoiceSetup(_device);

  Future<void> _applyAll() => _setup.apply(
    voiceName: _settings.voiceName,
    voiceLocale: _settings.voiceLocale,
    voiceIdentifier: _settings.voiceIdentifier,
    rate: _settings.speechRate,
    pitch: _settings.speechPitch,
    volume: _settings.speechVolume,
    tone: _settings.tone,
  );

  /// Pushes the settings to the engine and speaks, so the change is heard
  /// rather than described.
  Future<void> _previewDevice() async {
    await _applyAll();
    await _device.speak(VoiceScreen.previewSentence);
  }

  /// Speaks one voice without choosing it.
  ///
  /// A caregiver comparing a dozen voices should not have to set each one to
  /// hear it — the neural list has had a speaker on every row since it was
  /// written, and taking that away from the device list when the two were
  /// merged was a regression. The profile's own settings are put back
  /// afterwards, so listening changes nothing that is stored.
  ///
  /// One residue, and it is the platform's: there is no way to ask a speech
  /// engine to go back to "whatever this tablet uses". So for a profile that
  /// has never chosen a voice, the engine is left holding the last one
  /// auditioned until a voice is chosen or the app is next opened — which is
  /// when `openSession` applies the profile's settings again. Nothing is
  /// written down, and choosing one is the next tap on the same page.
  Future<void> _hearVoice(VoiceOption voice) async {
    await _setup.apply(
      voiceName: voice.name,
      voiceLocale: voice.locale,
      voiceIdentifier: voice.identifier,
      rate: _settings.speechRate,
      pitch: _settings.speechPitch,
      volume: _settings.speechVolume,
      tone: _settings.tone,
    );
    await _device.speak(VoiceScreen.previewSentence);
    await _applyAll();
  }

  /// What the board will actually say, in whichever voice is set.
  Future<void> _previewChosen() async {
    await _applyAll();
    await widget.speech.speak(VoiceScreen.previewSentence);
  }

  Future<void> _set(String key, Object? value) async {
    await _settings.set(key, value);
    if (mounted) setState(() {});
  }

  Future<void> _openDeviceVoices() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DeviceVoicePicker(
          setup: _setup,
          settings: _settings,
          locale: widget.locale,
          onPreview: _previewDevice,
          onHear: _hearVoice,
        ),
      ),
    );
    // The row is a route below the picker and cannot redraw while it is
    // covered, so it would still name the voice that was set before.
    if (mounted) setState(() {});
  }

  /// The device voice's own controls, in the order they are met.
  ///
  /// Of the four dials only speed reaches the neural voice — `useNeuralVoice`
  /// is handed `speechRate` and nothing else — so where both voices are on the
  /// screen the notes have to say which of them each dial moves. Otherwise a
  /// caregiver drags pitch, hears nothing change in the voice that is actually
  /// speaking, and concludes the dial is broken.
  List<Widget> _deviceControls({required bool neuralOn}) {
    final tone = _settings.tone;
    final heard = applyTone(
      tone,
      rate: _settings.speechRate,
      pitch: _settings.speechPitch,
      volume: _settings.speechVolume,
    );
    final toneLabel = tone == Tone.normal ? null : tone.label;
    final rateCeiling = tone.rateCeiling;

    return [
      ListTile(
        leading: const Icon(Icons.record_voice_over_outlined),
        title: const Text('Which voice'),
        subtitle: Text(
          deviceVoiceLine(_settings.voiceName, _settings.voiceLocale),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openDeviceVoices,
      ),

      const VoiceHeader('Tone'),
      RadioGroup<Tone>(
        groupValue: _settings.tone,
        onChanged: (value) async {
          if (value == null) return;
          await _set('tone', value.name);
          await _previewDevice();
        },
        child: Column(
          children: [
            for (final tone in Tone.values)
              RadioListTile<Tone>(value: tone, title: Text(tone.label)),
          ],
        ),
      ),
      VoiceNote(
        neuralOn
            ? 'The tone the device voice speaks in. The neural voice is not '
                  'given it.'
            : 'The tone the device voice speaks in.',
      ),

      const VoiceHeader('Speed, pitch and volume'),
      _Dial(
        label: 'Speed',
        value: _settings.speechRate,
        heard: heard.rate,
        toneLabel: toneLabel,
        min: VoiceScreen.speedMin,
        max: VoiceScreen.speedMax,
        ceiling: rateCeiling < VoiceScreen.speedMax ? rateCeiling : null,
        onChanged: (v) => _set('speechRate', v),
        onSettled: _previewDevice,
      ),
      _Dial(
        label: 'Pitch',
        value: _settings.speechPitch,
        heard: heard.pitch,
        toneLabel: toneLabel,
        min: VoiceScreen.pitchMin,
        max: VoiceScreen.pitchMax,
        onChanged: (v) => _set('speechPitch', v),
        onSettled: _previewDevice,
      ),
      _Dial(
        label: 'Volume',
        value: _settings.speechVolume,
        heard: heard.volume,
        toneLabel: toneLabel,
        min: VoiceScreen.volumeMin,
        max: VoiceScreen.volumeMax,
        onChanged: (v) => _set('speechVolume', v),
        onSettled: _previewDevice,
      ),
      VoiceNote(
        neuralOn
            ? 'Volume is a proportion of the device volume. Of these three, '
                  'speed is the only one the neural voice is given.'
            : 'Volume is a proportion of the device volume.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final neural = _neural;

    return Scaffold(
      appBar: AppBar(
        title: const Text('How it sounds'),
        actions: [
          IconButton(
            onPressed: _previewChosen,
            icon: const Icon(Icons.volume_up_rounded),
            tooltip: 'Hear it',
          ),
        ],
      ),
      body: ListView(
        children: [
          if (neural != null)
            // Which voice speaks is the first question on the screen, so the
            // section that asks it lays the whole body out and is handed the
            // device controls to place. The alternative was a chooser at the
            // top wired to state two widgets below it.
            NeuralVoiceSection(
              speech: neural,
              settings: _settings,
              db: widget.db!,
              vocabularyId: widget.vocabularyId!,
              deviceControls: _deviceControls,
              onChanged: () {
                if (mounted) setState(() {});
              },
            )
          else ...[
            // One voice, so there is nothing to choose between, and a chooser
            // with a single row is not a choice — it is a claim that something
            // was decided. What the chooser is for is that no voice speaks
            // unnamed, and the header does that on its own.
            const VoiceHeader('Device voice'),
            ..._deviceControls(neuralOn: false),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// One heading on the voice screen.
///
/// Shared with [NeuralVoiceSection] so the two halves of one screen cannot
/// come to head their sections differently.
class VoiceHeader extends StatelessWidget {
  const VoiceHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// The small print under a control, saying what it does and does not do.
class VoiceNote extends StatelessWidget {
  const VoiceNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    ),
  );
}

/// Every voice this tablet can speak in, on a page of its own.
///
/// A caregiver reads this list once and the dials every time they come back,
/// so the list is the thing that moves. It used to sit above them, and the
/// result was pitch control nobody knew was there.
class _DeviceVoicePicker extends StatefulWidget {
  const _DeviceVoicePicker({
    required this.setup,
    required this.settings,
    required this.locale,
    required this.onPreview,
    required this.onHear,
  });

  final VoiceSetup setup;
  final ProfileSettings settings;
  final String locale;
  final Future<void> Function() onPreview;

  /// Speaks one voice without choosing it.
  final Future<void> Function(VoiceOption) onHear;

  @override
  State<_DeviceVoicePicker> createState() => _DeviceVoicePickerState();
}

class _DeviceVoicePickerState extends State<_DeviceVoicePicker> {
  List<VoiceOption>? _voices;
  int _hiddenNovelty = 0;

  /// The voice being spoken right now, so its own row shows the wait.
  VoiceOption? _playing;

  ProfileSettings get _settings => widget.settings;

  Future<void> _hear(VoiceOption voice) async {
    setState(() => _playing = voice);
    await widget.onHear(voice);
    if (mounted) setState(() => _playing = null);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final voices = await widget.setup.usableVoices(
      locale: widget.locale,
      includeNovelty: _settings.noveltyVoices,
    );
    final hidden = await widget.setup.noveltyCount(locale: widget.locale);
    if (mounted) {
      setState(() {
        _voices = voices;
        _hiddenNovelty = hidden;
      });
    }
  }

  Future<void> _set(String key, Object? value) async {
    await _settings.set(key, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device voice')),
      body: ListView(
        children: [
          _VoiceList(
            voices: _voices,
            selectedName: _settings.voiceName,
            selectedLocale: _settings.voiceLocale,
            selectedIdentifier: _settings.voiceIdentifier,
            playing: _playing,
            onHear: _hear,
            onSelected: (voice) async {
              await _set('voiceName', voice?.name);
              await _set('voiceLocale', voice?.locale);
              await _set('voiceIdentifier', voice?.identifier);
              await widget.onPreview();
            },
          ),
          SwitchListTile(
            value: _settings.noveltyVoices,
            title: const Text('Include the joke voices'),
            subtitle: Text(
              _hiddenNovelty == 0
                  ? 'This device offers none.'
                  : 'Robots, singing and cartoon characters. '
                        '$_hiddenNovelty on this device, left out by default.',
            ),
            isThreeLine: _hiddenNovelty > 0,
            onChanged: (v) async {
              await _set('noveltyVoices', v);
              await _load();
            },
          ),
          const VoiceNote(
            'Only offline voices are listed, so the board still speaks with '
            'no signal.',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _VoiceList extends StatelessWidget {
  const _VoiceList({
    required this.voices,
    required this.selectedName,
    required this.selectedLocale,
    required this.selectedIdentifier,
    required this.playing,
    required this.onHear,
    required this.onSelected,
  });

  final List<VoiceOption>? voices;
  final String? selectedName;
  final String? selectedLocale;
  final String? selectedIdentifier;
  final VoiceOption? playing;
  final Future<void> Function(VoiceOption) onHear;
  final ValueChanged<VoiceOption?> onSelected;

  @override
  Widget build(BuildContext context) {
    final voices = this.voices;

    if (voices == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (voices.isEmpty) {
      return const VoiceNote(
        'No offline voices for the board language. The system voice is still '
        'used. Install one in the device speech settings to choose it here.',
      );
    }

    final byKey = <String, VoiceOption>{};
    for (final voice in voices) {
      byKey.putIfAbsent(VoiceSetup.voiceKey(voice), () => voice);
    }

    final selected = VoiceSetup.storedVoice(
      voices,
      name: selectedName,
      locale: selectedLocale,
      identifier: selectedIdentifier,
    );

    final groups = VoiceSetup.groupByGender(voices);
    final unlabeled = !VoiceSetup.reportsGender(voices);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<String?>(
          groupValue: selected == null ? null : VoiceSetup.voiceKey(selected),
          onChanged: (key) => onSelected(key == null ? null : byKey[key]),
          child: Column(
            children: [
              const RadioListTile<String?>(
                value: null,
                title: Text('Whatever the device uses'),
              ),
              for (final group in groups) ...[
                if (group.heading case final heading?) _GroupHeader(heading),
                for (final voice in group.voices)
                  RadioListTile<String?>(
                    value: VoiceSetup.voiceKey(voice),
                    title: Text(voice.name),
                    subtitle: Text(_describe(voice)),
                    // Hearing one is not choosing it. A caregiver comparing a
                    // dozen voices for somebody else should be able to listen
                    // through the list without setting each one on the way.
                    secondary: IconButton(
                      icon: playing == voice
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volume_up_rounded),
                      tooltip: 'Hear ${voice.name}',
                      onPressed: playing == null ? () => onHear(voice) : null,
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (unlabeled)
          const VoiceNote(
            'This device does not report which voices are male and which are '
            'female, so they are listed together.',
          ),
      ],
    );
  }

  static String _describe(VoiceOption voice) {
    final quality = VoiceSetup.qualityLabel(voice.quality);
    return quality == null ? voice.locale : '${voice.locale} · $quality';
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// A slider that previews when the finger comes off, not while it is moving.
///
/// Speaking on every value would stutter through a dozen half-sentences and
/// tell the caregiver nothing.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.label,
    required this.value,
    required this.heard,
    required this.toneLabel,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onSettled,
    this.ceiling,
  });

  final String label;

  /// Where the slider sits: the profile's own setting, before any tone.
  final double value;

  /// What the engine is handed once the tone has multiplied [value].
  ///
  /// Shown beside the setting rather than instead of it, because the setting is
  /// the thing being dragged and a slider whose number does not follow the
  /// thumb is unusable. Both have to be on screen: a caregiver is matching what
  /// they hear against a number, for somebody who cannot tell them it is wrong.
  final double heard;

  /// Null under Normal, where the two figures are the same.
  final String? toneLabel;

  final double min;
  final double max;

  /// The highest [value] the tone carries before the engine's own limit takes
  /// over, or null where every setting on this slider still moves the voice.
  final double? ceiling;

  final ValueChanged<double> onChanged;
  final VoidCallback onSettled;

  static String _percent(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final setting = _percent(value);
    final effective = _percent(heard);
    final ceiling = this.ceiling;

    return ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            toneLabel == null || effective == setting
                ? setting
                : '$setting · $effective with $toneLabel',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) * 20).round(),
            onChanged: onChanged,
            onChangeEnd: (_) => onSettled(),
          ),
          if (ceiling != null && value > ceiling)
            VoiceNote(
              '$toneLabel already reaches the limit text to speech accepts, '
              'so anything above ${_percent(ceiling)} sounds the same.',
            ),
        ],
      ),
    );
  }
}
