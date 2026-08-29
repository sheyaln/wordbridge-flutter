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
            min: 0.4,
            max: 1.8,
            onChanged: (v) => _set('speechRate', v),
            onSettled: _preview,
          ),
          _Dial(
            label: 'Pitch',
            value: _settings.speechPitch,
            min: 0.6,
            max: 1.6,
            onChanged: (v) => _set('speechPitch', v),
            onSettled: _preview,
          ),
          _Dial(
            label: 'Volume',
            value: _settings.speechVolume,
            min: 0.1,
            max: 1.0,
            onChanged: (v) => _set('speechVolume', v),
            onSettled: _preview,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Text(
              'Volume here is a share of the device\'s own volume and cannot '
              'go above it. If this is not loud enough across a room or from '
              'the back of a car, turn the device up too — the app cannot do '
              'it for you.',
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
    required this.onSelected,
  });

  final List<VoiceOption>? voices;
  final String? selectedName;
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

    final byName = {for (final voice in voices) voice.name: voice};

    return RadioGroup<String?>(
      groupValue: selectedName,
      onChanged: (name) => onSelected(name == null ? null : byName[name]),
      child: Column(
        children: [
          const RadioListTile<String?>(
            value: null,
            title: Text('Whatever the device uses'),
          ),
          for (final voice in voices)
            RadioListTile<String?>(
              value: voice.name,
              title: Text(voice.name),
              subtitle: Text(voice.locale),
            ),
        ],
      ),
    );
  }
}

/// A slider that previews when the finger comes off, not while it is moving.
///
/// Speaking on every value would stutter through a dozen half-sentences and
/// tell the caregiver nothing.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onSettled,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onSettled;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          '${(value * 100).round()}%',
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    ),
    subtitle: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: ((max - min) * 20).round(),
      onChanged: onChanged,
      onChangeEnd: (_) => onSettled(),
    ),
  );
}
