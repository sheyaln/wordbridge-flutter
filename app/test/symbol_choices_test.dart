import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/caregiver/symbol_packs_screen.dart';
import 'package:wordbridge/features/symbols/arasaac_pack.dart';
import 'package:wordbridge/features/symbols/bundled_pack.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';
import 'package:wordbridge/features/symbols/symbol_choices.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';

/// Which picture sets this tablet may use, and whether that answer survives.
///
/// The rule underneath all of it: a pack whose license forbids commercial use
/// is inert until somebody turns it on. Fetching one on a person's instruction
/// is their choice to make; shipping it enabled would make it ours.
void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  SymbolRegistry registryWith({Map<String, bool> choices = const {}}) =>
      SymbolRegistry(
        packs: [...bundledSymbolPacks(), GlobalSymbolsPack(), ArasaacPack()],
        choices: choices,
      );

  group('what is on by default', () {
    test('a noncommercial pack is off, without anybody deciding', () {
      // From its license alone. Nothing is stored, nothing was asked, and it
      // still contributes nothing to a search.
      final registry = registryWith();

      expect(registry.isEnabled('arasaac'), isFalse);
      expect(
        registry.enabledPacks.map((p) => p.id),
        isNot(contains('arasaac')),
      );
    });

    test('and a pack that permits commercial use is on', () {
      expect(registryWith().isEnabled('globalsymbols'), isTrue);
    });
  });

  group('remembering the answer', () {
    test('nothing is stored until somebody decides', () async {
      expect(await loadSymbolChoices(db), isEmpty);
    });

    test('and a decision survives a relaunch', () async {
      final registry = registryWith();
      registry.setEnabled('arasaac', true);
      await saveSymbolChoices(db, registry.choices);

      final next = registryWith(choices: await loadSymbolChoices(db));
      expect(next.isEnabled('arasaac'), isTrue);
      expect(next.enabledPacks.map((p) => p.id), contains('arasaac'));
    });

    test('turning it back off is also a decision, and is kept', () async {
      final registry = registryWith();
      registry.setEnabled('arasaac', true);
      await saveSymbolChoices(db, registry.choices);

      registry.setEnabled('arasaac', false);
      await saveSymbolChoices(db, registry.choices);

      final next = registryWith(choices: await loadSymbolChoices(db));
      expect(next.isEnabled('arasaac'), isFalse);
    });

    test(
      'a stored map that will not parse falls back to the licenses',
      () async {
        // Guessing at it could turn a noncommercial pack on, which is the one
        // outcome this must never reach by accident.
        await db
            .into(db.appState)
            .insertOnConflictUpdate(
              AppStateCompanion.insert(
                key: symbolChoicesKey,
                value: 'not json',
              ),
            );

        expect(await loadSymbolChoices(db), isEmpty);
        expect(
          registryWith(choices: await loadSymbolChoices(db))
              .isEnabled('arasaac'),
          isFalse,
        );
      },
    );

    test(
      'and a pack nobody has decided about is absent from what is stored',
      () async {
        // So a noncommercial pack added in a later release arrives off, rather
        // than inheriting a saved map that predates it.
        final registry = registryWith();
        registry.setEnabled('arasaac', true);
        await saveSymbolChoices(db, registry.choices);

        expect(await loadSymbolChoices(db), {'arasaac': true});
      },
    );
  });

  group('what the switch tells a caregiver', () {
    test('a noncommercial pack says so', () {
      // The license term itself, which is what a caregiver deciding needs to
      // see. It used to spell out the consequence as well — "leave this off if
      // the app will be sold" — and that sentence went when the settings text
      // was cut back to plain statements of what each option does. What still
      // guards the licensing is the default: these packs arrive off, and CI
      // fails a build that bundles one.
      expect(subtitleFor(ArasaacPack()), contains('noncommercial'));
    });

    test('a pack that permits commercial use does not say that', () {
      expect(
        subtitleFor(GlobalSymbolsPack()),
        isNot(contains('noncommercial')),
      );
    });

    test('and a bundled pack says it works offline', () {
      expect(subtitleFor(bundledSymbolPacks().first), contains('offline'));
    });

    test('no subtitle carries a dash or a hyphen', () {
      // §4.50. "non-commercial" is the spelling that would slip through here.
      for (final pack in [
        ...bundledSymbolPacks(),
        GlobalSymbolsPack(),
        ArasaacPack(),
      ]) {
        expect(
          RegExp(r'[-‐-―]').hasMatch(subtitleFor(pack)),
          isFalse,
          reason: '${pack.id}: ${subtitleFor(pack)}',
        );
      }
    });
  });
}
