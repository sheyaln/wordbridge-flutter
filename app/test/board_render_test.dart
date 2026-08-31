@Tags(['golden'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
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
  Future<void> openBoard(WidgetTester tester, String name) async {
    final board = await (db.select(
      db.boards,
    )..where((b) => b.name.equals(name))).getSingle();

    final key = await (db.select(db.buttons).join([
      innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
    ])..where(db.buttons.targetBoardId.equals(board.id))).get();

    final cell = key.first.readTable(db.cells);
    await tester.tap(find.byKey(ValueKey('${cell.row}:${cell.col}')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
      matchesGoldenFile('goldens/home_labelled.png'),
    );
  });

  testWidgets('the second page of the home board, with its regions named', (
    tester,
  ) async {
    // The one to look at for the regions. Every band here sits on the columns
    // it holds on page one, so the strip along the top reads the same on both —
    // and the columns a band has nothing to put here stay empty rather than
    // being handed to its neighbour.
    await settings.set('regionLabels', true);
    await pump(tester);
    await openBoard(tester, 'home 2');
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/home_page_two_labelled.png'),
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
      matchesGoldenFile('goldens/food_labelled.png'),
    );
  });

  testWidgets('the board that gained an adverb row, with its rows named', (
    tester,
  ) async {
    // §4.42 gave `doing` a `how` band, which is a seventh band on a board with
    // six content rows at 7x12 — so something now pages off that did not
    // before. This is the picture of what that costs, and it is here because
    // no golden covered either of the two boards that gained a band.
    await settings.set('regionLabels', true);
    await pump(tester);
    await openBoard(tester, 'doing');
    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/doing_labelled.png'),
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
      matchesGoldenFile('goldens/time_labelled.png'),
    );
  });
}
