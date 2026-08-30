import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/auth/corner_hold_target.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/grid/grid_geometry.dart';
import 'package:wordbridge/features/grid/grid_surface.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
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

/// The way into caregiver mode must not stand on a key.
///
/// It is a 2-second hold on a fixed patch of the screen, hit-tested before the
/// board. A patch that covers part of a key takes the taps that land there,
/// and the user it takes them from is one who cannot say that the board has
/// stopped answering: they press home, nothing happens, and the next word they
/// say comes off whatever category board they are still on.
///
/// Home is the key at risk, because [SystemRowPlan] puts it at the bottom-left
/// cell of every board at every grid size.
void main() {
  /// Devices the app is used on. The grid is derived per device, so every one
  /// of them produces a different set of cell sizes.
  const screens = <String, Size>{
    'iPad mini': Size(744, 1133),
    'iPad 10.9': Size(820, 1180),
    'iPad 13': Size(1032, 1376),
    'phone': Size(390, 844),
  };

  /// The board's own rectangle: what is left under the utterance bar, inset.
  Rect boardRect(Size surface) => Rect.fromLTRB(
    gridInset,
    utteranceBarHeight + gridInset,
    surface.width - gridInset,
    surface.height - gridInset,
  );

  /// Where the home key is drawn, in the talk screen's coordinates.
  Rect homeKeyRect(Size surface, GridChoice choice) {
    final plan = SystemRowPlan.forGrid(
      rows: choice.rows,
      cols: choice.cols,
      // Home sits at column 0 of the last row whatever else the row carries.
      categories: 6,
    );
    final board = boardRect(surface);
    final geometry = GridGeometry(
      rows: choice.rows,
      cols: choice.cols,
      size: board.size,
    );
    return geometry.rectFor(plan.row, plan.homeCol).shift(board.topLeft);
  }

  /// The surface the talk screen lays out in, for a chosen orientation.
  Size surfaceFor(Size screen, BoardOrientation orientation) =>
      orientation == BoardOrientation.landscape
      ? Size(screen.longestSide, screen.shortestSide)
      : Size(screen.shortestSide, screen.longestSide);

  group('the gesture is clear of the home key', () {
    for (final entry in screens.entries) {
      for (final orientation in BoardOrientation.values) {
        for (final iconSize in IconSize.values) {
          final choice = GridChoice.derive(
            screen: entry.value,
            orientation: orientation,
            iconSize: iconSize,
          );
          if (!choice.isUsable) continue;

          test('${entry.key}, ${orientation.label.toLowerCase()}, '
              '${iconSize.label.toLowerCase()} icons '
              '(${choice.rows}x${choice.cols})', () {
            final surface = surfaceFor(entry.value, orientation);
            final home = homeKeyRect(surface, choice);

            expect(
              caregiverGestureRect.overlaps(home),
              isFalse,
              reason:
                  'the caregiver gesture covers '
                  '${caregiverGestureRect.intersect(home).width.round()}x'
                  '${caregiverGestureRect.intersect(home).height.round()} '
                  'of the ${home.width.round()}x${home.height.round()} home '
                  'key, and a user cannot report a key that does nothing',
            );
          });
        }
      }
    }
  });

  group('the gesture is clear of the whole board', () {
    // Stronger than the home key alone, and the reason it holds at every grid
    // size: the clearance is the utterance bar's own height, not a margin that
    // shrinks as cells get smaller.
    for (final entry in screens.entries) {
      for (final orientation in BoardOrientation.values) {
        test('${entry.key}, ${orientation.label.toLowerCase()}', () {
          final surface = surfaceFor(entry.value, orientation);

          expect(
            caregiverGestureRect.overlaps(boardRect(surface)),
            isFalse,
            reason: 'a reach for a cell can land on the caregiver gesture',
          );
        });
      }
    }
  });

  testWidgets('the gesture leaves the touch to what it sits on', (
    tester,
  ) async {
    // It shares the utterance bar's band with the Speak button. Sitting on a
    // control is only survivable because the target passes touches through.
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
              ),
            ),
            Positioned.fromRect(
              rect: caregiverGestureRect,
              child: CornerHoldTarget(onTriggered: () {}),
            ),
          ],
        ),
      ),
    );

    await tester.tapAt(caregiverGestureRect.center);
    await tester.pump();

    expect(
      taps,
      1,
      reason: 'the gesture swallowed a tap meant for what is underneath it',
    );
  });

  testWidgets('a two-second hold still opens caregiver mode', (tester) async {
    var triggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
              ),
            ),
            Positioned.fromRect(
              rect: caregiverGestureRect,
              child: CornerHoldTarget(onTriggered: () => triggered = true),
            ),
          ],
        ),
      ),
    );

    final hold = await tester.startGesture(caregiverGestureRect.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(triggered, isFalse, reason: 'a short press must do nothing');

    await tester.pump(const Duration(milliseconds: 2));
    expect(triggered, isTrue);

    await hold.up();
    await tester.pump();
  });

  testWidgets('the drawn target lands where the geometry says it does', (
    tester,
  ) async {
    // The rectangles above are only worth anything if the screen puts the
    // target where they say. The database is deliberately not closed: closing
    // it inside a widget test waits on work the fake clock never runs.
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    final vocabularyId = await seedCoreBoardSet(db);
    final vocab = await (db.select(
      db.vocabularies,
    )..where((v) => v.id.equals(vocabularyId))).getSingle();

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
    // The board arrives over several turns: the vocabulary read, then the
    // first cells off the query stream. Each pump drains one.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(tester.getRect(find.byType(CornerHoldTarget)), caregiverGestureRect);

    final board = tester.getRect(find.byType(GridSurface));
    final home = GridGeometry(
      rows: vocab.gridRows,
      cols: vocab.gridCols,
      size: board.size,
    ).rectFor(vocab.gridRows - 1, 0).shift(board.topLeft);

    expect(
      tester.getRect(find.byType(CornerHoldTarget)).overlaps(home),
      isFalse,
      reason: 'the caregiver gesture is drawn on top of the home key',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    // Drift schedules a zero-duration timer when a query stream is dropped.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
