import 'package:flutter/foundation.dart';

import '../../db/tables.dart';

/// One word in the sentence, and what it was.
///
/// The part of speech is carried along rather than thrown away, because it is
/// what lets the board offer "+ed" after a verb and not after a preposition.
/// [inflected] stops a suffix being applied twice to produce "wanteded".
typedef UtteranceEntry = ({String text, PartOfSpeech? pos, bool inflected});

/// The sentence being built.
class UtteranceBar extends ChangeNotifier {
  final _entries = <UtteranceEntry>[];

  List<UtteranceEntry> get entries => List.unmodifiable(_entries);
  List<String> get words => [for (final e in _entries) e.text];
  bool get isEmpty => _entries.isEmpty;

  /// The sentence as it will be spoken.
  ///
  /// Punctuation joins without a leading space so the speech engine sees
  /// "you want that?" rather than "you want that ?". Engines read
  /// sentence-final punctuation for prosody, and a stray space in front of it
  /// is enough for some of them to miss it.
  String get text {
    final buffer = StringBuffer();
    for (final entry in _entries) {
      if (buffer.isNotEmpty && !isPunctuation(entry.text)) buffer.write(' ');
      buffer.write(entry.text);
    }
    return buffer.toString();
  }

  static bool isPunctuation(String text) =>
      text.length == 1 && '?!.,'.contains(text);

  /// Ends the sentence with a mark that carries tone.
  ///
  /// One mark at a time: tapping "?" twice leaves one question mark rather
  /// than two, and tapping "!" after "?" swaps it. Nothing is appended to an
  /// empty bar, because a lone "?" is not a question.
  void punctuate(String mark) {
    if (_entries.isEmpty) return;

    if (isPunctuation(_entries.last.text)) {
      if (_entries.last.text == mark) return;
      _entries.removeLast();
    }

    _entries.add((text: mark, pos: PartOfSpeech.question, inflected: true));
    notifyListeners();
  }

  UtteranceEntry? get last => _entries.isEmpty ? null : _entries.last;

  void add(String word, {PartOfSpeech? pos}) {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;

    _fixPrecedingArticle(trimmed);
    _entries.add((text: trimmed, pos: pos, inflected: false));
    notifyListeners();
  }

  /// Corrects "a" to "an" once the following word is known.
  ///
  /// The article has to be chosen before the noun exists, so it is inserted as
  /// "a" and repaired here. Doing it the other way round would mean asking the
  /// user to know how the next word starts before choosing it.
  void _fixPrecedingArticle(String next) {
    if (_entries.isEmpty) return;
    final previous = _entries.last;
    if (previous.text != 'a' && previous.text != 'an') return;

    final startsWithVowel = RegExp(
      '^[aeiou]',
      caseSensitive: false,
    ).hasMatch(next);
    final corrected = startsWithVowel ? 'an' : 'a';
    if (corrected != previous.text) {
      _entries[_entries.length - 1] = (
        text: corrected,
        pos: previous.pos,
        inflected: previous.inflected,
      );
    }
  }

  /// Rewrites the last word in place.
  ///
  /// Tapping "+ed" after "want" should leave one word reading "wanted", not
  /// two reading "want ed".
  String? replaceLast(String Function(String) transform) {
    if (_entries.isEmpty) return null;

    final previous = _entries.last;
    final replaced = transform(previous.text);
    _entries[_entries.length - 1] = (
      text: replaced,
      pos: previous.pos,
      inflected: true,
    );
    notifyListeners();
    return replaced;
  }

  void backspace() {
    if (_entries.isEmpty) return;
    _entries.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}
