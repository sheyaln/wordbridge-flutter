import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/caregiver/picture_browser.dart';
import 'package:wordbridge/features/symbols/symbol_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/symbol_resolver.dart';

/// A pack that answers instantly with whatever it was given.
class _Pack implements SymbolPack {
  _Pack(
    this.id,
    this.name, {
    this.words = const {},
    this.allowsCommercialUse = true,
  });

  @override
  final String id;
  @override
  final String name;

  /// word to the labels this pack has for it.
  final Map<String, List<String>> words;

  final bool allowsCommercialUse;

  @override
  List<SymbolSet> get sets => [
    (
      slug: id,
      name: name,
      attribution: attribution,
      license: license,
      allowsCommercialUse: allowsCommercialUse,
    ),
  ];

  /// Every query this pack was actually asked, which is how "the filter did
  /// not reach it" is checked rather than assumed.
  final asked = <String>[];

  @override
  bool get isBundled => true;
  @override
  String get license => 'CC-BY-SA-4.0';
  @override
  String get attribution => 'Test set';

  @override
  Future<List<SymbolRef>> search(
    String query, {
    String locale = 'en',
    int limit = 24,
    Set<String>? sets,
  }) async {
    asked.add(query);
    return [
      for (final label in words[query.toLowerCase()] ?? const <String>[])
        (packId: id, externalId: label, label: label),
    ];
  }

  @override
  Future<String?> resolve(SymbolRef ref, {Set<String>? sets}) async => null;
}

/// A pack assembled from several upstream sets, like the bundled one.
class _Assembled extends _Pack implements AssembledSymbolPack {
  _Assembled(super.id, super.name, {super.words, required this.sources});

  /// label to the upstream set that drew it.
  final Map<String, String> sources;

  @override
  String get attribution => 'Assembled from Mulberry, OpenMoji and Tawasol';

  @override
  String? sourceOf(SymbolRef ref) => sources[ref.label];

  @override
  String? creditFor(SymbolRef ref) {
    final set = sourceOf(ref);
    return set == null ? null : '$set, who drew this one';
  }
}

