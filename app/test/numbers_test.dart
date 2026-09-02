import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/utterance/numbers.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// §4.74. Saying a number the board has no key for.
///
/// The numbers row stops at ten because ten keys scan in one sweep, which is a
/// good argument about keys and was taken as an argument about numbers. Two
/// presses already make the digits of anything somebody wants; what was
/// missing was the app agreeing that `1` then `2` is twelve.
void main() {
  group('a number in words', () {
    test('is the word, not the digits read out', () {
      expect(numberInWords(12), 'twelve');
      expect(numberInWords(7), 'seven');
    });

    test('through the teens, which are the ones that are not a pattern', () {
      expect(numberInWords(11), 'eleven');
      expect(numberInWords(13), 'thirteen');
      expect(numberInWords(15), 'fifteen');
      expect(numberInWords(19), 'nineteen');
    });

    test('and the tens, joined without a hyphen', () {
      // §5: no dashes in anything a person reads or hears.
      expect(numberInWords(20), 'twenty');
      expect(numberInWords(21), 'twenty one');
      expect(numberInWords(45), 'forty five');
      expect(numberInWords(99), 'ninety nine');
      expect(numberInWords(21), isNot(contains('-')));
    });

    test('hundreds and thousands, for an age, a year or a price', () {
      expect(numberInWords(100), 'one hundred');
      expect(numberInWords(101), 'one hundred one');
      expect(numberInWords(250), 'two hundred fifty');
      expect(numberInWords(1000), 'one thousand');
      expect(numberInWords(1999), 'one thousand nine hundred ninety nine');
    });

    test('and a run of zeroes does not say them', () {
      expect(numberInWords(10), 'ten');
      expect(numberInWords(30), 'thirty');
      expect(numberInWords(2000), 'two thousand');
    });
  });

  group('what counts as a numeral', () {
    test('is the key label, which is digits', () {
      expect(isNumeral('1'), isTrue);
      expect(isNumeral('10'), isTrue);
    });

    test('and not the word it speaks', () {
      // Joining works on what is written, because `1` and `2` concatenate and
      // `one` and `two` do not.
      expect(isNumeral('one'), isFalse);
      expect(isNumeral(''), isFalse);
      expect(isNumeral('3rd'), isFalse);
    });
  });

  group('joining', () {
    test('makes one number out of two presses', () {
      final bar = UtteranceBar()..add('1');
      expect(bar.joinNumber('2'), 'twelve');
      expect(bar.words, ['12']);
    });

    test('keeps going past two digits', () {
      final bar = UtteranceBar()..add('1');
      bar.joinNumber('9');
      expect(bar.joinNumber('9'), 'one hundred ninety nine');
      expect(bar.words, ['199']);
    });

    test('stops rather than building a number nobody meant', () {
      // Past four digits this is somebody pressing keys, not saying a number.
      final bar = UtteranceBar()..add('1');
      for (final digit in ['2', '3', '4']) {
        bar.joinNumber(digit);
      }
      expect(bar.words, ['1234']);

      expect(bar.joinNumber('5'), isNull, reason: 'five digits is not a join');
      expect(bar.words, ['1234'], reason: 'and the bar is left alone');
    });

    test('does nothing where the word before is not a number', () {
      final bar = UtteranceBar()..add('want');
      expect(bar.joinNumber('2'), isNull);
      expect(bar.words, ['want']);
    });

    test('does nothing on an empty bar', () {
      expect(UtteranceBar().joinNumber('2'), isNull);
    });

    test('and a word after a number starts a word, not a longer number', () {
      final bar = UtteranceBar()..add('1');
      bar.joinNumber('2');
      bar.add('apples');
      expect(bar.words, ['12', 'apples']);
    });

    test('a joined number is marked so no ending is applied to it', () {
      // The ending keys rewrite the last word, and "12ed" is not a word. The
      // join marks the entry inflected for exactly that reason, the same way
      // a contraction does.
      final bar = UtteranceBar()..add('1');
      bar.joinNumber('2');
      expect(bar.last!.inflected, isTrue);
      expect(bar.last!.text, '12');
    });
  });
}
