import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/utterance/keypad.dart';
import 'package:wordbridge/features/utterance/morphology.dart';
import 'package:wordbridge/features/utterance/utterance.dart';

/// Typing a number rather than counting to it (§4.77).
///
/// The counting row stops at ten and a person's numbers do not: an age, a
/// date, a price, a bus, a door, a phone number. The pad is the other way to
/// one, and it costs no location on any board — it is opened, used and closed,
/// and nothing on it has to be learned as a position.
void main() {
  /// What the pad handed back, filled in when it closes.
  late List<String?> handedBack;

  Future<void> pumpPad(WidgetTester tester, {List<String>? spoken}) async {
    handedBack = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                handedBack.add(
                  await Keypad.show(
                    context,
                    onDigit: spoken == null
                        ? null
                        : (digit) async => spoken.add(digit),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String digit) async {
    await tester.tap(find.widgetWithText(InkWell, digit));
    await tester.pump();
  }

  group('the pad', () {
    testWidgets('lays the digits out the way a calculator does', (
      tester,
    ) async {
      await pumpPad(tester);

      // Nine at the top and zero at the bottom, which is a keyboard's own pad
      // and every calculator anybody has held. A phone is the other way up,
      // and picking one and keeping it is the whole of the argument.
      double y(String digit) =>
          tester.getCenter(find.widgetWithText(InkWell, digit)).dy;

      expect(y('7'), lessThan(y('4')));
      expect(y('4'), lessThan(y('1')));
      expect(y('1'), lessThan(y('0')));

      double x(String digit) =>
          tester.getCenter(find.widgetWithText(InkWell, digit)).dx;

      expect(x('7'), lessThan(x('8')));
      expect(x('8'), lessThan(x('9')));
      // Zero under the one, on the left, where the row it opens sits.
      expect(x('0'), x('1'));
    });

    testWidgets('shows the digits and the number they read as', (tester) async {
      await pumpPad(tester);
      await press(tester, '1');
      await press(tester, '5');

      expect(find.text('15'), findsOneWidget);
      expect(
        find.text('fifteen'),
        findsOneWidget,
        reason: 'the number is confirmed in words before it is said out loud',
      );
    });

    testWidgets('says each digit as it is pressed', (tester) async {
      // Every key in this app speaks when it is tapped. A silent one reads as
      // a press that did not register, so the person presses it again and the
      // number gains a digit nobody meant.
      final spoken = <String>[];
      await pumpPad(tester, spoken: spoken);

      await press(tester, '4');
      await press(tester, '0');
      await press(tester, '7');

      expect(spoken, ['4', '0', '7']);
    });

    testWidgets('deletes a digit rather than the whole number', (tester) async {
      await pumpPad(tester);
      await press(tester, '1');
      await press(tester, '2');
      await press(tester, '3');

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('stops rather than taking a number nobody could say', (
      tester,
    ) async {
      await pumpPad(tester);
      for (var i = 0; i < Keypad.maxDigits + 4; i++) {
        await press(tester, '9');
      }

      expect(find.text('9' * Keypad.maxDigits), findsOneWidget);
    });

    testWidgets('hands back the digits, not the words', (tester) async {
      // The digits are what the bar holds, because that is what a speech
      // engine reads as a number.
      await pumpPad(tester);

      await press(tester, '2');
      await press(tester, '0');
      await press(tester, '2');
      await press(tester, '6');
      await tester.tap(find.text('Add to the sentence'));
      await tester.pumpAndSettle();

      expect(handedBack, ['2026']);
      expect(find.byType(Keypad), findsNothing);
    });

    testWidgets('an empty pad cannot be added to the sentence', (tester) async {
      await pumpPad(tester);

      final add = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add to the sentence'),
      );
      expect(add.onPressed, isNull);
    });

    testWidgets('closing it adds nothing', (tester) async {
      // Half a number typed and then abandoned is not a number, and putting
      // it in the sentence would be the board saying something nobody chose.
      await pumpPad(tester);
      await press(tester, '9');

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(handedBack, [null]);
      expect(find.byType(Keypad), findsNothing);
    });
  });

  group('what a typed number does in the sentence', () {
    test('goes in as digits, so the engine says the number', () {
      final bar = UtteranceBar();
      bar.add('15', pos: PartOfSpeech.determiner, inflected: true);
      bar.add('minutes');

      expect(bar.text, '15 minutes');
    });

    test('and no ending is applied to it', () {
      // The ending keys rewrite the last word, and "15s" is not a word. A
      // joined number is marked the same way for the same reason.
      final bar = UtteranceBar();
      bar.add('15', pos: PartOfSpeech.determiner, inflected: true);

      expect(bar.last!.inflected, isTrue);
      expect(
        grammarHelperApplies(
          kind: MorphemeKind.pluralS,
          tense: '',
          previousText: bar.last!.text,
          previousPos: bar.last!.pos,
          previousInflected: bar.last!.inflected,
          atStart: false,
          copulaCycles: false,
        ),
        isFalse,
      );
    });

    test('an ordinary word still takes one', () {
      final bar = UtteranceBar();
      bar.add('minute', pos: PartOfSpeech.noun);

      expect(bar.last!.inflected, isFalse);
    });
  });

  group('the key that opens it', () {
    late WordbridgeDatabase db;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      await seedCoreBoardSet(db);
    });

    tearDown(() async => db.close());

    Future<Map<String, ({int row, int col, ButtonAction action})>>
    numbersBoard() async {
      final board = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('numbers'))).getSingle();

      final rows = await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(board.id))).get();

      return {
        for (final r in rows)
          r.readTable(db.buttons).label: (
            row: r.readTable(db.cells).row,
            col: r.readTable(db.cells).col,
            action: r.readTable(db.buttons).action,
          ),
      };
    }

    test('is on the numbers board, at the end of the counting row', () async {
      final board = await numbersBoard();

      expect(board['123'], isNotNull, reason: 'no way to open the pad');
      expect(board['123']!.action, ButtonAction.keypad);
      expect(
        board['123']!.row,
        board['10']!.row,
        reason: 'the pad key left the row the numbers are on',
      );
      expect(
        board['123']!.col,
        board['10']!.col + 1,
        reason:
            'appended, so every numeral keeps the location it was learned '
            'in',
      );
    });

    test('draws at level 2, with the numbers a small board shows', () async {
      // The board drawing one to five is the one that most needs another way
      // to a sixth, and the pad is the way that costs no location.
      final board = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('numbers'))).getSingle();

      final rows = await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(board.id))).get();

      final pad = rows
          .map((r) => r.readTable(db.buttons))
          .firstWhere((b) => b.label == '123');

      expect(pad.vocabLevel, 2);
      expect(pad.hidden, isFalse);
    });

    test('speaks nothing on its own', () async {
      // It is not a word. Anything that walks the board looking for something
      // to say has to pass over it rather than say "123".
      final board = await (db.select(
        db.boards,
      )..where((b) => b.name.equals('numbers'))).getSingle();

      final rows = await (db.select(db.buttons).join([
        innerJoin(db.cells, db.cells.id.equalsExp(db.buttons.cellId)),
      ])..where(db.cells.boardId.equals(board.id))).get();

      final pad = rows
          .map((r) => r.readTable(db.buttons))
          .firstWhere((b) => b.label == '123');

      expect(pad.message, isEmpty);
      expect(pad.action, isNot(ButtonAction.speak));
    });

    test('and the numerals it sits beside are unchanged', () async {
      final board = await numbersBoard();

      for (final digit in ['1', '2', '3', '4', '5', '10']) {
        expect(
          board[digit]!.action,
          ButtonAction.speak,
          reason: '$digit stopped being a word',
        );
      }
      expect(board['1']!.col, 0);
      expect(board['1']!.row, board['10']!.row);
    });
  });
}
