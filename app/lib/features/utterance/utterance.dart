import 'package:flutter/foundation.dart';

import '../../db/tables.dart';
import 'contractions.dart';
import 'morphology.dart';
import 'pronunciation.dart';
import 'numbers.dart';

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

  /// How to say this word, where that is not how it is written (§4.84).
  ///
  /// Null for every ordinary word. Set where the two genuinely differ — the
  /// past of `read` is written `read` and said `red` — so the bar shows the
  /// sentence somebody built and the voice says the word they meant.
  String? spoken,
});

/// The sentence being built.
class UtteranceBar extends ChangeNotifier {
  final _entries = <UtteranceEntry>[];

  /// Where the next word goes, or null for the end of the sentence.
  ///
  /// **Null is not the same as `entries.length`, and the difference is the
  /// whole feature.** Null means nobody has picked a place, so the bar grows
  /// at the end and stays there however long the sentence gets — which is what
  /// it has always done and what every key on the board was learned against. A
  /// number means somebody has tapped a word to go back to, and the bar stays
  /// there until they leave.
  ///
  /// Kept as the *insertion point* rather than as the selected word, because
  /// that is what every operation here actually needs: [add] inserts at it,
  /// [backspace] deletes in front of it, and the endings, the article repair,
  /// the copula agreement and the contractions all read the word behind it. So
  /// one number moves the entire grammar engine to the middle of a sentence,
  /// and at the end of one it is arithmetic that changes nothing.
  int? _caret;

  List<UtteranceEntry> get entries => List.unmodifiable(_entries);
  List<String> get words => [for (final e in _entries) e.text];
  bool get isEmpty => _entries.isEmpty;

  /// The index the next word is inserted at.
  int get caret => _caret ?? _entries.length;

  /// Whether the bar is being edited somewhere other than its end.
  bool get isEditingSegment => _caret != null;

  /// The word the caret sits behind — the one a person has selected — or null
  /// when the caret is at the very front of the sentence.
  int? get selectedIndex {
    final at = caret;
    return at == 0 ? null : at - 1;
  }

  /// The sentence as it will be spoken.
  ///
  /// Punctuation joins without a leading space so the speech engine sees
  /// "you want that?" rather than "you want that ?". Engines read
  /// sentence-final punctuation for prosody, and a stray space in front of it
  /// is enough for some of them to miss it.
  String get text => _join((e) => e.text);

  /// The sentence as it should be *said*.
  ///
  /// The same string as [text] except where a word is written one way and said
  /// another — see [UtteranceEntry.spoken]. Everything that speaks reads this;
  /// everything that draws reads [text].
  String get spokenText => _join((e) => e.spoken ?? e.text);

  String _join(String Function(UtteranceEntry) of) {
    final buffer = StringBuffer();
    for (final entry in _entries) {
      if (buffer.isNotEmpty && !isPunctuation(entry.text)) buffer.write(' ');
      buffer.write(of(entry));
    }
    return buffer.toString();
  }

  static bool isPunctuation(String text) =>
      text.length == 1 && '?!.,'.contains(text);

  /// Puts the caret after the word at [index], so the next key lands there.
  ///
  /// Tapping the word the caret is already behind puts it back at the end,
  /// which is the way out of editing and the same movement as the way in. A
  /// person who has fixed the word they went back for gets to the end of the
  /// sentence by tapping it once more, rather than by finding a second control
  /// somewhere else on the bar.
  ///
  /// An index outside the sentence is the end of it. Words are deleted while
  /// this is held, and a caret pointing past the last word would be a bar that
  /// silently refuses the next key.
  void selectAt(int index) {
    if (index < 0 || index >= _entries.length) return toEnd();
    final wanted = index + 1;
    if (_caret == wanted) return toEnd();
    _caret = wanted;
    notifyListeners();
  }

  /// Puts the caret back at the end of the sentence.
  void toEnd() {
    if (_caret == null) return;
    _caret = null;
    notifyListeners();
  }

  /// The word the next key acts on: the one behind the caret.
  ///
  /// At the end of the sentence this is the last word, which is what it has
  /// always been and why every caller reading it needed no change.
  UtteranceEntry? get last {
    final at = caret;
    return at == 0 ? null : _entries[at - 1];
  }

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

    final behind = last;
    if (behind != null && isPunctuation(behind.text)) {
      if (behind.text == mark) return;
      _removeAt(caret - 1);
    }

