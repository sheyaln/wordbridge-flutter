import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../grid/grid_geometry.dart';
import '../speech/speech_engine.dart';

/// Gap between keys, and between the keys and the edge of the block.
const _gutter = 6.0;

/// Flex units across a row. Every row spends exactly this many, so the block
/// is a rectangle and the ends of one row line up with the ends of the next.
const _units = 20;

/// Typing a word the board does not hold.
///
/// A board holds the words somebody put on it, which is most of what a person
/// says and never all of it: a friend's name, the name of a game, the word for
/// whatever happened at school today. Without somewhere to spell one, those
/// words are simply unavailable and the person is left pointing at something
/// near enough.
///
/// **Nothing is spoken until the word is finished.** A keyboard that says each
/// letter as it lands turns one word into five noises, and the five are not
/// what is being said — the person listening hears "d, r, i, n, k" and has to
/// assemble it, or looks away before the word arrives. Letters are the means;
/// the word is the utterance. So the letters are silent and the finished word
/// is spoken once, when it is sent.
///
/// The word is handed to [onWord] and then forgotten. Whether a word typed
/// twice should be offered a location of its own is a real question and not
/// this widget's: it types, it speaks, it takes nothing from the board.
///
/// ## Why QWERTY
///
/// Because it is the layout on every other keyboard the person touches — the
/// school iPad, a phone, a sibling's laptop — and this one is reached for
/// rarely, so nearly all of the practice behind it is practice that happened
/// somewhere else. The rows sit where the iPad's own keyboard puts them,
/// backspace right of `m` and the action key at the bottom right, so that
/// carry-over is as complete as it can be.
///
/// ABC order is a legitimate preference and a better one for somebody: a child
/// who has the alphabet and has never met a keyboard can reason out where `m`
/// is, where on QWERTY they can only hunt. If it becomes a setting it belongs
/// with the other per-profile choices made at setup, because changing it once
/// somebody has practised on one order is the kind of move the rest of the app
/// refuses to make.
///
/// There is no shift and no number row. A key that changes what the keys around
/// it mean is a keyboard with more than one layout, and one fixed place per
/// letter is worth more here than capitals are — nothing about how a word is
/// spoken depends on its case.
class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({super.key, this.speech, this.onWord, this.onClose});

  /// The voice the finished word comes out in.
  ///
  /// Null only where there is nothing to hand it; the keyboard then builds its
  /// own, which speaks in the device's voice rather than the one the caregiver
  /// chose. Pass the talk screen's engine wherever there is one, so a typed
  /// word sounds like every other word the board says.
  final SpeechEngine? speech;

  /// The finished word, **already spoken**.
  ///
  /// Whatever is wired here must not speak it again. Two goes at one word is
  /// one word nobody can make out.
  final void Function(String word)? onWord;

  /// Puts the keyboard away with nothing said.
  ///
  /// Null where there is nowhere to go, and then no close key is drawn: a key
  /// that answers a touch with nothing is worse than no key.
  final VoidCallback? onClose;

  /// Ids for the keys that are not a character. Every other key's id is the
  /// character it types.
  static const backspace = 'backspace';
  static const space = 'space';
  static const send = 'send';
  static const close = 'close';

  /// The keys, row by row, in the order they are drawn and in the only order
  /// they are ever drawn. Nothing here depends on what has been typed, so no
  /// key moves for the whole of a session.
  static const rows = <List<String>>[
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    // The apostrophe ends the home row, where a full keyboard keeps it. It
    // earns the place on its own: "don't" and "can't" are core vocabulary.
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', "'"],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', backspace],
    [space, send],
  ];

  /// Where a key is, for anything that needs to find one.
  static Key keyFor(String id) => ValueKey('key:$id');

  /// The typed word, when there is one. Absent while the field is empty.
  static const fieldKey = ValueKey('typed');

  /// The narrowest box the keys fit in with every one of them still a
  /// comfortable target — a letter key is the smallest, at two units wide.
  static const minWidth =
      (GridGeometry.minTouchTarget - _gutter) / 2 * _units +
      _gutter * (_units + 1);

  /// The shortest, at four rows.
  static const minHeight = GridGeometry.minTouchTarget * 4 + _gutter * 5;

  /// Opens the keyboard over the board. Returns the word that was said, or
  /// null if it was put away without saying one.
  static Future<String?> show(BuildContext context, {SpeechEngine? speech}) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => FractionallySizedBox(
          heightFactor: 0.75,
          child: OnScreenKeyboard(
            speech: speech,
            onWord: (word) => Navigator.of(sheet).pop(word),
            onClose: () => Navigator.of(sheet).pop(),
          ),
        ),
      );

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  late final SpeechEngine _speech = widget.speech ?? FlutterTtsEngine();
  bool _started = false;

  /// Exactly what has been pressed, spaces and all.
  String _typed = '';

  /// What would be said. Spaces at either end are typing, not speech.
  String get _word => _typed.trim();

  void _press(String id) {
    if (id == OnScreenKeyboard.send) {
      _send();
      return;
    }
    setState(() {
      if (id == OnScreenKeyboard.backspace) {
        _typed = _typed.substring(0, _typed.length - 1);
      } else if (id == OnScreenKeyboard.space) {
        _typed = '$_typed ';
      } else {
        _typed = '$_typed$id';
      }
    });
  }

  /// Says the word, once, and clears the field for the next one.
  ///
  /// Speech is started before anything else happens and is never waited on: a
  /// caller that closes the keyboard on the word should close it now, not when
  /// the synthesiser has finished the last syllable, and nothing [onWord] does
  /// — or fails to do — can come between the person and the word.
  void _send() {
    final word = _word;
    unawaited(_say(word));
    setState(() => _typed = '');
    widget.onWord?.call(word);
  }

  Future<void> _say(String word) async {
    try {
      if (!_started) {
        _started = true;
        await _speech.init();
      }
      await _speech.speak(word);
    } catch (_) {
      // A voice that failed is bad. A keyboard that took the screen down with
      // it leaves the person with neither the word nor the board.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _Field(typed: _typed, onClose: widget.onClose),
            const SizedBox(height: 12),
            Expanded(
              child: _Keys(
                onPress: _press,
                canBackspace: _typed.isNotEmpty,
                canSend: _word.isNotEmpty,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What has been typed so far, at a size that reads from arm's length.
///
/// The one thing on the keyboard that changes as keys are pressed, and it sits
/// above them in a box of its own height, so a longer word never moves a key.
class _Field extends StatelessWidget {
  const _Field({required this.typed, required this.onClose});

  final String typed;
  final VoidCallback? onClose;

  static const _height = 84.0;
  static const _close = GridGeometry.minTouchTarget + 8;

  @override
  Widget build(BuildContext context) {
    final onClose = this.onClose;

    return Container(
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCFD8DC), width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: typed.isEmpty
                ? const Text(
                    'type a word',
                    style: TextStyle(fontSize: 30, color: Color(0xFF90A4AE)),
                  )
                : Text(
                    typed,
                    key: OnScreenKeyboard.fieldKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF102027),
                    ),
                  ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 12),
            // Up here rather than among the keys, and nowhere near backspace:
            // it is the one control that throws the whole word away.
            SizedBox(
              key: OnScreenKeyboard.keyFor(OnScreenKeyboard.close),
              width: _close,
              height: _close,
              child: Material(
                color: const Color(0xFFECEFF1),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClose,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 26,
                    color: Color(0xFF546E7A),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The keys, placed absolutely from the measured box.
///
/// The same arithmetic the boards use, for the same reason: a flow layout
/// shifts a target by a pixel or two between rebuilds, which is invisible and
/// quietly ruinous to anybody who has stopped looking at their fingers.
///
/// Keys never shrink below [GridGeometry.minTouchTarget]. A box too small for
/// that scrolls instead, because a key under a fingertip's width is a key that
/// gets mistyped, and a mistyped letter is a word nobody said.
class _Keys extends StatelessWidget {
  const _Keys({
    required this.onPress,
    required this.canBackspace,
    required this.canSend,
  });

  final void Function(String id) onPress;

  /// There has to be a letter to take back, and something to say. Both keys
  /// stay where they are and go dim rather than disappearing.
  final bool canBackspace;
  final bool canSend;

  static int _spanOf(String id) {
    if (id == OnScreenKeyboard.space) return 14;
    if (id == OnScreenKeyboard.backspace || id == OnScreenKeyboard.send) {
      return 6;
    }
    return 2;
  }

  bool _enabled(String id) {
    if (id == OnScreenKeyboard.backspace) return canBackspace;
    if (id == OnScreenKeyboard.send) return canSend;
    return true;
  }

  List<Widget> _placed(GridGeometry geometry) {
    final keys = <Widget>[];

    for (var row = 0; row < OnScreenKeyboard.rows.length; row++) {
      var col = 0;
      for (final id in OnScreenKeyboard.rows[row]) {
        final span = _spanOf(id);
        keys.add(
          Positioned.fromRect(
            rect: geometry.rectFor(row, col, spanCols: span),
            child: _Key(
              key: OnScreenKeyboard.keyFor(id),
              id: id,
              onTap: _enabled(id) ? () => onPress(id) : null,
            ),
          ),
        );
        col += span;
      }
    }

    return keys;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(box.maxWidth, OnScreenKeyboard.minWidth);
        final unit = (width - _gutter * (_units + 1)) / _units;

        // Square-ish keys, however tall the box is. A key three times taller
        // than it is wide is not a better target, only a stranger one.
        final natural =
            (unit * 2 + _gutter) * OnScreenKeyboard.rows.length +
            _gutter * (OnScreenKeyboard.rows.length + 1);
        final available = box.maxHeight.isFinite ? box.maxHeight : natural;
        final height = math.max(
          math.min(available, natural),
          OnScreenKeyboard.minHeight,
        );

        final geometry = GridGeometry(
          rows: OnScreenKeyboard.rows.length,
          cols: _units,
          size: Size(width, height),
          gutter: _gutter,
        );

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: available),
            // Against the bottom of the sheet, where the hands already are.
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(children: _placed(geometry)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.id, required this.onTap});

  final String id;

  /// Null while there is nothing for this key to do.
  final VoidCallback? onTap;

  static const _face = Color(0xFFECEFF1);
  static const _ink = Color(0xFF102027);
  static const _offFace = Color(0xFFF5F5F5);
  static const _offInk = Color(0xFFBDBDBD);

  /// The green of the utterance bar's speak button, because it is the same
  /// act: this is where a word becomes speech.
  static const _sendFace = Color(0xFFDCEDC8);
  static const _sendInk = Color(0xFF1B5E20);

  Widget _content(Color ink) {
    if (id == OnScreenKeyboard.backspace) {
      return Icon(Icons.backspace_outlined, size: 26, color: ink);
    }
    if (id == OnScreenKeyboard.send) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.volume_up_rounded, size: 26, color: ink),
          Text(
            'say it',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      );
    }
    if (id == OnScreenKeyboard.space) {
      return Text('space', style: TextStyle(fontSize: 18, color: ink));
    }
    return Text(
      id,
      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: ink),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final isSend = id == OnScreenKeyboard.send;
    final radius = BorderRadius.circular(8);

    return Material(
      color: enabled ? (isSend ? _sendFace : _face) : _offFace,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _content(enabled ? (isSend ? _sendInk : _ink) : _offInk),
          ),
        ),
      ),
    );
  }
}
