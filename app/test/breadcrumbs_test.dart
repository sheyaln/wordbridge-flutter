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
import 'package:wordbridge/features/grid/grid_surface.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/breadcrumb_strip.dart';
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

/// The trail records what somebody actually pressed to reach a word, and stays
/// up long enough to be read.
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

  String trail(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(BreadcrumbStrip),
        matching: find.byType(Text),
      ),
    );
    return text.textSpan!.toPlainText();
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

  /// A word the root board already says, where it is and what it reads.
  Future<({Cell cell, String label})> rootWord() async {
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
    return (
      cell: placed.first.readTable(db.cells),
      label: placed.first.readTable(db.buttons).label,
    );
  }

  group('the setting', () {
    testWidgets('a board that predates the strip does not gain it', (
      tester,
    ) async {
      // The guarantee, and the reason it is not the getter's fallback that
      // provides it: turning this on shortens every button, so a board laid
      // out before the strip existed keeps its geometry until somebody
      // chooses otherwise. The upgrade writes that choice down — see the
      // version 5 step in `database.dart` and `migration_test.dart`.
      await settings.set('breadcrumbs', false);

      await pumpTalkScreen(tester);
      expect(find.byType(BreadcrumbStrip), findsNothing);
    });

    testWidgets('a profile created from here gets one', (tester) async {
      expect(ProfileSettings.breadcrumbsForNewProfiles, isTrue);

      // Nothing stored, which is only ever true of a profile made after the
      // strip existed — every older one was written down during the upgrade.
      expect(settings.breadcrumbs, isTrue);

      await pumpTalkScreen(tester);
      expect(find.byType(BreadcrumbStrip), findsOneWidget);
    });

    testWidgets('turning it off gives the grid its height back', (
      tester,
    ) async {
      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);
      final withStrip = tester.getSize(find.byType(GridSurface));
      final strip = tester.getSize(find.byType(BreadcrumbStrip)).height;

      await settings.set('breadcrumbs', false);
      await pumpFrames(tester);
      final without = tester.getSize(find.byType(GridSurface));

      expect(find.byType(BreadcrumbStrip), findsNothing);
      expect(
        withStrip.height,
        lessThan(without.height),
        reason:
            'the strip is drawn over the grid rather than beside it, so '
            'what the caregiver screen says it costs is not true',
      );
      expect(without.height - withStrip.height, strip);
    });
  });

  group('what the trail records', () {
    testWidgets('a real sequence, and it survives auto-return', (tester) async {
      final target = categories.first;
      final cell = await place(target.boardId, 'quay');

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);
      expect(trail(tester), 'home');

      await tapCell(tester, wheelRow, wheelCols.first);
      expect(trail(tester), 'home → ${target.name}');

      await tapCell(tester, cell.row, cell.col);

      // Auto-return has taken the board home. A trail that vanished at the
      // moment it finished would never be read by anybody.
      expect(
        labelAt(tester, wheelRow, backCol),
        isNull,
        reason: 'auto-return did not fire, so nothing here is being tested',
      );
      expect(trail(tester), 'home → ${target.name} → quay');
    });

    testWidgets('the wheel contributes the word the key was showing', (
      tester,
    ) async {
      expect(categories.length, greaterThan(wheelCols.length));

      // A category only reachable on the second turn of the wheel, so its key
      // read something else a moment ago.
      final target = categories[wheelCols.length];
      final cell = await place(target.boardId, 'quay');

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      final firstTurn = categories.first.name;
      await tapCell(tester, wheelRow, cycleCol);
      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, cell.row, cell.col);

      expect(trail(tester), 'home → more categories → ${target.name} → quay');
      expect(
        trail(tester),
        isNot(contains(firstTurn)),
        reason: 'the crumb names the board behind the key, not the key’s word',
      );
    });

    testWidgets('spinning the wheel past a category costs it nothing', (
      tester,
    ) async {
      // The defect this replaces: every press of the cycle key was a crumb, so
      // cycling round the wheel and back recorded a route nobody would ever
      // walk again. Which turn a category is on is a fact about the category.
      final target = categories.first;
      final cell = await place(target.boardId, 'quay');

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      final pages = tester
          .state<TalkScreenState>(find.byType(TalkScreen))
          .wheelPages;
      expect(pages, greaterThan(1), reason: 'the wheel does not turn here');

      // All the way round, and one turn further, so the wheel is back where it
      // started and the category is on its first turn again.
      for (var i = 0; i < pages; i++) {
        await tapCell(tester, wheelRow, cycleCol);
      }
      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, cell.row, cell.col);

      expect(
        trail(tester),
        'home → ${target.name} → quay',
        reason:
            'the trail counted the presses that were made rather than the '
            'ones that reach the word from home',
      );
    });

    testWidgets('a category on the second turn costs one turn, not four', (
      tester,
    ) async {
      final target = categories[wheelCols.length];
      final cell = await place(target.boardId, 'quay');

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      final pages = tester
          .state<TalkScreenState>(find.byType(TalkScreen))
          .wheelPages;

      // Round the wheel a whole time, then on to the second turn — so the
      // board is showing exactly what one press would have shown.
      for (var i = 0; i < pages + 1; i++) {
        await tapCell(tester, wheelRow, cycleCol);
      }
      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, cell.row, cell.col);

      expect(trail(tester), 'home → more categories → ${target.name} → quay');
    });

    testWidgets('a category reached without the wheel still costs its turns', (
      tester,
    ) async {
      // A caregiver's own key straight onto a category board. It is one press
      // from here, but the trail is the route from home, and from home that
      // category is behind however many turns of the wheel it sits on — the
      // wheel is where it stands, not where it was left.
      final target = categories[wheelCols.length];
      final cell = await place(target.boardId, 'quay');

      final shortcut =
          await (db.select(db.cells)
                ..where(
                  (c) =>
                      c.boardId.equals(vocab.rootBoardId!) &
                      c.state.equalsValue(CellState.emptyReserved) &
                      c.row.isSmallerThanValue(wheelRow),
                )
                ..limit(1))
              .getSingle();

      await placeButton(
        db,
        vocabularyId: vocabularyId,
        cellId: shortcut.id,
        label: 'straight there',
        message: '',
        action: ButtonAction.navigate,
        targetBoardId: target.boardId,
      );

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, shortcut.row, shortcut.col);
      await tapCell(tester, cell.row, cell.col);

      expect(
        trail(tester),
        'home → more categories → ${target.name} → quay',
        reason:
            'the turns were counted from where the wheel happened to be '
            'standing rather than from where the category lives',
      );
    });

    testWidgets('pressing one category three times is one crumb', (
      tester,
    ) async {
      final target = categories.first;
      final cell = await place(target.boardId, 'quay');

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, cell.row, cell.col);

      expect(trail(tester), 'home \u2192 ${target.name} \u2192 quay');
    });

    testWidgets('a category reached from another is still one press', (
      tester,
    ) async {
      // Category keys sit on the system row of every board, so where somebody
      // was standing when they pressed one is not part of the way back.
      final first = categories.first;
      final second = categories[1];
      final cell = await place(second.boardId, 'quay');

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, wheelRow, wheelCols[1]);
      await tapCell(tester, cell.row, cell.col);

      expect(trail(tester), 'home \u2192 ${second.name} \u2192 quay');
      expect(trail(tester), isNot(contains(first.name)));
    });

    testWidgets('paging forward and back again is no steps at all', (
      tester,
    ) async {
      // The detour, which is not the route. Going to page two and coming back
      // leaves the board exactly where it started, so neither press is part of
      // the way to a word on page one.
      final map = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
      final forward = map['moreWords'] as int;
      final back = map['backAPage'] as int;

      final word = await rootWord();

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, forward);
      expect(
        labelAt(tester, wheelRow, back),
        isA<String>(),
        reason: 'the board did not page, so nothing here is tested',
      );

      await tapCell(tester, wheelRow, back);
      await tapCell(tester, word.cell.row, word.cell.col);

      expect(
        trail(tester),
        'home → ${word.label}',
        reason: 'the trail counted a round trip that goes nowhere',
      );
    });

    testWidgets('a detour on the way to page two is not part of it', (
      tester,
    ) async {
      // Ending back on page one clears the trail whatever the code does, so
      // that case cannot tell a walked route from an accumulated one. This can:
      // it ends on page *two*, reached the long way round.
      final names = {for (final b in await db.select(db.boards).get()) b.name};
      final paged = categories.indexWhere((c) => names.contains('${c.name} 2'));
      expect(
        paged,
        isNonNegative,
        reason: 'no category pages at ${rows}x$cols, so nothing here is tested',
      );
      expect(paged, lessThan(wheelCols.length));

      final first = categories[paged];
      final second = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('${first.name} 2'))).getSingle();
      final cell = await place(second.id, 'quay');

      final map = jsonDecode(vocab.systemCellMap) as Map<String, dynamic>;
      final forward = map['moreWords'] as int;
      final back = map['backAPage'] as int;

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols[paged]);
      await tapCell(tester, wheelRow, forward);
      await tapCell(tester, wheelRow, back);
      await tapCell(tester, wheelRow, forward);
      await tapCell(tester, cell.row, cell.col);

      expect(
        trail(tester),
        'home → ${first.name} → more words → quay',
        reason:
            'the trail accumulated the presses that were made instead of the '
            'ones that reach the word from home',
      );
    });

    testWidgets('paging is a step of its own', (tester) async {
      // The shape §4.8 asks for: a category, the paging key, then a word.
      final names = {for (final b in await db.select(db.boards).get()) b.name};
      final paged = categories.indexWhere((c) => names.contains('${c.name} 2'));
      expect(
        paged,
        isNonNegative,
        reason: 'no category pages at ${rows}x$cols, so nothing here is tested',
      );
      expect(
        paged,
        lessThan(wheelCols.length),
        reason: 'the paged category is not on the first turn of the wheel',
      );
      final first = categories[paged];

      final second = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('${first.name} 2'))).getSingle();

      final cell = await place(second.id, 'quay');
      final pageCol =
          (jsonDecode(vocab.systemCellMap) as Map<String, dynamic>)['moreWords']
              as int;

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols[paged]);
      await tapCell(tester, wheelRow, pageCol);
      await tapCell(tester, cell.row, cell.col);

      expect(trail(tester), 'home → ${first.name} → more words → quay');
    });
  });

  group('when it clears', () {
    testWidgets('the next word taken from home starts a new trail', (
      tester,
    ) async {
      final target = categories.first;
      final deep = await place(target.boardId, 'quay');
      final shallow = await rootWord();

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, deep.row, deep.col);
      expect(trail(tester), 'home → ${target.name} → quay');

      // Auto-return left the board at home; the route no longer describes the
      // way to anything, so the next word must not inherit it.
      await tapCell(tester, shallow.cell.row, shallow.cell.col);
      expect(trail(tester), 'home → ${shallow.label}');
    });

    testWidgets('home wipes it', (tester) async {
      final target = categories.first;
      final cell = await place(target.boardId, 'quay');

      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, cell.row, cell.col);
      expect(trail(tester), 'home → ${target.name} → quay');

      await tapCell(tester, wheelRow, homeCol);
      expect(
        trail(tester),
        'home',
        reason: 'home is a reset, so it cannot leave a route on screen',
      );
    });

    testWidgets('back rewinds the trail rather than lengthening it', (
      tester,
    ) async {
      await settings.set('breadcrumbs', true);
      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols.first);
      expect(trail(tester), 'home → ${categories.first.name}');

      await tapCell(tester, wheelRow, backCol);
      expect(trail(tester), 'home');
      expect(
        labelAt(tester, wheelRow, backCol),
        isNull,
        reason: 'back did not reach the root board',
      );
    });

    testWidgets('without auto-return the route stays under the next word', (
      tester,
    ) async {
      await settings.set('autoReturn', false);
      await settings.set('breadcrumbs', true);

      final target = categories.first;
      final first = await place(target.boardId, 'quay');
      final second = await place(target.boardId, 'quays');

      await pumpTalkScreen(tester);

      await tapCell(tester, wheelRow, wheelCols.first);
      await tapCell(tester, first.row, first.col);
      expect(trail(tester), 'home → ${target.name} → quay');

      // Still on the same board, so the route to this word is the same route.
      await tapCell(tester, second.row, second.col);
      expect(trail(tester), 'home → ${target.name} → quays');
    });
  });

  testWidgets('the trail takes no taps', (tester) async {
    final target = categories.first;
    final cell = await place(target.boardId, 'quay');

    await settings.set('breadcrumbs', true);
    await pumpTalkScreen(tester);

    await tapCell(tester, wheelRow, wheelCols.first);
    await tapCell(tester, cell.row, cell.col);
    expect(trail(tester), 'home → ${target.name} → quay');

    // Pressing the crumb naming a board must not open it. A second route to a
    // board is a second motor plan for every word on it.
    final strip = tester.getRect(find.byType(BreadcrumbStrip));
    await tester.tapAt(Offset(strip.left + 60, strip.center.dy));
    await pumpFrames(tester);

    expect(
      labelAt(tester, wheelRow, backCol),
      isNull,
      reason: 'a crumb navigated, so the strip is a control',
    );
    expect(trail(tester), 'home → ${target.name} → quay');
  });
}
