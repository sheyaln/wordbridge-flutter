import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/talk/route_walk.dart';
import 'package:wordbridge/features/talk/word_path.dart';

/// Turning a route into the movements that walk it.
///
/// The finder presses keys rather than arriving at a board (§4.42), so what is
/// under test is the sequence: home first, one beat per key, the wheel turning
/// in place, and a last beat that presses nothing because pressing the word is
/// the user's part.
void main() {
  PathStep step(
    String label, {
    String? boardId,
    ButtonAction action = ButtonAction.navigate,
  }) => (label: label, row: 6, col: 3, action: action, boardId: boardId);

  group('the sequence', () {
    test('starts at home, wherever the walker happens to be', () {
      // Routes are recorded from home because that is where the motor plan
      // starts. Beginning anywhere else presses a sequence that only works
      // from there.
      final beats = routeBeats(
        steps: [step('food', boardId: 'food')],
        rootBoardId: 'home',
        wheelPages: 3,
      );

      expect(beats.first.boardId, 'home');
      expect(beats.first.categoryPage, 0);
    });

    test('is one beat per key, and one more for arriving', () {
      final beats = routeBeats(
        steps: [
          step('more words', boardId: 'home 2'),
          step('food', boardId: 'food'),
        ],
        rootBoardId: 'home',
        wheelPages: 3,
      );

      expect(beats, hasLength(3));
      expect(
        [for (final b in beats) b.press?.label],
        ['more words', 'food', null],
      );
    });

    test('shows each key on the board it actually sits on', () {
      // The point of walking it. A key highlighted on the board it does not
      // sit on teaches a movement nobody can repeat.
      final beats = routeBeats(
        steps: [
          step('more words', boardId: 'home 2'),
          step('food', boardId: 'food'),
        ],
        rootBoardId: 'home',
        wheelPages: 3,
      );

      expect([for (final b in beats) b.boardId], ['home', 'home 2', 'food']);
    });

    test('presses nothing at the end', () {
      // Arriving is the finder's part; pressing the word is the user's. A word
      // spoken by something they did not touch is a word they did not say.
      final beats = routeBeats(
        steps: [step('food', boardId: 'food')],
        rootBoardId: 'home',
        wheelPages: 3,
      );

      expect(beats.last.press, isNull);
      expect(beats.last.boardId, 'food');
    });

    test('a word already on the home board is one beat', () {
      final beats = routeBeats(
        steps: const [],
        rootBoardId: 'home',
        wheelPages: 3,
      );

      expect(beats, hasLength(1));
      expect(beats.single.boardId, 'home');
      expect(beats.single.press, isNull);
    });
  });

  group('the wheel', () {
    test('turns in place rather than moving the board', () {
      final beats = routeBeats(
        steps: [
          step('more categories', action: ButtonAction.cycleCategories),
          step('numbers', boardId: 'numbers'),
        ],
        rootBoardId: 'home',
        wheelPages: 3,
      );

      expect([for (final b in beats) b.boardId], ['home', 'home', 'numbers']);
      expect([for (final b in beats) b.categoryPage], [0, 1, 1]);
    });

    test('comes back round', () {
      final beats = routeBeats(
        steps: [
          for (var i = 0; i < 4; i++)
            step('more categories', action: ButtonAction.cycleCategories),
        ],
        rootBoardId: 'home',
        wheelPages: 3,
      );

      expect([for (final b in beats) b.categoryPage], [0, 1, 2, 0, 1]);
    });

    test('a wheel of one page does not turn', () {
      // Which falls out of the modulo rather than being checked for — a grid
      // wide enough to show every category has a key that turns nothing.
      final beats = routeBeats(
        steps: [step('more categories', action: ButtonAction.cycleCategories)],
        rootBoardId: 'home',
        wheelPages: 1,
      );

      expect([for (final b in beats) b.categoryPage], [0, 0]);
    });
  });

  test('home puts the wheel back where it started', () {
    // Home is a reset on the board itself, so a route that passed through one
    // has to be walked the same way — otherwise the sequence the finder
    // presses reaches a different category from the one it names.
    final beats = routeBeats(
      steps: [
        step('more categories', action: ButtonAction.cycleCategories),
        step('home', boardId: 'home', action: ButtonAction.home),
        step('food', boardId: 'food'),
      ],
      rootBoardId: 'home',
      wheelPages: 3,
    );

    expect([for (final b in beats) b.categoryPage], [0, 1, 0, 0]);
    expect(
      [for (final b in beats) b.boardId],
      ['home', 'home', 'home', 'food'],
    );
  });

  group('against a real board set', () {
    late WordbridgeDatabase db;
    late String vocabId;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      // Narrow enough that the wheel has to turn, which is the case the walk
      // has to get right and the one no hand-written route covers honestly.
      vocabId = await seedCoreBoardSet(db, rows: 7, cols: 11);
    });

    tearDown(() async => db.close());

    test('every route the finder can offer ends where the word is', () async {
      final vocab = await (db.select(
        db.vocabularies,
      )..where((v) => v.id.equals(vocabId))).getSingle();
      final root = vocab.rootBoardId!;

      final found = await findWords(db, vocabularyId: vocabId, query: 'a');
      expect(
        found,
        isNotEmpty,
        reason: 'the premise: there is a route to walk',
      );

      for (final path in found) {
        final beats = routeBeats(
          steps: path.steps,
          rootBoardId: root,
          wheelPages: 3,
        );

        expect(
          beats.last.boardId,
          path.boardId,
          reason: 'walking the route to "${path.label}" ends somewhere else',
        );
        expect(beats.first.boardId, root);
        expect(beats.last.press, isNull);
        expect(beats, hasLength(path.steps.length + 1));
      }
    });
  });
}
