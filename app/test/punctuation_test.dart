import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// Ending a sentence with a mark that carries tone.
///
/// Platform speech engines read sentence-final punctuation for prosody, so a
/// question mark buys a genuine rising intonation rather than an imitation of
/// one. That only works if the mark reaches the engine attached to the last
/// word, with no space in front of it.
void main() {
  late UtteranceBar bar;

  setUp(() => bar = UtteranceBar());

  test('a question mark joins the sentence without a space', () async {
    bar.add('you', pos: PartOfSpeech.pronoun);
    bar.add('want', pos: PartOfSpeech.verb);
    bar.add('that', pos: PartOfSpeech.pronoun);
    bar.punctuate('?');

    expect(bar.text, 'you want that?');
  });

  test('the mark is its own word, so backspace takes only the mark', () {
    // Attaching it to the last word would mean deleting the question also
    // deletes the word it was asked about.
    bar.add('more');
    bar.punctuate('?');
    expect(bar.text, 'more?');

    bar.backspace();
    expect(bar.text, 'more');
  });

  test('two taps leave one mark', () {
    bar.add('more');
    bar.punctuate('?');
    bar.punctuate('?');

    expect(bar.text, 'more?');
  });

  test('a different mark replaces the one already there', () {
    bar.add('stop');
    bar.punctuate('?');
    bar.punctuate('!');

    expect(bar.text, 'stop!');
  });

  test('an empty sentence takes no mark', () {
    // A lone question mark is not a question, and speaking one says nothing.
    bar.punctuate('?');

    expect(bar.isEmpty, isTrue);
    expect(bar.text, '');
  });

  test('a word after a mark still reads correctly', () {
    bar.add('more');
    bar.punctuate('?');
    bar.add('please');

    expect(bar.text, 'more? please');
  });

  test('clearing removes the mark with everything else', () {
    bar.add('more');
    bar.punctuate('?');
    bar.clear();

    expect(bar.text, '');
  });
}
