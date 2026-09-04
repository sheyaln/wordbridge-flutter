import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/caregiver/board_files_screen.dart';
import 'package:wordbridge/features/interop/board_files.dart';

/// What the screen asks before it writes a file, and where the file goes
/// afterwards.
///
/// What an export *contains* is `interop_test.dart`'s question and what the
/// store writes is `board_files_test.dart`'s. This one is about the two things
/// only the screen can get wrong: asking about the boards a chosen page opens
/// before rather than after the file exists, and handing that file to the
/// platform without the screen going down with it if there is nowhere to send
/// it.
///
/// The store is held in memory. A widget test runs on a fake clock, and a real
/// folder read started inside one never comes back.
void main() {
  late WordbridgeDatabase db;
  late _Store store;
  late List<({BoardFile file, Rect? origin})> shared;
  late String? shareProblem;

  final file = (
    path: '/boards/Sam 2026-08-30.obz',
    name: 'Sam 2026-08-30.obz',
    bytes: 2048,
    at: DateTime(2026, 8, 30),
  );

  setUp(() {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    store = _Store(db);
    shared = [];
    shareProblem = null;
  });

  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BoardFilesScreen(
          db: db,
          vocabularyId: 'v1',
          store: store,
          share: (file, {origin}) async {
            shared.add((file: file, origin: origin));
            return shareProblem;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a board that opens nothing is exported without a second '
      'question', (tester) async {
    await open(tester);

    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(store.exported, [(scope: ExportScope.board, boardId: 'play')]);
    expect(
      find.text('This board alone'),
      findsNothing,
      reason: 'there was nothing to ask about',
    );
  });

  testWidgets('a board that opens others asks before writing anything', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('food'));
    await tester.pumpAndSettle();

    // Nothing has been written yet: the question is put before the file
    // exists, not reported once it has been handed over.
    expect(store.exported, isEmpty);
    expect(find.textContaining('"food" opens 2 other boards'), findsOneWidget);
    expect(
      find.textContaining('those keys will not open anything'),
      findsOneWidget,
    );
  });

  testWidgets('taking the board alone exports the board alone', (tester) async {
    await open(tester);

    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This board alone'));
    await tester.pumpAndSettle();

    expect(store.exported, [(scope: ExportScope.board, boardId: 'food')]);
  });

  testWidgets('taking the boards it opens exports the category', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take all 3'));
    await tester.pumpAndSettle();

    expect(store.exported, [(scope: ExportScope.category, boardId: 'food')]);
  });

  testWidgets('what the file could not carry is shown, not logged', (
    tester,
  ) async {
    store.notes = ['"fruit" is not in this file.'];
    await open(tester);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Exported, with these differences'), findsOneWidget);
    expect(find.textContaining('"fruit" is not in this file.'), findsOneWidget);
  });

  testWidgets('a file can be handed to the platform', (tester) async {
    store.listed = [file];
    await open(tester);

    await tester.tap(find.byTooltip('Send "${file.name}" somewhere'));
    await tester.pumpAndSettle();

    expect(shared, hasLength(1));
    expect(shared.single.file.path, file.path);
    expect(
      shared.single.origin,
      isNotNull,
      reason: 'an iPad popover with nowhere to point does not open',
    );
  });

  testWidgets('and a device with nowhere to send it says so instead of '
      'falling over', (tester) async {
    store.listed = [file];
    shareProblem = 'This device offered nowhere to send it.';
    await open(tester);

    await tester.tap(find.byTooltip('Send "${file.name}" somewhere'));
    await tester.pumpAndSettle();

    expect(
      find.text('This device offered nowhere to send it.'),
      findsOneWidget,
    );
    expect(find.text('Import and export'), findsOneWidget);
  });
}

/// The store without a folder under it, recording what it was asked for.
class _Store extends BoardFileStore {
  _Store(super.db);

  List<BoardFile> listed = const [];
  List<String> notes = const [];
  final exported = <({ExportScope scope, String? boardId})>[];

  @override
  Future<List<BoardFile>> files() async => listed;

  @override
  Future<List<ExportableBoard>> exportableBoards(String vocabularyId) async =>
      const [
        (id: 'home', name: 'home', opens: 3),
        (id: 'food', name: 'food', opens: 2),
        (id: 'play', name: 'play', opens: 0),
      ];

  @override
  Future<ExportOutcome> export({
    required String vocabularyId,
    required ExportScope scope,
    String? boardId,
    DateTime? at,
  }) async {
    exported.add((scope: scope, boardId: boardId));
    return (
      file: (
        path: '/boards/written.obz',
        name: 'written.obz',
        bytes: 12,
        at: DateTime(2026, 8, 30),
      ),
      notes: notes,
    );
  }
}
