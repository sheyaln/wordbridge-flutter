import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/speech/neural/neural_voice.dart';

/// Which of the model's speakers a person may be given (§4.80).
///
/// The model carries eleven and that is a fact about the model. Which of them
/// somebody is offered is a judgement about whether a voice is good enough to
/// speak with, and the two are not the same list — a person handed a bad voice
/// is judged on the voice rather than on what they said, which is the failure
/// this whole feature exists to avoid.
void main() {
  group('the speaker table', () {
    test('is the model’s own, all eleven of it', () {
      // `sid` is an index into the model's speaker table and this list is that
      // table. Dropping rows would make the remaining ids a puzzle, and the
      // model would go on carrying the speakers either way.
      expect(kokoroVoices, hasLength(11));

      for (var i = 0; i < kokoroVoices.length; i++) {
        expect(
          kokoroVoices[i].sid,
          i,
          reason: 'the speaker ids stopped being this list’s own indices',
        );
      }
    });

    test('and every id in it is distinct', () {
      // The id keys the clip pack. Two voices sharing one would mean a pack
      // baked in one being played back as the other.
      expect(
        kokoroVoices.map((v) => v.id).toSet(),
        hasLength(kokoroVoices.length),
      );
    });
  });

  group('what a caregiver is offered', () {
    test('leaves the British voices out', () {
      final offered = offeredNeuralVoices.map((v) => v.id);

      for (final withdrawn in [
        'bf_emma',
        'bf_isabella',
        'bm_george',
        'bm_lewis',
      ]) {
        expect(
          offered,
          isNot(contains(withdrawn)),
          reason: '$withdrawn is choosable again',
        );
      }
    });

    test('and keeps the seven that are worth speaking in', () {
      expect(offeredNeuralVoices, hasLength(7));
      expect(
        offeredNeuralVoices.every((v) => v.accent.startsWith('American')),
        isTrue,
      );
    });

    test('is a subset of the table, in the table’s order', () {
      // Derived, not written out again: a voice is withdrawn or restored by
      // changing one field, and nothing can disagree about which list is the
      // menu.
      expect(
        offeredNeuralVoices,
        kokoroVoices.where((v) => v.offered).toList(),
      );
    });
  });

  group('resolving a stored id', () {
    test('gives back the voice it names', () {
      expect(neuralVoiceById('am_adam').id, 'am_adam');
      expect(neuralVoiceById('af_sky').name, 'Sky');
    });

    test('and the default where it names nothing', () {
      expect(neuralVoiceById(null).id, defaultNeuralVoiceId);
      expect(neuralVoiceById('').id, defaultNeuralVoiceId);
      expect(neuralVoiceById('af_gone').id, defaultNeuralVoiceId);
    });

    test('and the default where it names one no longer offered', () {
      // A profile set to a withdrawn voice is a person still speaking in it,
      // with no row on the picker to change it from. Moving them is what makes
      // withdrawing one mean anything.
      for (final withdrawn in [
        'bf_emma',
        'bf_isabella',
        'bm_george',
        'bm_lewis',
      ]) {
        expect(
          neuralVoiceById(withdrawn).id,
          defaultNeuralVoiceId,
          reason: '$withdrawn still speaks for a profile set to it',
        );
      }
    });

    test('the default is itself offered', () {
      // Withdrawing the voice everything falls back to would leave the
      // fallback resolving to the first row by accident.
      expect(
        offeredNeuralVoices.map((v) => v.id),
        contains(defaultNeuralVoiceId),
      );
    });
  });
}
