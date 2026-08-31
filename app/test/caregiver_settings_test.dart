import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/age_presets.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/backup/backup_service.dart';
import 'package:wordbridge/features/backup/snapshot.dart';
import 'package:wordbridge/features/caregiver/caregiver_home.dart';
import 'package:wordbridge/features/interop/board_files.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/usage/logger.dart';

/// Backups without a disk under them.
///
/// The backups row opens its screen directly now, so this test walks into it —
/// and a widget test runs on a fake clock, where a real folder read started
/// inside one never comes back. What is under test here is that the control is
/// reachable, not what it does; `backups_screen_test.dart` owns that.
class _NoBackups extends BackupService {
  _NoBackups(super.db);

  @override
  Future<List<Snapshot>> snapshots() async => const [];

  // Caregiver mode takes a copy on the way in (§4.41 part 4b). Real, here,
  // would be a file write started inside a widget test.
  @override
  Future<Snapshot?> sessionSnapshot() async => null;

  @override
  Future<SnapshotAttempt> takeSessionSnapshot() async =>
      (snapshot: null, problem: null);
}

/// Board files without a folder under them, for the same reason as
/// [_NoBackups]: this walks into the screen, and a real directory read started
/// inside a widget test never comes back.
class _NoBoardFiles extends BoardFileStore {
  _NoBoardFiles(super.db);

