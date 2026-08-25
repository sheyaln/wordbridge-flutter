import 'package:flutter/material.dart';

import 'pin.dart';

/// PIN entry, and first-run PIN creation.
///
/// Returns true only on a correct entry. Caregiver mode is never persisted,
/// so a crash or a cold start always lands back in the communication view.
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

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final configured = await widget.auth.isConfigured();
    final lockout = await widget.auth.lockoutRemaining();
    if (mounted) {
      setState(() {
        _configured = configured;
        _lockout = lockout;
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            configured ? 'Caregiver PIN' : 'Set a caregiver PIN',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!configured) ...[
            const SizedBox(height: 8),
            const Text(
              'This keeps the board editor out of reach during everyday use. '
              '4 to 6 digits.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
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
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: locked ? null : _submit,
                child: Text(configured ? 'Unlock' : 'Set PIN'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
