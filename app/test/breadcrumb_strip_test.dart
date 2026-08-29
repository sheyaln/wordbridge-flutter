import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/talk/breadcrumb_strip.dart';

/// The strip is a display of a route, so everything here is about it being
/// readable and inert: the same height whatever it says, the destination
/// always in view, and nothing on it that answers a finger.
void main() {
  Crumb crumb(String label) => Crumb(label: label, boardId: label);

  Future<void> show(
    WidgetTester tester, {
    List<Crumb> route = const [],
    String? destination,
    double width = 800,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: width,
            child: BreadcrumbStrip(route: route, destination: destination),
          ),
        ),
      ),
    ),
  );

  String trail(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(BreadcrumbStrip),
        matching: find.byType(Text),
      ),
    );
    return text.textSpan!.toPlainText();
  }

  testWidgets('one step reads as a route, not as a stray word', (tester) async {
    // The common case under auto-return: a word tapped on the home board.
    await show(tester, destination: 'want');
    expect(trail(tester), 'home → want');
  });

  testWidgets('nothing walked yet still reads', (tester) async {
    await show(tester);
    expect(trail(tester), 'home');
  });

  testWidgets('the height does not move between lengths', (tester) async {
    await show(tester, destination: 'want');
    final short = tester.getSize(find.byType(BreadcrumbStrip)).height;

    await show(
      tester,
      route: [crumb('body'), crumb('more words'), crumb('more words')],
      destination: 'buttocks',
    );
    final long = tester.getSize(find.byType(BreadcrumbStrip)).height;

    expect(long, short);
    expect(short, BreadcrumbStrip.height);
  });

  testWidgets('a deep route reads in the order it was walked', (tester) async {
    await show(
      tester,
      route: [crumb('body'), crumb('more words'), crumb('more words')],
      destination: 'buttocks',
    );
    expect(trail(tester), 'home → body → more words → more words → buttocks');
  });

  testWidgets('a trail too wide loses its head, never its destination', (
    tester,
  ) async {
    await show(
      tester,
      route: [
        crumb('more categories'),
        crumb('feelings'),
        crumb('more words'),
        crumb('more words'),
      ],
      destination: 'embarrassed',
      width: 260,
    );

    final text = trail(tester);
    expect(
      text,
      endsWith('embarrassed'),
      reason: 'the word just spoken is the one part that must stay in view',
    );
    expect(
      text,
      startsWith('…'),
      reason: 'a trail cut short has to say that it was cut short',
    );
    expect(
      text,
      isNot(contains('home')),
      reason: 'the origin is the least informative crumb and goes first',
    );
    expect(
      tester.getSize(find.byType(BreadcrumbStrip)).height,
      BreadcrumbStrip.height,
    );
  });

  testWidgets('it keeps every step it has room for', (tester) async {
    await show(
      tester,
      route: [crumb('body'), crumb('more words')],
      destination: 'buttocks',
      width: 800,
    );
    expect(trail(tester), 'home → body → more words → buttocks');
    expect(trail(tester), isNot(startsWith('…')));
  });

  testWidgets('a word wider than the screen is not dropped', (tester) async {
    await show(tester, destination: 'antidisestablishmentarianism', width: 60);

    expect(
      trail(tester),
      contains('antidisestablishmentarianism'),
      reason: 'the destination is kept even when it cannot be drawn whole',
    );
    expect(
      tester.getSize(find.byType(BreadcrumbStrip)).height,
      BreadcrumbStrip.height,
    );
  });

  testWidgets('no crumb answers a finger', (tester) async {
    await show(
      tester,
      route: [crumb('body'), crumb('more words')],
      destination: 'buttocks',
    );

    // A crumb that navigated would be a second route to a board, and a word's
    // motor path has to be one sequence.
    for (final type in [InkWell, GestureDetector, TextButton, InkResponse]) {
      expect(
        find.descendant(
          of: find.byType(BreadcrumbStrip),
          matching: find.byWidgetPredicate((w) => w.runtimeType == type),
        ),
        findsNothing,
        reason: '$type in the strip makes the trail a control',
      );
    }
  });
}
