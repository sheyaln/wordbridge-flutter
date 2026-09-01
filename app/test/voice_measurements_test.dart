import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/reporting/voice_measurements.dart';

/// §4.52. The neural voice may be measured. The user may not be quoted.
///
/// The engine's own record of a fallback carries two things that would make
/// this a transcript rather than a measurement: the sentence somebody was
/// trying to say, and a reason string that interpolates the thrown exception.
/// Neither has anywhere to go in what leaves the tablet.
void main() {
  group('classifying why the platform voice spoke instead', () {
    test('the model was not there', () {
      expect(
        classifyFallback('the voice could not be loaded'),
        FallbackReason.voiceUnavailable,
      );
    });

    test('it ran past the budget', () {
      expect(
        classifyFallback('took longer than 1500 ms'),
        FallbackReason.overBudget,
      );
    });

    test('it threw', () {
      expect(
        classifyFallback('the voice failed: Bad state: no model'),
        FallbackReason.failed,
      );
    });

    test('and anything else is "other", never passed through', () {
      // The whole point. `'the voice failed: $e'` is assembled from a thrown
      // object, and a thrown object can quote a word, a path or a filename —
      // so a reason this version does not recognise is reported as
      // unrecognised rather than forwarded and hoped about.
      expect(
        classifyFallback('exploded while saying "I want the toilet"'),
        FallbackReason.other,
      );
    });
  });

  group('what the payload cannot carry', () {
    test('the sentence somebody was trying to say', () {
      const said = 'I want to go to grandmas house';

      final payload = voicePayload((
        voiceId: 'af_heart',
        budgetBaseMs: 747,
        budgetPerWordMs: 262,
        fallbackCount: 1,
        fallbacks: [
          (reason: FallbackReason.overBudget, words: said.split(' ').length),
        ],
      ));

      // Not "the field is null" — there is no field. Checked against the
      // rendered payload, because that is the thing that leaves.
      expect(payload.toString(), isNot(contains('grandmas')));
      expect(payload.toString(), isNot(contains(said)));
    });

    test('but keeps how long it was, which is what a timing needs', () {
      final payload = voicePayload((
        voiceId: 'af_heart',
        budgetBaseMs: 747,
        budgetPerWordMs: 262,
        fallbackCount: 1,
        fallbacks: [(reason: FallbackReason.overBudget, words: 7)],
      ));

      final fallbacks = payload['fallbacks']! as List<Object?>;
      expect((fallbacks.single! as Map)['words'], 7);
      expect((fallbacks.single! as Map)['reason'], 'overBudget');
    });

    test('and carries the budget it was measured against', () {
      // A latency with no budget beside it cannot be read: "1.2 seconds" is a
      // pass on one tablet's fitted budget and a failure on another's.
      final payload = voicePayload((
        voiceId: 'af_heart',
        budgetBaseMs: 900,
        budgetPerWordMs: 300,
        fallbackCount: 4,
        fallbacks: const [],
      ));

      expect(payload['budget_base_ms'], 900);
      expect(payload['budget_per_word_ms'], 300);
      expect(payload['fallback_count'], 4);
      expect(payload['voice_id'], 'af_heart');
    });
  });
}
