import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../speech/speech_engine.dart';

/// The words this board speaks when everything else has failed.
///
/// The same words the seed marks `essential: true` — the ones a grid too small
/// to hold them is refused over. Written out here rather than read from the
/// vocabulary because this board exists for the case where reading anything
/// has stopped working; `fallback_board_test.dart` holds the two lists to each
/// other so they cannot drift apart in silence.
///
/// Ordered by urgency rather than by the order the seed declares them. On a
/// working board the order is a motor plan and nothing may disturb it; here
/// there is no motor plan to protect, because the layout was in the database
/// and the database is what failed. What is left to get right is which word is
/// found first, and it is `help`.
const fallbackWords = <String>[
  'help',
  'stop',
  'wait',
  'no',
  'yes',
  'not',
  "don't",
  'want',
  'more',
  'I',
  'you',
  'finished',
  'what',
  'where',
];

/// A board that speaks when nothing else can.
///
/// §5 non-negotiable 6: a crash never leaves a user with nothing. What that
/// costs is stated rather than hidden — these are not the locations the person
/// learned, and they cannot be, so the strip along the top says the board is
/// broken rather than letting an unfamiliar layout read as one that rearranged
/// itself.
///
/// It depends on nothing that can have failed. No database, no symbol packs, no
/// profile, no settings, and no Material ancestor — this is inserted by
/// [ErrorWidget.builder], which can land above the widget that would have
/// provided a theme. Its speech engine is its own for the same reason, which
/// also means the system voice rather than the caregiver's chosen one: that
/// choice lives in the database.
class FallbackBoard extends StatefulWidget {
  const FallbackBoard({super.key, this.speech, this.detail});

  /// Left null outside tests, so the board builds its own rather than being
  /// handed one that may be part of what went wrong.
  final SpeechEngine? speech;

  /// What failed, for whoever is helping. Never the only thing on screen.
  final String? detail;

  @override
  State<FallbackBoard> createState() => _FallbackBoardState();
}

class _FallbackBoardState extends State<FallbackBoard> {
  late final SpeechEngine _speech = widget.speech ?? FlutterTtsEngine();
  bool _started = false;

  /// One tap, one word, no utterance bar.
  ///
  /// Building a sentence needs somewhere to hold it and something to send it
  /// with, and both are more to go wrong. Speaking on the tap is the shortest
  /// path there is between a person and a word.
  Future<void> _say(String word) async {
    try {
      if (!_started) {
        _started = true;
        await _speech.init();
      }
      await _speech.speak(word);
    } catch (_) {
      // Nothing to report it to and nowhere to report it. A key that stays
      // silent is bad; a crash inside the crash board is worse.
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset =
        MediaQuery.maybeOf(context)?.padding ?? const EdgeInsets.all(20);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF102027),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            math.max(inset.left, 12),
            math.max(inset.top, 12),
            math.max(inset.right, 12),
            math.max(inset.bottom, 12),
          ),
          child: Column(
            children: [
              _Banner(detail: widget.detail),
              const SizedBox(height: 12),
              Expanded(child: _Grid(onSay: _say)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Something went wrong. These words still work.',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'This is not the usual board and the words are not in their usual '
          'places. Nothing has been lost.',
          style: TextStyle(fontSize: 13, color: Color(0xFFB0BEC5)),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF78909C)),
          ),
        ],
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.onSay});

  final void Function(String) onSay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Cells as near square as the count and the box allow, which is the
        // largest a button can be — and on a board reached by somebody in
        // trouble, size is the only affordance that matters.
        final cols = math
            .sqrt(fallbackWords.length * box.maxWidth / box.maxHeight)
            .round()
            .clamp(2, fallbackWords.length);
        final rows = (fallbackWords.length / cols).ceil();

        return Column(
          children: [
            for (var row = 0; row < rows; row++)
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < cols; col++)
                      Expanded(
                        child: row * cols + col < fallbackWords.length
                            ? _Key(
                                word: fallbackWords[row * cols + col],
                                onSay: onSay,
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.word, required this.onSay});

  final String word;
  final void Function(String) onSay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onSay(word),
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFECEFF1),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          word,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Color(0xFF102027),
          ),
        ),
      ),
    );
  }
}
