import 'dart:async';

import 'package:flutter/foundation.dart';

/// A stretch of time during which the person selecting words is a
/// communication partner demonstrating on the user's device, not the user.
///
/// Aided language modelling — a parent or teacher picking the device up and
/// building sentences on it to show how — is the best-evidenced thing anyone
/// does with an AAC board, and partners are meant to be doing it constantly.
/// At the screen it is indistinguishable from use: the same locations, the
/// same speech, the same latency. Only the attribution differs, which is all
/// this changes. Nothing about the board behaves differently while it runs.
///
/// A moment, not a configuration. It belongs to the session and is never
/// written down: a device that came back from a restart still modelling would
/// be a device that had quietly stopped recording its owner's practice.
///
/// **It fails off.** [window] caps it, the board offers a one-tap [end], and
/// the talk screen ends it when the app leaves the foreground or the board
/// goes away. Ending it early costs a handful of a partner's taps counted as
/// the user's; leaving it on costs every one of the user's taps counted as
/// somebody else's, for as long as nobody notices — and the remap warning is
/// built on exactly those counts.
class ModellingSession extends ChangeNotifier {
  ModellingSession({this.window = defaultWindow});

  /// How long one stretch runs before it lapses on its own.
  ///
  /// Long enough for a shared activity, short enough that a forgotten mode
  /// costs part of an afternoon rather than all of it. Re-arming is a hold and
  /// a tap, so the cost of guessing low is small and the cost of guessing high
  /// is silent.
  static const defaultWindow = Duration(minutes: 10);

  final Duration window;

  /// Deliberately not extended by activity. Selections arriving during a
  /// stretch are the partner's by definition, so treating them as evidence the
  /// partner is still holding the device would keep the mode alive on exactly
  /// the taps that prove it should have ended.
  DateTime? _until;
  Timer? _timer;

  /// Read off the deadline rather than a flag, so a lapse the timer has not
  /// yet delivered still reads as over.
  bool get active => _until?.isAfter(DateTime.now()) ?? false;

  /// What is left of the current stretch, or null when none is running.
  Duration? get remaining {
    final until = _until;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Starts a stretch, or restarts the clock on one already running.
  void begin() {
    _timer?.cancel();
    _until = DateTime.now().add(window);
    _timer = Timer(window, end);
    notifyListeners();
  }

  void end() {
    _timer?.cancel();
    _timer = null;
    if (_until == null) return;
    _until = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Cleared as well as cancelled, so a later [end] from a screen still
    // coming down returns without waking a notifier that is gone.
    _until = null;
    super.dispose();
  }
}
