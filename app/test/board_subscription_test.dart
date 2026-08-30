import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
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

/// Records every statement the screen actually sends.
class _StatementLog extends QueryInterceptor {
  final statements = <String>[];

  /// Reads of a board: locations joined to whatever occupies them. Narrow
  /// enough not to catch the single-row lookups the screen makes elsewhere.
  int get boardReads => statements
      .where((s) => s.contains('FROM "cells"') && s.contains('LEFT OUTER JOIN'))
      .length;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return executor.runSelect(statement, args);
  }
}

/// A tap must cost nothing but the word it speaks, and the category keys must
/// keep cycling.
///
/// The two belong together: the board's query is held across rebuilds, and the
/// wheel's substitution depends on state that moves between them. Holding the
/// query and folding the substitution into it would freeze the categories on
/// whichever turn the subscription opened on.
void main() {
  late WordbridgeDatabase db;
  late _StatementLog log;
  late String vocabularyId;
  late Vocabulary vocab;

  /// The system row as the seeder recorded it.
  late int wheelRow;
  late List<int> wheelCols;
  late int cycleCol;
  late int homeCol;
  late int backCol;
  late List<({String name, String boardId})> categories;

  /// A grid narrow enough that the categories do not all fit along the system
  /// row, which is the only condition under which the wheel turns at all.
  const rows = 7;
  const cols = 10;

  setUp(() async {
    log = _StatementLog();
    db = WordbridgeDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory().interceptWith(log),
        // Drift otherwise keeps a dropped query stream cached for one turn of
        // the event loop, which hides re-subscriptions behind its own cache.
        // Off, every subscription is a statement, which is the thing being
        // counted.
        closeStreamsSynchronously: true,
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

    expect(
      categories.length,
      greaterThan(wheelCols.length),
      reason:
          'a ${rows}x$cols grid shows every category at once, so nothing here '
          'exercises the wheel',
    );
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
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// Taps a location by its coordinates, which is how the user reaches it.
  ///
  /// Every location is drawn whether or not anything occupies it, so this hits
  /// the same square regardless of what is on it.
  Future<void> tapCell(WidgetTester tester, int row, int col) async {
    await tester.tap(find.byKey(ValueKey('$row:$col')));

    // A board change makes the screen deaf for half a second, measured against
    // the wall clock rather than the one `pump` drives. Waiting it out before
    // the frames, so that the rebuild ending the delay sees it already spent.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await pumpFrames(tester);
  }

  /// What a location currently reads, or null where it is drawn as reserved.
  String? labelAt(WidgetTester tester, int row, int col) {
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('$row:$col')),
        matching: find.byType(Text),
      ),
    );
    return texts.isEmpty ? null : texts.first.data;
  }

  List<String?> wheelLabels(WidgetTester tester) => [
    for (final col in wheelCols) labelAt(tester, wheelRow, col),
  ];

  /// A word the root board says, and where it is.
  Future<Cell> spokenWord() async {
    final placed =
        await (db.select(db.buttons).join([
                innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
              ])
              ..where(
                db.cells.boardId.equals(vocab.rootBoardId!) &
                    db.buttons.action.equalsValue(ButtonAction.speak) &
                    db.buttons.hidden.equals(false) &
                    db.buttons.vocabLevel.isSmallerOrEqualValue(3),
              )
              ..orderBy([OrderingTerm.asc(db.buttons.id)]))
            .get();

    expect(placed, isNotEmpty, reason: 'the root board has nothing to say');
    return placed.first.readTable(db.cells);
  }

  group('the board is read once per board', () {
    testWidgets('speaking words does not read it again', (tester) async {
      final word = await spokenWord();
      await pumpTalkScreen(tester);

      expect(log.boardReads, 1);

      for (var i = 0; i < 4; i++) {
        await tapCell(tester, word.row, word.col);
      }

      expect(
        log.boardReads,
        1,
        reason:
            'each word spoken costs another read of the board, on the one '
            'path that must never be slow',
      );
    });

    testWidgets('moving between boards reads each board once', (tester) async {
      await pumpTalkScreen(tester);
      expect(log.boardReads, 1);
      expect(
        labelAt(tester, wheelRow, backCol),
        isNull,
        reason:
            'back is drawn on the root board, where it has nowhere to go; its '
            'location is reserved, not reused',
      );

      // Into the first category, then home.
      await tapCell(tester, wheelRow, wheelCols.first);
      expect(log.boardReads, 2);
      expect(
        labelAt(tester, wheelRow, backCol),
        'back',
        reason: 'the category board never opened, or back is missing from it',
      );

      await tapCell(tester, wheelRow, homeCol);
      expect(log.boardReads, 3);
      expect(
        labelAt(tester, wheelRow, backCol),
        isNull,
        reason: 'home did not come back to the root board',
      );
    });

    testWidgets('leaving the screen lets go of the board', (tester) async {
      await pumpTalkScreen(tester);
      final onScreen = log.boardReads;

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpFrames(tester, frames: 2);

      // Anything still listening re-reads the board when a button changes.
      final key =
          await (db.select(db.buttons)
                ..where((b) => b.label.equals('home'))
                ..limit(1))
              .getSingle();
      await (db.update(db.buttons)..where((b) => b.id.equals(key.id))).write(
        const ButtonsCompanion(label: Value('house')),
      );
      await pumpFrames(tester, frames: 2);

      expect(
        log.boardReads,
        onScreen,
        reason: 'the board query outlived the screen that opened it',
      );
    });
  });

  group('the category wheel', () {
    testWidgets('the cycle key changes what the category keys say', (
      tester,
    ) async {
      await pumpTalkScreen(tester);

      expect(wheelLabels(tester), [
        for (final c in categories.take(wheelCols.length)) c.name,
      ], reason: 'the system row is not showing the first turn of the wheel');

      final before = [
        for (final col in wheelCols)
          tester.getRect(find.byKey(ValueKey('$wheelRow:$col'))),
      ];

      await tapCell(tester, wheelRow, cycleCol);

      final second = categories.skip(wheelCols.length).toList();
      expect(
        wheelLabels(tester),
        [
          for (var slot = 0; slot < wheelCols.length; slot++)
            slot < second.length ? second[slot].name : null,
        ],
        reason:
            'the cycle key no longer reaches the categories that do not fit '
            'along the system row',
      );

      expect(
        [
          for (final col in wheelCols)
            tester.getRect(find.byKey(ValueKey('$wheelRow:$col'))),
        ],
        before,
        reason: 'a category key moved, so its motor plan is not a plan',
      );
      expect(
        labelAt(tester, wheelRow, cycleCol),
        'more categories',
        reason: 'the cycle key moved or was replaced by a category',
      );
    });

    testWidgets('a cycled key opens the category it now names', (tester) async {
      // A word only the second turn's first category can show, so reaching it
      // proves the key changed where it goes and not just what it reads.
      final target = categories[wheelCols.length];
      final free =
          await (db.select(db.cells)
                ..where(
                  (c) =>
                      c.boardId.equals(target.boardId) &
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
        label: 'quay',
        message: 'quay',
      );

      await pumpTalkScreen(tester);
      expect(find.text('quay'), findsNothing);

      await tapCell(tester, wheelRow, cycleCol);
      await tapCell(tester, wheelRow, wheelCols.first);

      expect(
        find.text('quay'),
        findsOneWidget,
        reason:
            'the key reads "${target.name}" and opens whatever it opened '
            'before the wheel turned',
      );
    });
  });
}
