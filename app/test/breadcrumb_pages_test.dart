import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/breadcrumb_strip.dart';
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

/// A trail must name the way *to* a word, and paging back is not it.
///
/// Reported: paging out to a later page of home, opening a category, pressing
/// back, then paging back again recorded `back a page` as a step. Every press
/// in that sequence undoes an earlier one, and the way to a word on page two is
/// forward from page one whichever key happened to land you there.
///
/// It needs a root board of at least three pages, which every four- and
/// five-row grid produces — extra-large icons on a small tablet. Two pages
/// cannot show it, because paging back from page two lands on the root board
/// and a route to the root is no steps at all.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late Vocabulary vocab;
  late ProfileSettings settings;

  late int wheelRow;
  late List<int> wheelCols;
  late int homeCol;
  late int backCol;
  late int forwardCol;
  late int backPageCol;

  const profileId = 'p1';
  const rows = 5;
  const cols = 11;

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
    vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();

    final map = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
    wheelRow = map['row'] as int;
    wheelCols = (map['categoryCols'] as List).cast<int>();
    homeCol = map['home'] as int;
    backCol = map['back'] as int;
    forwardCol = map['moreWords'] as int;
    backPageCol = map['backAPage'] as int;

    settings = ProfileSettings(db, profileId);
    await settings.load();
  });

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
          speech: _SilentSpeech(),
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

  Future<void> tapCell(WidgetTester tester, int row, int col) async {
    await tester.tap(find.byKey(ValueKey('$row:$col')));
    await pumpFrames(tester);
  }

  String trail(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(BreadcrumbStrip),
        matching: find.byType(Text),
      ),
    );
    return text.textSpan!.toPlainText();
  }

  /// A word on one page of home, where it is and what it reads.
  Future<({Cell cell, String label})> wordOn(String page) async {
    final board = await (db.select(
      db.boards,
    )..where((b) => b.name.equals(page))).getSingle();

    final placed =
        await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])
              ..where(
                db.cells.boardId.equals(board.id) &
                    db.buttons.action.equalsValue(ButtonAction.speak) &
                    db.buttons.hidden.equals(false) &
                    db.buttons.vocabLevel.isSmallerOrEqualValue(3),
              )
              ..orderBy([OrderingTerm.asc(db.buttons.id)]))
            .get();

    expect(placed, isNotEmpty, reason: '"$page" says nothing at this grid');
    return (
      cell: placed.first.readTable(db.cells),
      label: placed.first.readTable(db.buttons).label,
    );
  }

  testWidgets('the root board really does page three deep here', (
    tester,
  ) async {
    // The premise, asserted on its own. Without a third page the sequence
    // below cannot record a backward step, and the tests that follow would
    // pass by describing nothing.
    final names = {for (final b in await db.select(db.boards).get()) b.name};
    expect(names, containsAll(['home', 'home 2', 'home 3']));
  });

  testWidgets('paging back records the way forward, not the key pressed', (
    tester,
  ) async {
    final word = await wordOn('home 2');

    await settings.set('breadcrumbs', true);
    await pumpTalkScreen(tester);

    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, wheelRow, wheelCols.first);
    await tapCell(tester, wheelRow, backCol);
    await tapCell(tester, wheelRow, backPageCol);
    await tapCell(tester, word.cell.row, word.cell.col);

    expect(
      trail(tester),
      'home → more words → ${word.label}',
      reason:
          'the trail named the key that landed here rather than the way to '
          'get here, so it reads as a route that goes backwards',
    );
  });

  testWidgets('paging straight back from the third page reads the same', (
    tester,
  ) async {
    // No category and no back key, so nothing has cleared the trail. The
    // shorter way to the same place must read the same as the long way.
    final word = await wordOn('home 2');

    await settings.set('breadcrumbs', true);
    await pumpTalkScreen(tester);

    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, wheelRow, backPageCol);
    await tapCell(tester, word.cell.row, word.cell.col);

    expect(trail(tester), 'home → more words → ${word.label}');
  });

  testWidgets('each page forward is its own step', (tester) async {
    // Two of them, in order. The trail's own idea of where it stands is the
    // board its last crumb names, so a route assembled the wrong way round
    // reads as a trail for somewhere else and is thrown away the moment a word
    // is chosen.
    final word = await wordOn('home 3');

    await settings.set('breadcrumbs', true);
    await pumpTalkScreen(tester);

    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, word.cell.row, word.cell.col);

    expect(trail(tester), 'home → more words → more words → ${word.label}');
  });

  testWidgets('home is still no steps at all', (tester) async {
    final word = await wordOn('home 2');

    await settings.set('breadcrumbs', true);
    await pumpTalkScreen(tester);

    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, wheelRow, homeCol);
    await tapCell(tester, wheelRow, forwardCol);
    await tapCell(tester, word.cell.row, word.cell.col);

    expect(trail(tester), 'home → more words → ${word.label}');
  });
}
