import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/prediction/starter_predictions.dart';

/// The shipped prediction table has to name words that exist.
///
/// A word the boards do not carry is skipped in silence when the strip is
/// built — no error, no log, just a suggestion slot quietly filled by
/// something worse. That makes a typo here invisible in every way except a
/// slightly duller strip, which nobody would ever trace back to this file.
///
/// The trap that makes it worth a test rather than care: the labels a board
/// *displays* are not the words it can *speak*. Category keys like "people"
/// and "places" are navigation, and the articles are grammar keys, so both
/// appear on screen and neither can ever be suggested.
void main() {
  late WordbridgeDatabase db;
  late Set<String> offerable;

  setUpAll(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());

    // Every preset, because a profile may be on any of them and the table is
    // shared. Level 3 so nothing is excluded for being advanced.
    final words = <String>{};
    for (final band in AgeBand.values) {
      final vocabularyId = await seedCoreBoardSet(db, ageBand: band);

      final query = db.select(db.buttons)
        ..where(
          (b) =>
              b.vocabularyId.equals(vocabularyId) &
              b.action.equalsValue(ButtonAction.speak) &
              b.isSystem.equals(false) &
              b.deletedAt.isNull(),
        );

      for (final row in await query.get()) {
        words.add(row.message.trim().toLowerCase());
      }
    }
    offerable = words;
  });

  tearDownAll(() async => db.close());

  test('every suggested word is one a board can actually speak', () {
    final unknown = <String>{};
    for (final entry in starterPredictions.entries) {
      for (final word in entry.value) {
        if (!offerable.contains(word.trim().toLowerCase())) {
          unknown.add('${entry.key} -> $word');
        }
      }
    }

    expect(
      unknown,
      isEmpty,
      reason:
          'these suggestions name words no board can speak, so the strip '
          'silently drops them',
    );
  });

  test('every key is a word somebody can actually land on', () {
    // The empty key is the start of a sentence rather than a word.
    final unknown = {
      for (final key in starterPredictions.keys)
        if (key.isNotEmpty && !offerable.contains(key.toLowerCase())) key,
    };

    expect(
      unknown,
      isEmpty,
      reason: 'a key nothing can precede is dead weight nobody will notice',
    );
  });

  test('keys are lowercase, so lookups find them', () {
    for (final key in starterPredictions.keys) {
      expect(key, key.toLowerCase());
    }
  });

  test('no suggestion is offered twice in one list', () {
    for (final entry in starterPredictions.entries) {
      final seen = entry.value.map((w) => w.toLowerCase()).toSet();
      expect(
        seen,
        hasLength(entry.value.length),
        reason: 'a repeat in "${entry.key}" wastes a slot on the strip',
      );
    }
  });

  test('no word follows itself', () {
    for (final entry in starterPredictions.entries) {
      expect(
        entry.value.map((w) => w.toLowerCase()),
        isNot(contains(entry.key)),
        reason: 'suggesting "${entry.key}" after itself is never the answer',
      );
    }
  });
}
