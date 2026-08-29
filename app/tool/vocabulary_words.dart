// Prints every word the shipped vocabulary can display, one per line.
//
//   cd app && dart run tool/vocabulary_words.dart > /tmp/wordbridge-words.txt
//   dart run tools/fetch_symbols.dart /tmp/wordbridge-words.txt
//
// Deriving the list from the vocabulary keeps adding a word the only thing
// anyone has to remember to do.

import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';

/// Labels that no symbol set will ever index, and should not be asked for.
///
/// Word endings and the forms of "to be" are grammar keys — they render as
/// text on purpose, because a picture of a suffix is not a thing. Punctuation
/// likewise.
bool _isPictorial(String label) =>
    !label.startsWith('+') && !label.contains('/') && label != '?';

void main() {
  final words = <String>{};

  void add(String label) {
    if (_isPictorial(label)) words.add(label);
  }

  for (final band in homeBands) {
    for (final item in band.items) {
      add(item.value.label);
    }
  }
  for (final item in pinnedQuestions) {
    add(item.value.label);
  }
  for (final item in swearingBand.items) {
    add(item.value.label);
  }

  // The bottom-row category keys are buttons too, and want pictures as much as
  // the words behind them do.
  categoryNames.forEach(add);

  for (final entry in categoryBands.entries) {
    for (final band in entry.value) {
      for (final item in band.items) {
        add(item.value.label);
      }
    }
    // Every preset's extras, so one fetch covers whichever preset a profile
    // turns out to use.
    for (final preset in AgeBand.values) {
      for (final band in preset.extrasFor(entry.key)) {
        for (final item in band.items) {
          add(item.value.label);
        }
      }
    }
  }

  // A tool that writes to stdout by design; the lint is about app code.
  for (final word in words.toList()..sort()) {
    // ignore: avoid_print
    print(word);
  }
}
