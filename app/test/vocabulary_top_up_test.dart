import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/vocabulary_top_up.dart';
import 'package:wordbridge/db/tables.dart';

/// Every button in the whole board set, keyed by what it is and where it lives.
///
/// The key names the thing a user learned — this word, on this board — and the
/// value is everything about where it sits. Two fingerprints that differ on a
/// key that existed in both are a word that moved, which is the failure this
/// whole project is built to prevent.
Future<Map<String, String>> fingerprint(WordbridgeDatabase db) async {
  final names = {
    for (final b in await db.select(db.boards).get()) b.id: b.name,
  };

  final rows = await (db.select(db.buttons).join([
    innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
  ])).get();

  final out = <String, String>{};
  for (final r in rows) {
    final button = r.readTable(db.buttons);
    final cell = r.readTable(db.cells);
    out['${names[cell.boardId]}|${button.isSystem}|${button.label}'] = [
      cell.id,
      cell.row,
      cell.col,
      button.hidden,
      button.vocabLevel,
      names[button.targetBoardId] ?? '',
    ].join('|');
  }
  return out;
}

Future<SystemFrame> frameOf(WordbridgeDatabase db, String vocabId) async {
  final vocab = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabId))).getSingle();

  final frame = SystemFrame.parse(vocab.systemCellMap);
  expect(frame, isNotNull, reason: 'the wheel recording is unreadable');
  return frame!;
}

/// Which turn of the wheel each category shows on, and in which slot.
///
/// What a user has learned is not the list but this: press that key, on that
/// turn, get that board. It has to survive a category being added.
Future<Map<String, ({int page, int slot})>> wheelPositions(
  WordbridgeDatabase db,
  String vocabId,
) async {
  final frame = await frameOf(db, vocabId);
  final slots = frame.categoryCols.length;

  return {
    for (var i = 0; i < frame.categories.length; i++)
      frame.categories[i].name: (page: i ~/ slots, slot: i % slots),
  };
}

/// Puts the board set back to what a profile set up before [category] shipped
/// would actually have: no board, no key anywhere, and a recording that has
/// never heard of it.
///
/// The keys come off and go back on from the plan for one fewer category,
/// which is the plan that built those boards in the first place.
Future<void> unship(
  WordbridgeDatabase db,
  String vocabId,
  String category,
) async {
  final vocab = await (db.select(
    db.vocabularies,
  )..where((v) => v.id.equals(vocabId))).getSingle();
  final frame = await frameOf(db, vocabId);

  final pages = await (db.select(
    db.boards,
  )..where((b) => b.name.equals(category) | b.name.like('$category %'))).get();

  // Every key that navigates comes off first: the category keys and the cycle
  // key go back on from the older plan, and the paging keys between the pages
  // would otherwise hold the boards in place.
  final slots = [
    ...frame.categoryCols,
    if (frame.cycleCol != null) frame.cycleCol!,
  ];

  for (final board in await db.select(db.boards).get()) {
    for (final col in slots) {
      final cell = await cellAt(
        db,
        boardId: board.id,
        row: frame.row,
        col: col,
      );
      await (db.delete(
        db.buttons,
      )..where((b) => b.cellId.equals(cell.id))).go();
      await (db.update(db.cells)..where((c) => c.id.equals(cell.id))).write(
        const CellsCompanion(state: Value(CellState.emptyReserved)),
      );
    }
  }

  for (final board in pages) {
    await (db.delete(db.buttons)..where(
          (b) => b.cellId.isInQuery(
            db.selectOnly(db.cells)
              ..addColumns([db.cells.id])
              ..where(db.cells.boardId.equals(board.id)),
          ),
        ))
        .go();
  }

  for (final board in pages) {
    await (db.delete(db.cells)..where((c) => c.boardId.equals(board.id))).go();
    await (db.delete(db.boards)..where((b) => b.id.equals(board.id))).go();
  }

  final older = SystemFrame.of(
    SystemRowPlan.forGrid(
      rows: vocab.gridRows,
      cols: vocab.gridCols,
      categories: frame.categories.length - 1,
    ),
    [
      for (final c in frame.categories)
        if (c.name != category) c,
    ],
  );

  for (final board in await db.select(db.boards).get()) {
    for (var i = 0; i < older.categoryCols.length; i++) {
      final cell = await cellAt(
        db,
        boardId: board.id,
        row: older.row,
        col: older.categoryCols[i],
      );
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: older.categories[i].name,
        message: '',
        action: ButtonAction.navigate,
        targetBoardId: older.categories[i].boardId,
        isSystem: true,
      );
    }

    if (older.cycleCol != null) {
      final cell = await cellAt(
        db,
        boardId: board.id,
        row: older.row,
        col: older.cycleCol!,
      );
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'more categories',
        message: '',
        action: ButtonAction.cycleCategories,
        isSystem: true,
      );
    }
  }

  await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId))).write(
    VocabulariesCompanion(systemCellMap: Value(older.toJson())),
  );
}

