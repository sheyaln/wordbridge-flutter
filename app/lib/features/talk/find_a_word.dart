import 'package:flutter/material.dart';

import '../../db/database.dart';
import 'word_path.dart';

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
  });

  final WordbridgeDatabase db;
  final String vocabularyId;

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

  /// The word to walk to, or null if nobody chose one.
  static Future<WordPath?> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required String vocabularyId,
    int? vocabLevel,
  }) => Navigator.of(context).push<WordPath>(
    MaterialPageRoute<WordPath>(
      fullscreenDialog: true,
      builder: (_) =>
          FindAWord(db: db, vocabularyId: vocabularyId, vocabLevel: vocabLevel),
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

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
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
    final found = await _lookUp(query);

    if (!mounted || mine != _search) return;
    setState(() => _found = found);
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
                    onTap: () => Navigator.of(context).pop(path),
                  ),
              ],
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
