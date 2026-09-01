import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/caregiver/about_screen.dart';
import 'package:wordbridge/features/reporting/report.dart';
import 'package:wordbridge/features/symbols/symbol_credits.dart';

/// What a caregiver, a teacher or a therapist is owed before they decide what
/// this app is allowed to do.
///
/// The strings are written out here rather than read from the screen's own
/// constants. A disclaimer stated as `AboutScreen.disclaimer == ...` says only
/// that the constant equals itself, and would survive being reworded to
/// nothing.
void main() {
  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pump();
  }

  testWidgets('says the app was developed with the assistance of generative '
      'AI', (tester) async {
    await pumpAbout(tester);

    expect(
      find.text('This app was developed with the assistance of generative AI.'),
      findsOneWidget,
    );
  });

  testWidgets('and says where the words came from, which is not that', (
    tester,
  ) async {
    await pumpAbout(tester);

    // The claim the disclaimer raises and has to answer. Both halves, because
    // `docs/starter-vocabulary.md` makes both: a published core list, and most
    // of the rest recorded as judgment rather than as evidence.
    expect(find.textContaining('Universal Core 36'), findsOneWidget);
    expect(find.textContaining('editorial judgment'), findsOneWidget);
  });

  testWidgets('names who wrote it and what it may be used under', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(find.textContaining(AboutScreen.developer), findsOneWidget);
    expect(find.textContaining('MIT license'), findsOneWidget);
  });

  testWidgets('reads its version from the constants a report carries', (
    tester,
  ) async {
    // Those are pinned to `pubspec.yaml` by `report_payload_test.dart`, so a
    // version on this screen cannot drift from the build it is describing.
    await pumpAbout(tester);

    expect(
      find.text('Version $appVersion, build $appBuild'),
      findsOneWidget,
      reason: 'the version is hardcoded rather than read from the build',
    );
  });

  testWidgets('the symbol credits are still one tap from it', (tester) async {
    await pumpAbout(tester);

    await tester.tap(find.text('Symbol credits'));
    // Pumped rather than settled: the credits screen holds a spinner until its
    // manifests are read, and a spinner is an animation that never settles.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.byType(SymbolCredits), findsOneWidget);
  });

  testWidgets('carries no dash or hyphen, between words or inside one', (
    tester,
  ) async {
    // §4.50. This screen is read by somebody deciding whether to trust the
    // app, which is the worst place for the house style to lapse.
    await pumpAbout(tester);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data;
      if (data == null) continue;
      expect(
        data.contains('-') || data.contains('—') || data.contains('–'),
        isFalse,
        reason: '"$data" carries a dash or a hyphen',
      );
    }
  });
}
