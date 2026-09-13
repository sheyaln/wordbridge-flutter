/// The three dials somebody changes while they are talking (§4.81).
///
/// Volume, tone and favorites live behind the caregiver door as well, and for
/// two of them that is the wrong door: a voice too loud for the room somebody
/// just walked into, or the wrong tone for the sentence already in the bar, is
/// a thing to fix *now*, in the middle of a conversation. A setting you have to
/// stop talking to reach is one that does not get changed, and a person whose
/// only volume control is behind a PIN somebody else knows does not have a
/// volume control.
///
/// **Nothing here leaves the board.** Every one of these is a layer over the
/// board that dismisses back to exactly the state underneath: the same board,
/// the same sentence, the same place in it. That is what makes the key
/// affordable to put on the system row at all — see `SystemRowPlan.forGrid`
/// for the column it spends and why a mis-reach onto it is recoverable in a
/// way a mis-reach onto a category key is not.
library;

import 'package:flutter/material.dart';

import '../symbols/symbol_pack.dart';
import '../symbols/symbol_resolver.dart';
import '../grid/symbol_view.dart';
import '../profiles/profile_settings.dart';
import '../grid/grid_geometry.dart';
import '../grid/grid_surface.dart';
import '../speech/speech_engine.dart';
import '../speech/tone.dart';
import '../../db/tables.dart';

/// Draws the menu over the board, and hands back the row that was pressed.
///
/// **A layer, never a departure.** The board underneath is not replaced, not
/// scrolled and not navigated away from: it is dimmed, the key and its rows
/// stay lit, and dismissing puts the person back exactly where they were with
/// the same sentence in the bar. That is what makes the key affordable to put
/// on the system row at all — a mis-reach onto it costs one tap to undo, where
/// a mis-reach onto a category key replaces the board under a moving hand.
///
/// The rows are drawn with [BoardCell] at the coordinates the menu board
/// actually holds them at, so a row is a board key in every sense: same shape,
/// same color rule, same picture pipeline, same fixed location.
Future<ButtonAction?> showQuickSettings(
  BuildContext context, {
  required GridGeometry geometry,
  required Offset gridOrigin,
  required int keyRow,
  required int keyCol,
  required List<PlacedCell> rows,
  required SymbolResolver? resolver,
  required ColorConvention colorConvention,
}) => Navigator.of(context).push<ButtonAction>(
  // A route rather than a dialog, so the scrim is ours to paint and the board
  // behind it is never rebuilt.
  PageRouteBuilder<ButtonAction>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    reverseTransitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (context, animation, _) => _QuickSettingsOverlay(
      animation: animation,
      geometry: geometry,
      gridOrigin: gridOrigin,
      keyRow: keyRow,
      keyCol: keyCol,
      rows: rows,
      resolver: resolver,
      colorConvention: colorConvention,
    ),
  ),
);

class _QuickSettingsOverlay extends StatelessWidget {
  const _QuickSettingsOverlay({
    required this.animation,
    required this.geometry,
    required this.gridOrigin,
    required this.keyRow,
    required this.keyCol,
    required this.rows,
    required this.resolver,
    required this.colorConvention,
  });

  final Animation<double> animation;
  final GridGeometry geometry;
  final Offset gridOrigin;
  final int keyRow;
  final int keyCol;
  final List<PlacedCell> rows;
  final SymbolResolver? resolver;
  final ColorConvention colorConvention;

  Rect _rectFor(int row, int col) =>
      geometry.rectFor(row, col).shift(gridOrigin);

  @override
  Widget build(BuildContext context) {
    final key = _rectFor(keyRow, keyCol);

    // The lit region: the key and the rows above it, as one rectangle. Cut out
    // of the scrim in a single piece so the gutters between the rows are lit
    // too — a ladder of separately-lit squares reads as separate things, and
    // this is one thing that opened from one key.
    final lit = rows
        .fold<Rect>(
          key,
          (all, placed) =>
              all.expandToInclude(_rectFor(placed.cell.row, placed.cell.col)),
        )
        .inflate(geometry.gutter);

    return Stack(
      children: [
        // Everything dark except the key and its rows. A dismissal anywhere on
        // the dark, which is the whole rest of the screen.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) => CustomPaint(
                painter: _Scrim(hole: lit, opacity: animation.value * 0.62),
              ),
            ),
          ),
        ),

        for (var i = 0; i < rows.length; i++)
          _MenuRow(
            animation: animation,
            // Nearest the key first. The row against the key is the one a hand
            // arrives at soonest, so it is the one drawn soonest.
            delay: (rows.length - 1 - i) * 0.18,
            from: key,
            to: _rectFor(rows[i].cell.row, rows[i].cell.col),
            child: BoardCell(
              placed: rows[i],
              vocabLevel: 99,
              colorConvention: colorConvention,
              showHidden: false,
              viewAll: false,
              resolver: resolver,
              symbolPackIds: boardSymbolPackIds,
              isAvailable: null,
              onSelect: (placed) =>
                  Navigator.of(context).pop(placed.button?.action),
            ),
          ),
      ],
    );
  }
}

