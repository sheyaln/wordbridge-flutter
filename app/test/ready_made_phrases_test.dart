import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/editor/board_editor.dart';

/// §4.42. Phrases a caregiver can put on a board without inventing them.
///
/// Putting a phrase on a board was always possible — "Add a word" takes
/// whatever is typed, spaces included. What was missing is the pre-made half:
/// a caregiver staring at an empty cell has to think of the phrase first, and
/// the ones worth having are the ones nobody thinks of until they are needed.
void main() {
  group('what is offered', () {
    test('is grouped by the moment it is for', () {
      // Not by word class. A caregiver looking for the phrase that ends a
      // conversation is not looking for an interjection.
      expect(readyMadePhrases.keys, contains('Getting a word in'));
      expect(readyMadePhrases.keys, contains('Ending it'));
      expect(readyMadePhrases.keys, contains('Putting it right'));
    });

    test('and every group has something in it', () {
      for (final group in readyMadePhrases.entries) {
        expect(
          group.value,
          isNotEmpty,
          reason: '"${group.key}" is a heading over nothing',
        );
      }
    });

    test('with no phrase offered twice', () {
      final all = [for (final g in readyMadePhrases.values) ...g];
      expect(
        all.toSet(),
        hasLength(all.length),
        reason: 'one phrase in two groups is two locations for one key',
      );
    });
  });

  group('what the phrases themselves have to be', () {
    test('sayable as they stand, with nothing to fill in', () {
      // A board says what a key says. A phrase with a blank in it is a key
      // that speaks a sentence nobody finished.
      for (final phrase in [for (final g in readyMadePhrases.values) ...g]) {
        expect(phrase, isNot(contains('_')), reason: phrase);
        expect(phrase, isNot(contains('...')), reason: phrase);
        expect(phrase.trim(), phrase, reason: '"$phrase" is padded');
        expect(phrase, isNotEmpty);
      }
    });

    test('and written the way somebody would say them', () {
      // No leading capital and no full stop: the label is the utterance, and a
      // board that shouts its keys in title case is reading them out as
      // headings. "I" stays capital, because it is the word.
      for (final phrase in [for (final g in readyMadePhrases.values) ...g]) {
        final first = phrase.split(' ').first;
        expect(
          first == 'I' || first == first.toLowerCase(),
          isTrue,
          reason: '"$phrase" opens with a capital',
        );
        expect(phrase.endsWith('.'), isFalse, reason: phrase);
      }
    });

    test('and they are the ones a slow board cannot otherwise reach', () {
      // The argument for spending a location on a phrase at all: by the time
      // it has been built word by word, the conversation has moved on.
      final all = [for (final g in readyMadePhrases.values) ...g];

      expect(all, contains('wait, I am typing'));
      expect(all, contains('ask me, not them'));
      expect(all, contains('that is not what I meant'));

      // Every one of them is more than one word, or it would be a word.
      for (final phrase in all) {
        expect(
          phrase.split(' ').length,
          greaterThan(1),
          reason: '"$phrase" is a word, and belongs in the vocabulary',
        );
      }
    });
  });
}