/// Looking at the picture sets without editing anything (§4.65).
void main() {
  late _Pack mulberry;
  late _Pack openmoji;

  SymbolRegistry registryOf(List<SymbolPack> packs, {Map<String, bool>? on}) =>
      SymbolRegistry(packs: packs, choices: on ?? const {});

  setUp(() {
    mulberry = _Pack(
      'mulberry',
      'Mulberry',
      words: {
        'cat': ['cat drawing'],
      },
    );
    openmoji = _Pack(
      'openmoji',
      'OpenMoji',
      words: {
        'cat': ['cat face'],
      },
    );
  });

  group('searching one set at a time', () {
    test('every set, when none is named', () async {
      final registry = registryOf([mulberry, openmoji]);
      final hits = await registry.search('cat');

      expect(hits, hasLength(2));
      expect(mulberry.asked, ['cat']);
      expect(openmoji.asked, ['cat']);
    });

    test('only the one named', () async {
      final registry = registryOf([mulberry, openmoji]);
      final hits = await registry.search('cat', packId: 'openmoji');

      expect(hits.single.packId, 'openmoji');
      expect(
        mulberry.asked,
        isEmpty,
        reason: 'a filter that still queries the others is not a filter',
      );
    });

    test('a set that is off is not searched, even when named', () async {
      // The rule this registry exists for. Naming a pack explicitly is the
      // obvious way around "off means inert", and a noncommercial pack that
      // answered a filtered search would be the opt-in undone by a chip.
      final arasaac = _Pack(
        'arasaac',
        'ARASAAC',
        words: {
          'cat': ['gato'],
        },
        allowsCommercialUse: false,
      );
      final registry = registryOf([mulberry, arasaac]);
      expect(registry.isEnabled('arasaac'), isFalse, reason: 'the premise');

      final hits = await registry.search('cat', packId: 'arasaac');

      expect(hits, isEmpty);
      expect(arasaac.asked, isEmpty, reason: 'it must not even be asked');
    });

    test('a set nobody has heard of returns nothing', () async {
      final registry = registryOf([mulberry]);
      expect(await registry.search('cat', packId: 'nonesuch'), isEmpty);
      expect(mulberry.asked, isEmpty);
    });

    test('an empty query is still nothing, filtered or not', () async {
      final registry = registryOf([mulberry]);
      expect(await registry.search('   ', packId: 'mulberry'), isEmpty);
      expect(mulberry.asked, isEmpty);
    });
  });

  group('the browser', () {
    Future<void> pump(WidgetTester tester, SymbolRegistry registry) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PictureBrowser(
            registry: registry,
            resolver: SymbolResolver(registry: registry),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> searchFor(WidgetTester tester, String word) async {
      await tester.enterText(find.byType(TextField), word);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('says what to do before anything is searched', (tester) async {
      await pump(tester, registryOf([mulberry, openmoji]));

      expect(find.textContaining('Search for a word'), findsOneWidget);
    });

    testWidgets('shows what every set has for a word', (tester) async {
      await pump(tester, registryOf([mulberry, openmoji]));
      await searchFor(tester, 'cat');

      expect(find.text('cat drawing'), findsOneWidget);
      expect(find.text('cat face'), findsOneWidget);
    });

    testWidgets('narrows to one set when a chip is chosen', (tester) async {
      await pump(tester, registryOf([mulberry, openmoji]));
      await searchFor(tester, 'cat');

      await tester.tap(find.widgetWithText(ChoiceChip, 'OpenMoji'));
      await tester.pumpAndSettle();

      expect(find.text('cat face'), findsOneWidget);
      expect(find.text('cat drawing'), findsNothing);
    });

    testWidgets('and back to all of them', (tester) async {
      await pump(tester, registryOf([mulberry, openmoji]));
      await searchFor(tester, 'cat');
      await tester.tap(find.widgetWithText(ChoiceChip, 'OpenMoji'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'All sets'));
      await tester.pumpAndSettle();

      expect(find.text('cat drawing'), findsOneWidget);
      expect(find.text('cat face'), findsOneWidget);
    });

    testWidgets('offers no chips where there is one set to choose from', (
      tester,
    ) async {
      // A filter over a single option is a control that cannot do anything.
      await pump(tester, registryOf([mulberry]));

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('a set that is off is not offered as a chip', (tester) async {
      final arasaac = _Pack('arasaac', 'ARASAAC', allowsCommercialUse: false);
      await pump(tester, registryOf([mulberry, openmoji, arasaac]));

      expect(find.widgetWithText(ChoiceChip, 'ARASAAC'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Mulberry'), findsOneWidget);
    });

    testWidgets('says so when a set has nothing for the word', (tester) async {
      await pump(tester, registryOf([mulberry, openmoji]));
      await searchFor(tester, 'aardvark');

      expect(find.textContaining('No pictures for that word'), findsOneWidget);
    });

    testWidgets('a result says what it is rather than going anywhere', (
      tester,
    ) async {
      // The whole difference from the button picker: there is no button in
      // scope, so a tap cannot change one. What somebody needs instead is the
      // reference, which is how a picture gets asked for by name.
      await pump(tester, registryOf([mulberry, openmoji]));
      await searchFor(tester, 'cat');

      await tester.tap(find.text('cat drawing'));
      await tester.pumpAndSettle();

      expect(find.text('mulberry.cat drawing'), findsOneWidget);
      expect(find.text('CC-BY-SA-4.0'), findsOneWidget);
    });
  });

  group('who a picture is credited to', () {
    testWidgets('is the set that drew it, not every set in the pack', (
      tester,
    ) async {
      // §4.72. The pack's own attribution names all four upstream sets. Beside
      // one drawing that is not a credit, it is a list — and it credits three
      // people who had nothing to do with the picture on screen.
      final assembled = _Assembled(
        'core',
        'Core symbols',
        words: {
          'cat': ['cat drawing'],
        },
        sources: {'cat drawing': 'Mulberry'},
      );
      final registry = SymbolRegistry(packs: [assembled]);

      await tester.pumpWidget(
        MaterialApp(
          home: PictureBrowser(
            registry: registry,
            resolver: SymbolResolver(registry: registry),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cat');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.text('cat drawing'));
      await tester.pumpAndSettle();

      expect(find.text('Mulberry, who drew this one'), findsOneWidget);
      expect(
        find.textContaining('Assembled from'),
        findsNothing,
        reason: 'the whole pack was credited for one picture',
      );
    });
  });
}