/// One row, travelling up out of the key it came from.
///
/// Short and slight on purpose. The movement says where the menu came from,
/// which is the only thing it is for; a long or bouncing one would be a delay
/// between somebody pressing a key and being able to use what it opened.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.animation,
    required this.delay,
    required this.from,
    required this.to,
    required this.child,
  });

  final Animation<double> animation;
  final double delay;
  final Rect from;
  final Rect to;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(delay.clamp(0.0, 0.6), 1, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        final rect = Rect.lerp(from, to, t)!;
        return Positioned.fromRect(
          rect: rect,
          child: Opacity(opacity: t, child: child),
        );
      },
      child: child,
    );
  }
}

/// Dark everywhere but one rectangle.
class _Scrim extends CustomPainter {
  const _Scrim({required this.hole, required this.opacity});

  final Rect hole;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(hole, const Radius.circular(12));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rounded),
      ),
      Paint()..color = Colors.black.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_Scrim old) => old.hole != hole || old.opacity != opacity;
}

/// The two ends of the volume slider, as a person would describe them.
///
/// Named for how it sounds in the room rather than for a number. "60%" is not
/// something anybody can hear; "loud enough for the back seat" is.
const volumeLoudest = (label: 'Yelling', value: 1.0);
const volumeQuietest = (label: 'Whisper', value: 0.15);

/// The middle of the slider, and where a voice sits when nobody has moved it.
///
/// Below it is quieter than ordinary speech, above it is louder, and the
/// distance to each end is the same — which is what makes the slider readable
/// without hearing it.
///
/// **This is as loud as the device goes, and no louder.** Both engines clamp
/// volume to 0..1 and refuse anything above silently: `flutter_tts.setVolume`
/// on the platform voice, and `ClipPlayer.play` on the neural one. Carrying a
/// voice further than the device allows is a gain problem — amplifying the
/// samples with a limiter, which only the neural path could even attempt —
/// and not something a settings dial can promise.
const volumeNormal = (label: 'Normal', value: 0.6);

/// What is said back after a change, so the change can be heard.
const volumeSample = 'like this';

/// Asks for a volume, as a slider between a whisper and a yell (§4.81).
///
/// A slider, which is the one control this app otherwise avoids: it asks for a
/// controlled drag along a track, and unsteady hands are the population this
/// board is built for. It earns its place here because volume is the one
/// setting with no right answers to choose *from* — a list of five steps is
/// five guesses at rooms nobody described, and the distance between audible in
/// a car and rude in a waiting room is a slide, not a menu.
///
/// Made as forgiving as a slider gets: a tall track, a large thumb, both ends
/// pressable as targets in their own right for the two positions actually
/// wanted most, and nothing written until the finger lifts.
Future<void> chooseVolume(
  BuildContext context, {
  required ProfileSettings settings,
  required SymbolResolver? resolver,
  SpeechEngine? speech,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _VolumeDialog(settings: settings, resolver: resolver, speech: speech),
);

class _VolumeDialog extends StatefulWidget {
  const _VolumeDialog({
    required this.settings,
    required this.resolver,
    this.speech,
  });

  final ProfileSettings settings;
  final SymbolResolver? resolver;
  final SpeechEngine? speech;

  @override
  State<_VolumeDialog> createState() => _VolumeDialogState();
}

class _VolumeDialogState extends State<_VolumeDialog> {
  late double _value = widget.settings.speechVolume.clamp(
    volumeQuietest.value,
    volumeLoudest.value,
  );

  /// Writes it, then says something at it.
  ///
  /// Hearing the result is the only way to judge a volume: the position of a
  /// thumb on a track cannot tell anybody whether they will be heard across a
  /// room. Spoken on release rather than on every frame, so a drag does not
  /// stammer.
  Future<void> _commit(double value) async {
    setState(() => _value = value);
    await widget.settings.set('speechVolume', value);
    await widget.speech?.setVolume(value);
    await widget.speech?.speak(volumeSample);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('How loud?'),
    // Tight to its contents: this dialog is a slider and two labels, and an
    // unbounded content box let it grow to the height of the screen.
    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SliderEnd(
                label: volumeQuietest.label,
                resolver: widget.resolver,
                onTap: () => _commit(volumeQuietest.value),
              ),
              Expanded(
                // **Slider takes `constraints.maxHeight` whenever it is bounded.**
                // Inside a dialog it is, so an unbounded one grew the card to the
                // height of the screen for a control that is one row tall. Given a
                // height, it draws at that height.
                child: SizedBox(
                  height: 72,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 18,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 18,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 34,
                      ),
                    ),
                    child: Slider(
                      value: _value,
                      min: volumeQuietest.value,
                      max: volumeLoudest.value,
                      onChanged: (v) => setState(() => _value = v),
                      onChangeEnd: _commit,
                    ),
                  ),
                ),
              ),
              _SliderEnd(
                label: volumeLoudest.label,
                resolver: widget.resolver,
                onTap: () => _commit(volumeLoudest.value),
              ),
            ],
          ),
          // Under the middle of the track, where the value it sets is. Both a
          // label and a target: back to ordinary is the move somebody makes
          // most often after trying an end, and hunting for the middle of a
          // slider with an unsteady hand is the worst way to make it.
          TextButton(
            onPressed: () => _commit(volumeNormal.value),
            child: Text(
              volumeNormal.label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      ),
    ],
  );
}

