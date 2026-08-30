/// How long the bar's speak key is allowed to wait before the platform voice
/// takes over.
///
/// **Both terms are needed and the device says why.** Fitting the measured
/// timings against utterance length on an iPad mini 5 gives
/// `747 ms + 262 ms/word`, R² 0.990 over eight lengths from one word to
/// twenty-four — a large fixed per-call overhead with a smaller per-word term
/// on top. So:
///
/// - **A per-word budget alone starves short utterances.** One word would get
///   262 ms against a fixed overhead of 747 ms, and short utterances are most
///   of what an AAC board says.
/// - **A fixed budget alone picks one length and fails the rest.** Generous
///   enough for twenty words and a two-word answer may hang for five seconds;
///   tight enough for two words and the user's longest, most deliberate
///   sentences are the ones that never arrive in their own voice.
///
/// A timeout that fires in ordinary use is not a safety net, it is a random
/// voice generator — so the shipped default is about **twice** the fitted line
/// and only a genuine stall reaches it.
class SynthesisBudget {
  const SynthesisBudget({required this.base, required this.perWord});

  /// The fixed cost of asking the model for anything at all.
  final Duration base;

  final Duration perWord;

  /// What synthesis actually costs on the floor device: iPad mini 5, A12,
  /// 3 GB, release build, Kokoro v0.19 fp32, two threads, after warm-up.
  ///
  /// Kept as a named constant rather than folded into [shipped] so that the
  /// measurement and the margin over it stay separately arguable.
  static const fitted = SynthesisBudget(
    base: Duration(milliseconds: 747),
    perWord: Duration(milliseconds: 262),
  );

  /// The default until a device measures its own.
  ///
  /// This is the floor device's number and every other supported tablet is
  /// faster — the same model reports RTF 0.62 on an A12X and 4–4.5× real time
  /// through Core ML on an A17 — so shipping the slowest device's budget is
  /// generous everywhere else, which is the safe direction for a control whose
  /// failure mode is speaking in the wrong voice.
  static const shipped = SynthesisBudget(
    base: Duration(milliseconds: 1500),
    perWord: Duration(milliseconds: 525),
  );

  /// Bounds on anything measured or stored.
  ///
  /// The lower bounds are below the floor device's fitted line, so a fast
  /// tablet can genuinely tighten this. The upper ones are the point past
  /// which a person is waiting rather than pausing, whatever the arithmetic
  /// says: a sentence nobody hears for fifteen seconds was not spoken.
  static const minBase = Duration(milliseconds: 400);
  static const maxBase = Duration(seconds: 6);
  static const minPerWord = Duration(milliseconds: 60);
  static const maxPerWord = Duration(milliseconds: 1200);

  /// How long [text] is allowed to take.
  ///
  /// **Word count is a proxy and it is loosest at the bottom.** The one-word
  /// point measured 598 ms against a fitted 1009, by far the worst residual of
  /// the eight, because synthesis cost tracks phonemes rather than words and
  /// the sweep's one-word case was `the`. A long single word — `emergency` —
  /// costs far more than a short one. If the budget starts firing on short
  /// utterances the answer is to predict from characters, not to widen this.
  Duration forText(String text) {
    final words = wordsIn(text);
    return base + perWord * words;
  }

  /// How many words [text] is, counted the way the fit counted them.
  static int wordsIn(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  /// Twice this line, which is what gets shipped or stored after a
  /// measurement. Doubling is the margin, and it is deliberately crude: the
  /// thing being guarded against is a stall, not a slow sentence.
  SynthesisBudget get doubled =>
      SynthesisBudget(base: base * 2, perWord: perWord * 2);

  /// Clamped into something a person could live with, whatever produced it.
  SynthesisBudget get sane => SynthesisBudget(
    base: _clamp(base, minBase, maxBase),
    perWord: _clamp(perWord, minPerWord, maxPerWord),
  );

  /// The line through two measured points, in the form this class carries.
  ///
  /// Two points rather than a sweep because this runs at setup while somebody
  /// waits, and the residual that matters — the fixed overhead — is what two
  /// well-separated lengths already resolve. Falls back to [shipped] where the
  /// points are degenerate or come out backwards, which is what a device under
  /// load produces and is not something to ship a budget from.
  static SynthesisBudget fit({
    required int shortWords,
    required Duration shortTook,
    required int longWords,
    required Duration longTook,
  }) {
    if (longWords <= shortWords) return shipped;

    final rise = longTook.inMicroseconds - shortTook.inMicroseconds;
    final run = longWords - shortWords;
    final perWordUs = rise / run;
    if (perWordUs <= 0) return shipped;

    final baseUs = shortTook.inMicroseconds - perWordUs * shortWords;
    if (baseUs <= 0) return shipped;

    return SynthesisBudget(
      base: Duration(microseconds: baseUs.round()),
      perWord: Duration(microseconds: perWordUs.round()),
    ).doubled.sane;
  }

  static Duration _clamp(Duration value, Duration min, Duration max) =>
      value < min ? min : (value > max ? max : value);

  @override
  bool operator ==(Object other) =>
      other is SynthesisBudget && other.base == base && other.perWord == perWord;

  @override
  int get hashCode => Object.hash(base, perWord);

  @override
  String toString() =>
      '${base.inMilliseconds}ms + ${perWord.inMilliseconds}ms/word';
}
