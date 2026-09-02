import 'package:flutter/material.dart';

import '../symbols/symbol_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import '../symbols/symbol_result_tile.dart';

/// Looking at what the picture sets hold, without putting anything anywhere.
///
/// The only way to see this used to be a button's picker, which meant choosing
/// a button first and backing out without picking — browsing by pretending to
/// edit, on a screen whose one purpose is to change something. A caregiver
/// wondering whether a word has a usable picture had to risk changing a button
/// to find out.
///
/// So: the same search, the same tiles, and no button in scope. Tapping a
/// result says what it is rather than putting it somewhere, which is also what
/// somebody needs in order to ask for a particular picture by name.
class PictureBrowser extends StatefulWidget {
  const PictureBrowser({
    super.key,
    required this.registry,
    required this.resolver,
  });

  final SymbolRegistry registry;
  final SymbolResolver resolver;

  @override
  State<PictureBrowser> createState() => _PictureBrowserState();
}

class _PictureBrowserState extends State<PictureBrowser> {
  final _query = TextEditingController();

  List<SymbolRef> _results = const [];
  bool _searching = false;
  bool _searched = false;

  /// Which set the results are from, or null for all of them.
  String? _packId;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Only the sets that are switched on.
  ///
  /// A chip for a pack that is off would offer a search that returns nothing,
  /// and read as an empty catalog rather than as a pack somebody turned off.
  List<SymbolPack> get _packs => widget.registry.enabledPacks;

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }

    setState(() => _searching = true);
    final hits = await widget.registry.search(q, limit: 120, packId: _packId);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _filterTo(String? packId) async {
    setState(() => _packId = packId);
    if (_query.text.trim().isNotEmpty) await _search();
  }

  /// What a picture is, since it is not going anywhere.
  ///
  /// The catalog number is the point of this sheet. Two sets draw the same word
  /// and a person who wants the other one has no way to say which they mean
  /// without it.
  void _describe(SymbolRef ref) {
    final pack = widget.registry.packFor(ref.packId);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ref.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _Fact('Set', symbolOrigin(pack, ref) ?? ref.packId),
              _Fact('Reference', '${ref.packId}.${ref.externalId}'),
              if (pack != null) _Fact('License', pack.license),
              // The set that drew this one, not the pack's list of every set
              // it was assembled from (§4.72).
              if (_creditFor(pack, ref) case final credit?)
                _Fact('Credit', credit),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packs = _packs;

    return Scaffold(
      appBar: AppBar(title: const Text('Browse pictures')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search pictures',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: 'Search',
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),

          if (packs.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All sets'),
                      selected: _packId == null,
                      onSelected: (_) => _filterTo(null),
                    ),
                  ),
                  for (final pack in packs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(pack.name),
                        selected: _packId == pack.id,
                        onSelected: (_) => _filterTo(pack.id),
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                ? const _Empty(
                    'Search for a word to see what the picture sets have '
                    'for it.',
                  )
                : _results.isEmpty
                ? const _Empty('No pictures for that word in this set.')
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: _results.length,
                    itemBuilder: (context, i) => SymbolResultTile(
                      ref: _results[i],
                      resolver: widget.resolver,
                      pack: widget.registry.packFor(_results[i].packId),
                      onTap: () => _describe(_results[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Who to credit for one picture.
///
/// An assembled pack knows which upstream set each symbol came from and what
/// that set asks to be called. Falling back to the pack's own line is right for
/// a pack that is one set; for the bundled one it names all four, which beside
/// a single drawing credits three people who had nothing to do with it.
String? _creditFor(SymbolPack? pack, SymbolRef ref) {
  if (pack == null) return null;
  if (pack is AssembledSymbolPack) {
    final credit = pack.creditFor(ref);
    if (credit != null) return credit;
    // Known to be assembled and the set is not known, so the pack's own line
    // would be a guess dressed as a credit.
    if (pack.sourceOf(ref) == null && pack.attribution.contains(',')) {
      return null;
    }
  }
  return pack.attribution.isEmpty ? null : pack.attribution;
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black45),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
}