/// One end of the slider: a picture, the word, and a target that jumps there.
class _SliderEnd extends StatelessWidget {
  const _SliderEnd({
    required this.label,
    required this.resolver,
    required this.onTap,
  });

  final String label;
  final SymbolResolver? resolver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resolver = this.resolver;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 84,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            // Sized to what is in it. An `Expanded` picture here made the row
            // as tall as whatever the dialog was willing to give it, which for
            // two small labels and a slider was most of the screen.
            mainAxisSize: MainAxisSize.min,
            children: [
              // From the packs the board itself draws from, so it is the same
              // drawing the person already knows. Where the pack has nothing
              // for it the word stands in, exactly as an unfetched picture does
              // anywhere else on the board.
              if (resolver != null)
                SizedBox(
                  height: 44,
                  child: SymbolView(
                    resolver: resolver,
                    label: label,
                    packIds: boardSymbolPackIds,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a tone, drawn as tiles with pictures.
///
/// "Quiet" is not on this list and never was a tone — see [Tone.quiet].
Future<void> chooseTone(
  BuildContext context, {
  required ProfileSettings settings,
  required SymbolResolver? resolver,
  SpeechEngine? speech,
  String? sentence,
}) async {
  final current = settings.tone;

  final chosen = await showDialog<Tone>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How should it sound?'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (settings.neuralVoice) ...[
              const NeuralIncompatible('Tone'),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final tone in Tone.offeredTones)
                  _ToneTile(
                    tone: tone,
                    resolver: resolver,
                    chosen: tone == current,
                    onTap: () => Navigator.of(context).pop(tone),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (chosen == null) return;

  await settings.set('tone', chosen.name);

  // Spoken in the tone that was picked, for the same reason the volume speaks
  // back: the name of a way of speaking is not the way it sounds.
  final voice = applyTone(
    chosen,
    rate: settings.speechRate,
    pitch: settings.speechPitch,
    volume: settings.speechVolume,
  );
  await speech?.setRate(voice.rate);
  await speech?.setPitch(voice.pitch);
  await speech?.setVolume(voice.volume);

  // The sentence they are actually holding, said the new way — which is the
  // only thing that answers "is this the right tone for this?". A fixed sample
  // demonstrates the tone; their own words demonstrate the decision. Falls back
  // to the sample when the bar is empty, because there is nothing else to say.
  final say = sentence == null || sentence.trim().isEmpty
      ? volumeSample
      : sentence;
  await speech?.speak(say);
}

class _ToneTile extends StatelessWidget {
  const _ToneTile({
    required this.tone,
    required this.resolver,
    required this.chosen,
    required this.onTap,
  });

  final Tone tone;
  final SymbolResolver? resolver;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resolver = this.resolver;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: chosen ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 130,
          height: 130,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                if (resolver != null)
                  Expanded(
                    child: SymbolView(
                      resolver: resolver,
                      label: tone.label,
                      packIds: boardSymbolPackIds,
                    ),
                  ),
                Text(
                  tone.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says that a control does nothing while the neural voice is speaking (§4.83).
///
/// **Said rather than hidden, and said rather than left to be discovered.** A
/// dial that silently does nothing is a control a person learns to distrust,
/// and the thing they distrust afterwards is the board. Hiding it instead
/// would be worse: the setting is real, it is what the device voice uses, and
/// it comes back the moment the neural voice is switched off.
///
/// What is actually incompatible, and why: the neural voice speaks from clips
/// baked ahead of time. Tone is rate, pitch and volume applied at speaking
/// time, and Kokoro has no pitch at all; sentence-final punctuation buys its
/// rising intonation from the platform engine reading the mark, which a clip
/// that was baked before the mark existed cannot do.
class NeuralIncompatible extends StatelessWidget {
  const NeuralIncompatible(this.what, {super.key});

  final String what;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFFCC80)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 20, color: Color(0xFFE65100)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$what is not compatible with the neural voice. It still applies '
            'to the device voice.',
            style: const TextStyle(fontSize: 13, color: Color(0xFFE65100)),
          ),
        ),
      ],
    ),
  );
}

