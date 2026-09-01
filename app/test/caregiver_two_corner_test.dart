import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/caregiver_gesture.dart';
import 'package:wordbridge/features/auth/corner_hold_target.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';
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

/// The two-corner way into caregiver mode.
///
/// Two things have to hold at once and they pull against each other: the
/// gesture has to be reachable, and the two keys it stands on have to keep
/// working every other time they are pressed. A gesture that swallowed home
/// would take it from a user who cannot report that the board has stopped
/// answering.
void main() {
  const rows = 5;
  const cols = 8;
  const homeKey = ValueKey('4:0');
  const pagingKey = ValueKey('4:7');

  late WordbridgeDatabase db;
  late String vocabularyId;
  late String boardId;

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

    // A board of its own, with a key at each end of the bottom row, so the
    // test is not at the mercy of whether the shipped root board happens to
    // have a second page today.
    boardId = await materializeBoard(
      db,
      vocabularyId: vocabularyId,
      name: 'scratch',
      kind: BoardKind.category,
    );

    for (final entry in {0: 'home', cols - 1: 'more words'}.entries) {
      final cell = await cellAt(
        db,
        boardId: boardId,
        row: rows - 1,
        col: entry.key,
      );
      await placeButton(
        db,
        vocabularyId: vocabularyId,
        cellId: cell.id,
        label: entry.value,
        message: '',
        action: ButtonAction.home,
        isSystem: true,
      );
    }
  });

  Future<List<PlacedCell>> boardCells() async {
    final query = db.select(db.cells).join([
      leftOuterJoin(db.buttons, db.buttons.cellId.equalsExp(db.cells.id)),
    ])..where(db.cells.boardId.equals(boardId));

    final result = await query.get();
    return [
      for (final r in result)
        (cell: r.readTable(db.cells), button: r.readTableOrNull(db.buttons)),
    ];
  }

  /// The grid on its own, at a fixed size, so the corner rectangles are the
  /// ones the geometry produced rather than whatever a screen gave it.
  Future<({List<String> selected, List<int> opened})> pumpGrid(
    WidgetTester tester, {
    required Duration? pairHold,
  }) async {
    final cells = await boardCells();
    final selected = <String>[];
    final opened = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 500,
              child: GridSurface(
                rows: rows,
                cols: cols,
                cells: cells,
                vocabLevel: 3,
                colorConvention: ColorConvention.modifiedFitzgerald,
                pairHold: pairHold,
                onPairHold: pairHold == null ? null : () => opened.add(1),
                onSelect: (placed) =>
                    selected.add('${placed.cell.row}:${placed.cell.col}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return (selected: selected, opened: opened);
  }

  testWidgets('both corners held together open caregiver mode', (tester) async {
    final r = await pumpGrid(tester, pairHold: const Duration(seconds: 5));

    final left = await tester.startGesture(
      tester.getCenter(find.byKey(homeKey)),
    );
    final right = await tester.startGesture(
      tester.getCenter(find.byKey(pagingKey)),
    );
    // A controller's ticker takes its start time from its first tick, so the
    // clock cannot jump straight to the end of the hold.
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 4999));
    expect(r.opened, isEmpty, reason: 'it opened before the hold was up');

    await tester.pump(const Duration(milliseconds: 2));
    expect(r.opened, hasLength(1));

    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(
      r.selected,
      isEmpty,
      reason:
          'a caregiver opening settings also sent the user somewhere: the two '
          'keys act on release, and the release that ends the gesture is the '
          'one that has to be swallowed',
    );
  });

  testWidgets('letting go of one corner leaves both keys working', (
    tester,
  ) async {
    final r = await pumpGrid(tester, pairHold: const Duration(seconds: 5));

    final left = await tester.startGesture(
      tester.getCenter(find.byKey(homeKey)),
    );
    final right = await tester.startGesture(
      tester.getCenter(find.byKey(pagingKey)),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 2));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(r.opened, isEmpty);
    expect(
      r.selected,
      containsAll(<String>['4:0', '4:7']),
      reason:
          'an abandoned hold has to leave both keys doing what they have '
          'always done',
    );
  });

  testWidgets('a corner pressed on its own is still just that key', (
    tester,
  ) async {
    final r = await pumpGrid(tester, pairHold: const Duration(seconds: 5));

    final left = await tester.startGesture(
      tester.getCenter(find.byKey(homeKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await left.up();
    await tester.pumpAndSettle();

    expect(r.opened, isEmpty, reason: 'one contact opened caregiver mode');
    expect(r.selected, <String>['4:0']);
  });

  testWidgets('a second hold after the first still opens', (tester) async {
    // The suppression is cleared by the next contact rather than by the
    // release that ends the gesture, so it has to actually clear.
    final r = await pumpGrid(tester, pairHold: const Duration(seconds: 5));

    for (var attempt = 0; attempt < 2; attempt++) {
      final left = await tester.startGesture(
        tester.getCenter(find.byKey(homeKey)),
      );
      final right = await tester.startGesture(
        tester.getCenter(find.byKey(pagingKey)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
    }

    expect(r.opened, hasLength(2));
    expect(r.selected, isEmpty);
  });

  testWidgets('home works again once the gesture is over', (tester) async {
    // The cost of getting the suppression wrong in the other direction: home
    // dead for the rest of the session, on a board whose user cannot say so.
    final r = await pumpGrid(tester, pairHold: const Duration(seconds: 5));

    final left = await tester.startGesture(
      tester.getCenter(find.byKey(homeKey)),
    );
    final right = await tester.startGesture(
      tester.getCenter(find.byKey(pagingKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(r.opened, hasLength(1));
    expect(r.selected, isEmpty);

    await tester.tap(find.byKey(homeKey));
    await tester.pumpAndSettle();

    expect(r.selected, <String>['4:0']);
  });

  testWidgets('the gesture does nothing where it is not the device\'s', (
    tester,
  ) async {
    final r = await pumpGrid(tester, pairHold: null);

    final left = await tester.startGesture(
      tester.getCenter(find.byKey(homeKey)),
    );
    final right = await tester.startGesture(
      tester.getCenter(find.byKey(pagingKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(r.opened, isEmpty);
    expect(r.selected, containsAll(<String>['4:0', '4:7']));
  });

  testWidgets('the talk screen arms whichever gesture the device carries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await CaregiverEntryStore(db).write(
      const CaregiverEntry.standard().withGesture(CaregiverGesture.twoCorners),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TalkScreen(
          db: db,
          speech: _SilentSpeech(),
          vocabularyId: vocabularyId,
          logger: UsageLogger(db, deviceId: 'test'),
          auth: PinAuth(db, storage: _FakeSecretStore()),
          profileId: 'p1',
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      tester.widget<GridSurface>(find.byType(GridSurface)).pairHold,
      CaregiverEntry.defaultPairHold,
    );
    expect(
      tester
          .widget<CornerHoldTarget>(find.byType(CornerHoldTarget))
          .holdDuration,
      CaregiverEntry.oneHandedFallback,
      reason:
          'the one-handed way in was closed rather than slowed, which leaves '
          'anybody who cannot make the two-corner hold locked out of their own '
          'settings',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });

  group('what the device remembers', () {
    test('nothing chosen is the one-point hold at two seconds', () async {
      final entry = await CaregiverEntryStore(db).read();

      expect(entry.gesture, CaregiverGesture.cornerHold);
      expect(entry.hold, CaregiverEntry.defaultCornerHold);
      expect(entry.pairHold, isNull);
      expect(entry.cornerHold, CaregiverEntry.defaultCornerHold);
    });

    test('a choice survives a re-read', () async {
      final store = CaregiverEntryStore(db);
      await store.write(
        const CaregiverEntry(
          gesture: CaregiverGesture.twoCorners,
          hold: Duration(seconds: 8),
        ),
      );

      final entry = await store.read();
      expect(entry.gesture, CaregiverGesture.twoCorners);
      expect(entry.hold, const Duration(seconds: 8));
      expect(entry.pairHold, const Duration(seconds: 8));
    });

    test('the one-point hold is slowed, never removed', () {
      const entry = CaregiverEntry(
        gesture: CaregiverGesture.twoCorners,
        hold: Duration(seconds: 5),
      );

      expect(entry.cornerHold, CaregiverEntry.oneHandedFallback);
      expect(
        entry.cornerHold.inSeconds,
        greaterThan(CaregiverEntry.defaultCornerHold.inSeconds),
        reason:
            'the door that cannot be taken away has to be the slower one, or '
            'choosing the two-corner hold buys nothing',
      );
    });

    test('a hold of zero is refused', () async {
      final store = CaregiverEntryStore(db);
      await store.write(
        const CaregiverEntry(
          gesture: CaregiverGesture.cornerHold,
          hold: Duration.zero,
        ),
      );

      expect((await store.read()).hold, CaregiverEntry.minimumHold);
    });

    test('a value nothing recognizes falls back rather than throwing', () async {
      await db
          .into(db.appState)
          .insertOnConflictUpdate(
            AppStateCompanion.insert(
              key: CaregiverEntryStore.gestureKey,
              value: 'sevenFingers',
            ),
          );

      expect(
        (await CaregiverEntryStore(db).read()).gesture,
        CaregiverGesture.cornerHold,
        reason:
            'a device that cannot read its own setting must still have a door '
            'into the settings that would fix it',
      );
    });

    test('switching gesture takes that gesture\'s own duration', () {
      const entry = CaregiverEntry(
        gesture: CaregiverGesture.cornerHold,
        hold: Duration(seconds: 2),
      );

      expect(
        entry.withGesture(CaregiverGesture.twoCorners).hold,
        CaregiverEntry.defaultPairHold,
      );
    });
  });
}
