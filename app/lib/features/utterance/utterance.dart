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