/// The favorites list, drawn like the All Categories sheet it sits beside.
///
/// **A favorite is a shortcut, not a location.** Nothing in this dialog places
/// a button, moves one, or changes the board in any way — see
/// [ProfileSettings.favorites]. Somebody with fifty favorites and somebody
/// with none are looking at the same board, with the same words in the same
/// places, and a favorite that is also on the board is reached by either route
/// without the two disagreeing.
class FavoritesSheet extends StatefulWidget {
  const FavoritesSheet({
    super.key,
    required this.settings,
    required this.resolver,
    required this.color,
    required this.onAdd,
  });

  final ProfileSettings settings;
  final SymbolResolver? resolver;

  /// Drawn in the system color, like a category key: these are controls that
  /// reach words, not words. Taken from the caller so it comes from the same
  /// function the board uses.
  final Color color;

  /// Finds a word to add — from the board or typed — and returns it, or null
  /// if nothing was chosen. The finder belongs to the talk screen, which has
  /// the board and the voice; this dialog only says where the answer goes.
  final Future<String?> Function() onAdd;

  /// Opens it, and returns the word to say, or null if nothing was pressed.
  static Future<String?> show(
    BuildContext context, {
    required ProfileSettings settings,
    required SymbolResolver? resolver,
    required Color color,
    required Future<String?> Function() onAdd,
  }) => showDialog<String>(
    context: context,
    builder: (context) => FavoritesSheet(
      settings: settings,
      resolver: resolver,
      color: color,
      onAdd: onAdd,
    ),
  );

  @override
  State<FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<FavoritesSheet> {
  Future<void> _add() async {
    final word = await widget.onAdd();
    if (word == null || word.isEmpty) return;
    await widget.settings.addFavorite(word);
    if (mounted) setState(() {});
  }

  /// Removal is a hold and then a confirmation, and both halves are on purpose.
  ///
  /// A tap removes nothing: on this grid the difference between the word
  /// somebody wanted and the one beside it is a few millimetres, and a list
  /// that loses a word to a mis-reach is a list nobody can trust to still hold
  /// what they put in it.
  Future<void> _remove(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “$label”?'),
        content: const Text(
          'It stays on the board. This only takes it off the favorites list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.settings.removeFavorite(label);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final favorites = widget.settings.favorites;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Favorites',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Flexible(
                child: GridView.extent(
                  shrinkWrap: true,
                  // Square and the same size as the category sheet's, so a
                  // word here reads as the same kind of thing as a word there.
                  maxCrossAxisExtent: 150,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final favorite in favorites)
                      _FavoriteCell(
                        label: favorite.label,
                        color: widget.color,
                        resolver: widget.resolver,
                        onTap: () =>
                            Navigator.of(context).pop(favorite.message),
                        onLongPress: () => _remove(favorite.label),
                      ),
                    // Last, not first. A tile that added a word would sit where
                    // the first favorite goes, and the first favorite is the
                    // one most likely to be reached for without looking.
                    _AddFavoriteCell(onTap: _add),
                  ],
                ),
              ),
              if (favorites.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Add a word to keep it here. Hold a favorite to remove it.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteCell extends StatelessWidget {
  const _FavoriteCell({
    required this.label,
    required this.color,
    required this.resolver,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final Color color;
  final SymbolResolver? resolver;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final resolver = this.resolver;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Center(
            child: resolver == null
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  )
                : SymbolView(
                    resolver: resolver,
                    label: label,
                    packIds: boardSymbolPackIds,
                  ),
          ),
        ),
      ),
    );
  }
}

class _AddFavoriteCell extends StatelessWidget {
  const _AddFavoriteCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 36),
              SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Add a word',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
