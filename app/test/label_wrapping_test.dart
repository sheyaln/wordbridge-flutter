import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/grid/symbol_view.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';

/// A word must never break inside itself.
///
/// Flutter breaks a line between words where it can and inside one where it
/// cannot, so a label laid out in a box narrower than its longest word comes
/// back as "comput" over "er". Two words on two lines is a label; one word on
/// two lines is a defect — and for a reader still learning the word it is
/// worse than a defect, because the thing on the button is not the word.
///
/// **Asserted through intrinsic widths, which is exactly what they mean.** A
/// paragraph's minimum intrinsic width *is* the width of its widest word: lay
/// it out at least that wide and every word fits on a line, lay it out
/// narrower and one of them is broken. Nothing else here needs measuring.
///
/// A phrase still wraps. That is the whole reason the label is laid out in a
/// bounded box at all: given as much width as it likes, "I use a computer
/// voice to talk" is one line shrunk until nobody can read it.
void main() {
  /// A resolver that finds nothing, so every button falls to its label — which
  /// is the case under test.
  ///
  /// Deliberately not closed: closing inside a widget test waits on work the
  /// fake clock never runs.
  SymbolResolver labelOnly() =>
      SymbolResolver(registry: SymbolRegistry(packs: const []));

  Future<RenderParagraph> pumpLabel(
    WidgetTester tester,
    String label, {
    required double cell,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: cell,
              child: SymbolView(resolver: labelOnly(), label: label),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return tester.renderObject<RenderParagraph>(find.text(label));
  }

  /// The width of the widest single word, which is the floor the layout has to
  /// clear for every word to stay whole.
  double widestWord(RenderParagraph p) =>
      p.getMinIntrinsicWidth(double.infinity);

  /// The width the whole label would take on one line.
  double oneLine(RenderParagraph p) => p.getMaxIntrinsicWidth(double.infinity);

  testWidgets('a single long word is never broken in a narrow cell', (
    tester,
  ) async {
    // 60pt is the phone tier — the smallest cell the app offers, and the one
    // this went wrong on.
    final text = await pumpLabel(tester, 'neurodivergent', cell: 60);

    expect(
      text.size.width,
      greaterThanOrEqualTo(widestWord(text)),
      reason: '"neurodivergent" was broken across lines inside the word',
    );
  });

  testWidgets('the longest word in a phrase is what sets the width', (
    tester,
  ) async {
    // One long word among short ones is the case that fails if the floor is
    // taken from the whole string rather than from each word in it.
    final text = await pumpLabel(tester, 'take the medication', cell: 60);

    expect(
      text.size.width,
      greaterThanOrEqualTo(widestWord(text)),
      reason: '"medication" was broken to fit a box sized for "take"',
    );
  });

  testWidgets('a phrase still wraps rather than shrinking to one line', (
    tester,
  ) async {
    final text = await pumpLabel(
      tester,
      'I use a computer voice to talk',
      cell: 72,
    );

    expect(
      text.size.width,
      lessThan(oneLine(text)),
      reason: 'the phrase was set on one line and scaled until unreadable',
    );
    expect(text.size.width, greaterThanOrEqualTo(widestWord(text)));
  });

  testWidgets('a short word is unchanged', (tester) async {
    // The common case, and the one that must not move: it was already narrower
    // than the box and it lays out exactly as it always did.
    final text = await pumpLabel(tester, 'more', cell: 96);

    expect(text.size.width, closeTo(oneLine(text), 0.5));
  });
}
