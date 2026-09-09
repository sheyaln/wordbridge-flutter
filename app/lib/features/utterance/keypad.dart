import 'package:flutter/material.dart';

import 'numbers.dart';

/// Typing a number instead of counting to it (§4.77).
///
/// The numbers board holds ten keys, for the reason the seed gives: ten is one
/// row and one movement wide, and a row that scans in one sweep is worth more
/// than a row that holds more numbers. That is right about the *row*, and it
/// leaves a person unable to say a house number, a bus, a price, a date or a
/// phone number without pressing digits one at a time and hoping the joining
/// setting is on.
///
/// So this is the other way to a number, and it is deliberately not the board:
/// a pad is opened, used and closed, and nothing on it is a location anybody
/// has to learn. The keys underneath never move.
///
/// **The digits always join here, whatever the joining setting says.** That
/// setting answers a question about the *board* — whether somebody pressing
/// `1` then `2` on the counting row means twelve or means one, two — and it is
/// a real question, because on that row both are things people do. On a pad
/// there is no question: nobody opens a number pad to say "one, two".
class Keypad extends StatefulWidget {
  const Keypad({super.key, this.onDigit});

  /// Says a digit as it is pressed, if the caller wants that.
  ///
  /// Every key in this app speaks when it is tapped, and a key that stays
  /// silent reads as a press that did not register — so the person presses it
  /// again and the number gains a digit nobody meant. The digit is spoken
  /// rather than the number so far, because "one, twelve, one hundred and
  /// twenty three" is three answers to a question nobody asked.
  final Future<void> Function(String digit)? onDigit;

  /// Opens the pad, and returns the digits typed — or null if nothing was.
  static Future<String?> show(
    BuildContext context, {
    Future<void> Function(String digit)? onDigit,
  }) => showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(child: Keypad(onDigit: onDigit)),
  );

  /// As many digits as anybody types in one go.
  ///
  /// A phone number is the long case and the reason this is not
  /// [maxJoinedDigits], which caps the *board's* joining at four on the
  /// argument that a fifth press there is more likely somebody pressing keys
  /// than somebody saying a number. On a pad, pressing keys is the point.
  static const maxDigits = 15;

  @override
  State<Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<Keypad> {
  final _digits = StringBuffer();

  /// The calculator arrangement, which is the one on a keyboard's own pad and
  /// on every calculator anybody has held: low row at the bottom, zero under
  /// it. A phone lays it out the other way up, and a person who has learned
  /// one of the two is faster on it than on a grid they have to read.
  static const _rows = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
  ];

  String get _typed => _digits.toString();

  Future<void> _press(String digit) async {
    if (_typed.length >= Keypad.maxDigits) return;
    setState(() => _digits.write(digit));
    await widget.onDigit?.call(digit);
  }

  void _backspace() {
    if (_typed.isEmpty) return;
    final kept = _typed.substring(0, _typed.length - 1);
    setState(() {
      _digits.clear();
      _digits.write(kept);
    });
  }

  /// What the number reads as, under the digits being typed.
  ///
  /// Confirmation before it is said out loud, which is the whole reason the pad
  /// holds its digits rather than putting each one into the sentence: a wrong
  /// digit is deleted here, in front of the person who typed it, instead of
  /// being spoken and then repaired in the bar.
  ///
  /// Blank past four digits, which is where [numberInWords] hands back the
  /// digits it was given. That is the right answer — nobody says a phone
  /// number as a number, and a voice reading one out digit by digit is what
  /// anybody wants — and printing the digits underneath themselves says
  /// nothing.
  String get _spoken {
    final value = int.tryParse(_typed);
    if (value == null) return '';
    final words = numberInWords(value);
    return words == _typed ? '' : words;
  }

  @override
  Widget build(BuildContext context) {
    final empty = _typed.isEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Type a number',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Back to the board',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // The digits, large, with the words under them. Both, because the
            // digits are what lands in the sentence and the words are what
            // comes out of the speaker, and somebody checking their own number
            // is checking one or the other.
            Container(
              height: 76,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    empty ? '0' : _typed,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: empty ? Colors.black26 : Colors.black87,
                    ),
                  ),
                  if (!empty && _spoken.isNotEmpty)
                    Text(
                      _spoken,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            for (final row in _KeypadState._rows) ...[
              Row(
                children: [
                  for (final digit in row) ...[
                    Expanded(child: _Key(digit, onTap: () => _press(digit))),
                    if (digit != row.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Zero on the bottom row with delete beside it, which is where a
            // calculator puts both. The third cell is left empty rather than
            // filled with something: a key next to delete that does something
            // else is a key that gets pressed instead of it.
            Row(
              children: [
                Expanded(child: _Key('0', onTap: () => _press('0'))),
                const SizedBox(width: 8),
                Expanded(
                  child: _Key.icon(
                    Icons.backspace_outlined,
                    tooltip: 'Delete a digit',
                    onTap: empty ? null : _backspace,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 16),

            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: empty ? null : () => Navigator.of(context).pop(_typed),
              child: const Text('Add to the sentence'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label, {required this.onTap}) : icon = null, tooltip = null;

  const _Key.icon(this.icon, {required this.tooltip, required this.onTap})
    : label = '';

  final String label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final key = Material(
      color: onTap == null ? const Color(0xFFF5F5F5) : const Color(0xFFE8EAF0),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        // Bigger than the 44pt floor the grid holds to. A pad is typed at
        // speed by somebody who is not aiming carefully, and there is room
        // here that a board does not have.
        child: SizedBox(
          height: 56,
          child: Center(
            child: icon == null
                ? Text(
                    label,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: onTap == null ? Colors.black26 : Colors.black87,
                    ),
                  )
                : Icon(
                    icon,
                    size: 24,
                    color: onTap == null ? Colors.black26 : Colors.black87,
                  ),
          ),
        ),
      ),
    );

    return tooltip == null ? key : Tooltip(message: tooltip!, child: key);
  }
}
