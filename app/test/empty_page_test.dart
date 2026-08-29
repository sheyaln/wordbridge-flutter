import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
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

/// A key that leads to a page with nothing on it.
///
/// Pages exist because a band owns whole lines and a narrow grid cannot hold
/// every line, so what spills is whatever the level filter was going to draw
/// last — which means a page can be entirely above the level the person using
/// the board is on. The frame is on every board, so arriving there shows the
/// same keys they left from.
///
/// The user this costs is the one who cannot say the board has stopped
/// answering. They press "more words", nothing they recognise appears, and the
/// next word they say comes off whichever page they are still standing on.
void main() {
  const rows = 7;
  const cols = 12;

  late WordbridgeDatabase db;
  late String vocabularyId;
  late Vocabulary vocab;

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
            id: 'p1',
            displayName: 'Maya',
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(
      db,
      rows: rows,
      cols: cols,
      profileId: 'p1',
    );
    vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();
  });

  Future<Board> board(String name) =>
      (db.select(db.boards)..where((b) => b.name.equals(name))).getSingle();

  /// The lowest level at which a board draws anything of its own, ignoring the
  /// frame every board carries.
  Future<int?> lowestContentLevel(String boardId) async {
    final rows_ =
        await (db.select(db.buttons).join([
              innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
            ])..where(
              db.cells.boardId.equals(boardId) &
                  db.buttons.hidden.equals(false) &
                  db.cells.row.isSmallerThanValue(rows - 1) &
                  db.cells.col.isSmallerThanValue(cols - 1),
            ))
            .get();

    final levels = [for (final r in rows_) r.readTable(db.buttons).vocabLevel];
    return levels.isEmpty ? null : levels.reduce((a, b) => a < b ? a : b);
  }

  Future<void> pump(WidgetTester tester, {required int level}) async {
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
          profileId: 'p1',
          vocabLevel: level,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> teardownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  test('the shipped board really does produce a page above level 1', () async {
    // The premise the rest of this file rests on. If a seed change ever puts a
    // level-1 word on every second page, these tests would pass by describing
    // nothing.
    expect(
      await lowestContentLevel((await board('home 2')).id),
      greaterThan(1),
      reason: 'home page two now has something a level-1 board would draw',
    );
  });

  testWidgets('the paging key is not drawn onto an empty page', (tester) async {
    await pump(tester, level: 1);

    expect(
      find.text('more words'),
      findsNothing,
      reason:
          'the key is drawn on a level-1 board whose second page holds nothing '
          'that level draws',
    );

    await teardownScreen(tester);
  });

  testWidgets('the same key is drawn once the page has something', (
    tester,
  ) async {
    final lowest = await lowestContentLevel((await board('home 2')).id);
    await pump(tester, level: lowest!);

    expect(
      find.text('more words'),
      findsOneWidget,
      reason:
          'raising the level filled page two and the key that reaches it did '
          'not come back',
    );

    await teardownScreen(tester);
  });

  testWidgets('a page whose words are all switched off is empty too', (
    tester,
  ) async {
    // Above the level and switched off by a caregiver are different states and
    // both mean the same thing here: nothing is drawn, so there is nothing to
    // go and see.
    final page = await board('home 2');
    final cells = await (db.select(
      db.cells,
    )..where((c) => c.boardId.equals(page.id))).get();

    for (final cell in cells) {
      if (cell.row >= rows - 1 || cell.col >= cols - 1) continue;
      await (db.update(db.buttons)..where((b) => b.cellId.equals(cell.id)))
          .write(const ButtonsCompanion(hidden: Value(true)));
    }

    await pump(tester, level: 3);

    expect(
      find.text('more words'),
      findsNothing,
      reason:
          'every word on page two is switched off and the key that reaches it '
          'is still drawn',
    );

    await teardownScreen(tester);
  });

  testWidgets('its location stays reserved rather than being reused', (
    tester,
  ) async {
    // Hiding it is a rendering decision, not a move. The cell keeps the button
    // in the database, so the key reappears in exactly the same place the
    // moment the page is worth going to.
    await pump(tester, level: 1);

    final cell = await cellAt(
      db,
      boardId: vocab.rootBoardId!,
      row: rows - 1,
      col: cols - 1,
    );
    final held = await (db.select(
      db.buttons,
    )..where((b) => b.cellId.equals(cell.id))).getSingleOrNull();

    expect(cell.state, CellState.occupied);
    expect(held?.label, 'more words');

    await teardownScreen(tester);
  });
}
