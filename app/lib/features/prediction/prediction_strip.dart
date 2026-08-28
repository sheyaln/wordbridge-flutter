import 'dart:async';

import 'package:flutter/material.dart';

/// The row of suggested next words.
///
/// It sits outside the grid and never reaches into it. Predictive *reordering*
/// — rearranging the board to put likely words under the finger — is the one
/// thing that reliably prevents a motor plan forming, so the suggestions get
/// their own strip and the board is left alone.
///
/// Two rules make the strip itself safe to reach for:
///
/// **Fixed slots.** The width is divided evenly and a word is drawn inside its
/// slot. Sizing each chip to its text would mean the third suggestion sat in a
/// different place depending on how long the first two words were.
///
/// **It settles.** The contents change after every word, so the same spot holds
/// something new a moment later. A finger already on its way down when that
/// happens is ignored for the same delay the boards use.
class PredictionStrip extends StatefulWidget {
  const PredictionStrip({
    super.key,
    required this.words,
    required this.onSelect,
    this.slots = 5,
    this.settleDelay = const Duration(milliseconds: 500),
  });

  final List<String> words;
  final ValueChanged<String> onSelect;

  /// How many places the strip has. Constant, so an empty one still holds its
  /// position rather than letting the others spread out.
  final int slots;

  final Duration settleDelay;

  /// Tall enough for a comfortable target, short enough that what it costs the
  /// grid stays small.
  static const height = 56.0;

  @override
  State<PredictionStrip> createState() => _PredictionStripState();
}

class _PredictionStripState extends State<PredictionStrip> {
  bool _settling = false;
  Timer? _settleTimer;

  @override
  void didUpdateWidget(PredictionStrip old) {
    super.didUpdateWidget(old);
    if (!_sameWords(old.words, widget.words)) _settle();
  }

  static bool _sameWords(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _settle() {
    if (widget.settleDelay <= Duration.zero) return;

    _settleTimer?.cancel();
    _settling = true;
    _settleTimer = Timer(widget.settleDelay, () {
      if (mounted) setState(() => _settling = false);
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PredictionStrip.height,
      color: const Color(0xFFEFEFEF),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: AbsorbPointer(
        absorbing: _settling,
        child: Row(
          children: [
            for (var slot = 0; slot < widget.slots; slot++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _Slot(
                    word: slot < widget.words.length
                        ? widget.words[slot]
                        : null,
                    onTap: widget.onSelect,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One place in the strip, with or without a word in it.
///
/// An empty slot is a hole, not a button. It takes no tap and speaks nothing,
/// for the same reason a masked cell does not: the user cannot see a word
/// there, so nothing may happen when they touch it.
class _Slot extends StatelessWidget {
  const _Slot({required this.word, required this.onTap});

  final String? word;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final word = this.word;

    if (word == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x11000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const SizedBox.expand(),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => onTap(word),
        borderRadius: BorderRadius.circular(6),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Color(0xFF212121)),
            ),
          ),
        ),
      ),
    );
  }
}
