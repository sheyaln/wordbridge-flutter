@Tags(['golden'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/fallback_board.dart';
import 'package:wordbridge/features/talk/talk_screen.dart';
import 'package:wordbridge/features/usage/logger.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

class _SilentSpeech implements SpeechEngine {
  @override
  Future<void> speak(String text) async {}

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

/// Pictures of the board, so a layout can be looked at rather than reasoned
/// about.
///
/// The row labels shipped stacked on top of each other and invisible, and
/// every widget test passed: the labels were in the tree, at distinct offsets,
/// positioned outside a box nobody could see into. `find.text` cannot tell the
/// difference and neither can a person reading the assertions.
///
/// These render the real screen to a PNG. Run with
/// `flutter test --concurrency=1 --update-goldens test/board_render_test.dart`
/// after any deliberate layout change, and **look at the file**. That is the
/// point of it; a golden nobody opens is a checksum.
///
/// Text renders as boxes without a font bundle, which is fine — what these
/// catch is geometry: a strip on the wrong edge, a band in the wrong place, a
/// grid that lost a column.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;

  const profileId = 'p1';

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
            vocabLevel: const Value(3),
            settingsJson: Value(jsonEncode({'settleDelayMs': 0})),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(
      db,
      rows: 7,
      cols: 12,
      profileId: profileId,
    );
    settings = ProfileSettings(db, profileId);
    await settings.load();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: TalkScreen(
          db: db,
          speech: _SilentSpeech(),
          vocabularyId: vocabularyId,
          logger: UsageLogger(db, deviceId: 'test'),
          auth: PinAuth(db, storage: _FakeSecretStore()),
          settings: settings,
          profileId: profileId,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens a category by pressing the key that navigates to it, the way a user
  /// reaches it.
  /// A word on [boardId] that is on no other board, so its presence proves
  /// which board is being looked at.
  Future<String> landmarkOn(String boardId) async {
    final here =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.cells.boardId.equals(boardId) &
                  db.buttons.isSystem.equals(false),
            ))
            .get();

    for (final row in here) {
      final label = row.readTable(db.buttons).label;
      final everywhere = await (db.select(
        db.buttons,
      )..where((b) => b.label.equals(label))).get();
      if (everywhere.length == 1) return label;
    }

    fail('no word is unique to that board, so arriving cannot be detected');
  }

  Future<void> openBoard(WidgetTester tester, String name) async {
    final board = await (db.select(
      db.boards,
    )..where((b) => b.name.equals(name))).getSingle();

    // A word that is on the board being opened and nowhere else, so arriving
    // can be told from not arriving.
    final landmark = await landmarkOn(board.id);

    Future<bool> arrived() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return find.text(landmark).evaluate().isNotEmpty;
    }

    // A paging key is a real button with a real target, so it can be found in
    // the database and pressed by its coordinates.
    final keys = await (db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.buttons.targetBoardId.equals(board.id))).get();

    for (final key in keys) {
      final cell = key.readTable(db.cells);
      final at = find.byKey(ValueKey('${cell.row}:${cell.col}'));
      if (at.evaluate().isEmpty) continue;
      await tester.tap(at);
      if (await arrived()) return;
    }

    // A category key is not. The system row shows a window onto the category
    // list and the keys are remapped as the window moves, so nothing in the
    // database points at `doing` except a paging key on `doing 2`. Looking one
    // up and tapping its coordinates was the original bug: it landed on an
    // empty cell of the home board, nothing navigated, and the golden recorded
    // the home board under another name — byte identical to
    // `home_labeled.png`, which is exactly what a golden is meant to prevent.
    //
    // So this turns the wheel the way a person does.
    final cycle =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.buttons.action.equalsValue(ButtonAction.cycleCategories),
            ))
            .get();

    for (var turn = 0; turn <= categoryNames.length; turn++) {
      final key = find.text(name);
      if (key.evaluate().isNotEmpty) {
        await tester.tap(key.first);
        if (await arrived()) return;
      }

      var turned = false;
      for (final row in cycle) {
        final cell = row.readTable(db.cells);
        final at = find.byKey(ValueKey('${cell.row}:${cell.col}'));
        if (at.evaluate().isEmpty) continue;
        await tester.tap(at);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        turned = true;
        break;
      }
      if (!turned) break;
    }

    fail('could not open the "$name" board: "$landmark" never appeared');
  }

  testWidgets('the home board', (tester) async {
    await pump(tester);
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/home.png'),
    );
  });

  testWidgets('the home board with its regions named', (tester) async {
    await settings.set('regionLabels', true);
    await pump(tester);
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/home_labeled.png'),
    );
  });

  testWidgets('the second page of the home board, with its regions named', (
    tester,
  ) async {
    // The one to look at for the regions. Every band here sits on the columns
    // it holds on page one, so the strip along the top reads the same on both —
    // and the columns a band has nothing to put here stay empty rather than
    // being handed to its neighbor.
    await settings.set('regionLabels', true);
    await pump(tester);
    await openBoard(tester, 'home 2');
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/home_page_two_labeled.png'),
    );
  });

  testWidgets('the board that speaks when everything else has failed', (
    tester,
  ) async {
    // Look at this one. It is the screen a person is handed on the worst day
    // the app has, and nothing else in the suite can tell whether it is legible.
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const FallbackBoard(detail: 'Bad state: the database would not open'),
    );

    await expectLater(
      find.byType(FallbackBoard),
      matchesGoldenFile('goldens/fallback_board.png'),
    );
  });

  testWidgets('a category board', (tester) async {
    await pump(tester);
    await openBoard(tester, 'food');
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/food.png'),
    );
  });

  testWidgets('a category board with its rows named', (tester) async {
    // The one that was broken. A strip drawn across the wrong edge stacks
    // every label into a band too short to show any of them.
    await settings.set('regionLabels', true);
    await pump(tester);
    await openBoard(tester, 'food');
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/food_labeled.png'),
    );
  });

  testWidgets('the board that gained an adverb row, with its rows named', (
    tester,
  ) async {
    // §4.42 gave `doing` a `how` band, which is a seventh band on a board with
    // six content rows at 7x12 — so something now pages off that did not
    // before. This is the picture of what that costs.
    //
    // **Page two, because that is where the adverbs went.** Page one holds six
    // rows of verbs and not one adverb, so a golden of it could never show
    // what this test is named for. It did not show it before either: the
    // navigation silently failed and the file was a byte identical copy of
    // `home_labeled.png`, so this has been a picture of the home board
    // labeled as the `doing` board since §4.42 added it.
    await settings.set('regionLabels', true);
    await pump(tester);
    await openBoard(tester, 'doing');
    await openBoard(tester, 'doing 2');
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/doing_page_two_labeled.png'),
    );
  });

  testWidgets('the newest category board, with its rows named', (tester) async {
    // The board added last, which is the one nobody has looked at yet. Its
    // rows carry the widest labels in the set — "days of the week", "parts of
    // the day" — and §4.29 is the standing reminder that a label nobody can
    // read teaches nothing.
    //
    // Reached by turning the wheel rather than by `openBoard`, and that is the
    // point worth recording: a category past the last slot has no navigate
    // button of its own anywhere in the database. Its slot is re-pointed at
    // render time, so the only way to it is the way a person takes.
    await settings.set('regionLabels', true);
    await pump(tester);

    final vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();
    final frame = SystemFrame.parse(vocab.systemCellMap)!;

    final index = frame.categories.indexWhere((c) => c.name == 'time');
    expect(index, isNonNegative, reason: 'the time board is not on the wheel');

    final slots = frame.categoryCols.length;
    for (var turn = 0; turn < index ~/ slots; turn++) {
      await tester.tap(find.byKey(ValueKey('${frame.row}:${frame.cycleCol}')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(
      find.byKey(ValueKey('${frame.row}:${frame.categoryCols[index % slots]}')),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/time_labeled.png'),
    );
  });
}
