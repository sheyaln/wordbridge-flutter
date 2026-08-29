import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
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

/// The category keys are a window onto one list, and the cycle key moves the
/// window. A key therefore means a different board on each turn, so where the
/// window is left standing is part of where a word is.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late Vocabulary vocab;
  late ProfileSettings settings;

  late int wheelRow;
  late List<int> wheelCols;
  late int cycleCol;
  late int homeCol;
  late int backCol;
  late List<({String name, String boardId})> categories;

  const profileId = 'p1';

  /// Narrow enough that the categories do not all fit along the system row,
  /// which is the only condition under which the wheel turns at all.
  const rows = 7;
  const cols = 10;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        // Drift otherwise defers closing a dropped query stream by a turn of
        // the event loop, which outlives the widget tree the test tears down.
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
    cycleCol = map['cycleCol'] as int;
    homeCol = map['home'] as int;
    backCol = map['back'] as int;
    categories = [
      for (final c in (map['categories'] as List).cast<Map<String, dynamic>>())
        (name: c['name'] as String, boardId: c['boardId'] as String),
    ];

    settings = ProfileSettings(db, profileId);
    await settings.load();
  });

  // The database is deliberately not closed inside a widget test: closing it
  // waits on work the fake clock never runs. Each test gets its own in-memory
  // instance and the process ends with the file.

  Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpTalkScreen(WidgetTester tester) async {
    // A tablet-shaped surface. On a phone-sized default window every cell is
    // smaller than a fingertip and taps land on the wrong one.
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
    // Long enough for the settle flag's timer to have run, so the next tap is
    // heard.
    await pumpFrames(tester);
  }

  String? labelAt(WidgetTester tester, int row, int col) {
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('$row:$col')),
        matching: find.byType(Text),
      ),
    );
    return texts.isEmpty ? null : texts.first.data;
  }

  /// Puts a word on [boardId] where the grid draws it, and says where.
  Future<Cell> place(String boardId, String word) async {
    final free =
        await (db.select(db.cells)
              ..where(
                (c) =>
                    c.boardId.equals(boardId) &
                    c.state.equalsValue(CellState.emptyReserved) &
                    c.row.isSmallerThanValue(wheelRow),
              )
              ..orderBy([(c) => OrderingTerm.asc(c.row)])
              ..limit(1))
            .getSingle();

    await placeButton(
      db,
      vocabularyId: vocabularyId,
      cellId: free.id,
      label: word,
      message: word,
    );
    return free;
  }

  group('home turns the wheel back to the first turn', () {
    testWidgets('a cycled key reads its first-turn category again', (
      tester,
    ) async {
      expect(categories.length, greaterThan(wheelCols.length));

      await pumpTalkScreen(tester);

      final firstTurn = labelAt(tester, wheelRow, wheelCols.first);
      expect(firstTurn, categories.first.name);

      await tapCell(tester, wheelRow, cycleCol);
      expect(labelAt(tester, wheelRow, wheelCols.first), isNot(firstTurn));

      await tapCell(tester, wheelRow, homeCol);
      expect(labelAt(tester, wheelRow, wheelCols.first), firstTurn);
    });

    testWidgets('and the key opens the board it names', (tester) async {
      // Not just the label: a wheel left turned would send the same movement
      // to a different board, which is the failure the reset exists to stop.
      final target = categories[wheelCols.length];
      final cell = await place(target.boardId, 'quay');

      await pumpTalkScreen(tester);
      await tapCell(tester, wheelRow, cycleCol);
      await tapCell(tester, wheelRow, homeCol);
      await tapCell(tester, wheelRow, wheelCols.first);

      expect(
        labelAt(tester, cell.row, cell.col),
        isNot('quay'),
        reason: 'the first-turn key still opened a second-turn board',
      );
    });

    testWidgets('back does not turn it, because back is a step', (
      tester,
    ) async {
      // Rewinding the wheel under somebody walking a route would move a key
      // they are about to press.
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, cycleCol);
      final cycled = labelAt(tester, wheelRow, wheelCols.first);

      await tapCell(tester, wheelRow, backCol);
      expect(labelAt(tester, wheelRow, wheelCols.first), cycled);
    });
  });
}
