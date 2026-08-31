/// Where a caregiver's own word may go, and where it may not.
///
/// One answer, asked by every path that puts a word somewhere. The editor has
/// two — tapping a reserved location to add a word, and finishing a move onto
/// one — and a rule enforced in only one of them is a rule with a way round it.
library;

import '../../db/database.dart';
import '../../db/seed/core_board_set.dart';

/// Why a word cannot go at this location, or null if it can.
///
/// Written to be read to a caregiver. A refusal that does not say why reads as
/// a broken screen, and this one refuses something that looks perfectly
/// reasonable until somebody explains the row.
Future<String?> refusalToPlaceAt(
  WordbridgeDatabase db, {
  required String vocabularyId,
  required int row,
}) async {
  final vocabulary = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabularyId))).getSingleOrNull();
  if (vocabulary == null) return null;

  if (!isSystemRow(vocabulary, row)) return null;

  return 'That row is the one every board carries: home, back, the category '
      'keys and the key that turns them. A word there would speak in a row '
      'that navigates, and it would take the gap that stops a reach for '
      '"back" landing on a category. Any other free location will take it.';
}

/// Whether a row is the one the frame owns on every board.
///
/// Read from what the vocabulary recorded rather than recomputed, for the same
/// reason [SystemFrame] is the authority everywhere else: a board set that
/// gained a category has a frame `SystemRowPlan` would no longer produce.
///
/// A vocabulary with nothing recorded — an imported board set, or one a
/// caregiver built by hand — has no frame, so no row is spoken for and nothing
/// is refused. Refusing on a guess would be worse: it would take locations away
/// from a board that never had a system row to protect.
bool isSystemRow(Vocabulary vocabulary, int row) {
  final frame = SystemFrame.parse(vocabulary.systemCellMap);
  return frame != null && row == frame.row;
}
