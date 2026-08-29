import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';
import 'package:wordbridge/features/profiles/profile_setup.dart';

const _iPadMini = Size(744, 1133);

/// The answer given at setup is the level the board opens on.
///
/// The birthday only proposes a level; the person setting the board up knows
/// whether words are being put together and the birthday does not. A profile
/// that quietly keeps the band's level whatever was chosen is a caregiver
/// answering a question that does nothing.
void main() {
  late WordbridgeDatabase db;
  late ProfileRepository profiles;

  GridChoice grid() => GridChoice.derive(
    screen: _iPadMini,
    orientation: BoardOrientation.landscape,
    iconSize: IconSize.medium,
  );

  group('the level create() is given', () {
    setUp(() {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      profiles = ProfileRepository(db);
    });

    tearDown(() async => db.close());

    test('an explicit level is the level the profile starts on', () async {
      final profile = await profiles.create(
        displayName: 'Maya',
        grid: grid(),
        vocabLevel: 3,
      );

      expect(profile.vocabLevel, 3);
    });

    test('an explicit level outranks the band the birthday falls in', () async {
      final now = DateTime.now();
      final born = DateTime(now.year - 4, now.month, now.day);
      final profile = await profiles.create(
        displayName: 'Maya',
        grid: grid(),
        birthDate: born,
        vocabLevel: 2,
      );

      expect(AgeBand.forBirthDate(born), AgeBand.earlyYears);
      expect(AgeBand.earlyYears.startingLevel, 1);
      expect(
        profile.vocabLevel,
        2,
        reason:
            'the board opened on the band’s level, so the caregiver who said '
            'this person is putting words together has no endings and no '
            'copula on the board they were shown',
      );
    });

    test('no level given follows the band', () async {
      final now = DateTime.now();
      final young = await profiles.create(
        displayName: 'Maya',
        grid: grid(),
        birthDate: DateTime(now.year - 4, now.month, now.day),
      );
      final older = await profiles.create(
        displayName: 'Sam',
        grid: grid(),
        birthDate: DateTime(now.year - 9, now.month, now.day),
      );

      expect(young.vocabLevel, AgeBand.earlyYears.startingLevel);
      expect(older.vocabLevel, AgeBand.child.startingLevel);
    });
  });

  group('the question on the setup page', () {
    // The database is deliberately not closed. Closing it inside a widget test
    // waits on work the fake clock never runs; each test gets its own
    // in-memory instance and the process ends with the file.
    setUp(() {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      profiles = ProfileRepository(db);
    });

    /// Setup builds a whole board set, which is hundreds of inserts across
    /// many turns of the event loop. Pumped until the profile lands rather
    /// than settled: the button shows a spinner that never stops.
    Future<Profile?> pumpUntilCreated(WidgetTester tester) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final made = await profiles.list();
        if (made.isNotEmpty) return made.first;
      }
      return null;
    }

    testWidgets('asks it, and the answer reaches the profile', (tester) async {
      tester.view.physicalSize = const Size(2048, 1536);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: ProfileSetup(db: db)));
      await tester.pump();

      // The page is one long list, and a sliver builds nothing it is not
      // showing, so each question has to be scrolled to before it exists.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('What are they ready for?'),
        120,
        scrollable: list,
      );
      expect(find.text('What are they ready for?'), findsOneWidget);

      // No birthday, so the band proposes level 2. Answering with the first
      // board is the answer that has to survive.
      expect(AgeBand.forBirthDate(null).startingLevel, 2);

      final firstBoard = find.text('Learning single words');
      await tester.scrollUntilVisible(firstBoard, 120, scrollable: list);
      // Built is not the same as on screen: the sliver builds a little past
      // the fold, and a card below it cannot be tapped.
      await tester.ensureVisible(firstBoard);
      await tester.pump();
      await tester.tap(firstBoard);
      await tester.pump();

      await tester.tap(find.text('Build the board'));
      final profile = await pumpUntilCreated(tester);

      expect(profile, isNotNull);
      expect(
        profile!.vocabLevel,
        1,
        reason:
            'the board was built at the level the birthday guessed rather '
            'than the one that was chosen on the page',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