    _insert((
      text: mark,
      pos: null,
      inflected: true,
      subjectFollows: false,
      spoken: null,
    ));
    notifyListeners();
  }

  /// Joins a word to the one in front of it, or leaves both alone.
  ///
  /// Returns the contraction when the pair collapsed into one — in which case
  /// [word] has **not** been added and the caller says the contraction instead
  /// of the word — and null when nothing happened, in which case the caller
  /// goes on to [add] it as usual.
  ///
  /// Asked before [add] rather than inside it because this is the one repair
  /// that removes a word rather than correcting one, so what to say afterwards
  /// is a different sentence rather than a longer one.
  ///
  /// **A copula still waiting for its subject is left alone.** "is" placed at
  /// the front of a question has not agreed with anything yet (§4.10), and
  /// "isn't" is outside the ring [_fixOpeningCopula] would correct — so
  /// contracting it there would strand "isn't you" where "aren't you" belongs.
  String? contract(String word) {
    if (!canFollowInContraction(word)) return null;

    final previous = last;
    if (previous == null || previous.subjectFollows) return null;

    final contracted = contractionOf(previous.text, word);
    if (contracted == null) return null;

    _entries[caret - 1] = (
      text: contracted,
      pos: previous.pos,
      // Inflected, so a word ending pressed afterwards does not try to build
      // "can'ted" out of it.
      inflected: true,
      subjectFollows: false,
      spoken: null,
    );
    notifyListeners();
    return contracted;
  }

  /// Joins a numeral onto the numeral already at the end, and returns what to
  /// say — or null where there is nothing to join (§4.74).
  ///
  /// The bar keeps the digits, so `1` then `2` reads `12`, and what is spoken
  /// is the number: *twelve*. Two keys, any number, which is why the numbers
  /// board can stop at ten without a person's vocabulary stopping there.
  ///
  /// **The bar has to be holding digits for this to fire**, which is what the
  /// talk screen puts there while the setting is on. It used to put the spoken
  /// word there — "one" — so the word behind a second numeral press was never
  /// a numeral and this returned null every time.
  ///
  /// Returns null rather than joining when the run would pass
  /// [maxJoinedDigits]: past four digits this is more likely somebody pressing
  /// keys than somebody saying a number, and the next press starts a new one.
  String? joinNumber(String digits) {
    if (!isNumeral(digits)) return null;

    final previous = last;
    if (previous == null || !isNumeral(previous.text)) return null;

    final joined = previous.text + digits.trim();
    if (joined.length > maxJoinedDigits) return null;

    _entries[caret - 1] = (
      text: joined,
      pos: previous.pos,
      // Inflected, so a word ending pressed afterwards does not try to build
      // "12ed" out of it.
      inflected: true,
      subjectFollows: false,
      spoken: null,
    );
    notifyListeners();
    return numberInWords(int.parse(joined));
  }

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
  /// [inflected] marks a word no ending may be applied to. A number typed on
  /// the pad is one: "12" is finished, and "12s" is not a word.
  String? add(
    String word, {
    PartOfSpeech? pos,
    bool subjectFollows = false,
    bool inflected = false,
  }) {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return null;

    // Words the engine says wrong are respelled on the way to the voice and
    // nowhere else — the bar keeps the word somebody pressed (§4.86).
    final saidAs = spokenForm(trimmed);

    final repaired =
        _fixPrecedingArticle(trimmed) ?? _fixOpeningCopula(trimmed);
    _insert((
      text: trimmed,
      pos: pos,
      inflected: inflected,
      subjectFollows: subjectFollows,
      spoken: saidAs,
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

    final subject = _subjectBefore(caret);
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
          : copulaFor(_subjectBefore(caret - 1), past: past);

      _entries[caret - 1] = (
        text: replacement,
        pos: PartOfSpeech.verb,
        inflected: false,
        subjectFollows: false,
        spoken: null,
      );
      notifyListeners();
      return replacement;
    }

    final form = copulaFor(_subjectBefore(caret), past: past);
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
    final previous = last;
    if (previous == null) return null;
    if (previous.text != 'a' && previous.text != 'an') return null;
    if (isCopula(next)) return null;

    final startsWithVowel = RegExp(
      '^[aeiou]',
      caseSensitive: false,
    ).hasMatch(next);
    final corrected = startsWithVowel ? 'an' : 'a';
    if (corrected == previous.text) return null;

    _entries[caret - 1] = (
      text: corrected,
      pos: previous.pos,
      inflected: previous.inflected,
      subjectFollows: previous.subjectFollows,
      spoken: null,
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
    final previous = last;
    if (previous == null || !previous.subjectFollows) return null;

    final settled = copulaAgreeingWith(previous.text, next) ?? previous.text;
    _entries[caret - 1] = (
      text: settled,
      pos: previous.pos,
      inflected: previous.inflected,
      subjectFollows: true,
      spoken: null,
    );
    return settled == previous.text ? null : settled;
  }

  /// Rewrites the word the caret is behind.
  ///
  /// Tapping "+ed" after "want" should leave one word reading "wanted", not
  /// two reading "want ed".
  String? replaceLast(
    String Function(String) transform, {
    String? Function(String written)? saidAs,
  }) {
    final previous = last;
    if (previous == null) return null;

    final replaced = transform(previous.text);
    _entries[caret - 1] = (
      text: replaced,
      pos: previous.pos,
      inflected: true,
      subjectFollows: previous.subjectFollows,
      spoken: saidAs?.call(replaced),
    );
    notifyListeners();
    return replaced;
  }

  /// Deletes the word the caret is behind.
  ///
  /// The caret comes with it, so holding delete inside a sentence eats
  /// backwards from where somebody put it rather than from the end — and the
  /// word that lands next goes where the deleted one was.
  void backspace() {
    if (caret == 0) return;
    _removeAt(caret - 1);
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) {
      // The caret can outlive the words when the sentence was emptied some
      // other way. Clearing an already-empty bar still puts it back.
      toEnd();
      return;
    }
    _entries.clear();
    _caret = null;
    notifyListeners();
  }

  /// Inserts at the caret and takes the caret with it.
  ///
  /// The caret moving is what makes a run of taps inside a sentence read left
  /// to right, the same way a run at the end does. Left where it was, the
  /// second word of a repair would land in front of the first.
  void _insert(UtteranceEntry entry) {
    final at = caret;
    _entries.insert(at, entry);
    if (_caret != null) _caret = at + 1;
  }

  /// Deletes at [index] and walks the caret back over the gap.
  ///
  /// Zero is a real place — in front of the whole sentence — and a word added
  /// there goes to the front, which is what deleting the first word and
  /// choosing another has to mean.
  ///
  /// An emptied bar drops the caret entirely. Editing a sentence that no
  /// longer exists is not a state, and leaving it set would show the bar as
  /// being edited with nothing in it.
  void _removeAt(int index) {
    _entries.removeAt(index);
    if (_entries.isEmpty) {
      _caret = null;
      return;
    }
    final at = _caret;
    if (at != null) _caret = at - 1;
  }
}
