import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/db/tables.dart';
import 'package:wordbridge/features/symbols/auto_symbol.dart';
import 'package:wordbridge/features/symbols/global_symbols_pack.dart';
import 'package:wordbridge/features/symbols/symbol_registry.dart';

/// Finding a picture for a word without anybody watching.
///
/// The whole risk here is that nobody is looking at the screen when it runs.
/// A picture attached automatically has to be certainly right, because a
/// plausible wrong one teaches an AAC user that a word means whatever the
/// picture shows, and they cannot contradict it.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('wb-auto'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// A Global Symbols search response. The real API is a substring match, so
  /// asking for "not" genuinely does return Notebook.
  String labels(List<({String text, int id})> hits) => jsonEncode([
    for (final hit in hits)
      {
        'text': hit.text,
        'picto': {
          'id': hit.id,
          'image_url': 'https://example.test/${hit.id}.svg',
          'native_format': 'svg',
        },
      },
  ]);

  GlobalSymbolsPack packReturning(
    List<({String text, int id})> hits, {
    List<int>? image,
  }) => GlobalSymbolsPack(
    documentsDirectory: () async => temp,
    client: MockClient((request) async {
      if (request.url.host == GlobalSymbolsPack.host) {
        return http.Response(labels(hits), 200);
      }
      return http.Response.bytes(image ?? [1, 2, 3], 200);
    }),
  );

  group('what may be attached unattended', () {
    test('an exact match is', () async {
      final pack = packReturning([(text: 'drink', id: 42)]);
      addTearDown(pack.dispose);

      expect((await pack.bestMatch('drink'))?.externalId, '42');
    });

    test('a near miss is not', () async {
      // The three that shipped wrong once: "all" returning Ball, "not"
      // returning Notebook, "she" returning Sheep.
      final pack = packReturning([
        (text: 'Ball', id: 1),
        (text: 'Notebook', id: 2),
        (text: 'Sheep', id: 3),
      ]);
      addTearDown(pack.dispose);

      expect(await pack.bestMatch('all'), isNull);
      expect(await pack.bestMatch('not'), isNull);
      expect(await pack.bestMatch('she'), isNull);
    });

    test('the top-ranked result is not a fallback', () async {
      // An exact match further down the list is found; the first result is
      // never taken just for being first.
      final pack = packReturning([
        (text: 'Notebook', id: 1),
        (text: 'Nothing', id: 2),
        (text: 'not', id: 3),
      ]);
      addTearDown(pack.dispose);

      expect((await pack.bestMatch('not'))?.externalId, '3');
    });

    test('case and punctuation do not make a word a different word', () async {
      final pack = packReturning([(text: 'Ice Cream', id: 7)]);
      addTearDown(pack.dispose);

      expect((await pack.bestMatch('ice cream'))?.externalId, '7');
    });
  });

  group('what a person is offered to choose from', () {
    test('search returns near misses, because a person is looking', () async {
      // The looser half of the same source. A caregiver deciding a picture of
      // a cup means "drink" is judgment, which is what they are for.
      final pack = packReturning([
        (text: 'Ball', id: 1),
        (text: 'Balloon', id: 2),
      ]);
      addTearDown(pack.dispose);

      final results = await pack.search('ball');
      expect(results, hasLength(greaterThan(1)));
      expect(results.map((r) => r.label), contains('Balloon'));
    });

    test('an empty query asks for nothing', () async {
      final pack = packReturning([(text: 'Ball', id: 1)]);
      addTearDown(pack.dispose);

      expect(await pack.search('   '), isEmpty);
    });
  });

  group('attaching to a button', () {
    late WordbridgeDatabase db;
    late String vocabId;

    setUp(() async {
      db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      vocabId = await seedCoreBoardSet(db);
    });
    tearDown(() async => db.close());

    Future<String> addWord(String label) async {
      final cell = await (db.select(
        db.cells,
      )..where((c) => c.state.equalsValue(CellState.emptyReserved))).get();
      final id = newId();
      await db
          .into(db.buttons)
          .insert(
            ButtonsCompanion.insert(
              id: id,
              cellId: Value(cell.first.id),
              vocabularyId: vocabId,
              label: label,
              message: label,
              action: ButtonAction.speak,
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
      return id;
    }

    Future<Button> buttonById(String id) =>
        (db.select(db.buttons)..where((b) => b.id.equals(id))).getSingle();

    /// A photograph a caregiver imported, as a row the button can point at.
    Future<String> theirOwnPhoto() async {
      const id = 'their-own-photo';
      await db
          .into(db.symbols)
          .insert(
            SymbolsCompanion.insert(
              id: id,
              source: SymbolSource.custom,
              label: 'colleague',
              license: 'user-owned',
              attribution: 'Supplied by the device owner.',
              createdAt: nowMs(),
            ),
          );
      return id;
    }

    test('an exact match is attached', () async {
      final pack = packReturning([(text: 'Nana', id: 99)]);
      addTearDown(pack.dispose);

      final buttonId = await addWord('Nana');
      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [pack]),
        fetcher: pack,
      ).attachTo(buttonId: buttonId, label: 'Nana');

      expect(attached, isTrue);
      expect((await buttonById(buttonId)).symbolId, isNotNull);
    });

    test('a picture a caregiver chose is never overwritten', () async {
      // §4.89. This runs unwatched and can take seconds — nothing bundled
      // matches, so the network is asked and then the picture is fetched — and
      // those are exactly the seconds in which somebody looking at a blank
      // button opens the picker and puts their own photograph on it. Landing
      // last, it used to take the photograph straight back off, so the picker
      // appeared to do nothing at all.
      final pack = packReturning([(text: 'colleague', id: 42)]);
      addTearDown(pack.dispose);

      final buttonId = await addWord('colleague');
      // The caregiver got there first.
      final theirs = await theirOwnPhoto();
      await (db.update(db.buttons)..where((b) => b.id.equals(buttonId))).write(
        ButtonsCompanion(symbolId: Value(theirs)),
      );

      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [pack]),
        fetcher: pack,
      ).attachTo(buttonId: buttonId, label: 'colleague');

      expect(attached, isFalse);
      expect(
        (await buttonById(buttonId)).symbolId,
        'their-own-photo',
        reason: 'the lookup overwrote a picture somebody chose',
      );
    });

    test('and not one chosen while the lookup was still running', () async {
      // The real shape of it: the button is blank when the lookup starts, and
      // the choice lands while the network is being asked.
      final buttonId = await addWord('colleague');
      final theirs = await theirOwnPhoto();

      // The choice lands while the lookup is out on the network, which is the
      // seam the real one is slow at.
      final racing = GlobalSymbolsPack(
        documentsDirectory: () async => temp,
        client: MockClient((request) async {
          if (request.url.host == GlobalSymbolsPack.host) {
            await (db.update(db.buttons)..where((b) => b.id.equals(buttonId)))
                .write(ButtonsCompanion(symbolId: Value(theirs)));
            return http.Response(labels([(text: 'colleague', id: 42)]), 200);
          }
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      addTearDown(racing.dispose);

      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [racing]),
        fetcher: racing,
      ).attachTo(buttonId: buttonId, label: 'colleague');

      expect(attached, isFalse);
      expect((await buttonById(buttonId)).symbolId, 'their-own-photo');
    });

    test('nothing is taken from a set that is switched off', () async {
      // The unattended path, which is where a set switched off matters most:
      // nobody is looking, so a picture from a set this device was told not to
      // use would arrive on a button and stay there unnoticed.
      final pack = packReturning([(text: 'Nana', id: 99)]);
      addTearDown(pack.dispose);
      final registry = SymbolRegistry(packs: [pack]);
      for (final set in GlobalSymbolsPack.commercialSets) {
        registry.setSetEnabled(set.slug, false);
      }

      final buttonId = await addWord('Nana');
      final attached = await AutoSymbol(
        db: db,
        registry: registry,
        fetcher: pack,
      ).attachTo(buttonId: buttonId, label: 'Nana');

      expect(attached, isFalse);
      expect((await buttonById(buttonId)).symbolId, isNull);
    });

    test('and the credit written down is the set that drew it', () async {
      // Not the pack's own line, which names all six sets. That row is what
      // an export carries out of this device (§4.72).
      final pack = packReturning([(text: 'Nana', id: 99)]);
      addTearDown(pack.dispose);

      final buttonId = await addWord('Nana');
      await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [pack]),
        fetcher: pack,
      ).attachTo(buttonId: buttonId, label: 'Nana');

      final symbolId = (await buttonById(buttonId)).symbolId;
      final symbol = await (db.select(
        db.symbols,
      )..where((s) => s.id.equals(symbolId!))).getSingle();

      // Every set answers with the same hit here, and `bestMatch` walks them
      // in preference order, so the first one is the one that drew it.
      expect(
        symbol.attribution,
        GlobalSymbolsPack.commercialSets.first.attribution,
      );
      expect(symbol.license, GlobalSymbolsPack.commercialSets.first.license);
    });

    test('a near miss leaves the button without a picture', () async {
      final pack = packReturning([(text: 'Notebook', id: 1)]);
      addTearDown(pack.dispose);

      final buttonId = await addWord('not');
      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [pack]),
        fetcher: pack,
      ).attachTo(buttonId: buttonId, label: 'not');

      expect(attached, isFalse);
      expect(
        (await buttonById(buttonId)).symbolId,
        isNull,
        reason: 'a blank button says "no picture yet"; a wrong one lies',
      );
    });

    test('no network leaves the button working and unchanged', () async {
      final offline = GlobalSymbolsPack(
        documentsDirectory: () async => temp,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      addTearDown(offline.dispose);

      final buttonId = await addWord('Nana');
      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: [offline]),
        fetcher: offline,
      ).attachTo(buttonId: buttonId, label: 'Nana');

      expect(attached, isFalse);
      expect((await buttonById(buttonId)).label, 'Nana');
    });

    test(
      'a download that never lands still leaves a readable button',
      () async {
        // The picture is queued, not waited for. If it never arrives the button
        // shows its word — the same thing it would show with no symbol at all,
        // and never a broken image.
        final pack = GlobalSymbolsPack(
          documentsDirectory: () async => temp,
          client: MockClient((request) async {
            if (request.url.host == GlobalSymbolsPack.host) {
              return http.Response(labels([(text: 'Nana', id: 5)]), 200);
            }
            return http.Response('gone', 404);
          }),
        );
        addTearDown(pack.dispose);

        final buttonId = await addWord('Nana');
        await AutoSymbol(
          db: db,
          registry: SymbolRegistry(packs: [pack]),
          fetcher: pack,
        ).attachTo(buttonId: buttonId, label: 'Nana');

        final symbolId = (await buttonById(buttonId)).symbolId;
        if (symbolId != null) {
          final symbol = await (db.select(
            db.symbols,
          )..where((s) => s.id.equals(symbolId))).getSingle();
          expect(
            symbol.localUri,
            isNull,
            reason: 'a symbol with no file must not claim to have one',
          );
        }
        expect((await buttonById(buttonId)).label, 'Nana');
      },
    );

    test('without a fetcher it still checks what is already bundled', () async {
      final buttonId = await addWord('zzzznotaword');
      final attached = await AutoSymbol(
        db: db,
        registry: SymbolRegistry(packs: const []),
      ).attachTo(buttonId: buttonId, label: 'zzzznotaword');

      expect(attached, isFalse);
    });
  });

  group('the license boundary', () {
    test('only commercially clean sets are reachable', () {
      // ARASAAC and Sclera are CC BY-NC and belong behind their own opt-in
      // pack. This one may be bundled, sold, or shipped on hardware.
      expect(GlobalSymbolsPack.commercialSets.map((s) => s.slug), [
        'mulberry',
        'corona-symbols',
        'additional-mulberry-symbols',
        'stellar-symbols',
        'tawasol',
        'openmoji',
      ]);

      final pack = GlobalSymbolsPack(
        client: MockClient((_) async {
          return http.Response('[]', 200);
        }),
      );
      addTearDown(pack.dispose);

      for (final set in pack.sets) {
        expect(set.allowsCommercialUse, isTrue);
      }
      expect(pack.license, 'CC-BY-SA-4.0');
    });

    test('every search names the set it is asking', () {
      for (final set in GlobalSymbolsPack.commercialSets) {
        final uri = GlobalSymbolsPack.searchUri('drink', set.slug);
        expect(uri.host, GlobalSymbolsPack.host);
        expect(uri.queryParameters['symbolset'], set.slug);
      }
    });

    test('attribution names every set, as the license requires', () {
      final pack = GlobalSymbolsPack(
        client: MockClient((_) async {
          return http.Response('[]', 200);
        }),
      );
      addTearDown(pack.dispose);

      for (final set in GlobalSymbolsPack.commercialSets) {
        expect(pack.attribution, contains(set.name));
      }
    });
  });
}
