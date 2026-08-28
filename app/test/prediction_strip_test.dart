import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/prediction/prediction_strip.dart';

/// The strip is the one part of the screen that is *meant* to change under the
/// user, so everything here is about making that safe rather than preventing
/// it: a place that holds still, and a moment before it can be pressed.
void main() {
  Future<void> show(
    WidgetTester tester, {
    required List<String> words,
    required void Function(String) onSelect,
    Duration settle = const Duration(milliseconds: 500),
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PredictionStrip(
          words: words,
          onSelect: onSelect,
          settleDelay: settle,
        ),
      ),
    ),
  );

  Rect slotRect(WidgetTester tester, String word) =>
      tester.getRect(find.text(word));

  testWidgets('a word sits in the same place whatever is beside it', (
    tester,
  ) async {
    // The third suggestion must not move because the first two got longer.
    await show(
      tester,
      words: ['I', 'go', 'more'],
      onSelect: (_) {},
      settle: Duration.zero,
    );
    final short = slotRect(tester, 'more');

    await show(
      tester,
      words: ['different', 'something', 'more'],
      onSelect: (_) {},
      settle: Duration.zero,
    );
    final long = slotRect(tester, 'more');

    expect(long.center.dx, closeTo(short.center.dx, 0.01));
  });

  testWidgets('an empty place is not a button and speaks nothing', (
    tester,
  ) async {
    final chosen = <String>[];
    await show(
      tester,
      words: ['only'],
      onSelect: chosen.add,
      settle: Duration.zero,
    );

    // Every slot after the first is empty. Pressing one must do nothing at
    // all, for the same reason a masked cell does nothing: there is no word
    // there to have meant.
    final strip = tester.getRect(find.byType(PredictionStrip));
    await tester.tapAt(Offset(strip.right - 20, strip.center.dy));
    await tester.pump();

    expect(chosen, isEmpty);
  });

  testWidgets('taps are ignored while the suggestions are still changing', (
    tester,
  ) async {
    final chosen = <String>[];
    await show(
      tester,
      words: ['want'],
      onSelect: chosen.add,
      settle: const Duration(milliseconds: 500),
    );

    // A different word arrives in the place the finger was already heading
    // for.
    await show(
      tester,
      words: ['stop'],
      onSelect: chosen.add,
      settle: const Duration(milliseconds: 500),
    );

    // The tap is expected to land on nothing, which is the point of it.
    await tester.tap(find.text('stop'), warnIfMissed: false);
    await tester.pump();
    expect(chosen, isEmpty, reason: 'the strip had only just changed');

    await tester.pump(const Duration(milliseconds: 501));
    await tester.tap(find.text('stop'));
    await tester.pump();
    expect(chosen, ['stop']);
  });

  testWidgets('a zero delay switches the wait off entirely', (tester) async {
    final chosen = <String>[];
    await show(
      tester,
      words: ['want'],
      onSelect: chosen.add,
      settle: Duration.zero,
    );
    await show(
      tester,
      words: ['stop'],
      onSelect: chosen.add,
      settle: Duration.zero,
    );

    await tester.tap(find.text('stop'));
    await tester.pump();
    expect(chosen, ['stop']);
  });

  testWidgets('the same suggestions arriving again do not restart the wait', (
    tester,
  ) async {
    // The screen rebuilds for all sorts of reasons. Only the words changing
    // should cost the user the delay.
    final chosen = <String>[];
    await show(
      tester,
      words: ['want'],
      onSelect: chosen.add,
      settle: const Duration(milliseconds: 500),
    );
    await tester.pump(const Duration(milliseconds: 501));

    await show(
      tester,
      words: ['want'],
      onSelect: chosen.add,
      settle: const Duration(milliseconds: 500),
    );

    await tester.tap(find.text('want'));
    await tester.pump();
    expect(chosen, ['want']);
  });
}
