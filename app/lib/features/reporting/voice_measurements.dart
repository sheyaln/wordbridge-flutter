/// What may be measured about the neural voice, and the two fields that make
/// that a careful question (§4.52).
///
/// The question being asked is whether the neural voice is fast enough on real
/// hardware. That is answerable with numbers. It is not answerable with
/// anything the user said, and the engine's own record of a fallback contains
/// two things that are:
///
/// - **`Fallback.text` is the sentence the user was trying to say.** There is
///   no field here to put it in. Not a nullable one, not one behind a flag —
///   the type cannot carry it.
/// - **`Fallback.reason` interpolates the exception** in one of its three
///   forms: `'the voice failed: $e'`. An exception string is assembled from
///   whatever threw and can quote a word, a path or a filename. So the reason
///   is classified into a fixed code rather than forwarded.
///
/// What survives is the shape of the failure and how long things took, which
/// is what the question needed.
library;

import '../speech/neural/neural_engine.dart';
import '../speech/neural/synthesis_budget.dart';

/// Why the platform voice spoke instead. A closed set, so nothing a thrown
/// object happens to say can reach a report.
enum FallbackReason {
  /// The model was not loaded or could not be.
  voiceUnavailable,

  /// Synthesis ran past the budget and the platform voice took over.
  overBudget,

  /// Synthesis threw.
  failed,

  /// A reason this version does not recognise. Reaching the intake at all is
  /// the finding: it means the engine grew a case this did not.
  other;

  String get wire => name;
}

/// One fallback, with nothing in it that anybody said.
///
/// [words] is a count, not the words. How long an utterance was is what makes
/// a timing mean something, and a number is not a sentence.
typedef FallbackFact = ({FallbackReason reason, int words});

/// The measurements, as the intake receives them.
typedef VoiceMeasurements = ({
  String voiceId,
  int budgetBaseMs,
  int budgetPerWordMs,
  int fallbackCount,
  List<FallbackFact> fallbacks,
});

/// Turns the engine's free-text reason into one of a fixed set.
///
/// Matched on what `NeuralSpeechEngine` actually writes. A reason that matches
/// nothing is [FallbackReason.other] rather than being passed through, because
/// passing it through is the whole thing this exists to prevent.
FallbackReason classifyFallback(String reason) {
  if (reason.startsWith('the voice could not be loaded')) {
    return FallbackReason.voiceUnavailable;
  }
  if (reason.startsWith('took longer than')) return FallbackReason.overBudget;
  if (reason.startsWith('the voice failed')) return FallbackReason.failed;
  return FallbackReason.other;
}

/// Everything worth measuring about how the neural voice is behaving.
VoiceMeasurements voiceMeasurements(NeuralSpeechEngine engine) => (
  voiceId: engine.voice.id,
  budgetBaseMs: engine.budget.base.inMilliseconds,
  budgetPerWordMs: engine.budget.perWord.inMilliseconds,
  fallbackCount: engine.fallbackCount,
  fallbacks: [
    for (final f in engine.fallbacks)
      (
        reason: classifyFallback(f.reason),
        words: SynthesisBudget.wordsIn(f.text),
      ),
  ],
);

/// The measurements as the intake receives them.
Map<String, Object?> voicePayload(VoiceMeasurements m) => {
  'voice_id': m.voiceId,
  'budget_base_ms': m.budgetBaseMs,
  'budget_per_word_ms': m.budgetPerWordMs,
  'fallback_count': m.fallbackCount,
  'fallbacks': [
    for (final f in m.fallbacks) {'reason': f.reason.wire, 'words': f.words},
  ],
};
