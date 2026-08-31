import 'package:flutter/material.dart';

import '../speech/speech_engine.dart';
import 'find_a_word.dart';

/// Typing a word the board does not have.
///
/// For the word that is not on the board and is not going to be — a place name,
/// a visitor, the title of something somebody watched once. A location for it
/// would cost that location on every board in the set, and most of these are
/// said once.
///
/// The device's own keyboard rather than one drawn here. It is the keyboard
/// this person has already learned, carrying whatever has been set up on it —
/// text replacements, a second language, a third-party layout — and it comes
/// with the platform's own accessibility rather than an imitation of it. It is
/// also full height, which a keyboard drawn inside a sheet is not.
///
/// Nothing is spoken until the word is finished. A keyboard that said each
/// letter as it landed would make typing a word an announcement of how it is
/// spelled, to a room that was waiting for the word.
class TypeAWord extends StatefulWidget {
  const TypeAWord({super.key, this.speech});

  final SpeechEngine? speech;

  /// The finished word, already spoken, or null if nobody finished one.
  static Future<String?> show(BuildContext context, {SpeechEngine? speech}) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => TypeAWord(speech: speech),
        ),
      );

  @override
  State<TypeAWord> createState() => _TypeAWordState();
}

class _TypeAWordState extends State<TypeAWord> {
  final _field = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The keyboard is the screen, so it comes up without anybody asking for it.
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasWord => _field.text.trim().isNotEmpty;

  /// Says the word once and hands it back.
  ///
  /// Speech is tried before the screen closes, and a failure closes it anyway:
  /// the word still belongs in the sentence, and a screen that would not shut
  /// because the voice was busy is a person stuck behind a keyboard.
  Future<void> _send() async {
    final word = _field.text.trim();
    if (word.isEmpty) return;

    try {
      await widget.speech?.speak(word);
    } catch (_) {
      // Nowhere to report it to, and the word is not lost by it.
    }

    if (mounted) Navigator.of(context).pop(word);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Type a word'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Back to the board',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _field,
              focusNode: _focus,
              autofocus: true,
              // Nothing here overrides how the keyboard behaves. Whatever has
              // been set up on this device — replacements, corrections, a
              // second language — is the reason for using it rather than
              // drawing one.
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _send(),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 34),
              decoration: const InputDecoration(
                hintText: 'A word the board does not have',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Beside the return key rather than instead of it, because a
            // keyboard set up for another language may not put "done" where
            // this one expects it.
            FilledButton.icon(
              onPressed: _hasWord ? _send : null,
              icon: const Icon(Icons.volume_up_rounded),
              label: Text(sayItLabel(speaks: widget.speech != null)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
