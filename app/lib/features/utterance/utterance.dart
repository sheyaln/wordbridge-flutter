import 'package:flutter/foundation.dart';

import '../../db/tables.dart';
import 'morphology.dart';

/// One word in the sentence, and what it was.
///
/// The part of speech is carried along rather than thrown away, because it is
/// what lets the board offer "+ed" after a verb and not after a preposition.
/// [inflected] stops a suffix being applied twice to produce "wanteded".
/// [subjectFollows] marks a copula placed before its subject, the way a yes/no
/// question puts it — it agrees with whatever word lands after it, and it is
/// what keeps that agreement off every other copula.
typedef UtteranceEntry = ({
  String text,
  PartOfSpeech? pos,
  bool inflected,
  bool subjectFollows,
});

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
  ///
  /// A mark carries no part of speech: it is not a word, and the keys that
  /// read the word before them — the endings, the article, "to be" — have
  /// nothing to work from once a sentence has been ended.
  void punctuate(String mark) {
    if (_entries.isEmpty) return;

    if (isPunctuation(_entries.last.text)) {
      if (_entries.last.text == mark) return;
      _entries.removeLast();
    }

    _entries.add((
      text: mark,
      pos: null,
      inflected: true,
      subjectFollows: false,
    ));
    notifyListeners();
  }

  UtteranceEntry? get last => _entries.isEmpty ? null : _entries.last;

  /// Adds a word, and returns the word before it if adding this one corrected
  /// that word — null when nothing was corrected.
  ///
  /// The correction has to be heard. Every word speaks as it is tapped, so a
  /// silent repair leaves the sentence in the bar different from the one the
  /// user heard themselves say, and nothing tells them it happened. For
  /// someone whose speech *is* that audio, a silent correction is no
  /// correction: what is returned here is spoken with the new word behind it,
  /// so "is" followed by "you" is heard as "are you".
  ///
  /// Only one of the two repairs can fire, because both look at the word
  /// immediately behind and no word is both an article and a form of "to be".
  String? add(String word, {PartOfSpeech? pos, bool subjectFollows = false}) {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return null;

    final repaired =
        _fixPrecedingArticle(trimmed) ?? _fixOpeningCopula(trimmed);
    _entries.add((
      text: trimmed,
      pos: pos,
      inflected: false,
      subjectFollows: subjectFollows,
    ));
    notifyListeners();
    return repaired;
  }

  /// Puts a form of "to be" into the sentence, and returns the form to speak.
  ///
  /// Under [CopulaMode.agree] the form is provisional: a question puts the
  /// subject after the verb, so nothing before the copula is one when the bar
  /// is empty, when a question word precedes it ("what is that?"), or when the
  /// sentence before it has been ended, and [_fixOpeningCopula] settles it
  /// once the subject lands.
  ///
  /// Under [CopulaMode.toggle] the first press does the same agreement and
  /// nothing is settled afterwards — a press on the key while a form of "to
  /// be" is the last word replaces that word instead of appending to it.
  String addCopula({required bool past, required CopulaMode mode}) {
    if (mode == CopulaMode.toggle) return _cycleCopula(past: past);

    final subject = _subjectBefore(_entries.length);
    final form = copulaFor(subject, past: past);
    add(form, pos: PartOfSpeech.verb, subjectFollows: subject == null);
    return form;
  }

  /// Advances the form of "to be" at the end of the bar, or places the first.
  ///
  /// Pressing the other tense while a copula is the last word switches tense
  /// rather than stacking a second one, and lands on the form that agrees with
  /// whatever sits in front of it — "I am" pressed on the past key is "I was",
  /// not "I am was".
  String _cycleCopula({required bool past}) {
    final previous = last;

    if (previous != null && isCopula(previous.text)) {
      final ring = past ? pastCopulaRing : presentCopulaRing;
      final form = previous.text.trim().toLowerCase();
      final replacement = ring.contains(form)
          ? nextCopulaForm(form)!
          : copulaFor(_subjectBefore(_entries.length - 1), past: past);

      _entries[_entries.length - 1] = (
        text: replacement,
        pos: PartOfSpeech.verb,
        inflected: false,
        subjectFollows: false,
      );
      notifyListeners();
      return replacement;
    }

    final form = copulaFor(_subjectBefore(_entries.length), past: past);
    add(form, pos: PartOfSpeech.verb);
    return form;
  }

  /// The word a copula placed at [index] would agree with.
  ///
  /// Null where there is nothing to agree with: the start of the bar, a
  /// question word ("what is that?"), or a sentence that has been ended.
  String? _subjectBefore(int index) {
    if (index <= 0) return null;

    final previous = _entries[index - 1];
    if (previous.pos == PartOfSpeech.question) return null;
    if (isPunctuation(previous.text)) return null;
    return previous.text;
  }

  /// Corrects "a" to "an" once the following word is known.
  ///
  /// The article has to be chosen before the noun exists, so it is inserted as
  /// "a" and repaired here. Doing it the other way round would mean asking the
  /// user to know how the next word starts before choosing it.
  ///
  /// The noun is what the article is waiting for, and "to be" is not one, so a
  /// copula landing next leaves the article alone.
  String? _fixPrecedingArticle(String next) {
    if (_entries.isEmpty) return null;
    final previous = _entries.last;
    if (previous.text != 'a' && previous.text != 'an') return null;
    if (isCopula(next)) return null;

    final startsWithVowel = RegExp(
      '^[aeiou]',
      caseSensitive: false,
    ).hasMatch(next);
    final corrected = startsWithVowel ? 'an' : 'a';
    if (corrected == previous.text) return null;

    _entries[_entries.length - 1] = (
      text: corrected,
      pos: previous.pos,
      inflected: previous.inflected,
      subjectFollows: previous.subjectFollows,
    );
    return corrected;
  }

  /// Agrees an opening "to be" with the subject that follows it.
  ///
  /// A yes/no question inverts the two — "are you ok?", "is it my turn?" — so
  /// the copula is placed before there is a subject to agree with, exactly as
  /// the article is placed before its noun. Only a copula placed that way is
  /// touched; one tapped after its subject already agrees with it.
  ///
  /// The mark stays on the word, so backspacing the subject and choosing
  /// another agrees again: correcting "are you" to "is it" is one delete and
  /// one tap, not a sentence to rebuild.
  ///
  /// Returns the form it settled on when that is not the form already there,
  /// so the change can be spoken rather than only shown.
  String? _fixOpeningCopula(String next) {
    if (_entries.isEmpty) return null;
    final previous = _entries.last;
    if (!previous.subjectFollows) return null;

    final settled = copulaAgreeingWith(previous.text, next) ?? previous.text;
    _entries[_entries.length - 1] = (
      text: settled,
      pos: previous.pos,
      inflected: previous.inflected,
      subjectFollows: true,
    );
    return settled == previous.text ? null : settled;
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
      subjectFollows: previous.subjectFollows,
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
