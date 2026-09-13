import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import '../backup/recovery.dart';
import '../backup/snapshot.dart';
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
  'finish',
  'what',
  'where',
];

/// How long the corner is held to reach the way back.
///
/// The device's own caregiver gesture and its duration are rows in the
/// database, so this board cannot read them and states its own. Long enough
/// that neither a hand resting on a tablet nor a user exploring a grid
/// produces it, short enough to be described in the one sentence the banner
/// has room for.
const recoveryHold = Duration(seconds: 3);

/// The way in for anyone who cannot hold a point.
///
/// Switch access, VoiceOver and eye-gaze dwell all drive a board like this one
/// and none of them holds a corner, so a held gesture alone would put the only
/// way back behind a hand some users do not have. A custom action is offered
/// by assistive technology on request and cannot be produced by a touch, which
/// is the same bargain the hold makes, from the other side.
const recoveryAction = CustomSemanticsAction(
  label: 'Caregiver: restore a backup',
);

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
///
/// [recovery] is the only thing here that touches the disk, and it sits behind
/// [recoveryHold] or [recoveryAction]. Nothing it does happens while this
/// board is being drawn, and a device that cannot even list its backups says
/// so on the recovery screen rather than taking this one down with it.
class FallbackBoard extends StatefulWidget {
  const FallbackBoard({
    super.key,
    this.speech,
    this.detail,
    this.recovery,
    this.onRelaunch,
  });

  /// Left null outside tests, so the board builds its own rather than being
  /// handed one that may be part of what went wrong.
  final SpeechEngine? speech;

  /// What failed, for whoever is helping. Never the only thing on screen.
  final String? detail;

  /// The way back to a backup.
  ///
  /// Null leaves this board what it is: fourteen words and no door. A caller
  /// that can say where the database file sits passes one, and the banner then
  /// says how to reach it.
  final BoardRecovery? recovery;

  /// Starts the app over on a board that has just been put back.
  ///
  /// Null is a supported answer and costs the caregiver a relaunch by hand,
  /// which the screen tells them to do either way.
  final VoidCallback? onRelaunch;

  @override
  State<FallbackBoard> createState() => _FallbackBoardState();
}

class _FallbackBoardState extends State<FallbackBoard> {
  late final SpeechEngine _speech = widget.speech ?? FlutterTtsEngine();
  bool _started = false;

