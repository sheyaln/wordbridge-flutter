import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/auth/pin.dart';
import 'package:wordbridge/features/auth/pin_gate.dart';

class _FakeSecretStore implements SecretStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

/// A forgotten PIN must cost the PIN and nothing else.
///
/// The alternative escape from a lockout is a reinstall, which takes the board
/// with it — and losing a board somebody spent months learning is the failure
/// this project exists to prevent. So recovery has to be reachable by a parent
/// who has no code written down, and unreachable by the person using the board,
/// who may press every part of the screen at length and may not read.
void main() {
  late WordbridgeDatabase db;
  late PinAuth auth;

  setUp(() {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    auth = PinAuth(db, storage: _FakeSecretStore());
  });

  group('the credential', () {
    tearDown(() async => db.close());

    test('a reset clears it and lets a new PIN be set', () async {
      await auth.setPin('1234');
      expect(await auth.verify('1234'), isTrue);

      await auth.reset();

      expect(await auth.isConfigured(), isFalse);
      expect(
        await auth.verify('1234'),
        isFalse,
        reason: 'the old PIN still opens caregiver mode after a reset',
      );

      await auth.setPin('5678');
      expect(await auth.verify('5678'), isTrue);
      expect(await auth.verify('1234'), isFalse);
    });

    test('the lockout still applies to PIN attempts', () async {
      await auth.setPin('1234');

      for (var i = 0; i < PinAuth.maxAttempts; i++) {
        expect(await auth.verify('0000'), isFalse);
      }
      expect(await auth.lockoutRemaining(), isNotNull);

      expect(
        await auth.verify('1234'),
        isFalse,
        reason: 'the correct PIN is accepted while locked out',
      );
    });

    test('a reset during a lockout hands back nothing', () async {
      await auth.setPin('1234');
      for (var i = 0; i < PinAuth.maxAttempts; i++) {
        await auth.verify('0000');
      }
      expect(await auth.lockoutRemaining(), isNotNull);

      await auth.reset();

      expect(
        await auth.verify('1234'),
        isFalse,
        reason: 'a reset let the old PIN through instead of destroying it',
      );

      await auth.setPin('4321');
      expect(
        await auth.lockoutRemaining(),
        isNull,
        reason: 'the new PIN inherited the old one’s lockout',
      );
      expect(await auth.verify('4321'), isTrue);
    });

    test('a reset is recorded, so a second parent finds out', () async {
      expect(await auth.lastResetAt(), isNull);

      await auth.setPin('1234');
      expect(
        await auth.lastResetAt(),
        isNull,
        reason: 'setting a PIN is not a reset',
      );

      final before = DateTime.now().subtract(const Duration(seconds: 5));
      await auth.reset();

      final at = await auth.lastResetAt();
      expect(at, isNotNull);
      expect(at!.isAfter(before), isTrue);
    });
  });

  group('a reset leaves the rest of the device alone', () {
    // Counts and content both. A reset that quietly relabeled a button or
    // moved it would pass a count check and still have destroyed the thing
    // the PIN was guarding.
    Future<int> count(String table) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle();
      return row.read<int>('n');
    }

    Future<Map<String, int>> counts() async => {
      for (final table in const [
        'profiles',
        'vocabularies',
        'boards',
        'cells',
        'buttons',
        'symbols',
        'usage_events',
        'edit_events',
        'prediction_pairs',
      ])
        table: await count(table),
    };

    Future<List<String>> board() async {
      final rows = await db
          .customSelect(
            'SELECT b.id, b.label, b.hidden, b.vocab_level, '
            'c.id AS cell, c.row, c.col, c.state '
            'FROM buttons b LEFT JOIN cells c ON c.id = b.cell_id '
            'ORDER BY b.id',
          )
          .get();
      return [
        for (final r in rows)
          '${r.read<String>('id')}|${r.read<String>('label')}|'
              '${r.read<int>('hidden')}|${r.read<int>('vocab_level')}|'
              '${r.read<String?>('cell')}|${r.read<int?>('row')}|'
              '${r.read<int?>('col')}|${r.read<String?>('state')}',
      ];
    }

    late String vocabularyId;

    setUp(() async {
      vocabularyId = await seedCoreBoardSet(db);
      final ts = nowMs();

      await db
          .into(db.usageEvents)
          .insert(
            UsageEventsCompanion.insert(
              deviceId: 'test',
              profileId: 'default',
              vocabularyId: vocabularyId,
              boardId: 'b1',
              cellId: 'c1',
              labelSnapshot: 'more',
              action: ButtonAction.speak,
              source: UsageSource.touch,
              sessionId: 's1',
              occurredAt: ts,
            ),
          );

      await db
          .into(db.editEvents)
          .insert(
            EditEventsCompanion.insert(
              id: newId(),
              vocabularyId: vocabularyId,
              kind: EditKind.remap,
              buttonId: const Value('b1'),
              changedAt: ts,
            ),
          );

      await db
          .into(db.predictionPairs)
          .insert(
            PredictionPairsCompanion.insert(
              profileId: 'default',
              previous: 'i',
              word: 'want',
              count: const Value(3),
            ),
          );
    });

    tearDown(() async => db.close());

    test('the board, the profiles and the usage log survive it', () async {
      await auth.setPin('1234');

      final before = await counts();
      final layout = await board();

      expect(before['buttons'], greaterThan(0));
      expect(before['cells'], greaterThan(0));
      expect(before['profiles'], greaterThan(0));
      expect(before['usage_events'], 1);
      expect(before['edit_events'], 1);

      await auth.reset();

      expect(await counts(), before);
      expect(
        await board(),
        layout,
        reason: 'a PIN reset moved or rewrote something on the board',
      );
      expect(
        await count('caregiver_auth'),
        0,
        reason:
            'the credential outlived the reset that was supposed to clear it',
      );
    });

    test('the reset is not written into the motor-plan audit log', () async {
      // `edit_events` answers "what changed on the board", is anchored to a
      // vocabulary, and its newest row is what the editor's undo reaches for.
      // A credential belongs to the device, not to the head of that queue.
      await auth.setPin('1234');
      await auth.reset();

      expect(await count('edit_events'), 1);
    });
  });

  group('the way in', () {
    late bool? result;

    tearDown(() async => db.close());

    Future<void> openGate(WidgetTester tester) async {
      result = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await PinGate.show(context, auth),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    final recovery = find.text('Forgotten it?');
    final confirm = find.text('Reset the caregiver PIN?');
    final confirmField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    /// Drains the reads the gate kicks off after a state change.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('an ordinary tap does not reach it', (tester) async {
      await auth.setPin('1234');
      await openGate(tester);

      expect(recovery, findsOneWidget);

      await tester.tap(recovery);
      await settle(tester);

      expect(
        confirm,
        findsNothing,
        reason: 'a tap opened the reset, and the user taps everything',
      );
      expect(await auth.isConfigured(), isTrue);
    });

    testWidgets('a short press does not reach it', (tester) async {
      await auth.setPin('1234');
      await openGate(tester);

      final hold = await tester.startGesture(tester.getCenter(recovery));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4999));

      expect(
        confirm,
        findsNothing,
        reason: 'the hold fired before the five seconds were up',
      );

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pumpAndSettle();

      expect(confirm, findsOneWidget);
      await hold.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a released hold starts again from nothing', (tester) async {
      await auth.setPin('1234');
      await openGate(tester);

      final at = tester.getCenter(recovery);

      var hold = await tester.startGesture(at);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await hold.up();
      await tester.pump();

      hold = await tester.startGesture(at);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(
        confirm,
        findsNothing,
        reason: 'two partial holds added up to a reset',
      );

      await hold.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the hold alone does not reset anything', (tester) async {
      await auth.setPin('1234');
      await openGate(tester);

      final hold = await tester.startGesture(tester.getCenter(recovery));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await hold.up();
      await tester.pumpAndSettle();

      expect(confirm, findsOneWidget);

      await tester.enterText(confirmField, 'yes please');
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Reset PIN'),
            )
            .onPressed,
        isNull,
        reason: 'anything typed was taken as confirmation',
      );

      await tester.tap(find.text('Keep the PIN'));
      await tester.pumpAndSettle();

      expect(await auth.isConfigured(), isTrue);
      expect(await auth.verify('1234'), isTrue);
    });

    testWidgets('holding, typing RESET, then setting a new PIN gets in', (
      tester,
    ) async {
      await auth.setPin('1234');
      await openGate(tester);

      final hold = await tester.startGesture(tester.getCenter(recovery));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await hold.up();
      await tester.pumpAndSettle();

      await tester.enterText(confirmField, 'reset');
      await tester.pump();
      await tester.tap(find.text('Reset PIN'));
      await settle(tester);

      expect(find.text('Set a new caregiver PIN'), findsOneWidget);
      expect(
        find.text('Cancel'),
        findsNothing,
        reason: 'the gate offered a way out of setting a new PIN',
      );
      expect(await auth.isConfigured(), isFalse);

      await tester.enterText(find.byType(TextField).at(0), '9876');
      await tester.enterText(find.byType(TextField).at(1), '9876');
      await tester.tap(find.text('Set PIN'));
      await settle(tester);

      expect(result, isTrue, reason: 'a new PIN did not open caregiver mode');
      expect(await auth.verify('9876'), isTrue);
      expect(await auth.verify('1234'), isFalse);
    });

    testWidgets('a locked-out caregiver can still reach it', (tester) async {
      // The case the whole path exists for: five wrong guesses is usually the
      // moment somebody realizes they do not remember it at all.
      await auth.setPin('1234');
      for (var i = 0; i < PinAuth.maxAttempts; i++) {
        await auth.verify('0000');
      }
      expect(await auth.lockoutRemaining(), isNotNull);

      await openGate(tester);

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Unlock'))
            .onPressed,
        isNull,
        reason: 'the lockout stopped applying to PIN attempts',
      );

      final hold = await tester.startGesture(tester.getCenter(recovery));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await hold.up();
      await tester.pumpAndSettle();

      expect(confirm, findsOneWidget);
    });

    testWidgets('there is nothing to recover before a PIN exists', (
      tester,
    ) async {
      await openGate(tester);

      expect(find.text('Set a caregiver PIN'), findsOneWidget);
      expect(recovery, findsNothing);
    });

    testWidgets('the next unlock says a reset happened', (tester) async {
      await auth.setPin('1234');
      await auth.reset();
      await auth.setPin('9876');

      await openGate(tester);

      expect(
        find.textContaining('This PIN was reset on'),
        findsOneWidget,
        reason: 'the parent who did not reset the PIN is never told',
      );
    });
  });
}
