import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/board_builder.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/band_layout.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/grid/region_label_strip.dart';
import 'package:wordbridge/features/grid/region_labels.dart';
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

/// Naming each run of locations by what it is for.
///
/// The board groups words by their job — a column of the root board is a slot
/// in a sentence, a row of a category board is a word class — and nothing on
/// the grid says so. The people who have to teach that are the ones reading it
/// for the first time.
void main() {
  late WordbridgeDatabase db;
  late String vocabularyId;
  late ProfileSettings settings;

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
            vocabLevel: const Value(3),
            settingsJson: Value(jsonEncode({'settleDelayMs': 0})),
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    vocabularyId = await seedCoreBoardSet(
      db,
      rows: 7,
      cols: 12,
      profileId: profileId,
    );
    settings = ProfileSettings(db, profileId);
    await settings.load();
  });

  group('what the seed records', () {
    tearDown(() => db.close());

    test('every seeded board knows which lines its bands own', () async {
      for (final board in await db.select(db.boards).get()) {
        final regions = BoardRegions.decode(board.bandMap);
        expect(
          regions,
          isNotNull,
          reason: '"${board.name}" cannot say what its regions are',
        );
        expect(regions!.isEmpty, isFalse);
      }
    });

    test('the root board bands by column and a category board by row', () {
      // Column position on the root board is sentence order. A category board
      // has no sentence order to encode, so it groups by word class instead.
      Future<BoardRegions?> regionsOf(String name) async {
        final board = await (db.select(
          db.boards,
        )..where((b) => b.name.equals(name))).getSingle();
        return BoardRegions.decode(board.bandMap);
      }

      expectLater(
        regionsOf('home').then((r) => r!.axis),
        completion(BandAxis.columns),
      );
      expectLater(
        regionsOf('food').then((r) => r!.axis),
        completion(BandAxis.rows),
      );
    });

    test('a board a caregiver made has no regions to name', () async {
      final id = await materialiseBoard(
        db,
        vocabularyId: vocabularyId,
        name: 'brekfist',
        kind: BoardKind.category,
      );

      final board = await (db.select(
        db.boards,
      )..where((b) => b.id.equals(id))).getSingle();

      expect(BoardRegions.decode(board.bandMap), isNull);
    });

    test(
      'the regions cover the pinned column and every content line',
      () async {
        final home = await (db.select(
          db.boards,
        )..where((b) => b.name.equals('home'))).getSingle();

        final regions = BoardRegions.decode(home.bandMap)!;
        final lines = {
          for (final b in regions.bands)
            for (var i = b.first; i <= b.last; i++) i,
        };

        // Eleven content columns; the twelfth is the pinned question column and
        // is not a band.
        expect(lines, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10});
      },
    );
  });

  group('what a name reads as', () {
    tearDown(() => db.close());

    test('the jargon ones are rewritten for somebody reading the board', () {
      expect(regionLabel('pronouns'), 'who');
      expect(regionLabel('verbs'), 'doing');
      expect(regionLabel('places'), 'where');
      expect(regionLabel('endings'), 'word endings');
    });

    test('a band already named after what it holds is left alone', () {
      // Inventing a second name for "family" or "eating" would be two things
      // to keep in step for no gain.
      expect(regionLabel('family'), 'family');
      expect(regionLabel('eating'), 'eating');
    });
  });

  group('on the board', () {
    Future<void> pump(WidgetTester tester) async {
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
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('nothing is labelled until a caregiver asks', (tester) async {
      await pump(tester);
      expect(find.byType(RegionLabelStrip), findsNothing);
    });

    testWidgets('switching it on names the regions', (tester) async {
      await settings.set('regionLabels', true);
      await pump(tester);

      expect(find.byType(RegionLabelStrip), findsOneWidget);
      expect(find.text('WHO'), findsOneWidget);
      expect(find.text('DOING'), findsOneWidget);
      expect(find.text('WHERE'), findsOneWidget);
    });

    testWidgets('and switching it off puts the buttons back', (tester) async {
      await settings.set('regionLabels', true);
      await pump(tester);

      final labelled = tester.getSize(find.byKey(const ValueKey('0:0')));

      await settings.set('regionLabels', false);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final plain = tester.getSize(find.byKey(const ValueKey('0:0')));

      expect(find.byType(RegionLabelStrip), findsNothing);
      expect(
        plain.height,
        greaterThan(labelled.height),
        reason: 'the strip costs grid height and has to give it back',
      );
      expect(plain.width, labelled.width);
    });
  });
}
