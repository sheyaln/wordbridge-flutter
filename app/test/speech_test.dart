import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

void main() {
  group('lone capital letters', () {
    test('"I" is lowercased so it is not announced as "capital I"', () {
      // Reported from a real device: the word every AAC user needs most was
      // being read out as the name of a letter.
      expect(normalizeForSpeech('I'), 'i');
    });

    test('any single capital is normalized', () {
      // A caregiver adding a name initial hits the same defect.
      for (final letter in ['A', 'B', 'X', 'Z']) {
        expect(normalizeForSpeech(letter), letter.toLowerCase());
      }
    });

    test('a capital inside a sentence is left alone', () {
      // The synthesizer has enough context here, and rewriting would be
      // meddling with text the caregiver wrote.
      expect(normalizeForSpeech('I want more'), 'I want more');
    });

    test('multi-letter words are untouched', () {
      expect(normalizeForSpeech('OK'), 'OK');
      expect(normalizeForSpeech('want'), 'want');
    });

    test('single lowercase letters are untouched', () {
      expect(normalizeForSpeech('a'), 'a');
    });

    test('whitespace is trimmed', () {
      expect(normalizeForSpeech('  I  '), 'i');
      expect(normalizeForSpeech('   '), '');
    });
  });
}
