import 'package:flutter/material.dart';

import '../profiles/profile_settings.dart';
import '../speech/speech_engine.dart';
import '../speech/tone.dart';
import '../speech/voice_setup.dart';

/// Choosing how this profile sounds.
///
/// Every control previews itself the moment it moves. A caregiver setting a
/// voice for someone else cannot judge it from a number, and the person it is
/// for may not be able to tell them it is wrong.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.speech,
    required this.settings,
    this.locale = 'en',
  });

  final SpeechEngine speech;
  final ProfileSettings settings;
  final String locale;

  static Future<void> show(
    BuildContext context, {
    required SpeechEngine speech,
    required ProfileSettings settings,
    String locale = 'en',
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          VoiceScreen(speech: speech, settings: settings, locale: locale),
    ),
  );

  /// What the preview says.
  ///
  /// A whole sentence rather than a word, because rate and tone are properties
  /// of a sentence and cannot be heard in one syllable.
  static const previewSentence = 'I want to go outside now';

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
  late final _setup = VoiceSetup(widget.speech);

  List<VoiceOption>? _voices;
  int _hiddenNovelty = 0;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final voices = await _setup.usableVoices(
      locale: widget.locale,
      includeNovelty: _settings.noveltyVoices,
    );
    final hidden = await _setup.noveltyCount(locale: widget.locale);
    if (mounted) {
      setState(() {
        _voices = voices;
        _hiddenNovelty = hidden;
      });
    }
  }

  ProfileSettings get _settings => widget.settings;

  /// Pushes the settings to the engine and speaks, so the change is heard
  /// rather than described.
  Future<void> _preview() async {
    await _applyAll();
    await widget.speech.speak(VoiceScreen.previewSentence);
  }

  Future<void> _applyAll() => _setup.apply(
    voiceName: _settings.voiceName,
    voiceLocale: _settings.voiceLocale,
    voiceIdentifier: _settings.voiceIdentifier,
    rate: _settings.speechRate,
    pitch: _settings.speechPitch,
    volume: _settings.speechVolume,
    tone: _settings.tone,
  );

  Future<void> _set(String key, Object? value) async {
    await _settings.set(key, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tone = _settings.tone;
    final heard = applyTone(
      tone,
      rate: _settings.speechRate,
      pitch: _settings.speechPitch,
      volume: _settings.speechVolume,
    );
    final toneLabel = tone == Tone.normal ? null : tone.label;
    final rateCeiling = tone.rateCeiling;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice'),
        actions: [
          IconButton(
            onPressed: _preview,
            icon: const Icon(Icons.volume_up_rounded),
            tooltip: 'Hear it',
          ),
        ],
      ),
      body: ListView(
        children: [
          const _SectionHeader('Voice'),
          _VoiceList(
            voices: _voices,
            selectedName: _settings.voiceName,
            selectedLocale: _settings.voiceLocale,
            selectedIdentifier: _settings.voiceIdentifier,
            onSelected: (voice) async {
              await _set('voiceName', voice?.name);
              await _set('voiceLocale', voice?.locale);
              await _set('voiceIdentifier', voice?.identifier);
              await _preview();
            },
          ),
          SwitchListTile(
            value: _settings.noveltyVoices,
            title: const Text('Include the joke voices'),
            subtitle: Text(
              _hiddenNovelty == 0
                  ? 'This device offers none.'
                  : 'Robots, singing and cartoon characters — '
                        '$_hiddenNovelty of them on this device. Left out by '
                        'default so the speaking voices are easier to compare.',
            ),
            isThreeLine: _hiddenNovelty > 0,
            onChanged: (v) async {
              await _set('noveltyVoices', v);
              await _loadVoices();
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Only voices that work without a connection are listed. A voice '
              'that needs the network is one this device loses exactly when '
              'it is furthest from home.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ),
          const Divider(),
          const _SectionHeader('Tone'),
          RadioGroup<Tone>(
            groupValue: _settings.tone,
            onChanged: (value) async {
              if (value == null) return;
              await _set('tone', value.name);
              await _preview();
            },
            child: Column(
              children: [
                for (final tone in Tone.values)
                  RadioListTile<Tone>(value: tone, title: Text(tone.label)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'These four are what a phone or tablet\'s own speech can '
              'actually do: it offers speed, pitch and volume, and nothing '
              'else. Sarcasm needs a rise and fall across the whole sentence, '
              'and a real whisper needs breath — neither is something an app '
              'can ask for. "Quiet" is this voice turned down, and is named '
              'that rather than "whisper" because that is what you will hear.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ),
          const Divider(),
          const _SectionHeader('Speed, pitch and volume'),
          _Dial(
            label: 'Speed',
            value: _settings.speechRate,
            heard: heard.rate,
            toneLabel: toneLabel,
            min: VoiceScreen.speedMin,
            max: VoiceScreen.speedMax,
            ceiling: rateCeiling < VoiceScreen.speedMax ? rateCeiling : null,
            onChanged: (v) => _set('speechRate', v),
            onSettled: _preview,
          ),
          _Dial(
            label: 'Pitch',
            value: _settings.speechPitch,
            heard: heard.pitch,
            toneLabel: toneLabel,
            min: VoiceScreen.pitchMin,
            max: VoiceScreen.pitchMax,
            onChanged: (v) => _set('speechPitch', v),
            onSettled: _preview,
          ),
          _Dial(
            label: 'Volume',
            value: _settings.speechVolume,
            heard: heard.volume,
            toneLabel: toneLabel,
            min: VoiceScreen.volumeMin,
            max: VoiceScreen.volumeMax,
            onChanged: (v) => _set('speechVolume', v),
            onSettled: _preview,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Text(
              'A tone multiplies these, so where one is set the second figure '
              'is what the voice is actually given. Volume here is a share of '
              'the device\'s own volume and cannot go above it. If this is not '
              'loud enough across a room or from the back of a car, turn the '
              'device up too — the app cannot do it for you.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
    ),
  );
}

class _VoiceList extends StatelessWidget {
  const _VoiceList({
    required this.voices,
    required this.selectedName,
    required this.selectedLocale,
    required this.selectedIdentifier,
    required this.onSelected,
  });

  final List<VoiceOption>? voices;
  final String? selectedName;
  final String? selectedLocale;
  final String? selectedIdentifier;
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
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'This device reports no offline voices for the board\'s language. '
          'The system voice is still used; install a voice in the device\'s '
          'own speech settings to choose one here.',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
        ),
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
    final unlabelled = !VoiceSetup.reportsGender(voices);

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
                  ),
              ],
            ],
          ),
        ),
        if (unlabelled)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'This device does not say which of its voices are male and which '
              'are female, so they are listed together. The names are the only '
              'clue it gives.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
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
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: Colors.black54,
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
            style: const TextStyle(color: Colors.black54),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$toneLabel already takes this to the limit of what the '
                'device\'s speech accepts, so anything above '
                '${_percent(ceiling)} sounds the same.',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
