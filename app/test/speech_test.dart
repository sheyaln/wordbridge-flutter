import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';

void main() {
  group('lone capital letters', () {
    test('"I" is lowercased so it is not announced as "capital I"', () {
      // Reported from a real device: the word every AAC user needs most was
      // being read out as the name of a letter.
      expect(normaliseForSpeech('I'), 'i');
    });

    test('any single capital is normalised', () {
      // A caregiver adding a name initial hits the same defect.
      for (final letter in ['A', 'B', 'X', 'Z']) {
        expect(normaliseForSpeech(letter), letter.toLowerCase());
      }
    });

    test('a capital inside a sentence is left alone', () {
      // The synthesiser has enough context here, and rewriting would be
      // meddling with text the caregiver wrote.
      expect(normaliseForSpeech('I want more'), 'I want more');
    });

    test('multi-letter words are untouched', () {
      expect(normaliseForSpeech('OK'), 'OK');
      expect(normaliseForSpeech('want'), 'want');
    });

    test('single lowercase letters are untouched', () {
      expect(normaliseForSpeech('a'), 'a');
    });

    test('whitespace is trimmed', () {
      expect(normaliseForSpeech('  I  '), 'i');
      expect(normaliseForSpeech('   '), '');
    });
  });
}