/// Words on a board, ignoring the keys every board carries.
Future<Map<String, ({int row, int col, bool hidden})>> wordsOn(
  WordbridgeDatabase db,
  String boardName,
) async {
  final board = await (db.select(
    db.boards,
  )..where((b) => b.name.equals(boardName))).getSingle();

  final rows =
      await (db.select(db.buttons).join([
            innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
          ])..where(
            db.cells.boardId.equals(board.id) &
                db.buttons.isSystem.equals(false),
          ))
          .get();

  return {
    for (final r in rows)
      r.readTable(db.buttons).label: (
        row: r.readTable(db.cells).row,
        col: r.readTable(db.cells).col,
        hidden: r.readTable(db.buttons).hidden,
      ),
  };
}

/// Words on every page of a board, wherever the grid put them.
Future<Map<String, ({int row, int col, bool hidden})>> wordsAcross(
  WordbridgeDatabase db,
  String category,
) async {
  final pages = await (db.select(
    db.boards,
  )..where((b) => b.name.equals(category) | b.name.like('$category %'))).get();

  final words = <String, ({int row, int col, bool hidden})>{};
  for (final page in pages) {
    words.addAll(await wordsOn(db, page.name));
  }
  return words;
}

/// Bringing new shipped words to a board that already exists.
///
/// The whole point is that it is additive: a word lands where the layout rule
/// already puts it, or it does not land at all. A top-up that moved something
/// would be a rebuild wearing a disguise.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db);
  });

  tearDown(() async => db.close());

  Future<Board> boardNamed(String name) =>
      (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

  Future<Map<String, ({int row, int col})>> positionsOn(String boardId) async {
    final query = db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.cells.boardId.equals(boardId));

    return {
      for (final r in await query.get())
        r.readTable(db.buttons).label: (
          row: r.readTable(db.cells).row,
          col: r.readTable(db.cells).col,
        ),
    };
  }

  /// Removes a word, leaving its location free, to stand in for a board built
  /// before that word shipped.
  Future<({int row, int col})> removeWord(String label) async {
    final button = await (db.select(
      db.buttons,
    )..where((b) => b.label.equals(label))).getSingle();

    final cell = await (db.select(
      db.cells,
    )..where((c) => c.id.equals(button.cellId!))).getSingle();

    await (db.delete(db.buttons)..where((b) => b.id.equals(button.id))).go();
    await (db.update(db.cells)..where((c) => c.id.equals(cell.id))).write(
      const CellsCompanion(state: Value(CellState.emptyReserved)),
    );

    return (row: cell.row, col: cell.col);
  }

  test('a missing word returns to the location the rule gives it', () async {
    final home = await boardNamed('home');
    final was = await removeWord('yes');

    final result = await topUpVocabulary(db, vocabularyId: vocabId);

    expect(result.added.map((a) => a.label), contains('yes'));
    expect((await positionsOn(home.id))['yes'], was);
  });

  test('nothing already on the board moves', () async {
    // The one thing a top-up must never do.
    final home = await boardNamed('home');
    await removeWord('yes');

    final before = await positionsOn(home.id);
    await topUpVocabulary(db, vocabularyId: vocabId);
    final after = await positionsOn(home.id);

    for (final entry in before.entries) {
      expect(
        after[entry.key],
        entry.value,
        reason: '"${entry.key}" moved during a top-up',
      );
    }
  });

  test('a board with nothing missing is left alone', () async {
    final result = await topUpVocabulary(db, vocabularyId: vocabId);

    expect(result.added, isEmpty);
    expect(result.blocked, isEmpty);
    expect(result.isEmpty, isTrue);
  });

  test('a caregiver’s own word keeps the location', () async {
    // Their choice about their own child's board outranks ours about a
    // shipped default.
    final home = await boardNamed('home');
    final was = await removeWord('yes');

    final cell = await cellAt(db, boardId: home.id, row: was.row, col: was.col);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: 'Nana',
      message: 'Nana',
      partOfSpeech: PartOfSpeech.noun,
    );

    final result = await topUpVocabulary(db, vocabularyId: vocabId);

    expect(result.added.map((a) => a.label), isNot(contains('yes')));
    expect(
      result.blocked.map((b) => b.label),
      contains('yes'),
      reason: 'a caregiver has to be told what did not fit, not left guessing',
    );
    expect(result.blocked.single.occupant, 'Nana');
    expect((await positionsOn(home.id))['Nana'], was);
  });

  test('a dry run changes nothing', () async {
    await removeWord('yes');

    final preview = await topUpVocabulary(
      db,
      vocabularyId: vocabId,
      dryRun: true,
    );
    expect(preview.added.map((a) => a.label), contains('yes'));

    final home = await boardNamed('home');
    expect((await positionsOn(home.id))['yes'], isNull);

    // And the real run then does exactly what the preview said.
    final applied = await topUpVocabulary(db, vocabularyId: vocabId);
    expect(applied.added.length, preview.added.length);
  });

  test('the question mark reaches every board, not just the root', () async {
    // The pinned column is the same on every board or it is not pinned.
    for (final board in await db.select(db.boards).get()) {
      final button =
          await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])..where(
                db.cells.boardId.equals(board.id) &
                    db.buttons.label.equals('?'),
              ))
              .get();

      expect(button, hasLength(1), reason: '"${board.name}" cannot ask');
    }
  });

  test('a top-up run twice adds nothing the second time', () async {
    await removeWord('yes');
    await removeWord('no');

    final first = await topUpVocabulary(db, vocabularyId: vocabId);
    expect(first.added, hasLength(2));

    final second = await topUpVocabulary(db, vocabularyId: vocabId);
    expect(second.added, isEmpty);
  });

  test('every location stays occupied by exactly one word', () async {
    await removeWord('yes');
    await topUpVocabulary(db, vocabularyId: vocabId);

    final seen = <String>{};
    for (final r in await (db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])).get()) {
      final cell = r.readTable(db.cells);
      expect(seen.add(cell.id), isTrue);
    }
  });

  /// A category that shipped after the board set was built.
  ///
  /// Adding a whole board displaces nothing — that is what makes it the safest
  /// change available — so a profile that has invested most in its board is
  /// exactly the one that should receive it, rather than being told to rebuild.
  group('a category board that shipped later', () {
    test('the board arrives, with its words in it', () async {
      await unship(db, vocabId, 'doing');
      expect(
        await (db.select(
          db.boards,
        )..where((b) => b.name.equals('doing'))).get(),
        isEmpty,
        reason: 'the fixture did not remove the board',
      );

      final result = await topUpVocabulary(db, vocabularyId: vocabId);

      expect(result.addedBoards, ['doing']);
      expect(result.refusedBoards, isEmpty);

      // Not "a board exists" — a board with the vocabulary in it. An empty
      // category teaches that navigating is pointless.
      final words = await wordsOn(db, 'doing');
      expect(
        words.keys,
        containsAll(['wash', 'sit', 'ask', 'remember', 'hold', 'share']),
      );
      expect(words.keys.where((l) => l != '?'), hasLength(48 + 5));
      expect(
        result.added.where((a) => a.board == 'doing').map((a) => a.label),
        containsAll(['wash', 'breathe', 'cry']),
      );
    });

    test('nothing already on the board moves', () async {
      // The one thing adding a board may never do. Every button and every key
      // has to come out of this identical, down to the cell it sits in.
      await unship(db, vocabId, 'doing');
      final before = await fingerprint(db);
      final boardsBefore = (await db.select(db.boards).get()).length;

      await topUpVocabulary(db, vocabularyId: vocabId);

      final after = await fingerprint(db);
      for (final entry in before.entries) {
        expect(after[entry.key], entry.value, reason: '${entry.key} moved');
      }

      // And the only thing new on a board that already existed is the one key
      // that opens the new one.
      final onOldBoards = after.keys
          .toSet()
          .difference(before.keys.toSet())
          .where((k) => !k.startsWith('doing'))
          .toList();

      expect(onOldBoards, hasLength(boardsBefore));
      for (final key in onOldBoards) {
        expect(key, endsWith('|true|doing'));
      }
    });

    test('the new key opens the new board from everywhere', () async {
      // A key on one board and not another is not a fixed key.
      await unship(db, vocabId, 'doing');
      await topUpVocabulary(db, vocabularyId: vocabId);

      final doing = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('doing'))).getSingle();

      for (final board in await db.select(db.boards).get()) {
        final rows =
            await (db.select(db.buttons).join([
                  innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
                ])..where(
                  db.cells.boardId.equals(board.id) &
                      db.buttons.label.equals('doing') &
                      db.buttons.isSystem.equals(true),
                ))
                .get();

        expect(rows, hasLength(1), reason: '"${board.name}" cannot reach it');
        expect(rows.single.readTable(db.buttons).targetBoardId, doing.id);
        expect(rows.single.readTable(db.cells).row, 6);
        expect(rows.single.readTable(db.cells).col, 9);
      }
    });

    test('the wheel gains it at the end, and moves nothing else', () async {
      await unship(db, vocabId, 'doing');
      final before = await wheelPositions(db, vocabId);
      final colsBefore = (await frameOf(db, vocabId)).categoryCols;

      await topUpVocabulary(db, vocabularyId: vocabId);

      final after = await wheelPositions(db, vocabId);
      final frame = await frameOf(db, vocabId);

      for (final entry in before.entries) {
        expect(
          after[entry.key],
          entry.value,
          reason: '"${entry.key}" is on a different turn or slot of the wheel',
        );
      }

      expect(after['doing'], (page: 0, slot: 6));
      expect(frame.categories.map((c) => c.name).toList(), [
        'people',
        'food',
        'play',
        'feelings',
        'places',
        'body',
        'doing',
      ]);

      // At 7x12 a seventh category fits in a column the system row was not
      // using, so the wheel still never turns.
      expect(frame.categoryCols.take(colsBefore.length), colsBefore);
      expect(frame.categoryCols, [...colsBefore, 9]);
      expect(frame.cycleCol, isNull);
    });

    test('running it twice adds nothing the second time', () async {
      await unship(db, vocabId, 'doing');
      await topUpVocabulary(db, vocabularyId: vocabId);

      final settled = await fingerprint(db);
      final second = await topUpVocabulary(db, vocabularyId: vocabId);

      expect(second.addedBoards, isEmpty);
      expect(second.added, isEmpty);
      expect(second.blocked, isEmpty);
      expect(await fingerprint(db), settled);

      expect(
        await (db.select(
          db.boards,
        )..where((b) => b.name.equals('doing'))).get(),
        hasLength(1),
      );
      expect(
        (await frameOf(db, vocabId)).categories.map((c) => c.name),
        hasLength(7),
      );
    });

    test('a board set that already has it is left alone', () async {
      final before = await fingerprint(db);
      final result = await topUpVocabulary(db, vocabularyId: vocabId);

      expect(result.addedBoards, isEmpty);
      expect(result.isEmpty, isTrue);
      expect(await fingerprint(db), before);
    });

    test('a dry run reports the board and creates nothing', () async {
      await unship(db, vocabId, 'doing');
      final before = await fingerprint(db);

      final preview = await topUpVocabulary(
        db,
        vocabularyId: vocabId,
        dryRun: true,
      );

      expect(preview.addedBoards, ['doing']);
      expect(await fingerprint(db), before);
      expect(
        await (db.select(
          db.boards,
        )..where((b) => b.name.equals('doing'))).get(),
        isEmpty,
      );

      // And the run that follows does exactly what the preview promised.
      final applied = await topUpVocabulary(db, vocabularyId: vocabId);
      expect(applied.added, preview.added);
    });

    test('a recording that is not a wheel is refused, not guessed at', () async {
      // What an imported board set carries. Inventing a frame for it would put
      // keys wherever this build happens to think they go.
      await unship(db, vocabId, 'doing');
      await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId)))
          .write(const VocabulariesCompanion(systemCellMap: Value('{}')));

      final before = await fingerprint(db);
      final result = await topUpVocabulary(db, vocabularyId: vocabId);

      expect(result.refusedBoards, ['doing']);
      expect(result.addedBoards, isEmpty);
      expect(await fingerprint(db), before);
    });
  });

  group('a category board on a grid that is not 7x12', () {
    late WordbridgeDatabase narrow;
    late String narrowId;

    Future<void> seedAt(int rows, int cols) async {
      narrow = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(narrow.close);
      narrowId = await seedCoreBoardSet(narrow, rows: rows, cols: cols);
      await unship(narrow, narrowId, 'doing');
    }

    test('a wheel that already turns just gains a turn', () async {
      // 5x9 shows three categories at a time, so a seventh costs no key at
      // all — it is one more press of one that is already there.
      await seedAt(5, 9);
      final before = await wheelPositions(narrow, narrowId);
      final was = await frameOf(narrow, narrowId);
      final fingerprintBefore = await fingerprint(narrow);

      await topUpVocabulary(narrow, vocabularyId: narrowId);

      final frame = await frameOf(narrow, narrowId);
      expect(frame.categoryCols, was.categoryCols);
      expect(frame.cycleCol, was.cycleCol);
      expect(frame.cycleCol, isNotNull);

      final after = await wheelPositions(narrow, narrowId);
      for (final entry in before.entries) {
        expect(after[entry.key], entry.value, reason: '"${entry.key}" moved');
      }
      expect(after['doing'], (page: 2, slot: 0));

      for (final entry in fingerprintBefore.entries) {
        expect(
          (await fingerprint(narrow))[entry.key],
          entry.value,
          reason: '${entry.key} moved',
        );
      }
    });

    test('a full row of slots gains the cycle key it needs', () async {
      // 11 columns leaves room for exactly six category keys. The seventh
      // cannot have one, so the wheel has to start turning — and the key that
      // turns it goes in the gap column, the only one the row is not using.
      await seedAt(7, 11);
      final was = await frameOf(narrow, narrowId);
      expect(was.cycleCol, isNull, reason: 'the fixture already cycles');
      expect(was.categoryCols, [3, 4, 5, 6, 7, 8]);

      final before = await wheelPositions(narrow, narrowId);
      final fingerprintBefore = await fingerprint(narrow);

      await topUpVocabulary(narrow, vocabularyId: narrowId);

      final frame = await frameOf(narrow, narrowId);
      expect(frame.categoryCols, was.categoryCols);
      expect(frame.cycleCol, 2);

      final after = await wheelPositions(narrow, narrowId);
      for (final entry in before.entries) {
        expect(after[entry.key], entry.value, reason: '"${entry.key}" moved');
      }
      expect(after['doing'], (page: 1, slot: 0));

      final now = await fingerprint(narrow);
      for (final entry in fingerprintBefore.entries) {
        expect(now[entry.key], entry.value, reason: '${entry.key} moved');
      }

      // And the key that turns the wheel is on every board, or the seventh
      // category is reachable from some boards and not others.
      for (final board in await narrow.select(narrow.boards).get()) {
        final cell = await cellAt(narrow, boardId: board.id, row: 6, col: 2);
        final key = await (narrow.select(
          narrow.buttons,
        )..where((b) => b.cellId.equals(cell.id))).getSingle();

        expect(key.action, ButtonAction.cycleCategories);
      }
    });

    test(
      'words the grid cannot hold shed to a page, as they always do',
      () async {
        // Nothing special about arriving late: the board pages exactly as it
        // would have if it had been there from the start.
        await seedAt(5, 9);
        await topUpVocabulary(narrow, vocabularyId: narrowId);

        final fresh = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        addTearDown(fresh.close);
        await seedCoreBoardSet(fresh, rows: 5, cols: 9);

        final pages = (await fresh.select(fresh.boards).get())
            .map((b) => b.name)
            .where((n) => n == 'doing' || n.startsWith('doing '))
            .toList();

        expect(
          pages,
          hasLength(greaterThan(1)),
          reason: '5x9 holds it on one page',
        );

        for (final page in pages) {
          expect(
            await wordsOn(narrow, page),
            await wordsOn(fresh, page),
            reason: '"$page" is not the board a new profile gets',
          );
        }
      },
    );
  });

  group('the presets a board set was set up with', () {
    /// The feelings board carries both an age preset's extras and the strong
    /// language, so it is the one that shows whether a late arrival is built
    /// the way an on-time one is.
    Future<Map<String, ({int row, int col, bool hidden})>> lateFeelings(
      AgeBand ageBand, {
      bool? profanity,
    }) async {
      await unship(db, vocabId, 'feelings');
      await topUpVocabulary(
        db,
        vocabularyId: vocabId,
        ageBand: ageBand,
        profanity: profanity,
      );
      return wordsAcross(db, 'feelings');
    }

    test('an adult board gets the adult words', () async {
      final words = await lateFeelings(AgeBand.adult);

      expect(
        words.keys,
        containsAll(['frustrated', 'patronised', 'I disagree', 'talk to me']),
        reason: 'the preset never reached the board that arrived late',
      );
    });

    test('a child board gets none of them', () async {
      final words = await lateFeelings(AgeBand.child);

      expect(words.keys, isNot(contains('frustrated')));
      expect(words.keys, isNot(contains('fuck')));
    });

    test('strong language is placed but switched off by default', () async {
      // Hiding holds the location, so switching it on later reveals it where
      // it has always been rather than pushing other words aside.
      final words = await lateFeelings(AgeBand.teen);

      expect(words['fuck'], isNotNull);
      expect(words['fuck']!.hidden, isTrue);
      expect(words['annoyed']!.hidden, isFalse);
    });

    test('and switched on when the caregiver asked for it', () async {
      final words = await lateFeelings(AgeBand.teen, profanity: true);

      expect(words['fuck']!.hidden, isFalse);
    });

    test('a late board is appended, never slotted back in', () async {
      // Its old position in the shipped order is not its position here: every
      // key after it has been learned opening something else.
      await unship(db, vocabId, 'feelings');
      await topUpVocabulary(db, vocabularyId: vocabId);

      expect((await frameOf(db, vocabId)).categories.map((c) => c.name), [
        'people',
        'food',
        'play',
        'places',
        'body',
        'doing',
        'feelings',
      ]);
    });
  });
}
