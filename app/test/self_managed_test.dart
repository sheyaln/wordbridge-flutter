import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/profiles/profile_setup.dart';

const _iPadMini = Size(744, 1133);

/// Whether the person on this board is the person who manages it (§4.78).
///
/// The PIN exists because an AAC device is usually set up by somebody other
/// than the person speaking on it, and the settings behind it can take that
/// person's words away. A door between the two is right when there are two.
///
/// There are not always two. An adult who bought this for themselves is the
/// user and the caregiver, and asking them for a PIN to reach their own
/// settings — under a heading calling them somebody else's charge — is the
/// software telling a competent adult what it thinks they are.
void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  GridChoice grid() => GridChoice.derive(
    screen: _iPadMini,
    orientation: BoardOrientation.landscape,
    iconSize: IconSize.medium,
  );

  Future<ProfileSettings> settingsFor(String profileId) async {
    final settings = ProfileSettings(db, profileId);
    await settings.load();
    return settings;
  }

  group('the setting', () {
    test('is off for a profile nobody answered the question for', () async {
      // The safe answer for the unanswered case: a board set up for somebody
      // else and left with the door open is the failure that costs a person
      // their vocabulary.
      final profile = await ProfileRepository(db)
          .create(displayName: 'Maya', grid: grid());

      expect((await settingsFor(profile.id)).selfManaged, isFalse);
    });

    test('is written when setup says the board is the user’s own', () async {
      final profile = await ProfileRepository(db)
          .create(displayName: 'Sam', grid: grid(), selfManaged: true);

      expect((await settingsFor(profile.id)).selfManaged, isTrue);
    });

    test('is written either way, rather than left to a default', () async {
      // The record says somebody was asked. A getter's default reaching a
      // profile built before the question existed is a different fact from a
      // person answering it.
      final profile = await ProfileRepository(db)
          .create(displayName: 'Maya', grid: grid(), selfManaged: false);

      final raw = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals(profile.id))).getSingle();

      expect(raw.settingsJson, contains('selfManaged'));
    });

    test('can be changed afterwards, because the answer changes', () async {
      // A child grows up, a person moves out, a device is handed over.
      final profile = await ProfileRepository(db)
          .create(displayName: 'Sam', grid: grid());
      final settings = await settingsFor(profile.id);

      await settings.set('selfManaged', true);
      expect(settings.selfManaged, isTrue);

      await settings.set('selfManaged', false);
      expect(settings.selfManaged, isFalse);
    });

    test('moves nothing on the board', () async {
      // It changes a door, not a layout. Two people set up the same way get
      // the same board however they answered this, which is what makes it safe
      // to change afterwards.
      Future<Set<String>> layout(bool self) async {
        final scratch = WordbridgeDatabase.forTesting(NativeDatabase.memory());
        addTearDown(scratch.close);

        await ProfileRepository(scratch)
            .create(displayName: 'Maya', grid: grid(), selfManaged: self);

        final boards = {
          for (final b in await scratch.select(scratch.boards).get())
            b.id: b.name,
        };

        final rows = await scratch.select(scratch.cells).join([
          innerJoin(
            scratch.buttons,
            scratch.buttons.cellId.equalsExp(scratch.cells.id),
          ),
        ]).get();

        return {
          for (final r in rows)
            '${boards[r.readTable(scratch.cells).boardId]}'
                '|${r.readTable(scratch.cells).row}'
                '|${r.readTable(scratch.cells).col}'
                '|${r.readTable(scratch.buttons).label}',
        };
      }

      expect(await layout(true), await layout(false));
    });
  });

  group('the question at setup', () {
    Future<void> pumpSetup(WidgetTester tester) async {
      tester.view.physicalSize = _iPadMini;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ProfileSetup(db: db, isFirstRun: true)),
      );
      await tester.pumpAndSettle();
    }

    /// Scrolls until something is on screen, rather than assuming it is. The
    /// page is a `ListView`, so anything far enough down it is not built yet.
    Future<Finder> reveal(WidgetTester tester, Finder target) async {
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 60,
        );
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      return target;
    }

    testWidgets('is asked, and asked first', (tester) async {
      await pumpSetup(tester);

      expect(find.text('Who is this board for?'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Someone else'), findsOneWidget);

      // Above the name, because it changes what the name field is asking.
      expect(
        tester.getCenter(find.text('Who is this board for?')).dy,
        lessThan(tester.getCenter(find.text('Date of birth')).dy),
      );
    });

    testWidgets('nothing is preselected', (tester) async {
      // A default here would read as the question already answered, and the
      // answer decides whether there is a door in front of the settings.
      await pumpSetup(tester);

      expect(
        find.byWidgetPredicate((w) => w is RadioGroup && w.groupValue != null),
        findsNothing,
      );
    });

    testWidgets('the name field asks about the right person', (tester) async {
      await pumpSetup(tester);
      expect(find.text('Their name'), findsOneWidget);

      await tester.tap(await reveal(tester, find.text('Me')));
      await tester.pumpAndSettle();

      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Their name'), findsNothing);
    });

    testWidgets('and the answer reaches the profile', (tester) async {
      await pumpSetup(tester);

      await tester.tap(await reveal(tester, find.text('Me')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Sam');
      await tester.pumpAndSettle();

      await tester.tap(await reveal(tester, find.text('Build the board')));
      await tester.pumpAndSettle();

      final profiles = await db.select(db.profiles).get();
      expect(profiles, hasLength(1));
      expect((await settingsFor(profiles.single.id)).selfManaged, isTrue);
    });

    testWidgets('and someone else is the other answer', (tester) async {
      await pumpSetup(tester);

      await tester.tap(await reveal(tester, find.text('Someone else')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Maya');
      await tester.pumpAndSettle();

      await tester.tap(await reveal(tester, find.text('Build the board')));
      await tester.pumpAndSettle();

      final profiles = await db.select(db.profiles).get();
      expect((await settingsFor(profiles.single.id)).selfManaged, isFalse);
    });
  });
}
