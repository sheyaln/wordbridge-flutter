import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../symbols/symbol_choices.dart';
import '../symbols/symbol_pack.dart';
import '../symbols/symbol_registry.dart';

/// Which picture sets this tablet may use.
///
/// The screen exists for one rule, which the registry enforces and this makes
/// visible: a pack whose license forbids commercial use is inert until
/// somebody turns it on. Fetching one on a person's instruction is their
/// choice; shipping it enabled would make it ours.
///
/// So the switch says what the license actually restricts, in the terms
/// somebody deciding would need. It does not argue for either answer.
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
  Future<void> _set(SymbolPack pack, bool enabled) async {
    widget.registry.setEnabled(pack.id, enabled);
    await saveSymbolChoices(widget.db, widget.registry.choices);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final packs = widget.registry.packs;

    return Scaffold(
      appBar: AppBar(title: const Text('Pictures')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Pictures that come with the app are always available. The rest '
              'are downloaded when a word needs one, and kept on the device '
              'afterwards.',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
          for (final pack in packs)
            SwitchListTile(
              value: widget.registry.isEnabled(pack.id),
              title: Text(pack.name),
              subtitle: Text(subtitleFor(pack)),
              isThreeLine: !pack.allowsCommercialUse,
              // A bundled pack is the app's own artwork and switching it off
              // would leave the shipped board blank.
              onChanged: pack.isBundled ? null : (v) => _set(pack, v),
            ),
        ],
      ),
    );
  }
}

/// What a caregiver reads under a pack's name.
///
/// Extracted so the one sentence that carries a license term can be tested
/// without building a screen. A noncommercial pack that quietly described
/// itself as ordinary would be the whole safeguard undone by a subtitle.
String subtitleFor(SymbolPack pack) {
  if (pack.isBundled) {
    return 'Comes with the app. Always available, and works offline.';
  }
  if (pack.allowsCommercialUse) {
    return 'Show results from this pack in picture search.';
  }
  return 'Show results from this pack in picture search. Licensed for '
      'noncommercial use only.';
}