  /// Whether the words have been swapped for the way back.
  ///
  /// Only ever set by the hold or the custom action, and the way out of it is
  /// the first control on the screen.
  bool _recovering = false;

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
    final recovery = widget.recovery;

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
              Stack(
                children: [
                  _Banner(detail: widget.detail, recoverable: recovery != null),
                  if (recovery != null && !_recovering)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: _RecoveryDoor(
                        onOpen: () => setState(() => _recovering = true),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: recovery != null && _recovering
                    ? _Recovery(
                        recovery: recovery,
                        onRelaunch: widget.onRelaunch,
                        onClose: () => setState(() => _recovering = false),
                      )
                    : _Grid(onSay: _say),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({this.detail, this.recoverable = false});

  final String? detail;
  final bool recoverable;

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
        // Printed rather than left to be discovered. Every other door in this
        // app is hidden from the person holding the tablet on purpose; this
        // one has to be findable by an adult who has never seen this screen and
        // is holding a device that will not talk.
        if (recoverable) ...[
          const SizedBox(height: 2),
          Text(
            'Caregiver: hold the top left corner for '
            '${recoveryHold.inSeconds} seconds to restore a backup.',
            style: const TextStyle(fontSize: 13, color: Color(0xFFB0BEC5)),
          ),
        ],
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

/// The held corner that opens the way back, and the action that opens it
/// without a hold.
///
/// Over the banner rather than over a key. The words underneath are the only
/// thing on this screen anybody is trying to use, and a door that could
/// swallow one of them would be the fallback board failing at the one job it
/// has.
class _RecoveryDoor extends StatefulWidget {
  const _RecoveryDoor({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_RecoveryDoor> createState() => _RecoveryDoorState();
}

class _RecoveryDoorState extends State<_RecoveryDoor>
    with SingleTickerProviderStateMixin {
  static const _size = 56.0;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: recoveryHold)
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          _reset();
          widget.onOpen();
        });

  Timer? _reveal;
  bool _visible = false;

  void _start(_) {
    // Nothing is drawn for the first quarter of the hold, so a stray touch
    // never learns there is anything here.
    _reveal = Timer(recoveryHold ~/ 4, () {
      if (mounted) setState(() => _visible = true);
    });
    _controller.forward(from: 0);
  }

  void _reset([_]) {
    _reveal?.cancel();
    // The door comes off the board the moment it opens, and the release that
    // ends the hold is still routed to it: a pointer's later events go to
    // whatever the press hit, mounted or not.
    if (!mounted) return;

    _controller.stop();
    _controller.value = 0;
    if (_visible) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Caregiver recovery',
      customSemanticsActions: {recoveryAction: widget.onOpen},
      child: Listener(
        onPointerDown: _start,
        onPointerUp: _reset,
        onPointerCancel: _reset,
        // Translucent, so every touch also reaches whatever is underneath.
        behavior: HitTestBehavior.translucent,
        child: SizedBox(
          width: _size,
          height: _size,
          child: _visible
              ? AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => Align(
                    alignment: Alignment.bottomLeft,
                    child: FractionallySizedBox(
                      widthFactor: _controller.value,
                      heightFactor: 0.08,
                      child: const ColoredBox(color: Color(0xFF78909C)),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// What a caregiver can do about a board that will not open.
///
/// Drawn with nothing above `package:flutter/widgets.dart`, like the board it
/// sits inside: it is reached from a screen that may have been inserted above
/// the app's own [Navigator] and theme, so there is no route to push and no
/// Material to sit on.
///
/// Every sentence names what is about to be replaced and what is kept. A
/// caregiver here is guessing already, and what makes a guess safe is knowing
/// the board it displaces is still on the tablet.
class _Recovery extends StatefulWidget {
  const _Recovery({
    required this.recovery,
    required this.onRelaunch,
    required this.onClose,
  });

  final BoardRecovery recovery;
  final VoidCallback? onRelaunch;
  final VoidCallback onClose;

  @override
  State<_Recovery> createState() => _RecoveryState();
}

class _RecoveryState extends State<_Recovery> {
  RecoveryOptions? _found;

  /// The backup a yes is being asked about, if any.
  Snapshot? _confirming;
  bool _confirmingFresh = false;

  bool _busy = false;
  String? _problem;

  /// What was done, once something has been.
  String? _done;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reads what is on the tablet, and survives not being able to.
  ///
  /// [BoardRecovery] already answers with a sentence rather than a throw, and
  /// this catches anyway: the board underneath this panel is the last thing
  /// standing, and it may not be taken down by the screen offering to repair
  /// it.
  Future<void> _load() async {
    RecoveryOptions found;
    try {
      found = await widget.recovery.options();
    } catch (e) {
      found = (
        options: const <RecoveryOption>[],
        problem: 'The backups on this tablet could not be listed. $e',
      );
    }
    if (mounted) setState(() => _found = found);
  }

  Future<void> _run(
    Future<RecoveryResult> Function() repair,
    String done,
  ) async {
    setState(() {
      _busy = true;
      _problem = null;
    });

    RecoveryResult result;
    try {
      result = await repair();
    } catch (e) {
      result = (done: false, problem: 'Nothing was changed on this tablet. $e');
    }
    if (!mounted) return;

    setState(() {
      _busy = false;
      _confirming = null;
      _confirmingFresh = false;
      _problem = result.problem;
      if (result.done) _done = done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // First, and on every screen this panel has. The person holding the
        // tablet may be mid-sentence, and the words stay one tap away.
        _Action(label: 'Back to the words', onTap: widget.onClose),
        const SizedBox(height: 16),
        if (_problem case final problem?) ...[
          _Body(problem, color: const Color(0xFFFFAB91)),
          const SizedBox(height: 16),
        ],
        ..._body(),
      ],
    );
  }

  List<Widget> _body() {
    if (_done case final done?) return _finished(done);
    if (_busy) return const [_Body('Working…')];

    if (_confirming case final snapshot?) return _confirmRestore(snapshot);
    if (_confirmingFresh) return _confirmFresh();

    return _choices();
  }

  List<Widget> _finished(String done) => [
    _Title(done),
    const SizedBox(height: 8),
    if (widget.onRelaunch case final relaunch?) ...[
      _Action(label: 'Open the board', onTap: relaunch, emphasis: true),
      const SizedBox(height: 8),
    ],
    const _Body(
      'If the board does not come back, close Wordbridge AAC completely and '
      'open it again.',
    ),
  ];

  List<Widget> _choices() {
    final found = _found;
    if (found == null) return const [_Body('Looking for backups…')];

    return [
      const _Title('Backups on this tablet'),
      const SizedBox(height: 8),
      if (found.problem case final problem?) ...[
        _Body(problem, color: const Color(0xFFFFAB91)),
        const SizedBox(height: 8),
      ],
      if (found.options.isEmpty) ...[
        const _Body(
          'There are no backups on this tablet. Backups are made when a '
          'caregiver taps “Back up now” in settings, and before an app update '
          'changes the board.',
        ),
        const SizedBox(height: 16),
      ] else ...[
        const _Body(
          'Choosing one replaces the board on this tablet with the board as it '
          'stood then.',
        ),
        const SizedBox(height: 8),
        for (final option in found.options) ...[
          _Action(
            label: snapshotWhen(option.snapshot.takenAt),
            detail: option.refusal ?? snapshotSize(option.snapshot.bytes),
            enabled: option.usable,
            onTap: () => setState(() => _confirming = option.snapshot),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
      _Action(
        label: 'Build a new board',
        detail: 'For when there is no backup to go back to.',
        onTap: () => setState(() => _confirmingFresh = true),
      ),
    ];
  }

  List<Widget> _confirmRestore(Snapshot snapshot) {
    final when = snapshotWhen(snapshot.takenAt);

    return [
      _Title('Go back to $when?'),
      const SizedBox(height: 8),
      _Body(
        'The board on this tablet is replaced by the one from $when. Anything '
        'added, moved or hidden since then goes with it.',
      ),
      const SizedBox(height: 8),
      const _Body(
        'The board that is on the tablet now is kept in the backups folder '
        'rather than deleted, so nothing is thrown away.',
      ),
      const SizedBox(height: 16),
      _Action(
        label: 'Restore this backup',
        emphasis: true,
        onTap: () => _run(
          () => widget.recovery.restore(snapshot),
          'Restored the board from $when.',
        ),
      ),
      const SizedBox(height: 8),
      _Action(label: 'Cancel', onTap: () => setState(() => _confirming = null)),
    ];
  }

  List<Widget> _confirmFresh() => [
    const _Title('Build a new board?'),
    const SizedBox(height: 8),
    const _Body(
      'Wordbridge AAC starts again from setup and builds a board from scratch. '
      'None of the words, pictures or places added to this one carry over, and '
      'every location will be new to the person using it.',
    ),
    const SizedBox(height: 8),
    const _Body(
      'The board that is on the tablet now is kept in the backups folder '
      'rather than deleted, so nothing is thrown away.',
    ),
    const SizedBox(height: 16),
    _Action(
      label: 'Build a new board',
      emphasis: true,
      onTap: () => _run(
        widget.recovery.startAgain,
        'The board on this tablet has been set aside.',
      ),
    ),
    const SizedBox(height: 8),
    _Action(
      label: 'Cancel',
      onTap: () => setState(() => _confirmingFresh = false),
    ),
  ];
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text, {this.color = const Color(0xFFB0BEC5)});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 13, color: color));
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    this.detail,
    this.enabled = true,
    this.emphasis = false,
  });

  final String label;
  final String? detail;
  final VoidCallback onTap;

  /// A choice this build cannot take, shown with its reason rather than
  /// hidden. A backup that exists and cannot be used is still the answer to
  /// "is the board gone", which is the question being asked.
  final bool enabled;

  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ground = enabled
        ? (emphasis ? const Color(0xFFECEFF1) : const Color(0xFF37474F))
        : const Color(0xFF1B2A32);
    final ink = enabled
        ? (emphasis ? const Color(0xFF102027) : const Color(0xFFECEFF1))
        : const Color(0xFF78909C);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            if (detail case final detail?) ...[
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled
                      ? const Color(0xFFB0BEC5)
                      : const Color(0xFF546E7A),
                ),
              ),
            ],
          ],
        ),
      ),
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
