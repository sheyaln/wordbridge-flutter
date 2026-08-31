import 'dart:async';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/breadcrumb_strip.dart';
import 'package:wordbridge/features/talk/find_a_word.dart';
import 'package:wordbridge/features/talk/route_walk.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/talk/word_path.dart';
import 'package:wordbridge/features/usage/logger.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

class _Speech implements SpeechEngine {
  final said = <String>[];

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> speakUtterance(String text) => speak(text);

  @override
  Future<void> init() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<List<VoiceOption>> voices() async => const [];
  @override
  Future<void> useVoice(VoiceOption voice) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVolume(double volume) async {}
}

/// A voice that refuses. The word still has to reach the sentence.
class _BrokenSpeech extends _Speech {
  @override
  Future<void> speak(String text) async => throw StateError('no voice');
}

/// Finding a word, and being shown the way to it.
///
/// The decision under test is §4.42's: the finder presses the keys rather than
/// arriving at the board. A finder that teleported would give every word it
/// found a second motor path, and would teach that the way to a word is to
/// search for it — to somebody whose whole board is a fixed sequence.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;
  late _Speech speech;

  const profileId = 'p1';

  /// Narrow enough that the categories do not all fit along the system row,
  /// so the wheel has to turn — the case a walk has to get right.
  const rows = 7;
  const cols = 10;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );

    final ts = nowMs();
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            displayName: 'Maya',
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(db, rows: rows, cols: cols);
    settings = ProfileSettings(db, profileId);
    await settings.load();
    speech = _Speech();
  });

  // The database is deliberately not closed inside a widget test: closing it
  // waits on work the fake clock never runs.

  Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpTalkScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: TalkScreen(
          db: db,
          speech: speech,
          vocabularyId: vocabularyId,
          logger: UsageLogger(db, deviceId: 'test'),
          auth: PinAuth(db, storage: _FakeSecretStore()),
          settings: settings,
          profileId: profileId,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  ({int row, int col})? pointer(WidgetTester tester) =>
      tester.widget<GridSurface>(find.byType(GridSurface)).pointAt;

  String? labelAt(WidgetTester tester, int row, int col) {
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('$row:$col')),
        matching: find.byType(Text),
      ),
    );
    return texts.isEmpty ? null : texts.first.data;
  }

  /// A word that is not on the home board, so there is a route to walk.
  Future<WordPath> somewhereElse() async {
    final found = await findWords(
      db,
      vocabularyId: vocabularyId,
      query: 'a',
      limit: 200,
    );
    return found.firstWhere(
      (p) => p.steps.isNotEmpty,
      orElse: () => throw StateError('this grid puts everything on home'),
    );
  }

  group('the route a result shows', () {
    test('reads as the movements, not the board it ends on', () {
      final text = routeText((
        label: 'apple',
        buttonId: 'b',
        boardId: 'food',
        row: 2,
        col: 3,
        steps: [
          (
            label: 'more categories',
            row: 6,
            col: 9,
            action: ButtonAction.cycleCategories,
            boardId: null,
          ),
          (
            label: 'food',
            row: 6,
            col: 2,
            action: ButtonAction.navigate,
            boardId: 'food',
          ),
        ],
      ));

      expect(text, 'home  →  more categories  →  food');
    });

    test('a word on the home board says so rather than showing nothing', () {
      final text = routeText((
        label: 'want',
        buttonId: 'b',
        boardId: 'home',
        row: 1,
        col: 1,
        steps: const [],
      ));

      expect(text, 'On the home board');
    });
  });

  group('the finder', () {
    Future<void> openFinder(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FindAWord(db: db, vocabularyId: vocabularyId),
        ),
      );
      await pumpFrames(tester);
    }

    testWidgets('offers a word and the way to it', (tester) async {
      await openFinder(tester);

      await tester.enterText(find.byType(TextField), 'eat');
      await pumpFrames(tester);

      // Possibly more than one: a word can genuinely hold locations on two
      // boards, and both are two movements to two places.
      final rows = find.widgetWithText(ListTile, 'eat');
      expect(rows, findsWidgets);

      for (final tile in tester.widgetList<ListTile>(rows)) {
        expect(
          (tile.subtitle! as Text).data,
          startsWith('home'),
          reason: 'a result without a route answers a question nobody asked',
        );
      }
    });

    testWidgets('says so when nothing matches', (tester) async {
      await openFinder(tester);

      await tester.enterText(find.byType(TextField), 'zzzzz');
      await pumpFrames(tester);

      expect(find.textContaining('No word on this board matches'), findsOne);
    });

    testWidgets('says nothing at all before anything is typed', (tester) async {
      await openFinder(tester);

      expect(
        find.textContaining('No word on this board matches'),
        findsNothing,
      );
    });

    testWidgets('a slow answer to an old query does not replace the list', (
      tester,
    ) async {
      // Typing is faster than the database. Without the guard, the answer to
      // "fo" arriving after the answer to "food" puts the wrong list back, and
      // the word somebody is reaching for moves under their finger.
      final held = <String, Completer<List<WordPath>>>{};

      await tester.pumpWidget(
        MaterialApp(
          home: FindAWord(
            db: db,
            vocabularyId: vocabularyId,
            search: (query) =>
                (held[query] = Completer<List<WordPath>>()).future,
          ),
        ),
      );
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'fo');
      await pumpFrames(tester);
      await tester.enterText(find.byType(TextField), 'food');
      await pumpFrames(tester);

      // The newer query answers first, then the older one.
      held['food']!.complete([_result('food')]);
      await pumpFrames(tester);
      held['fo']!.complete([_result('forget')]);
      await pumpFrames(tester);

      expect(find.widgetWithText(ListTile, 'food'), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'forget'),
        findsNothing,
        reason: 'a stale answer replaced the list under the user',
      );
    });

    testWidgets('hands back the word that was chosen', (tester) async {
      FindResult? chosen;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await FindAWord.show(
                  context,
                  db: db,
                  vocabularyId: vocabularyId,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'eat');
      await pumpFrames(tester);

      // The row, not `find.text`, which also matches what was typed into the
      // field.
      await tester.tap(find.widgetWithText(ListTile, 'eat').first);
      await tester.pumpAndSettle();

      expect(chosen, isA<RouteToWord>());
      expect((chosen! as RouteToWord).path.label, 'eat');
    });
  });

  /// §4.46. A word the board does not have is still a word somebody is
  /// holding, and they have already typed it.
  group('a word the finder cannot find', () {
    group('when the offer to say it anyway applies', () {
      test('not before anything is typed', () {
        expect(nothingIsThatWord('', const []), isFalse);
        expect(nothingIsThatWord('   ', const []), isFalse);
      });

      test('when nothing came back at all', () {
        expect(nothingIsThatWord('grandma', const []), isTrue);
      });

      test('and when something came back that is a different word', () {
        // "grandad" for "grandma" is the board answering a different
        // question. The person is still holding a word it does not have.
        expect(nothingIsThatWord('grandma', [_result('grandad')]), isTrue);
      });

      test('but not when the board has exactly that word', () {
        expect(nothingIsThatWord('food', [_result('food')]), isFalse);
      });

      test('however it was capitalised or spaced', () {
        expect(nothingIsThatWord('  Food ', [_result('food')]), isFalse);
      });
    });

    testWidgets('the offer is not made while the word is on the board', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FindAWord(db: db, vocabularyId: vocabularyId),
        ),
      );
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'eat');
      await pumpFrames(tester);

      expect(find.text('Say it and add it'), findsNothing);
    });

    testWidgets('and it says the word and hands it back as typed', (
      tester,
    ) async {
      FindResult? chosen;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await FindAWord.show(
                  context,
                  db: db,
                  vocabularyId: vocabularyId,
                  speech: speech,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Battenberg');
      await pumpFrames(tester);

      await tester.tap(find.text('Say it and add it'));
      await tester.pumpAndSettle();

      expect(chosen, isA<TypedWord>());
      expect((chosen! as TypedWord).word, 'Battenberg');
      expect(speech.said, [
        'Battenberg',
      ], reason: 'the one hearing is the feedback that the typing worked');
    });

    testWidgets('a voice that will not speak still lets the word through', (
      tester,
    ) async {
      // A screen that would not shut because the voice was busy is a person
      // stuck behind a keyboard.
      FindResult? chosen;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await FindAWord.show(
                  context,
                  db: db,
                  vocabularyId: vocabularyId,
                  speech: _BrokenSpeech(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Battenberg');
      await pumpFrames(tester);

      await tester.tap(find.text('Say it and add it'));
      await tester.pumpAndSettle();

      expect((chosen! as TypedWord).word, 'Battenberg');
    });

    testWidgets('the word reaches the sentence without being said twice', (
      tester,
    ) async {
      await pumpTalkScreen(tester);

      await tester.tap(find.byTooltip('Another way to a word'));
      await pumpFrames(tester);
      await tester.tap(find.text('Find a word'));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'Battenberg');
      await pumpFrames(tester);
      await tester.tap(find.text('Say it and add it'));
      await pumpFrames(tester);

      expect(find.textContaining('Battenberg'), findsWidgets);
      expect(speech.said, [
        'Battenberg',
      ], reason: 'the finder said it and the sentence said it again');
    });
  });

  group('walking the way there', () {
    testWidgets('starts at home, pointing at the first key', (tester) async {
      await pumpTalkScreen(tester);
      final path = await somewhereElse();

      tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
      await tester.pump();

      expect(pointer(tester), (
        row: path.steps.first.row,
        col: path.steps.first.col,
      ));
      expect(
        labelAt(tester, path.steps.first.row, path.steps.first.col),
        isNotNull,
        reason: 'the ring is over a location with no key on it',
      );
    });

    testWidgets('presses each key in turn', (tester) async {
      await pumpTalkScreen(tester);
      final path = await somewhereElse();

      final state = tester.state<TalkScreenState>(find.byType(TalkScreen));
      state.walkTo(path);
      await tester.pump();

      final pointed = <({int row, int col})?>[pointer(tester)];
      for (var i = 0; i < path.steps.length; i++) {
        await tester.pump(TalkScreenState.walkBeat);
        await pumpFrames(tester);
        pointed.add(pointer(tester));
      }

      expect(pointed, [
        for (final step in path.steps) (row: step.row, col: step.col),
        (row: path.row, col: path.col),
      ], reason: 'the walk did not press the keys the route names, in order');
    });

    testWidgets('ends on the word, and does not say it', (tester) async {
      // Arriving is the finder's part; pressing is the user's. A word said by
      // something they did not touch is a word they did not say.
      await pumpTalkScreen(tester);
      final path = await somewhereElse();

      tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
      for (var i = 0; i <= path.steps.length; i++) {
        await tester.pump(TalkScreenState.walkBeat);
        await pumpFrames(tester);
      }

      expect(pointer(tester), (row: path.row, col: path.col));
      expect(labelAt(tester, path.row, path.col), path.label);
      expect(speech.said, isEmpty);
    });

    testWidgets('leaves the trail naming the way it came', (tester) async {
      await pumpTalkScreen(tester);
      final path = await somewhereElse();

      tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
      for (var i = 0; i <= path.steps.length; i++) {
        await tester.pump(TalkScreenState.walkBeat);
        await pumpFrames(tester);
      }

      final strip = find.byType(BreadcrumbStrip);
      expect(
        strip,
        findsOneWidget,
        reason: 'the premise: this profile is showing the trail at all',
      );

      final text = tester
          .widget<Text>(find.descendant(of: strip, matching: find.byType(Text)))
          .textSpan!
          .toPlainText();

      for (final step in path.steps) {
        expect(
          text,
          contains(step.label),
          reason: 'the trail does not name a movement the walk just made',
        );
      }
    });

    testWidgets('a press of the user\'s own ends it', (tester) async {
      // A walk that kept changing the board under somebody who had started
      // using it would be moving the board while they aimed at it.
      await pumpTalkScreen(tester);
      final path = await somewhereElse();

      final state = tester.state<TalkScreenState>(find.byType(TalkScreen));
      state.walkTo(path);
      await tester.pump();
      expect(pointer(tester), isNotNull, reason: 'the premise');

      await tester.tap(find.byKey(const ValueKey('0:0')));
      await pumpFrames(tester);

      expect(pointer(tester), isNull);

      // And it stays ended: the next beat does not arrive and move the board.
      final board = labelAt(tester, path.steps.first.row, path.steps.first.col);
      await tester.pump(TalkScreenState.walkBeat);
      await pumpFrames(tester);
      expect(
        labelAt(tester, path.steps.first.row, path.steps.first.col),
        board,
      );
    });

    testWidgets('pressing the key it is about to press still ends it', (
      tester,
    ) async {
      // While the board is pressing for itself, a press on the key under the
      // ring is still the user taking over — the walk stops rather than
      // counting it as the beat it was going to make. Only the waiting mode
      // treats that press as the movement it is asking for.
      await pumpTalkScreen(tester);
      final path = await somewhereElse();

      tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
      await tester.pump();

      final first = path.steps.first;
      await tester.tap(find.byKey(ValueKey('${first.row}:${first.col}')));
      await pumpFrames(tester);

      expect(pointer(tester), isNull);
    });

    /// §4.47. Watching a route is not learning it, so the ring can wait.
    group('when the ring waits to be pressed', () {
      setUp(() async => settings.set('walkMode', WalkMode.waits.name));

      testWidgets('the board does not move on its own', (tester) async {
        await pumpTalkScreen(tester);
        final path = await somewhereElse();

        tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
        await tester.pump();

        final first = (row: path.steps.first.row, col: path.steps.first.col);
        expect(pointer(tester), first, reason: 'the premise');

        // Several beats' worth of time, with nobody pressing anything.
        for (var i = 0; i <= path.steps.length; i++) {
          await tester.pump(TalkScreenState.walkBeat);
          await pumpFrames(tester);
        }

        expect(
          pointer(tester),
          first,
          reason: 'the ring moved on without anybody making the movement',
        );
      });

      testWidgets('the pressed key moves it on, one at a time', (tester) async {
        await pumpTalkScreen(tester);
        final path = await somewhereElse();

        tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
        await tester.pump();

        final pointed = <({int row, int col})?>[pointer(tester)];
        for (final step in path.steps) {
          await tester.tap(find.byKey(ValueKey('${step.row}:${step.col}')));
          await pumpFrames(tester);
          pointed.add(pointer(tester));
        }

        expect(pointed, [
          for (final step in path.steps) (row: step.row, col: step.col),
          (row: path.row, col: path.col),
        ], reason: 'pressing the pointed keys did not walk the same route');
      });

      testWidgets('and it arrives without saying the word', (tester) async {
        await pumpTalkScreen(tester);
        final path = await somewhereElse();

        tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
        await tester.pump();

        for (final step in path.steps) {
          await tester.tap(find.byKey(ValueKey('${step.row}:${step.col}')));
          await pumpFrames(tester);
        }

        expect(labelAt(tester, path.row, path.col), path.label);
        expect(speech.said, isEmpty);

        // And the last press is still theirs to make.
        await tester.tap(find.byKey(ValueKey('${path.row}:${path.col}')));
        await pumpFrames(tester);
        expect(speech.said, isNotEmpty);
      });

      testWidgets('a press somewhere else ends it', (tester) async {
        await pumpTalkScreen(tester);
        final path = await somewhereElse();

        final state = tester.state<TalkScreenState>(find.byType(TalkScreen));
        state.walkTo(path);
        await tester.pump();

        final wanted = (row: path.steps.first.row, col: path.steps.first.col);
        final elsewhere = wanted == (row: 0, col: 0)
            ? const ValueKey('0:1')
            : const ValueKey('0:0');

        await tester.tap(find.byKey(elsewhere));
        await pumpFrames(tester);

        expect(pointer(tester), isNull);
      });
    });

    testWidgets('the ring does not swallow the press it points at', (
      tester,
    ) async {
      // The whole point of arriving is that the user then presses the word.
      await pumpTalkScreen(tester);
      final path = await somewhereElse();

      tester.state<TalkScreenState>(find.byType(TalkScreen)).walkTo(path);
      for (var i = 0; i <= path.steps.length; i++) {
        await tester.pump(TalkScreenState.walkBeat);
        await pumpFrames(tester);
      }

      await tester.tap(find.byKey(ValueKey('${path.row}:${path.col}')));
      await pumpFrames(tester);

      expect(speech.said, isNotEmpty);
    });
  });
}

WordPath _result(String label) => (
  label: label,
  buttonId: 'b-$label',
  boardId: 'food',
  row: 2,
  col: 3,
  steps: const [],
);
