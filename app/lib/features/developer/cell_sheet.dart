import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../editor/board_editor.dart';
import '../editor/symbol_picker.dart';
import '../grid/grid_surface.dart' show PlacedCell;
import '../speech/neural/neural_engine.dart';
import '../speech/speech_engine.dart';
import '../symbols/global_symbols_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';

/// Why the board is not drawing what is at a location.
///
/// A pure function so the sentence is a thing a test can state. Null where the
/// location is drawn, or is genuinely empty — "there is nothing here" is not a
/// reason, it is the answer.
String? whyNotDrawn({
  required Button? button,
  required int vocabLevel,
  bool Function(Button)? isAvailable,
}) {
  if (button == null) return null;
  if (button.hidden) return 'Switched off. It keeps this location either way.';
  if (button.vocabLevel > vocabLevel) {
    return 'Level ${button.vocabLevel}, and this profile is at level '
        '$vocabLevel. Raising the level draws it here, where it already is.';
  }
  if (!(isAvailable?.call(button) ?? true)) {
    return 'An ending the sentence so far cannot take. It comes back in this '
        'same location when it applies.';
  }
  return null;
}

/// What is behind one location, and the four things worth doing to it.
///
/// Opened by holding a location while developer mode is on. It exists because
/// every question anyone asks of this board is about a location — what is
/// there, why is it blank, where did that picture come from, which voice says
/// it — and answering any of them otherwise means leaving the board, opening
/// caregiver mode, finding the right board in the editor and counting rows.
///
/// **Nothing here happens on the way in.** Everything it needs is read before
/// it opens, so no route out of the talk screen can end at a spinner over a
/// board somebody is trying to speak on.
class DeveloperCellSheet extends StatelessWidget {
  const DeveloperCellSheet({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.placed,
    required this.boardName,
    required this.vocabLevel,
    this.speech,
    this.registry,
    this.resolver,
    this.fetcher,
    this.userName,
    this.isAvailable,
    this.onViewAll,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final PlacedCell placed;
  final String boardName;
  final int vocabLevel;
  final SpeechEngine? speech;
  final SymbolRegistry? registry;
  final SymbolResolver? resolver;
  final GlobalSymbolsPack? fetcher;
  final String? userName;
  final bool Function(Button)? isAvailable;

  /// Turns on the board's own way of drawing everything it is hiding.
  ///
  /// Offered rather than reimplemented: view-all already exists, already says
  /// so on the board, and already leaves nothing written down.
  final ValueChanged<bool>? onViewAll;

  /// Opens the sheet for a held location.
  ///
  /// The board name is read here rather than inside, so the sheet is built
  /// from what is already in hand and cannot open onto a spinner.
  static Future<void> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required String vocabularyId,
    required PlacedCell placed,
    required int vocabLevel,
    SpeechEngine? speech,
    SymbolRegistry? registry,
    SymbolResolver? resolver,
    GlobalSymbolsPack? fetcher,
    String? userName,
    bool Function(Button)? isAvailable,
    ValueChanged<bool>? onViewAll,
  }) async {
    final board = await (db.select(
      db.boards,
    )..where((b) => b.id.equals(placed.cell.boardId))).getSingleOrNull();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: DeveloperCellSheet(
          db: db,
          vocabularyId: vocabularyId,
          placed: placed,
          boardName: board?.name ?? placed.cell.boardId,
          vocabLevel: vocabLevel,
          speech: speech,
          registry: registry,
          resolver: resolver,
          fetcher: fetcher,
          userName: userName,
          isAvailable: isAvailable,
          onViewAll: onViewAll,
        ),
      ),
    );
  }

  /// Where the picture on this button comes from, which is the distinction
  /// the picker exists to change and the one nothing else on screen states.
  static String _pictureSource(Button button) {
    final symbolId = button.symbolId;
    if (symbolId == removedPictureSymbolId) {
      return 'Its picture was taken off on purpose';
    }
    if (symbolId == null) {
      return 'Whatever the packs carry for "${button.label}"';
    }
    return 'A picture chosen for this button';
  }

  Cell get _cell => placed.cell;

  Button? get _button => placed.button;

  /// What this button would say if it were pressed.
  String? get _spoken {
    final button = _button;
    if (button == null) return null;
    final text = (button.speakText ?? button.message).trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final button = _button;
    final why = whyNotDrawn(
      button: button,
      vocabLevel: vocabLevel,
      isAvailable: isAvailable,
    );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              button?.label ?? 'Nothing here yet',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '$boardName, row ${_cell.row}, column ${_cell.col}\n'
              'cell ${_cell.id}'
              '${button == null ? '' : '\nbutton ${button.id}'}',
            ),
            isThreeLine: true,
          ),
          if (why != null)
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Not drawn right now'),
              subtitle: Text(why),
              isThreeLine: true,
              // The board's own way of showing what it is hiding, rather than
              // a second one that would have to be turned off separately.
              trailing: onViewAll == null
                  ? null
                  : TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onViewAll!(true);
                      },
                      child: const Text('Show all'),
                    ),
            ),
          const Divider(height: 1),
          ..._voices(context),
          if (button != null && registry != null && resolver != null)
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Change the picture'),
              subtitle: Text(_pictureSource(button)),
              onTap: () {
                // The navigator is taken before the sheet is closed, and the
                // picker is opened against the navigator's own context. Its
                // context is what outlives this sheet; the sheet's is halfway
                // through being taken off the screen.
                final navigator = Navigator.of(context)..pop();
                SymbolPicker.show(
                  navigator.context,
                  db: db,
                  registry: registry!,
                  resolver: resolver!,
                  fetcher: fetcher,
                  button: button,
                );
              },
            ),
          if (button == null)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Put a word here'),
              subtitle: const Text(
                'Opens the editor on this board with this location already '
                'chosen',
              ),
              isThreeLine: true,
              onTap: () => _openEditor(context, openCellId: _cell.id),
            ),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: Text('Edit "$boardName"'),
            subtitle: const Text('The whole board, in the caregiver editor'),
            onTap: () => _openEditor(context),
          ),
        ],
      ),
    );
  }

  /// The two voices, side by side on one word.
  ///
  /// This is the only place in the app where the choice is made per word
  /// rather than per profile, and that is the point: deciding whether a voice
  /// is right for somebody means hearing the same word said both ways, one
  /// after the other, without changing what the tablet is set to. Flipping the
  /// profile setting to compare would leave the wrong one in force the moment
  /// anybody was distracted.
  ///
  /// Only where there are two. On a build with no neural engine there is one
  /// voice and offering a choice between it and itself says something false.
  List<Widget> _voices(BuildContext context) {
    final speech = this.speech;
    final text = _spoken;
    if (speech == null || text == null) return const [];

    if (speech is! NeuralSpeechEngine) {
      return [
        ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: const Text('Say it'),
          subtitle: const Text('The only voice this build has'),
          onTap: () => _say(context, speech, text, 'the device voice'),
        ),
      ];
    }

    return [
      ListTile(
        leading: const Icon(Icons.graphic_eq),
        title: const Text('Say it with the neural voice'),
        subtitle: Text(
          speech.isOn
              ? 'The voice this profile is set to'
              : 'Switched off for this profile, so nothing is cached and the '
                    'device voice answers',
        ),
        isThreeLine: !speech.isOn,
        onTap: () => _say(context, speech, text, 'the neural voice'),
      ),
      ListTile(
        leading: const Icon(Icons.record_voice_over_outlined),
        title: const Text('Say it with the device voice'),
        subtitle: const Text('What the neural voice falls back to'),
        onTap: () => _say(context, speech.platform, text, 'the device voice'),
      ),
    ];
  }

  /// Says the word and reports what happened, which is the whole reason for
  /// the row.
  ///
  /// How long it took, and — where the neural engine answered — whether it got
  /// there or handed the word to the platform. The engine counts its own
  /// fallbacks, so the count either side of the call says which, without this
  /// having to reach inside it.
  ///
  /// The sheet stays open. Two voices are being compared, and a control that
  /// closed the screen after each one would make the comparison three taps
  /// apart instead of two.
  Future<void> _say(
    BuildContext context,
    SpeechEngine engine,
    String text,
    String which,
  ) async {
    final profileEngine = speech;
    final neural = profileEngine is NeuralSpeechEngine ? profileEngine : null;
    final before = neural?.fallbackCount ?? 0;
    final clock = Stopwatch()..start();

    var failure = '';
    try {
      await engine.speak(text);
    } catch (e) {
      failure = ', and threw: $e';
    }
    clock.stop();

    final fellBack =
        neural != null && engine == neural && neural.fallbackCount > before;
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"$text" in $which, ${clock.elapsedMilliseconds} ms'
          '${fellBack ? ', and fell back to the device voice' : ''}$failure',
        ),
      ),
    );
  }

  /// Closes the sheet and opens the editor behind it.
  ///
  /// The navigator is taken before the pop, for the reason the picker takes
  /// one: pushing through a context whose route is already leaving is pushing
  /// onto something that is on its way out.
  void _openEditor(BuildContext context, {String? openCellId}) {
    Navigator.of(context)
      ..pop()
      ..push(
        MaterialPageRoute<void>(
          builder: (_) => BoardEditor(
            db: db,
            vocabularyId: vocabularyId,
            boardId: _cell.boardId,
            registry: registry,
            fetcher: fetcher,
            resolver: resolver,
            userName: userName,
            openCellId: openCellId,
          ),
        ),
      );
  }
}
