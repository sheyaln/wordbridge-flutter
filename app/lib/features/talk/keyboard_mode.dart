import 'dart:async';

import 'package:flutter/material.dart';

import '../profiles/profile_settings.dart';
import '../speech/speech_engine.dart';
import '../utterance/utterance.dart';

/// Typing, for as long as somebody wants to type (§4.87).
///
/// **The board is for the words somebody has a location for. This is for
/// everybody else's sentence.** An adult who reads and writes does not need a
/// motor plan to say "the appointment was moved to Thursday" — they need a
/// keyboard, and the board's typing screen is built for one word at a time:
/// it opens, takes a word, and closes. Ten words is ten round trips through a
/// route transition, and a conversation held that way is not held.
///
/// So this is the same keyboard that stays. It opens once, the sentence builds
/// in front of the person typing it, and nothing closes until they are done.
///
/// **It does not replace the board and it does not own the sentence.** The
/// utterance bar it writes into is the board's own, so a sentence started by
/// tapping can be finished by typing and the other way round — which is the
/// case that matters, because the word somebody has to type is usually one
/// word in a sentence of words they know the locations of.
///
/// **A space is a word.** Every word goes into the bar the moment it is
/// finished and is said as it lands, exactly the way a key on the board
/// behaves — so typing and tapping produce the same sentence, built the same
/// way, and the delete key takes back one word from either. Nothing has to be
/// sent, and there is no unit of composition between the word and the
/// sentence for somebody to keep track of.
///
/// Committing on the space is also what makes autocorrect's answer the one
/// that lands: both platforms finalize the word being composed when the space
/// arrives, so what is taken is what the keyboard settled on rather than the
/// letters underneath it.
///
/// No part of speech, because nothing here knows one. The endings and the
/// copula read the word before them, and a typed word tells them nothing —
/// which is honest: guessing would offer "+ed" on a person's name.
class KeyboardMode extends StatefulWidget {
  const KeyboardMode({
    super.key,
    required this.utterance,
    required this.onSpeak,
    this.speech,
    this.settings,
  });

  /// The board's own sentence, written into directly.
  final UtteranceBar utterance;

  /// Says the whole sentence. The board's own route, so a sentence sent from
  /// here is learned from, ends the word-by-word pause, and shows the same
  /// ring as one sent from the bar.
  final Future<void> Function() onSpeak;

  /// Says each piece as it is sent, or null where this profile has asked for
  /// quiet — or has paused it (§4.88).
  final SpeechEngine? speech;

  final ProfileSettings? settings;

  static Future<void> show(
    BuildContext context, {
    required UtteranceBar utterance,
    required Future<void> Function() onSpeak,
    SpeechEngine? speech,
    ProfileSettings? settings,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => KeyboardMode(
        utterance: utterance,
        onSpeak: onSpeak,
        speech: speech,
        settings: settings,
      ),
    ),
  );

  @override
  State<KeyboardMode> createState() => _KeyboardModeState();
}

class _KeyboardModeState extends State<KeyboardMode> {
  final _field = TextEditingController();
  final _focus = FocusNode();

  /// Where the correction choice lives when there is no profile to write it to.
  bool _local = true;

  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    // The keyboard is the screen, so it comes up without anybody asking.
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasText => _field.text.trim().isNotEmpty;

  bool get _correcting => widget.settings?.keyboardAutocorrect ?? _local;

  /// Turns correction on or off, and keeps the keyboard up.
  ///
  /// Changing either flag rebuilds the input connection, which on both
  /// platforms can drop the keyboard — and a keyboard that closes mid-sentence
  /// has cost somebody their place. The text is held in the controller and
  /// survives it; the focus is asked for again.
  Future<void> _setCorrecting(bool on) async {
    setState(() => _local = on);
    await widget.settings?.set('keyboardAutocorrect', on);
    if (mounted) _focus.requestFocus();
  }

  /// Takes every finished word out of the field and into the sentence.
  ///
  /// A word is finished when a space follows it. What is left after the last
  /// space stays in the field, still being typed and still correctable —
  /// nothing is taken from somebody mid-word.
  ///
  /// Reads the whole field rather than the last character, so a pasted line
  /// and a held-down space both land as the words they are.
  void _onChanged(String value) {
    if (!value.contains(' ')) {
      setState(() {});
      return;
    }

    final parts = value.split(' ');
    final unfinished = parts.removeLast();

    // The field first, so the words below cannot be taken twice if speaking
    // one of them takes a moment.
    _field.value = TextEditingValue(
      text: unfinished,
      selection: TextSelection.collapsed(offset: unfinished.length),
    );

    for (final word in parts) {
      if (word.trim().isNotEmpty) unawaited(_commit(word.trim()));
    }
    setState(() {});
  }

