import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../speech/speech_engine.dart';
import 'word_path.dart';

/// What the finder hands back.
///
/// One screen answers both halves of the same question. Whether the word turns
/// out to be on the board is the answer, not a different question, so it must
/// not decide which screen somebody had to open (§4.46).
sealed class FindResult {
  const FindResult();
}

/// A word that is on the board, and the movements that reach it.
class RouteToWord extends FindResult {
  const RouteToWord(this.path);

  final WordPath path;
}

/// A word that is not on the board, typed out and already spoken.
class TypedWord extends FindResult {
  const TypedWord(this.word);

  final String word;
}

/// Whether the finder should offer to say the typed word as it stands.
///
/// True once something has been typed and nothing that came back is that word.
/// A near miss counts: "grandad" coming back for "grandma" is the board
/// answering a different question, and the person is still holding a word it
/// does not have.
///
/// On its own this is true almost all the time, because the search matches on a
/// prefix — "f" already returns "food" and is not "food". What keeps the button
/// from being furniture is not the predicate but the wait: it has to hold still
/// for [FindAWord.offerAfter] before the button appears, so it turns up when
/// somebody has stopped typing rather than between two letters.
bool nothingIsThatWord(String query, List<WordPath> found) {
  final typed = query.trim().toLowerCase();
  if (typed.isEmpty) return false;
  return !found.any((path) => path.label.trim().toLowerCase() == typed);
}

/// What the offer says it will do.
///
/// The word "say" comes off when this profile has asked for quiet (§4.48). A
/// button that promises a sound nobody is going to hear is a button that looks
/// broken the first time it is pressed.
String sayItLabel({required bool speaks}) =>
    speaks ? 'Say it and add to sentence' : 'Add to sentence';

/// Finding a word somebody knows is in there somewhere.
///
/// A board set is a few hundred words across a dozen boards, and the person who
/// needs a word is often not the person who placed it. Hunting for it by
/// opening every category costs the conversation the word was for.
///
/// What comes back is a route, not a destination, and choosing one walks it —
/// see `route_walk.dart` for why that is the whole point. So every result reads
/// as the movements that reach it: `home → more categories → food`. A caregiver
/// who never presses one has still been told where the word is.
///
/// Full screen rather than a sheet. It needs the device's keyboard, a list, and
/// a route under each row, and a half-height sheet with a keyboard over it has
/// room for about one result.
class FindAWord extends StatefulWidget {
  const FindAWord({
    super.key,
    required this.db,
    required this.vocabularyId,
    this.vocabLevel,
    this.search,
    this.speech,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;

  /// Says a word the board does not have, once, before handing it over.
  ///
  /// That one hearing is the feedback that the typing worked; it is not said
  /// again when it reaches the sentence.
  final SpeechEngine? speech;

  /// How words are looked up. [findWords] unless something supplies another.
  ///
  /// A seam, because what matters here is not the search but the race: two of
  /// them in flight with the older one slower. That cannot be arranged against
  /// a database that answers in a microsecond, and what it costs when it goes
  /// wrong is the word somebody was reaching for moving under their finger.
  final Future<List<WordPath>> Function(String query)? search;

  /// The ceiling the board is drawing at, so the finder cannot offer a word
  /// the grid will not show. A location somebody cannot walk to is a dead end,
  /// and this is the one place they would trust it.
  final int? vocabLevel;

  /// How long the typing has to stop before the offer to say the word anyway
  /// appears.
  ///
  /// The predicate behind it is true almost all the time — a prefix search
  /// means "f" returns "food" and is not "food" — so what makes the button an
  /// offer rather than furniture is that it waits for somebody to have
  /// finished, instead of flashing between two letters.
  static const offerAfter = Duration(seconds: 1);

  /// The word to walk to or to say, or null if nobody chose either.
  static Future<FindResult?> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required String vocabularyId,
    int? vocabLevel,
    SpeechEngine? speech,
  }) => Navigator.of(context).push<FindResult>(
    MaterialPageRoute<FindResult>(
      fullscreenDialog: true,
      builder: (_) => FindAWord(
        db: db,
        vocabularyId: vocabularyId,
        vocabLevel: vocabLevel,
        speech: speech,
      ),
    ),
  );

  @override
  State<FindAWord> createState() => _FindAWordState();
}

class _FindAWordState extends State<FindAWord> {
  final _field = TextEditingController();
  final _focus = FocusNode();

  List<WordPath> _found = const [];

  /// Which search the list belongs to.
  ///
  /// Typing is faster than the database. Without this, a slow answer to `fo`
  /// arriving after a fast answer to `food` would replace the right list with
  /// a stale one, and the word somebody was looking at would move under their
  /// finger as they reached for it.
  int _search = 0;

  /// Whether the offer to say the word anyway has settled into view.
  ///
  /// Goes false the instant a key is pressed and comes back a second after the
  /// last one. A button that appeared between two letters, next to a list still
  /// being filled, would be competing with the results for the press.
  bool _offering = false;
  Timer? _offerTimer;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _offerTimer?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<List<WordPath>> _lookUp(String query) =>
      widget.search?.call(query) ??
      findWords(
        widget.db,
        vocabularyId: widget.vocabularyId,
        query: query,
        vocabLevel: widget.vocabLevel,
      );

  Future<void> _look(String query) async {
    final mine = ++_search;
    // The offer goes away for the whole of the next keystroke, whatever it
    // turns out to be, and earns its way back after the typing stops.
    _offerTimer?.cancel();
    if (_offering) setState(() => _offering = false);

    final found = await _lookUp(query);

    if (!mounted || mine != _search) return;
    setState(() => _found = found);

    if (!nothingIsThatWord(query, found)) return;
    _offerTimer = Timer(FindAWord.offerAfter, () {
      if (mounted) setState(() => _offering = true);
    });
  }

  /// Says the typed word once and hands it over as it stands.
  ///
  /// Speech is tried before the screen closes, and a failure closes it anyway:
  /// the word still belongs in the sentence, and a screen that would not shut
  /// because the voice was busy is a person stuck behind a keyboard.
  Future<void> _sayItAnyway() async {
    final word = _field.text.trim();
    if (word.isEmpty) return;

    try {
      await widget.speech?.speak(word);
    } catch (_) {
      // Nowhere to report it to, and the word is not lost by it.
    }

    if (mounted) Navigator.of(context).pop(TypedWord(word));
  }

  @override
  Widget build(BuildContext context) {
    final typed = _field.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a word'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Back to the board',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: TextField(
              controller: _field,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _look,
              style: const TextStyle(fontSize: 30),
              decoration: const InputDecoration(
                hintText: 'A word you are looking for',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (typed && _found.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                'No word on this board matches that. It may be spelled '
                'differently here, or it may not have been added yet.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final path in _found)
                  ListTile(
                    title: Text(
                      path.label,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      routeText(path),
                      style: const TextStyle(fontSize: 16),
                    ),
                    trailing: const Icon(Icons.turn_right_rounded),
                    onTap: () => Navigator.of(context).pop(RouteToWord(path)),
                  ),
              ],
            ),
          ),

          // Below the results rather than above them. Somebody reading the
          // list should not have it pushed down by a control that appeared.
          if (_offering)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton.icon(
                onPressed: _sayItAnyway,
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(sayItLabel(speaks: widget.speech != null)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The route to a word, written the way it would be read aloud.
///
/// The result is the way there, not the board it ends on. Naming only the board
/// answers a question nobody asked: the board is not the hard part, the
/// movements are.
String routeText(WordPath path) => path.steps.isEmpty
    ? 'On the home board'
    : ['home', for (final step in path.steps) step.label].join('  →  ');
