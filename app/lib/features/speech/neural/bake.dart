import 'dart:async';

import 'package:flutter/foundation.dart';

import 'clip_store.dart';
import 'kokoro.dart';

enum BakeState { idle, running, waiting, paused, done, failed }

/// Synthesises the whole board, in the background, over about half an hour.
///
/// **Not a modal progress bar.** At 1.3 s a word and 1231 words a bake is
/// twenty-seven minutes on the floor device, and nobody sits through that
/// holding a tablet somebody else needs to talk on. So it runs while the board
/// is in use, it survives being interrupted, and it resumes.
///
/// **Resuming needs nothing stored.** The pack *is* the progress: whatever it
/// already holds is done, and the list is filtered against it every time this
/// starts. A tablet killed at word 800 comes back and bakes 431.
///
/// **It stands aside for the person.** The model is one engine behind one
/// pointer, so a word being baked is a bar press waiting — and a press that
/// waits for a background job is the failure §5 non-negotiable 1 is about.
/// Every clip is preceded by a check, and speech pushes the job out of the way
/// for a few quiet seconds.
class BakeJob extends ChangeNotifier {
  BakeJob(this._synthesiser, this._store, {required this.sid, this.speed = 1.0});

  final KokoroSynthesiser _synthesiser;
  final ClipStore _store;

  /// Which of the model's voices is being baked. Changing it does not change
  /// this job — it makes a different pack, and a different job.
  final int sid;

  final double speed;

  /// How long the board stays quiet after speech before baking resumes.
  ///
  /// Long enough to cover the gap between two words of one sentence, short
  /// enough that a tablet put down between conversations gets on with it.
  static const quietFor = Duration(seconds: 6);

  BakeState get state => _state;
  BakeState _state = BakeState.idle;

  /// What went wrong, for the screen to show rather than a bare "failed".
  String? get failure => _failure;
  String? _failure;

  int get done => _done;
  int _done = 0;

  int get total => _total;
  int _total = 0;

  /// How much of this board can be said in the chosen voice, 0 to 1.
  ///
  /// The number the caregiver screen reports, because "how much of the
  /// vocabulary is baked" is the honest way to say how often the platform
  /// voice is about to appear (§4.5).
  double get progress => _total == 0 ? 1 : _done / _total;

  bool get isRunning => _state == BakeState.running || _state == BakeState.waiting;

  List<String> _remaining = const [];
  bool _stop = false;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _loop;

  /// Pushes the bake out of the way, because somebody is speaking.
  ///
  /// Called on every utterance rather than only on a press, so a person
  /// building a sentence one tap at a time is never racing a background job
  /// for the engine.
  void standAside() {
    _quietUntil = DateTime.now().add(quietFor);
  }

  /// Starts, or picks up where the last run stopped.
  ///
  /// [words] is the whole vocabulary every time. Filtering here rather than at
  /// the call site is what makes resuming automatic: nothing has to remember
  /// where it got to, because the pack already knows.
  Future<void> start(List<String> words) async {
    _total = words.length;
    _remaining = [for (final word in words) if (!_store.contains(word)) word];
    _done = _total - _remaining.length;
    _failure = null;

    if (_remaining.isEmpty) {
      _state = BakeState.done;
      notifyListeners();
      return;
    }

    if (isRunning) {
      notifyListeners();
      return;
    }

    _stop = false;
    _state = BakeState.running;
    notifyListeners();
    return _loop = _run();
  }

  /// Stops after the word in flight. A blocking FFI call cannot be cancelled,
  /// so "paused" means "no further words", never "stopped mid-word".
  void pause() {
    if (!isRunning) return;
    _stop = true;
    _state = BakeState.paused;
    notifyListeners();
  }

  Future<void> _run() async {
    try {
      while (_remaining.isNotEmpty && !_stop) {
        // The person outranks the job, every time. Waiting rather than
        // abandoning: this is a half-hour of work and it will get its turn.
        if (_synthesiser.liveWaiting || DateTime.now().isBefore(_quietUntil)) {
          if (_state != BakeState.waiting) {
            _state = BakeState.waiting;
            notifyListeners();
          }
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        if (_state != BakeState.running) {
          _state = BakeState.running;
          notifyListeners();
        }

        final word = _remaining.first;
        final clip = await _synthesiser.generate(
          text: word,
          sid: sid,
          speed: speed,
        );
        await _store.write(word, clip);

        _remaining = _remaining.sublist(1);
        _done++;
        notifyListeners();
      }

      if (_remaining.isEmpty) _state = BakeState.done;
    } catch (e) {
      // A bake that stops is a board that speaks in the platform voice for the
      // words it did not reach, which is survivable and is what the ladder is
      // for. It is not a reason to take the app down.
      _failure = '$e';
      _state = BakeState.failed;
    } finally {
      _loop = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stop = true;
    super.dispose();
  }

  /// Waits for the loop to leave the engine alone. For teardown and for tests;
  /// nothing on a user's path waits on a bake.
  Future<void> settle() => _loop ?? Future.value();
}