  /// Puts one word into the sentence and says it.
  ///
  /// Said as it lands, where this profile hears each word, because that is the
  /// same feedback a tapped key gives.
  Future<void> _commit(String word) async {
    setState(() => widget.utterance.add(word));

    try {
      await widget.speech?.speak(word);
    } catch (_) {
      // Nowhere to report it to, and the word is not lost by it.
    }
  }

  /// Sends the word still being typed, for the one that has no space after it.
  Future<void> _send() async {
    final text = _field.text.trim();
    if (text.isEmpty) return;

    _field.clear();
    _focus.requestFocus();
    await _commit(text);
  }

  /// Sends anything still in the field, then says the sentence.
  ///
  /// Sending first is the one ordering that is never wrong: a person who typed
  /// a last word and pressed speak meant that word to be in the sentence, and
  /// a screen that spoke without it would have dropped what they just wrote.
  Future<void> _speak() async {
    if (_hasText) await _send();
    if (widget.utterance.isEmpty || !mounted) return;

    setState(() => _speaking = true);
    try {
      await widget.onSpeak();
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyboard'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Back to the board',
          // The sentence stays. Somebody who typed half of it and wants the
          // rest from the board is the case this screen is built around.
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          AutocorrectToggle(on: _correcting, onChanged: _setCorrecting),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SentenceSoFar(
              utterance: widget.utterance,
              onBackspace: () => setState(widget.utterance.backspace),
              onClear: () => setState(widget.utterance.clear),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _field,
              focusNode: _focus,
              autofocus: true,
              autocorrect: _correcting,
              enableSuggestions: _correcting,
              // Return finishes the word being typed, the way a space does,
              // and the screen stays open — which is what makes this a mode
              // rather than a dialog. "done" would be a lie about what it
              // does.
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              onChanged: _onChanged,
              maxLines: 1,
              style: const TextStyle(fontSize: 28),
              decoration: const InputDecoration(
                hintText: 'Type a word, then space',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hasText ? _send : null,
                    icon: const Icon(Icons.subdirectory_arrow_left_rounded),
                    // For the last word of a sentence, which has no space
                    // after it. Every other word has already gone in by
                    // itself.
                    label: const Text('Add this word'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _speaking ? null : _speak,
                    icon: _speaking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.volume_up_rounded),
                    label: Text(_speaking ? 'Speaking…' : 'Say it'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ],
            ),
            // Nothing below this. Whatever room is left belongs to the device
            // keyboard, which is most of the screen and is the point.
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// The sentence being built, above the field it is being typed into.
///
/// The bar is behind this screen and somebody typing cannot see it. A person
/// who cannot see what they have said so far is composing blind, which for a
/// sentence longer than a phrase is how words get said twice.
class _SentenceSoFar extends StatelessWidget {
  const _SentenceSoFar({
    required this.utterance,
    required this.onBackspace,
    required this.onClear,
  });

  final UtteranceBar utterance;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: utterance,
    builder: (context, _) {
      final empty = utterance.isEmpty;
      return Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                empty ? 'Nothing said yet' : utterance.text,
                style: TextStyle(
                  fontSize: 22,
                  color: empty
                      ? const Color(0xFF80868B)
                      : const Color(0xFF202124),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.backspace_outlined),
              tooltip: 'Delete last',
              onPressed: empty ? null : onBackspace,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Clear',
              onPressed: empty ? null : onClear,
            ),
          ],
        ),
      );
    },
  );
}

/// One tap, and it says which way it is set.
///
/// **Not an icon on its own.** Autocorrect is a two-state setting whose states
/// look identical until somebody types a word and watches what happens to it,
/// and the person most likely to want it off is the one least well served by
/// finding out that way. So the word is on the control, and so is the state.
class AutocorrectToggle extends StatelessWidget {
  const AutocorrectToggle({
    super.key,
    required this.on,
    required this.onChanged,
  });

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: on
        ? 'The keyboard is correcting what you type. Tap to stop it.'
        : 'The keyboard is leaving what you type alone. Tap to correct again.',
    child: TextButton.icon(
      onPressed: () => onChanged(!on),
      icon: Icon(
        on ? Icons.spellcheck_rounded : Icons.text_fields_rounded,
        size: 20,
      ),
      label: Text(on ? 'Autocorrect on' : 'Autocorrect off'),
      style: TextButton.styleFrom(
        // A control on a screen somebody is typing on, pressed by the same
        // hand that presses the board.
        minimumSize: const Size(44, 44),
        foregroundColor: on ? null : const Color(0xFFB71C1C),
      ),
    ),
  );
}
