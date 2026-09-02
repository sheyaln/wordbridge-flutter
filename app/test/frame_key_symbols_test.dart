import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/system_emoji_pack.dart';

/// §4.69. The keys every board carries, with a picture on them.
///
/// They had none. The talk grid resolves a bare word through the curated pack
/// alone, and that pack has no entry for `home`, `back`, `more categories` or a
/// paging key — so they drew as words while every ordinary word beside them
/// had a drawing.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
  });

  tearDown(() async => db.close());

  /// System keys only. Two of these labels are also ordinary words — `home`
  /// is a place and `back` is a body part — and those are vocabulary a person
  /// says, not controls. They keep whatever picture their word has and must
  /// never take the frame's arrow.
  Future<List<Button>> named(String label) =>
      (db.select(db.buttons)..where(
            (b) =>
                b.vocabularyId.equals(vocabId) &
                b.label.equals(label) &
                b.isSystem.equals(true),
          ))
          .get();

  Future<List<Button>> wordsNamed(String label) =>
      (db.select(db.buttons)..where(
            (b) =>
                b.vocabularyId.equals(vocabId) &
                b.label.equals(label) &
                b.isSystem.equals(false),
          ))
          .get();

  Future<Symbol?> symbolOn(Button button) async {
    final id = button.symbolId;
    if (id == null) return null;
    return (db.select(
      db.symbols,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  test('each fixed key carries the emoji chosen for it', () async {
    for (final entry in frameKeyEmoji.entries) {
      if (entry.key.isEmpty) continue; // the fallback's details, not a key
      final buttons = await named(entry.key);
      // A paging key does not exist on a board set with one page.
      if (buttons.isEmpty) {
        continue;
      }

      for (final button in buttons) {
        final symbol = await symbolOn(button);
        expect(
          symbol,
          isNotNull,
          reason: '"${entry.key}" has no picture and every word beside it does',
        );
        expect(symbol!.externalId, entry.value.$2);
        expect(symbol.packId, entry.value.$1);
      }
    }
  });

  test('back is the back arrow, which is what it was asked to be', () async {
    final back = (await named('back')).first;
    final symbol = await symbolOn(back);

    expect(symbol!.externalId, '1f519');
    expect(SystemEmojiPack.charactersFor('1f519'), isNotNull);
  });

  test('and a page key is not the same arrow as leaving the board', () async {
    // Both can stand in the same row at once — page two carries `back` and
    // `back a page` side by side — and they do different things. One glyph on
    // both would be two controls wearing one face.
    expect(frameKeyEmoji['back']!.$2, isNot(frameKeyEmoji['back a page']!.$2));
  });

  test('one symbol row per emoji, not one per board', () async {
    // Every board carries its own copy of each fixed key, because a location
    // is a row. The picture is not per location.
    final rows = await (db.select(
      db.symbols,
    )..where((s) => s.packId.equals(SystemEmojiPack.packId))).get();
    final ids = {for (final r in rows) r.id};

    expect(ids.length, rows.length, reason: 'duplicated symbol rows');
    expect(
      rows.length,
      lessThanOrEqualTo(frameKeyEmoji.length),
      reason: 'one row per emoji at most, however many boards carry the key',
    );
  });

  test('a category key keeps the picture its word already has', () async {
    // `food` is a word before it is a control, and it has a drawing in the
    // curated pack. Handing it an emoji would replace a chosen picture with a
    // guess.
    for (final button in await named('food')) {
      expect(await symbolOn(button), isNull);
    }
  });

  test('the emoji named are ones the pack actually carries', () async {
    // A codepoint with a typo in it resolves to nothing and draws nothing,
    // which looks exactly like the bug this fixes.
    final pack = SystemEmojiPack();
    for (final entry in frameKeyEmoji.entries) {
      if (entry.value.$1 != SystemEmojiPack.packId) continue;

      final characters = SystemEmojiPack.charactersFor(entry.value.$2);
      expect(
        characters,
        isNotNull,
        reason: '"${entry.key}" names ${entry.value.$2}, which is not an emoji',
      );
      expect(
        await pack.resolve((
          packId: SystemEmojiPack.packId,
          externalId: entry.value.$2,
          label: entry.value.$3,
        )),
        characters,
      );
    }
  });

  test('more categories is the picture that was chosen for it', () async {
    // A downloading pack, not the emoji font: no emoji says "more of these"
    // rather than "again". It arrives when it is fetched, and shows its words
    // until then, which is how every unfetched picture behaves.
    final chosen = frameKeyEmoji['more categories']!;
    expect(chosen.$1, 'globalsymbols');
    expect(chosen.$2, '53182');

    final key = (await named('more categories')).first;
    final symbol = await symbolOn(key);
    expect(symbol!.packId, 'globalsymbols');
    expect(symbol.externalId, '53182');
  });

  test('a word that shares a key\'s name does not take its arrow', () async {
    // `home` is on the places board and `back` is on the body board, as words
    // somebody says. Matching on the label alone would have put a navigation
    // arrow on a body part.
    for (final label in ['home', 'back']) {
      final words = await wordsNamed(label);
      expect(words, isNotEmpty, reason: '"$label" is vocabulary too');
      for (final word in words) {
        final symbol = await symbolOn(word);
        expect(
          symbol?.id.startsWith('frame-') ?? false,
          isFalse,
          reason: 'the body part "$label" is wearing the frame arrow',
        );
      }
    }
  });

  test('and its fallback emoji is on the device before it is needed', () async {
    // §4.73. The chosen picture for `more categories` is fetched, so a device
    // that has never had a network draws nothing there while the four keys
    // beside it are fine. The fallback is a glyph the platform already has.
    //
    // Seeded up front, not written when the first one fails: the device that
    // would have to write it is exactly the device that cannot.
    final fallbackId = symbolFallbacks['frame-53182'];
    expect(fallbackId, isNotNull, reason: 'nothing to fall back to');

    final row = await (db.select(
      db.symbols,
    )..where((s) => s.id.equals(fallbackId!))).getSingleOrNull();

    expect(row, isNotNull, reason: 'the fallback was never written');
    expect(row!.packId, SystemEmojiPack.packId);
    expect(SystemEmojiPack.charactersFor(row.externalId!), isNotNull);
  });

  test('and the fallback is not what the button points at', () async {
    // The moment the fetch lands the chosen picture wins again, which is only
    // true because nothing writes the fallback onto the button.
    final key = (await named('more categories')).first;
    expect(key.symbolId, 'frame-53182');
  });
}
