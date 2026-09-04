import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/caregiver/symbol_packs_screen.dart';
import 'package:wordbridge/features/symbols/arasaac_pack.dart';
import 'package:wordbridge/features/symbols/bundled_pack.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';
import 'package:wordbridge/features/symbols/symbol_choices.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';
import 'package:wordbridge/features/symbols/system_emoji_pack.dart';

/// Which picture sets this tablet may use, and whether that answer survives.
///
/// The rule underneath all of it: a set whose license forbids commercial use
/// is inert until somebody turns it on. Fetching one on a person's instruction
/// is their choice to make; shipping it enabled would make it ours.
void main() {
  late WordbridgeDatabase db;

  setUp(() => db = WordbridgeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  SymbolRegistry registryWith({Map<String, bool> choices = const {}}) =>
      SymbolRegistry(
        packs: [
          ...bundledSymbolPacks(),
          SystemEmojiPack(),
          GlobalSymbolsPack(),
          ArasaacPack(),
          GlobalSymbolsPack.nonCommercial(),
        ],
        choices: choices,
      );

  group('what is on by default', () {
    test('a noncommercial set is off, without anybody deciding', () {
      // From its license alone. Nothing is stored, nothing was asked, and it
      // still contributes nothing to a search.
      final registry = registryWith();

      expect(registry.isSetEnabled('arasaac'), isFalse);
      expect(registry.isSetEnabled('aac-image-library'), isFalse);
      expect(
        registry.enabledPacks.map((p) => p.id),
        isNot(contains('arasaac')),
        reason: 'a pack whose only set is off has nothing left to be asked',
      );
    });

    test('and every set that permits commercial use is on', () {
      final registry = registryWith();

      for (final set in registry.sets) {
        expect(
          registry.isSetEnabled(set.slug),
          set.allowsCommercialUse,
          reason: set.slug,
        );
      }
    });

    test('the six CC BY-SA sets are all of them, by name', () {
      // Named rather than counted, because the failure this guards is a set
      // silently dropping off the list a caregiver chooses from.
      // Order follows the packs a set is reached through, and a set reached
      // through two of them takes the earlier position. Which sets the
      // shipped manifest uses is a decision that moves, so this names the
      // members rather than pinning the order they arrive in.
      expect(registryWith().sets.map((s) => s.slug).toSet(), {
        'stellar-symbols',
        'openmoji',
        'device-emoji',
        'mulberry',
        'corona-symbols',
        'additional-mulberry-symbols',
        'tawasol',
        'arasaac',
        'aac-image-library',
      });
    });

    test('a set two packs both serve is listed once', () {
      // Stellar ships inside `core` and is also fetched. Listed twice it would
      // be two switches with one name, and turning one off would leave the
      // other drawing.
      final registry = registryWith();
      final slugs = registry.sets.map((s) => s.slug).toList();

      expect(slugs.toSet(), hasLength(slugs.length));
      expect(registry.packsOffering('stellar-symbols').map((p) => p.id), [
        'core',
        'globalsymbols',
      ]);
    });
  });

  group('remembering the answer', () {
    test('nothing is stored until somebody decides', () async {
      expect(await loadSymbolChoices(db), isEmpty);
    });

    test('and a decision survives a relaunch', () async {
      final registry = registryWith();
      registry.setSetEnabled('arasaac', true);
      await saveSymbolChoices(db, registry.choices);

      final next = registryWith(choices: await loadSymbolChoices(db));
      expect(next.isSetEnabled('arasaac'), isTrue);
      expect(next.enabledPacks.map((p) => p.id), contains('arasaac'));
    });

    test('turning it back off is also a decision, and is kept', () async {
      final registry = registryWith();
      registry.setSetEnabled('arasaac', true);
      await saveSymbolChoices(db, registry.choices);

      registry.setSetEnabled('arasaac', false);
      await saveSymbolChoices(db, registry.choices);

      final next = registryWith(choices: await loadSymbolChoices(db));
      expect(next.isSetEnabled('arasaac'), isFalse);
    });

    test('a commercial set switched off stays off', () async {
      // The other direction, which the license fallback would otherwise undo
      // at the next launch.
      final registry = registryWith()..setSetEnabled('tawasol', false);
      await saveSymbolChoices(db, registry.choices);

      final next = registryWith(choices: await loadSymbolChoices(db));
      expect(next.isSetEnabled('tawasol'), isFalse);
      expect(next.isSetEnabled('mulberry'), isTrue);
    });

    test(
      'a stored map that will not parse falls back to the licenses',
      () async {
        // Guessing at it could turn a noncommercial set on, which is the one
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
              .isSetEnabled('arasaac'),
          isFalse,
        );
      },
    );

    test(
      'and a set nobody has decided about is absent from what is stored',
      () async {
        // So a noncommercial set added in a later release arrives off, and a
        // seventh CC BY-SA set arrives on, rather than either inheriting a
        // saved map that predates it.
        final registry = registryWith();
        registry.setSetEnabled('arasaac', true);
        await saveSymbolChoices(db, registry.choices);

        expect(await loadSymbolChoices(db), {'arasaac': true});
      },
    );

    test('an unknown set cannot be enabled into existence', () {
      final registry = registryWith()..setSetEnabled('sclera', true);

      expect(registry.isSetEnabled('sclera'), isFalse);
      expect(registry.choices, isEmpty);
    });
  });

  group('what the switch tells a caregiver', () {
    String subtitle(SymbolRegistry registry, String slug) =>
        subtitleFor(registry.setFor(slug)!, registry.packsOffering(slug));

    test('a noncommercial set says so', () {
      // The license term itself, which is what a caregiver deciding needs to
      // see. It used to spell out the consequence as well — "leave this off if
      // the app will be sold" — and that sentence went when the settings text
      // was cut back to plain statements of what each option does. What still
      // guards the licensing is the default: these sets arrive off, and CI
      // fails a build that bundles one.
      expect(subtitle(registryWith(), 'arasaac'), contains('noncommercial'));
      expect(
        subtitle(registryWith(), 'aac-image-library'),
        contains('noncommercial'),
      );
    });

    test('a set that permits commercial use does not say that', () {
      expect(
        subtitle(registryWith(), 'mulberry'),
        isNot(contains('noncommercial')),
      );
    });

    test('a set that ships says it works offline', () {
      // And says the rest of it is a download, which is the fact a per pack
      // switch could not state: Stellar is both.
      final line = subtitle(registryWith(), 'stellar-symbols');

      expect(line, contains('come with the app'));
      expect(line, contains('downloaded'));
    });

    test('the emoji say the device draws them', () {
      expect(subtitle(registryWith(), 'device-emoji'), contains('offline'));
    });

    test('a set that is only fetched says it needs a network', () {
      // Not `tawasol` or `mulberry`: whether the shipped manifest happens to
      // carry a picture from a set is a decision that moves, and a set that is
      // bundled *and* fetched says both things. This one is fetched only.
      final line = subtitle(registryWith(), 'corona-symbols');

      expect(line, contains('Downloaded'));
      expect(line, isNot(contains('offline')));
    });

    test('no subtitle carries a dash or a hyphen', () {
      // §4.50. "non-commercial" is the spelling that would slip through here.
      final registry = registryWith();
      for (final set in registry.sets) {
        final line = subtitle(registry, set.slug);
        expect(
          RegExp(r'[-‐-―]').hasMatch(line),
          isFalse,
          reason: '${set.slug}: $line',
        );
      }
    });
  });
}
