import 'package:flutter/material.dart';

import 'pin.dart';

/// PIN entry, first-run PIN creation, and recovery of a forgotten one.
///
/// Returns true only on a correct entry, or once a new PIN has been set.
/// Caregiver mode is never persisted, so a crash or a cold start always lands
/// back in the communication view.
class PinGate extends StatefulWidget {
  const PinGate({super.key, required this.auth});

  final PinAuth auth;

  static Future<bool> show(BuildContext context, PinAuth auth) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(child: PinGate(auth: auth)),
    );
    return ok ?? false;
  }

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();

  bool? _configured;
  String? _error;
  Duration? _lockout;
  DateTime? _lastReset;
  bool _justReset = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final configured = await widget.auth.isConfigured();
    final lockout = await widget.auth.lockoutRemaining();
    final lastReset = await widget.auth.lastResetAt();
    if (mounted) {
      setState(() {
        _configured = configured;
        _lockout = lockout;
        _lastReset = lastReset;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text;

    if (_configured == false) {
      if (pin != _confirmController.text) {
        setState(() => _error = 'Those do not match.');
        return;
      }
      try {
        await widget.auth.setPin(pin);
        if (mounted) Navigator.of(context).pop(true);
      } on ArgumentError catch (e) {
        setState(() => _error = e.message.toString());
      }
      return;
    }

    if (await widget.auth.verify(pin)) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    _controller.clear();
    final lockout = await widget.auth.lockoutRemaining();
    if (mounted) {
      setState(() {
        _lockout = lockout;
        _error = lockout != null
            ? 'Too many attempts. Try again in ${lockout.inMinutes + 1} min.'
            : 'Incorrect PIN.';
      });
    }
  }

  /// Reachable during a lockout on purpose.
  ///
  /// A caregiver who has just burned five attempts is exactly the one who has
  /// realized they do not remember it, and waiting out a timer tells them
  /// nothing they do not already know. Nothing here shortens a guess: the
  /// credential is destroyed rather than revealed, and the cost of arriving
  /// here is a five-second hold and a typed word every single time.
  Future<void> _recover() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _TypeToConfirmReset(),
    );
    if (confirmed != true || !mounted) return;

    await widget.auth.reset();
    if (!mounted) return;

    _controller.clear();
    _confirmController.clear();
    setState(() {
      _configured = false;
      _justReset = true;
      _lockout = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final configured = _configured;
    if (configured == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final locked = _lockout != null;
    final lastReset = _lastReset;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              configured
                  ? 'Caregiver PIN'
                  : _justReset
                  ? 'Set a new caregiver PIN'
                  : 'Set a caregiver PIN',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (!configured) ...[
              const SizedBox(height: 8),
              Text(
                _justReset
                    ? 'The old PIN is cleared. Set a new one, 4 to 6 digits.'
                    : 'This keeps the board editor out of reach during '
                          'everyday use. 4 to 6 digits.',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
            if (configured && lastReset != null) ...[
              const SizedBox(height: 8),
              Text(
                'This PIN was reset on ${_shortDate(lastReset)}.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              enabled: !locked,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'PIN',
                counterText: '',
              ),
              onSubmitted: locked ? null : (_) => _submit(),
            ),
            if (!configured)
              TextField(
                controller: _confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Confirm',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Nothing to cancel back to once the credential is gone. The
                // barrier still dismisses: trapping anyone in a modal would
                // put a dialog between the user and their voice, which costs
                // more than the minutes this device spends without a PIN.
                if (!_justReset) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: locked ? null : _submit,
                  child: Text(configured ? 'Unlock' : 'Set PIN'),
                ),
              ],
            ),
            if (configured) ...[
              const SizedBox(height: 20),
              const Divider(height: 1),
              _HoldToReset(onHeld: _recover),
            ],
          ],
        ),
      ),
    );
  }
}

String _shortDate(DateTime at) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${at.day} ${months[at.month - 1]} ${at.year}';
}

/// The way to a forgotten PIN.
///
/// Written out in full rather than hidden, because a parent who cannot get
/// into their child's device at 9pm has to be able to find this without being
/// told about it six months earlier. Secrecy would not buy anything anyway:
/// whoever holds the tablet can already reinstall it.
///
/// What it does buy is that the reset cannot be produced by a tap. A person
/// exploring the screen presses everything; they do not hold one place for
/// five seconds and then type a word. The hold excludes the stray touch and
/// the typed word excludes the reader who cannot read, which is the pair of
/// barriers that actually separates the caregiver from the person using the
/// board.
class _HoldToReset extends StatefulWidget {
  const _HoldToReset({required this.onHeld});

  final VoidCallback onHeld;

  static const holdDuration = Duration(seconds: 5);

  @override
  State<_HoldToReset> createState() => _HoldToResetState();
}

class _HoldToResetState extends State<_HoldToReset>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _HoldToReset.holdDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _release();
            widget.onHeld();
          }
        });

  bool _holding = false;

  /// Every press starts the five seconds over. Five seconds accumulated across
  /// a morning of touches is not a decision anybody made.
  void _start(_) {
    setState(() => _holding = true);
    _controller.forward(from: 0);
  }

  void _release([_]) {
    _controller.stop();
    _controller.value = 0;
    if (mounted && _holding) setState(() => _holding = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _start,
      onPointerUp: _release,
      onPointerCancel: _release,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Forgotten it?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Press and hold this line for five seconds to clear the PIN and '
              'set a new one.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            // Reserved whether or not anything is drawn in it, so the line
            // does not move under a finger that is halfway through the hold.
            SizedBox(
              height: 4,
              child: _holding
                  ? AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _controller.value,
                        minHeight: 4,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Typing the word is the point.
///
/// Matches the register of the board rebuild: something that cannot be undone
/// by reflex should not be reachable by reflex. The copy is blunt about how
/// much the PIN is worth, because a caregiver deciding whether to reset it
/// deserves to know it was never a lock in the first place.
class _TypeToConfirmReset extends StatefulWidget {
  const _TypeToConfirmReset();

  @override
  State<_TypeToConfirmReset> createState() => _TypeToConfirmResetState();
}

class _TypeToConfirmResetState extends State<_TypeToConfirmReset> {
  final _typed = TextEditingController();
  static const _word = 'RESET';

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _typed.text.trim().toUpperCase() == _word;

    return AlertDialog(
      title: const Text('Reset the caregiver PIN?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clears the PIN so you can set a new one.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          const Text(
            'Anyone holding this device can do this. The PIN keeps the editor '
            'out of everyday reach; it is not a lock.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          const Text('Type RESET to continue.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _typed,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep the PIN'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Reset PIN'),
        ),
      ],
    );
  }
}