  @override
  Future<List<BoardFile>> files() async => const [];
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

/// Every control, and the section it is reached through.
///
/// The list a caregiver is owed: nothing here was reachable before and is not
/// now. Written as titles rather than as widget types because a title is what
/// somebody is actually looking for, and a rearrangement that keeps the widget
/// tree and loses the words is still a control they cannot find.
const _reachable = <String, List<String>>{
  'Who is using this': [
    'Profiles',
    'How many words are shown',
    'New words',
    'Include strong language',
  ],
  'The board': [
    'Button size and orientation',
    'Rebuild from the shipped vocabulary',
  ],
  // One screen rather than a page of controls, so the row on the list opens
  // it directly. What has to stay reachable is the control, not the hop.
  'Backups': ['Back up now'],
  // §4.41 part 3. The readers and writers existed and nothing called them.
  'Import and export': ['Write this board set out', 'Files on this tablet'],
  // Also one screen. The four below it were nominally reachable and
  // practically were not: they sat under every offline voice the tablet has,
  // and a caregiver who had used the app for weeks did not know pitch control
  // existed (§4.45). The list is behind "Which voice" now, and these are on
  // the screen the row opens.
  'How it sounds': ['Which voice', 'Tone', 'Speed', 'Pitch', 'Volume'],
  'How it behaves': [
    'Go back to the home board after each word',
    'Say each word as it is chosen',
    'Pause after the board changes',
    'Show how a word was reached',
    'Label what each part of the board is for',
    'After choosing a word in "Find a word"',
  ],
  'Words and grammar': [
    'Show word endings only when they fit',
    'Join "not" to the word before it',
    'Choosing between "am", "is" and "are"',
    'Hide other verbs after a verb',
    'Suggest the next word',
    'Start the suggestions over',
  ],
  'Getting in here': [
    'One corner, held',
    'Both bottom corners, held together',
    'Held for 2 seconds',
  ],
  'Recording': ['Track word usage'],
  'About': ['Symbol credits'],
};

/// A caregiver comes in here to change one thing.
///
/// Sections are pages, so the screen opens on eight lines rather than on two
/// dozen controls each explaining itself in a paragraph. What that must not
/// cost is a setting: a switch nobody can find is a switch that does not
/// exist, and three more modes are coming.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;
  late UsageLogger logger;

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
            // An adult, so the strong-language switch is offered at all.
            birthDate: Value(DateTime(1990, 4, 2).millisecondsSinceEpoch),
            vocabLevel: const Value(3),
            settingsJson: Value(
              jsonEncode({
                'settleDelayMs': 0,
                'voiceName': 'Alex',
                'tone': 'calm',
              }),
            ),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(
      db,
      rows: 7,
      cols: 12,
      profileId: profileId,
      ageBand: AgeBand.adult,
    );
    settings = ProfileSettings(db, profileId);
    await settings.load();
    logger = UsageLogger(db, deviceId: 'test');
  });

  /// Long enough for the settings reads and a route's slide. `pumpAndSettle`
  /// is out: the board list holds a spinner until its first frame of data.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Tall enough that a whole section fits without scrolling, so a missing
  /// control fails the test rather than hiding below the fold.
  Future<void> pumpSettings(
    WidgetTester tester, {
    bool withSettings = true,
    bool withSpeech = true,
    void Function(dynamic)? onSwitchProfile,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CaregiverHome(
          db: db,
          vocabularyId: vocabularyId,
          profileId: profileId,
          logger: logger,
          speech: withSpeech ? _SilentSpeech() : null,
          settings: withSettings ? settings : null,
          backup: _NoBackups(db),
          boards: _NoBoardFiles(db),
          userName: 'Maya',
          onSwitchProfile: onSwitchProfile,
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Settings'));
    await settle(tester);
  }

  /// Drops the widget before the database goes, so nothing is still reading
  /// from it when it closes.
  Future<void> closeHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> open(WidgetTester tester, String section) async {
    await tester.tap(find.text(section));
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await settle(tester);
  }

  tearDown(() => db.close());

  group('every setting is still reachable', () {
    testWidgets('each section holds the controls it is named for', (
      tester,
    ) async {
      await pumpSettings(tester, onSwitchProfile: (_) {});

      for (final section in _reachable.entries) {
        await open(tester, section.key);

        for (final title in section.value) {
          expect(
            find.text(title),
            findsOneWidget,
            reason: '"$title" is not on the "${section.key}" page',
          );
        }

        await back(tester);
      }

      await closeHome(tester);
    });

    testWidgets('the list is section names and nothing else', (tester) async {
      await pumpSettings(tester, onSwitchProfile: (_) {});

      expect(
        find.byType(Switch),
        findsNothing,
        reason: 'a control was left on the list a caregiver has to scan',
      );
      expect(find.byType(Slider), findsNothing);
      // The sections, plus the card at the top naming whose board this is.
      expect(find.byType(ListTile), findsNWidgets(_reachable.length + 1));

      await closeHome(tester);
    });

    testWidgets('says whose board it is, above everything else', (
      tester,
    ) async {
      // Every control below applies to one person and nothing else on the
      // screen says which. A caregiver changing a setting for the wrong child
      // finds out by noticing.
      await pumpSettings(tester, onSwitchProfile: (_) {});

      final header = find.descendant(
        of: find.byType(Card),
        matching: find.byType(ListTile),
      );
      expect(header, findsOneWidget);
      expect((tester.widget<ListTile>(header).title! as Text).data, 'Maya');

      // First on the screen, not merely present.
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
      expect((tiles.first.title! as Text).data, 'Maya');

      await closeHome(tester);
    });

    testWidgets('the sections keep the order they have always had', (
      tester,
    ) async {
      await pumpSettings(tester, onSwitchProfile: (_) {});

      // Past the card naming the person, which is a header rather than a
      // section.
      final titles = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data,
      ].skip(1).toList();
      expect(titles, _reachable.keys.toList());

      await closeHome(tester);
    });

    testWidgets('every row says what is behind it', (tester) async {
      await pumpSettings(tester, onSwitchProfile: (_) {});

      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        final title = (tile.title! as Text).data!;
        final subtitle = (tile.subtitle as Text?)?.data;

        expect(
          subtitle,
          isNotNull,
          reason: '"$title" is a bare name a caregiver has to open to read',
        );
        expect(subtitle!.split(' ').length, greaterThan(4), reason: title);
      }

      await closeHome(tester);
    });
  });

  group('a section with nothing on it', () {
    testWidgets('is not offered as a page that opens onto nothing', (
      tester,
    ) async {
      await pumpSettings(tester, withSettings: false, withSpeech: false);

      // Every control in these three needs the profile's settings, or a voice
      // to set.
      expect(find.text('How it sounds'), findsNothing);
      expect(find.text('How it behaves'), findsNothing);
      expect(find.text('Words and grammar'), findsNothing);

      // The rest still stand on their own.
      expect(find.text('Who is using this'), findsOneWidget);
      expect(find.text('The board'), findsOneWidget);
      expect(find.text('Backups'), findsOneWidget);
      expect(find.text('Import and export'), findsOneWidget);
      expect(find.text('Getting in here'), findsOneWidget);
      expect(find.text('Recording'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);

      await closeHome(tester);
    });

    testWidgets('what is left of a thinned section is still reachable', (
      tester,
    ) async {
      await pumpSettings(tester, withSettings: false, withSpeech: false);

      await open(tester, 'The board');
      expect(find.text('Rebuild from the shipped vocabulary'), findsOneWidget);
      expect(find.text('Button size and orientation'), findsNothing);

      await back(tester);
      await closeHome(tester);
    });
  });

  group('what the list says without opening anything', () {
    testWidgets('the voice and tone read from the row', (tester) async {
      await pumpSettings(tester);

      expect(find.textContaining('Alex · Calm'), findsOneWidget);

      await closeHome(tester);
    });

    testWidgets('and it names the voice that is actually speaking', (
      tester,
    ) async {
      // A profile carries `neuralVoice` across builds, and this build has no
      // neural engine to honour it. The row has to say what somebody will
      // hear, which here is still the device's own voice.
      await settings.set('neuralVoice', true);
      await pumpSettings(tester);

      expect(find.textContaining('Alex · Calm'), findsOneWidget);
      expect(find.textContaining('Neural voice'), findsNothing);

      await closeHome(tester);
    });

    testWidgets('so does the grid, and whether anything is recorded', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.textContaining('Medium icons, landscape'), findsOneWidget);
      expect(find.textContaining('\nOff'), findsOneWidget);

      await closeHome(tester);
    });

    testWidgets('recording says on once it is on', (tester) async {
      await pumpSettings(tester);

      await open(tester, 'Recording');
      await tester.tap(find.text('Track word usage'));
      await settle(tester);
      await back(tester);

      expect(find.textContaining('\nOn'), findsOneWidget);
      expect(logger.enabled, isTrue);

      await closeHome(tester);
    });
  });

  group('a control moved on a section page', () {
    testWidgets('shows its new value without leaving the page', (tester) async {
      await pumpSettings(tester);
      await open(tester, 'How it behaves');

      final auto = find.ancestor(
        of: find.text('Go back to the home board after each word'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(auto).value, isTrue);

      await tester.tap(find.text('Go back to the home board after each word'));
      await settle(tester);

      expect(
        tester.widget<SwitchListTile>(auto).value,
        isFalse,
        reason: 'the switch stayed where it was until the page was left',
      );
      expect(settings.autoReturn, isFalse);

      await back(tester);
      await closeHome(tester);
    });

    testWidgets('a control that only applies while another is on appears', (
      tester,
    ) async {
      await settings.set('prediction', false);
      await pumpSettings(tester);
      await open(tester, 'Words and grammar');

      expect(find.text('Start the suggestions over'), findsNothing);

      await tester.tap(find.text('Suggest the next word'));
      await settle(tester);

      expect(find.text('Start the suggestions over'), findsOneWidget);

      await back(tester);
      await closeHome(tester);
    });
  });

  group('what a page must not make easier', () {
    testWidgets('rebuilding still asks for the word to be typed', (
      tester,
    ) async {
      await pumpSettings(tester);
      await open(tester, 'The board');

      await tester.tap(find.text('Rebuild from the shipped vocabulary'));
      await settle(tester);

      expect(find.text('Type REBUILD to continue.'), findsOneWidget);
      expect(find.widgetWithText(AlertDialog, 'Rebuild'), findsOneWidget);

      await tester.tap(find.text('Keep these boards'));
      await settle(tester);
      await back(tester);
      await closeHome(tester);
    });

    testWidgets('changing the grid still goes through the cost screen', (
      tester,
    ) async {
      await pumpSettings(tester);
      await open(tester, 'The board');

      await tester.tap(find.text('Button size and orientation'));
      await settle(tester);

      expect(find.text('Button size and orientation'), findsWidgets);
      expect(find.text('Landscape'), findsOneWidget);
      expect(find.text('Extra large'), findsOneWidget);

      await back(tester);
      await back(tester);
      await closeHome(tester);
    });
  });

  group('leaving on a board that is no longer there', () {
    testWidgets('switching profile closes the caregiver screen behind it', (
      tester,
    ) async {
      final ts = nowMs();
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'p2',
              displayName: 'Sam',
              createdAt: ts,
              updatedAt: ts,
            ),
          );

      var switched = 0;
      await pumpSettings(tester, onSwitchProfile: (_) => switched++);

      await open(tester, 'Who is using this');
      await tester.tap(find.text('Profiles'));
      await settle(tester);

      await tester.tap(find.text('Sam'));
      await settle(tester);

      expect(switched, 1);
      expect(
        find.text('Caregiver'),
        findsNothing,
        reason: 'the caregiver screen was left over somebody else\'s board',
      );

      await closeHome(tester);
    });
  });
}
