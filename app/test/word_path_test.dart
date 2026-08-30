import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/talk/word_path.dart';

/// A word somebody knows is in there, and the movements that reach it.
///
/// Two things have to hold for the answer to be worth anything. It must name a
/// location the board will actually draw — an answer that leads to a masked
/// cell is worse than no answer, because it was trusted. And it must give the
/// whole route, turns of the category wheel and pages included, because the
/// board is not the hard part.
void main() {
  late WordbridgeDatabase db;
  late String vocabId;
  late Vocabulary vocab;
  late SystemFrame frame;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    vocabId = await seedCoreBoardSet(db, rows: 7, cols: 12);
    vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabId))).getSingle();
    frame = SystemFrame.parse(vocab.systemCellMap)!;
  });

  tearDown(() async => db.close());

  Future<List<WordPath>> find(String query, {int limit = 20, int? level}) =>
      findWords(
        db,
        vocabularyId: vocabId,
        query: query,
        limit: limit,
        vocabLevel: level,
      );

  Future<String> boardNamed(String name) async => (await (db.select(
    db.boards,
  )..where((b) => b.name.equals(name))).getSingle()).id;

  Future<Button> wordNamed(String label, String boardName) async {
    final board = await boardNamed(boardName);
    final rows =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.buttons.label.equals(label) & db.cells.boardId.equals(board),
            ))
            .get();
    return rows.single.readTable(db.buttons);
  }

  /// The first location on [boardId] that nothing has taken.
  Future<Cell> freeCellOn(String boardId) =>
      (db.select(db.cells)
            ..where(
              (c) =>
                  c.boardId.equals(boardId) &
                  c.state.equalsValue(CellState.emptyReserved),
            )
            ..orderBy([
              (c) => OrderingTerm.asc(c.row),
              (c) => OrderingTerm.asc(c.col),
            ])
            ..limit(1))
          .getSingle();

  /// A board a caregiver made, hung off a key on [from].
  Future<({String boardId, Cell key})> boardOffOf(
    String from, {
    String name = 'toys',
    String keyLabel = 'toys',
  }) async {
    final made = await materialiseBoard(
      db,
      vocabularyId: vocabId,
      name: name,
      kind: BoardKind.category,
    );
    final cell = await freeCellOn(from);
    await placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: keyLabel,
      message: '',
      action: ButtonAction.navigate,
      targetBoardId: made,
    );
    return (boardId: made, key: cell);
  }

  Future<String> placeOn(
    String boardId, {
    required String label,
    required String message,
    int vocabLevel = 1,
  }) async {
    final cell = await freeCellOn(boardId);
    return placeButton(
      db,
      vocabularyId: vocabId,
      cellId: cell.id,
      label: label,
      message: message,
      vocabLevel: vocabLevel,
    );
  }

  PathStep cycleStep(String label) => (
    label: label,
    row: frame.row,
    col: frame.cycleCol!,
    action: ButtonAction.cycleCategories,
    boardId: null,
  );

  Future<PathStep> categoryStep(String name) async {
    final at = frame.categories.indexWhere((c) => c.name == name);
    return (
      label: name,
      row: frame.row,
      col: frame.categoryCols[at % frame.categoryCols.length],
      action: ButtonAction.navigate,
      boardId: frame.categories[at].boardId,
    );
  }

  Future<PathStep> pageStep(String toBoard) async => (
    label: moreWordsLabel,
    row: frame.row,
    col: frame.pageForwardCol,
    action: ButtonAction.navigate,
    boardId: await boardNamed(toBoard),
  );

  group('the way to a word', () {
    test('on the home board is no way at all', () async {
      final found = await find('want');

      expect(found.single.boardId, vocab.rootBoardId);
      expect(
        found.single.steps,
        isEmpty,
        reason:
            'home is where every route starts, so reaching it costs no '
            'movements',
      );
    });

    test('on a category board is one press, from anywhere', () async {
      final found = await find('juice');
      final food = await boardNamed('food');

      expect(found.single.boardId, food);
      expect(found.single.steps, [await categoryStep('food')]);
    });

    test('behind the wheel counts the turns as well', () async {
      // `numbers` is the last category and the slots hold six, so it is on the
      // second turn of the wheel. A route that named the key without the turn
      // would describe a press that opens something else.
      final found = await find('none');

      expect(found.single.boardId, await boardNamed('numbers'));
      expect(found.single.steps, [
        cycleStep(cycleCategoriesLabel),
        await categoryStep('numbers'),
      ]);
    });

    test('on a later page counts the pages', () async {
      final found = await find('biscuit');

      expect(found.single.boardId, await boardNamed('food 2'));
      expect(found.single.steps, [
        await categoryStep('food'),
        await pageStep('food 2'),
      ]);
    });

    test("home's own second page is reached the same way", () async {
      final found = await find('think');

      expect(found.single.boardId, await boardNamed('home 2'));
      expect(found.single.steps, [await pageStep('home 2')]);
    });

    test('names the turn key the way the caregiver renamed it', () async {
      // The route is read off the screen, so it has to use the words that are
      // on it.
      final key = await wordNamed(cycleCategoriesLabel, 'home');
      await (db.update(db.buttons)..where((b) => b.id.equals(key.id))).write(
        const ButtonsCompanion(label: Value('more groups')),
      );

      final found = await find('none');
      expect(found.single.steps.first.label, 'more groups');
    });

    test('and reads it off home, which is where the route starts', () async {
      // The frame keeps every copy of a key reading the same thing. Where a
      // board set has drifted out of that, the route still has to name the key
      // somebody is about to press first.
      final home = await wordNamed(cycleCategoriesLabel, 'home');
      await (db.update(db.buttons)..where(
            (b) =>
                b.label.equals(cycleCategoriesLabel) & b.id.isNotValue(home.id),
          ))
          .write(const ButtonsCompanion(label: Value('somewhere else')));

      final found = await find('none');
      expect(found.single.steps.first.label, cycleCategoriesLabel);
    });

    test('a category listed twice keeps the first way in', () async {
      // Appending is how the wheel grows. Appending a board that is already on
      // it must not move the route round to the longer way of reaching it.
      await (db.update(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).write(
        VocabulariesCompanion(
          systemCellMap: Value(
            frame
                .copyWith(
                  categories: [...frame.categories, frame.categories[1]],
                )
                .toJson(),
          ),
        ),
      );

      expect((await find('juice')).single.steps, [await categoryStep('food')]);
    });
  });

  group('what it will not offer', () {
    test('a word the board is not drawing', () async {
      final drink = await wordNamed('drink', 'food');
      await hideButton(db, drink.id);

      expect(
        await find('drink'),
        isEmpty,
        reason:
            'a masked cell is a dead end, and the finder is the one place '
            'somebody would trust it',
      );
    });

    test('a word that has been deleted', () async {
      final drink = await wordNamed('drink', 'food');
      await (db.update(db.buttons)..where((b) => b.id.equals(drink.id))).write(
        ButtonsCompanion(deletedAt: Value(nowMs())),
      );

      expect(await find('drink'), isEmpty);
    });

    test('a word held above the profile level', () async {
      // `none` is level two, so a profile still on level one is not being
      // shown it.
      expect(await find('none', level: 1), isEmpty);
      expect(await find('none', level: 2), hasLength(1));
    });

    test('though no level asks for everything there is', () async {
      // What a caregiver looking for where they put something wants.
      expect(await find('none'), hasLength(1));
    });

    test('the keys every board carries', () async {
      // `more` is a word on the home board. `more words` and `more categories`
      // are keys, on thirteen boards each, and answering with them would bury
      // the word under its own frame.
      final found = await find('more');

      expect(found.single.label, 'more');
      expect(found.single.boardId, vocab.rootBoardId);
    });

    test('even where a real word wears the same name', () async {
      // `back` is a key on every board and also a body part on one of them.
      final found = await find('back');

      expect(found.single.boardId, await boardNamed('body'));
    });

    test('a word on a board nothing reaches', () async {
      final orphan = await materialiseBoard(
        db,
        vocabularyId: vocabId,
        name: 'orphan',
        kind: BoardKind.category,
      );
      await placeOn(orphan, label: 'kazoo', message: 'kazoo');

      expect(
        await find('kazoo'),
        isEmpty,
        reason: 'a location with no way to it is not somewhere to be sent',
      );
    });

    test('a word behind a key that has been hidden', () async {
      final made = await boardOffOf(vocab.rootBoardId!);
      await placeOn(made.boardId, label: 'kazoo', message: 'kazoo');
      expect(await find('kazoo'), hasLength(1));

      final key = await (db.select(
        db.buttons,
      )..where((b) => b.cellId.equals(made.key.id))).getSingle();
      await hideButton(db, key.id);

      expect(await find('kazoo'), isEmpty);
    });
  });

  group('a word with two homes', () {
    test('is offered at both of them', () async {
      // Deliberate in this board set: `doctor` is a person and also something
      // the body board needs. They are two movements to two places.
      final found = await find('doctor');

      expect(found, hasLength(2));
      expect(
        {for (final path in found) path.boardId},
        {await boardNamed('people'), await boardNamed('body')},
      );
    });

    test('nearest first', () async {
      // `bike` is one press away on `places` and two on the second page of
      // `play`. Offering the long way first offers the wrong one.
      final found = await find('bike');

      expect(found, hasLength(2));
      expect(found.first.boardId, await boardNamed('places'));
      expect(found.first.steps, hasLength(1));
      expect(found.last.boardId, await boardNamed('play 2'));
      expect(found.last.steps, hasLength(2));
    });
  });

  group('what counts as a match', () {
    test('the start of a label beats the middle of one', () async {
      final found = await find('ea');
      final labels = [for (final path in found) path.label];

      expect(labels, contains('eat'));
      expect(labels, contains('bread'));
      expect(
        labels.indexOf('eat'),
        lessThan(labels.indexOf('bread')),
        reason: 'the start of a word is what somebody types to look for it',
      );
    });

    test('what a key reads beats what it says', () async {
      final board = (await boardOffOf(vocab.rootBoardId!)).boardId;
      await placeOn(board, label: 'zoo', message: 'zoo');
      await placeOn(board, label: 'coach', message: 'zoo trip');

      final found = await find('zoo');
      expect([for (final path in found) path.label], ['zoo', 'coach']);
    });

    test('but the start of what it says beats the middle of either', () async {
      // The whole of the rule, not half of it: a prefix outranks a substring
      // wherever it is found. `zoo trip` is what somebody is about to say and
      // `bazooka` merely has the letters in it somewhere.
      final board = (await boardOffOf(vocab.rootBoardId!)).boardId;
      await placeOn(board, label: 'coach', message: 'zoo trip');
      await placeOn(board, label: 'bazooka', message: 'bazooka');

      final found = await find('zoo');
      expect([for (final path in found) path.label], ['coach', 'bazooka']);
    });

    test('a word is found by what the key says as well', () async {
      final board = (await boardOffOf(vocab.rootBoardId!)).boardId;
      await placeOn(board, label: 'cuppa', message: 'I want a drink');

      final found = await find('want');
      expect([for (final path in found) path.label], contains('cuppa'));
    });

    test('including the middle of what it says', () async {
      final board = (await boardOffOf(vocab.rootBoardId!)).boardId;
      await placeOn(board, label: 'cuppa', message: 'I want a drink');

      final found = await find('a drink');
      expect([for (final path in found) path.label], ['cuppa']);
    });

    test('and by what it speaks, where that differs', () async {
      // Both, because they are two different things on two different surfaces:
      // the message goes into the sentence somebody is reading, and the
      // vocalisation is what the room hears.
      final board = (await boardOffOf(vocab.rootBoardId!)).boardId;
      final id = await placeOn(board, label: 'polite', message: 'cheers mate');
      await (db.update(db.buttons)..where((b) => b.id.equals(id))).write(
        const ButtonsCompanion(speakText: Value('thanks ever so')),
      );

      expect((await find('ever so')).single.label, 'polite');
      expect((await find('cheers')).single.label, 'polite');
    });

    test('every surface a key has, in order of how sure the match is', () async {
      // The label, the message the sentence gets, and the vocalisation the
      // room hears are three places a word can live, and somebody looking for
      // it remembers any of them. A prefix is a better answer than a substring
      // wherever it turns up.
      final board = (await boardOffOf(vocab.rootBoardId!)).boardId;

      Future<void> says(String label, String message, String? speaks) async {
        final id = await placeOn(board, label: label, message: message);
        if (speaks == null) return;
        await (db.update(db.buttons)..where((b) => b.id.equals(id))).write(
          ButtonsCompanion(speakText: Value(speaks)),
        );
      }

      await says('zebra', 'zebra', null);
      await says('polite', 'zebra mate', 'thanks ever so');
      await says('thankful', 'cheers', 'zebra time');
      await says('a zebra', 'nope', null);
      await says('outing', 'see a zebra', 'off we go');

      expect(
        [for (final path in await find('zebra')) path.label],
        ['zebra', 'polite', 'thankful', 'a zebra', 'outing'],
      );
    });

    test('case is not something anybody should have to get right', () async {
      expect(
        [for (final path in await find('JUICE')) path.label],
        [for (final path in await find('juice')) path.label],
      );
    });

    test('and neither is a stray space', () async {
      expect(
        [for (final path in await find('  juice ')) path.label],
        [for (final path in await find('juice')) path.label],
      );
    });

    test('a question pinned to every board is offered once', () async {
      // One key, at one location, that every board carries. Thirteen answers
      // would say there are thirteen ways to reach it.
      final found = await find('what');

      expect(found, hasLength(1));
      expect(found.single.boardId, vocab.rootBoardId);
      expect(found.single.steps, isEmpty);
    });

    test('a caregiver word on a paging location is its own word', () async {
      // The last page has no forward key, so that location is free. What goes
      // there is not a copy of anything.
      final page = await boardNamed('home 2');
      final cell = await cellAt(
        db,
        boardId: page,
        row: frame.row,
        col: frame.pageForwardCol,
      );
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: cell.id,
        label: 'kazoo',
        message: 'kazoo',
      );

      expect((await find('kazoo')).single.boardId, page);
    });

    test('and two of them are two words, not one twice', () async {
      // Same location, two boards, and neither is a copy of the other: the
      // frame owns this column above the system row and nothing below it.
      for (final board in ['home 2', 'numbers']) {
        final cell = await cellAt(
          db,
          boardId: await boardNamed(board),
          row: frame.row,
          col: frame.pageForwardCol,
        );
        await placeButton(
          db,
          vocabularyId: vocabId,
          cellId: cell.id,
          label: 'kazoo',
          message: 'kazoo',
        );
      }

      expect(await find('kazoo'), hasLength(2));
    });
  });

  group('the shape of the answer', () {
    test('never longer than asked for', () async {
      final all = await find('a');
      expect(all.length, greaterThan(3));
      expect(await find('a', limit: 3), all.take(3));
    });

    test('nothing at all for nothing to look for', () async {
      expect(await find(''), isEmpty);
      expect(await find('   '), isEmpty);
      expect(await find('juice', limit: 0), isEmpty);
    });

    test('nothing for a vocabulary that is not there', () async {
      expect(
        await findWords(db, vocabularyId: newId(), query: 'juice'),
        isEmpty,
      );
    });

    test('the same order every time it is asked', () async {
      final once = await find('e');
      final twice = await find('e');

      expect(
        [for (final path in once) path.buttonId],
        [for (final path in twice) path.buttonId],
      );
    });
  });

  group('a board a caregiver made by hand', () {
    test('is reached by walking the key that opens it', () async {
      final made = await boardOffOf(vocab.rootBoardId!);
      await placeOn(made.boardId, label: 'kazoo', message: 'kazoo');

      final found = await find('kazoo');
      expect(found.single.boardId, made.boardId);
      expect(found.single.steps, [
        (
          label: 'toys',
          row: made.key.row,
          col: made.key.col,
          action: ButtonAction.navigate,
          boardId: made.boardId,
        ),
      ]);
    });

    test('through the category it was hung off', () async {
      final food = await boardNamed('food');
      final made = await boardOffOf(food, name: 'puddings', keyLabel: 'sweet');
      await placeOn(made.boardId, label: 'kazoo', message: 'kazoo');

      final found = await find('kazoo');
      expect(found.single.steps, [
        await categoryStep('food'),
        (
          label: 'sweet',
          row: made.key.row,
          col: made.key.col,
          action: ButtonAction.navigate,
          boardId: made.boardId,
        ),
      ]);
    });

    test('by the shorter way in, where there are two', () async {
      // The same board hung off the home board's second page and off the far
      // side of the category wheel. Both work; one is two presses and the
      // other is three.
      final made = await boardOffOf(await boardNamed('home 2'));
      final numbers = await freeCellOn(await boardNamed('numbers'));
      await placeButton(
        db,
        vocabularyId: vocabId,
        cellId: numbers.id,
        label: 'counting toys',
        message: '',
        action: ButtonAction.navigate,
        targetBoardId: made.boardId,
      );
      await placeOn(made.boardId, label: 'kazoo', message: 'kazoo');

      final found = await find('kazoo');
      expect(found.single.steps, hasLength(2));
      expect(found.single.steps.first, await pageStep('home 2'));
    });
  });

  test('a board set with no frame recorded keeps what it can', () async {
    // An imported board set. The category keys are still real buttons that
    // navigate, so the boards they open are still reachable — but the wheel is
    // what reaches the rest, and without a recording there is no wheel.
    await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId)))
        .write(const VocabulariesCompanion(systemCellMap: Value('')));

    expect((await find('juice')).single.steps, hasLength(1));
    expect(
      await find('none'),
      isEmpty,
      reason: 'nothing on this board set turns the wheel to `numbers`',
    );
  });

  test('a frame with more categories than it can turn to', () async {
    // A recording that names eight categories, one slot, and no key to move
    // the window. Seven of them have no way in at all, and saying so is the
    // only honest answer — a route through a key that is not on the board
    // would send somebody to a location that is not there.
    await (db.update(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabId))).write(
      VocabulariesCompanion(
        systemCellMap: Value(
          SystemFrame(
            row: frame.row,
            homeCol: frame.homeCol,
            backCol: frame.backCol,
            categoryCols: [frame.categoryCols.first],
            cycleCol: null,
            pageBackCol: frame.pageBackCol,
            pageForwardCol: frame.pageForwardCol,
            categories: frame.categories,
          ).toJson(),
        ),
      ),
    );

    expect(await find('none'), isEmpty);
    expect(
      (await find('juice')).single.steps,
      hasLength(1),
      reason: 'the category keys already on the board still open what they did',
    );
  });

  test('a vocabulary with no home board reaches nothing', () async {
    await (db.update(db.vocabularies)..where((v) => v.id.equals(vocabId)))
        .write(const VocabulariesCompanion(rootBoardId: Value(null)));

    expect(await find('juice'), isEmpty);
  });
}
