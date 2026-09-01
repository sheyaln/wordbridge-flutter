import 'package:flutter/material.dart';

import '../db/tables.dart';

/// Part-of-speech color coding.
///
/// Two conventions are in clinical use and practitioners are split between
/// them. The literature is consistent that *which* scheme a user learns
/// matters far less than that it never changes under them, so the scheme is
/// stored per vocabulary rather than hardcoded.
///
/// Colors are muted rather than saturated: they must carry black label text
/// at readable contrast, and a wall of fully saturated cells is a real source
/// of visual overwhelm for users who report sensory sensitivity.
abstract final class Fitzgerald {
  /// Modified Fitzgerald Key, descended from Edith Fitzgerald's 1926 scheme
  /// for deaf education.
  static const modified = <PartOfSpeech, Color>{
    PartOfSpeech.pronoun: Color(0xFFFFE9A3),
    PartOfSpeech.verb: Color(0xFFB7E4C7),
    PartOfSpeech.adjective: Color(0xFFBFD7ED),
    PartOfSpeech.noun: Color(0xFFFFD6A5),
    PartOfSpeech.preposition: Color(0xFFF7C6D9),
    PartOfSpeech.question: Color(0xFFD9C2E9),
    PartOfSpeech.adverb: Color(0xFFDCC7B8),
    PartOfSpeech.conjunction: Color(0xFFF2F2F2),
    PartOfSpeech.negation: Color(0xFFF4A6A6),
    PartOfSpeech.determiner: Color(0xFFDDDDDD),
    PartOfSpeech.social: Color(0xFFF7C6D9),
    PartOfSpeech.other: Color(0xFFECECEC),
  };

  /// Goossens', Crain & Elder. Deliberately different from the above — do not
  /// try to reconcile them.
  static const goossens = <PartOfSpeech, Color>{
    PartOfSpeech.verb: Color(0xFFF7C6D9),
    PartOfSpeech.adjective: Color(0xFFBFD7ED),
    PartOfSpeech.preposition: Color(0xFFB7E4C7),
    PartOfSpeech.noun: Color(0xFFFFE9A3),
    PartOfSpeech.question: Color(0xFFFFD6A5),
    PartOfSpeech.negation: Color(0xFFFFD6A5),
    PartOfSpeech.pronoun: Color(0xFFFFD6A5),
    PartOfSpeech.social: Color(0xFFFFD6A5),
    PartOfSpeech.adverb: Color(0xFFECECEC),
    PartOfSpeech.conjunction: Color(0xFFF2F2F2),
    PartOfSpeech.determiner: Color(0xFFDDDDDD),
    PartOfSpeech.other: Color(0xFFECECEC),
  };

  static const _systemCell = Color(0xFFCFD8DC);

  static Color colorFor(ColorConvention scheme, PartOfSpeech? pos) {
    if (pos == null) return _systemCell;
    final map = switch (scheme) {
      ColorConvention.goossens => goossens,
      _ => modified,
    };
    return map[pos] ?? modified[PartOfSpeech.other]!;
  }
}
