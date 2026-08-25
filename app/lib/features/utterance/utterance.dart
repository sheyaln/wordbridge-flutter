import 'package:flutter/foundation.dart';

/// The sentence being built.
class UtteranceBar extends ChangeNotifier {
  final _words = <String>[];

  List<String> get words => List.unmodifiable(_words);
  String get text => _words.join(' ');
  bool get isEmpty => _words.isEmpty;

  void add(String word) {
    if (word.trim().isEmpty) return;
    _words.add(word.trim());
    notifyListeners();
  }

  /// Rewrites the last word in place.
  ///
  /// Used by the suffix keys: tapping "+ed" after "want" should leave one
  /// word reading "wanted", not two reading "want ed".
  String? replaceLast(String Function(String) transform) {
    if (_words.isEmpty) return null;
    final replaced = transform(_words.last);
    _words[_words.length - 1] = replaced;
    notifyListeners();
    return replaced;
  }

  String? get last => _words.isEmpty ? null : _words.last;

  void backspace() {
    if (_words.isEmpty) return;
    _words.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_words.isEmpty) return;
    _words.clear();
    notifyListeners();
  }
}
