import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/auth/caregiver_gesture.dart';
import 'package:wordbridge/features/profiles/profile_setup.dart';

/// How long the way into settings is held for, chosen at setup (§4.62).
///
/// The slider already existed — in caregiver settings, which sit behind the
/// gesture it configures. So a caregiver who found the default too easy to
/// trigger by accident, or too hard to hold, had to get through the door in
/// order to change the door. Setup is the one moment they are certainly on the
/// other side of it.
void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// A surface an iPad's worth of grid derives from, so the build button is
  /// reachable rather than disabled on an unusable geometry.
  Future<void> pumpSetup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: ProfileSetup(db: db, isFirstRun: true)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setHold(WidgetTester tester, int seconds) async {
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(seconds.toDouble());
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, CaregiverGesture gesture) async {
    await tester.ensureVisible(find.text(gesture.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(gesture.label));
    await tester.pumpAndSettle();
  }

  Future<void> build(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Build the board'));
    await tester.tap(find.text('Build the board'));
    await tester.pumpAndSettle();
  }

  testWidgets('is offered on the first run', (tester) async {
    await pumpSetup(tester);

    expect(find.byType(Slider), findsOneWidget);
    expect(
      find.text(
        'Held for ${CaregiverEntry.defaultCornerHold.inSeconds} '
        'seconds',
      ),
      findsOneWidget,
    );
  });

  testWidgets('and what was chosen is what is stored', (tester) async {
    await pumpSetup(tester);
    await setHold(tester, 7);

    expect(find.text('Held for 7 seconds'), findsOneWidget);

    await build(tester);

    final entry = await CaregiverEntryStore(db).read();
    expect(entry.gesture, CaregiverGesture.cornerHold);
    expect(
      entry.hold,
      const Duration(seconds: 7),
      reason: 'setup wrote the gesture and threw the number away',
    );
  });

  testWidgets('choosing a gesture takes that gesture’s own length', (
    tester,
  ) async {
    // The two want different durations, and somebody switching between them is
    // choosing a gesture rather than carrying a number across.
    await pumpSetup(tester);
    await setHold(tester, 12);
    expect(find.text('Held for 12 seconds'), findsOneWidget);

    await choose(tester, CaregiverGesture.twoCorners);

    expect(
      find.text('Held for ${CaregiverEntry.defaultPairHold.inSeconds} seconds'),
      findsOneWidget,
    );

    await build(tester);
    final entry = await CaregiverEntryStore(db).read();
    expect(entry.gesture, CaregiverGesture.twoCorners);
    expect(entry.hold, CaregiverEntry.defaultPairHold);
  });

  testWidgets('the note names the number actually chosen', (tester) async {
    // It said "fifteen seconds rather than two" when two was the only value
    // this screen could produce. It is not any more.
    await pumpSetup(tester);
    await choose(tester, CaregiverGesture.twoCorners);
    await setHold(tester, 9);

    expect(
      find.textContaining(
        '${CaregiverEntry.oneHandedFallback.inSeconds} seconds rather than 9',
      ),
      findsOneWidget,
    );
  });
}
