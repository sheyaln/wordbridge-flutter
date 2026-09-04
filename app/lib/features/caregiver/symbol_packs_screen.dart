import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../symbols/symbol_choices.dart';
import '../symbols/symbol_pack.dart';
import '../symbols/symbol_registry.dart';

/// Which picture sets this tablet may use.
///
/// The screen exists for one rule, which the registry enforces and this makes
/// visible: a set whose license forbids commercial use is inert until somebody
/// turns it on. Fetching one on a person's instruction is their choice;
/// shipping it enabled would make it ours.
///
/// **Sets, not packs.** Whether a picture ships in the binary or is downloaded
/// when a word needs one is how the app is built, and it used to be the thing
/// a caregiver was asked about: two switches called "Wordbridge AAC core
/// symbols" and "More pictures", neither of which is a name anybody chooses
/// between. Somebody deciding wants Mulberry drawings and not emoji, or the
/// other way round. So the list is the sets themselves, and the row says what
/// each one costs to use rather than which mechanism carries it.
class SymbolPacksScreen extends StatefulWidget {
  const SymbolPacksScreen({
    super.key,
    required this.db,
    required this.registry,
  });

  final WordbridgeDatabase db;
  final SymbolRegistry registry;

  @override
  State<SymbolPacksScreen> createState() => _SymbolPacksScreenState();
}

class _SymbolPacksScreenState extends State<SymbolPacksScreen> {
  Future<void> _set(SymbolSet set, bool enabled) async {
    widget.registry.setSetEnabled(set.slug, enabled);
    await saveSymbolChoices(widget.db, widget.registry.choices);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final registry = widget.registry;

    return Scaffold(
      appBar: AppBar(title: const Text('Pictures')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Each set is drawn by different people in a different style. '
              'Turning one off takes it out of picture search and off the '
              'buttons that were using it.',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
          for (final set in registry.sets)
            SwitchListTile(
              value: registry.isSetEnabled(set.slug),
              title: Text(set.name),
              subtitle: Text(
                subtitleFor(set, registry.packsOffering(set.slug)),
              ),
              isThreeLine: !set.allowsCommercialUse,
              onChanged: (v) => _set(set, v),
            ),
        ],
      ),
    );
  }
}

/// What a caregiver reads under a set's name.
///
/// Two things, in the order they matter to somebody deciding: whether it works
/// without a network, and what the license restricts.
///
/// Extracted so the sentence that carries a license term can be tested without
/// building a screen. A noncommercial set that quietly described itself as
/// ordinary would be the whole safeguard undone by a subtitle.
String subtitleFor(SymbolSet set, List<SymbolPack> offering) {
  final ships = offering.any((p) => p.isBundled);
  final glyph = offering.any((p) => p is GlyphSymbolPack);
  final fetches = offering.any((p) => p is DownloadingSymbolPack);

  final cost = switch ((ships, glyph, fetches)) {
    // Both, which is the case a per pack switch could not describe: some of
    // this set is in the app and the rest of it is a download away.
    (true, _, true) =>
      'Some pictures come with the app. More are downloaded when a word '
          'needs one.',
    (true, _, _) => 'Comes with the app. Works offline.',
    (_, true, _) => 'Drawn by this device. Works offline.',
    (_, _, true) =>
      'Downloaded when a word needs one, and kept on the device afterwards.',
    _ => 'Show pictures from this set.',
  };

  if (set.allowsCommercialUse) return cost;
  return '$cost Licensed for noncommercial use only.';
}
