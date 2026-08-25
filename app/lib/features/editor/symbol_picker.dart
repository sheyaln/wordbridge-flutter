import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';

import 'package:image_picker/image_picker.dart';

import '../symbols/custom_upload.dart';
import '../symbols/symbol_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';

/// Choosing the picture on a button.
///
/// Two sources, deliberately equal: the bundled packs, and a photograph the
/// caregiver takes. The second is not a fallback. A photo of the actual
/// person, the actual cup, the actual front door is usually a better symbol
/// than any drawing, and the most-repeated complaint about commercial AAC
/// boards is that the words a family needs have no picture and adding one is
/// too much work.
class SymbolPicker extends StatefulWidget {
  const SymbolPicker({
    super.key,
    required this.db,
    required this.registry,
    required this.resolver,
    required this.button,
  });

  final WordbridgeDatabase db;
  final SymbolRegistry registry;
  final SymbolResolver resolver;
  final Button button;

  /// Returns true if the button's symbol changed.
  static Future<bool> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required SymbolRegistry registry,
    required SymbolResolver resolver,
    required Button button,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: SymbolPicker(
          db: db,
          registry: registry,
          resolver: resolver,
          button: button,
        ),
      ),
    );
    return changed ?? false;
  }

  @override
  State<SymbolPicker> createState() => _SymbolPickerState();
}

class _SymbolPickerState extends State<SymbolPicker> {
  late final TextEditingController _query = TextEditingController(
    text: widget.button.label,
  );

  List<SymbolRef> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }

    setState(() => _searching = true);
    final hits = await widget.registry.search(q, limit: 60);
    if (mounted) {
      setState(() {
        _results = hits;
        _searching = false;
      });
    }
  }

  Future<void> _assign(String symbolId) async {
    await (widget.db.update(
      widget.db.buttons,
    )..where((b) => b.id.equals(widget.button.id))).write(
      ButtonsCompanion(symbolId: Value(symbolId), updatedAt: Value(nowMs())),
    );

    await widget.db
        .into(widget.db.editEvents)
        .insert(
          EditEventsCompanion.insert(
            id: newId(),
            vocabularyId: widget.button.vocabularyId,
            cellId: Value(widget.button.cellId),
            buttonId: Value(widget.button.id),
            kind: EditKind.resymbol,
            changedAt: nowMs(),
          ),
        );

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _assignFromPack(SymbolRef ref) async {
    final uri = await widget.resolver.resolve(ref);
    final id = newId();
    final pack = widget.registry.packFor(ref.packId);

    await widget.db
        .into(widget.db.symbols)
        .insert(
          SymbolsCompanion.insert(
            id: id,
            packId: Value(ref.packId),
            source: pack?.isBundled ?? true
                ? SymbolSource.bundled
                : SymbolSource.downloaded,
            externalId: Value(ref.externalId),
            localUri: Value(uri.image?.uri),
            label: ref.label,
            license: pack?.license ?? 'unknown',
            attribution: pack?.attribution ?? '',
            createdAt: nowMs(),
          ),
        );

    await _assign(id);
  }

  Future<void> _useOwnPhoto(ImageSource source) async {
    final symbol = await CustomSymbolImporter(db: widget.db)
        .importFrom(source, label: widget.button.label);
    if (symbol == null) return;
    await _assign(symbol.id);
  }

  Future<void> _clear() async {
    await (widget.db.update(
      widget.db.buttons,
    )..where((b) => b.id.equals(widget.button.id))).write(
      ButtonsCompanion(symbolId: const Value(null), updatedAt: Value(nowMs())),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Picture for "${widget.button.label}"',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take a photo'),
                    onPressed: () => _useOwnPhoto(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose a photo'),
                    onPressed: () => _useOwnPhoto(ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'A photo of the real person or object is often clearer than a '
              'drawing. Photos stay on this device.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),

            const Divider(height: 28),

            TextField(
              controller: _query,
              decoration: InputDecoration(
                labelText: 'Search symbols',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? const Center(
                      child: Text(
                        'No symbols found for that word.\n'
                        'A button with no picture still works — it shows the '
                        'word instead.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: _results.length,
                      itemBuilder: (context, i) => _SymbolTile(
                        ref: _results[i],
                        resolver: widget.resolver,
                        onTap: () => _assignFromPack(_results[i]),
                      ),
                    ),
            ),

            if (widget.button.symbolId != null)
              TextButton.icon(
                icon: const Icon(Icons.hide_image_outlined),
                label: const Text('Remove the picture'),
                onPressed: _clear,
              ),
          ],
        ),
      ),
    );
  }
}

class _SymbolTile extends StatelessWidget {
  const _SymbolTile({
    required this.ref,
    required this.resolver,
    required this.onTap,
  });

  final SymbolRef ref;
  final SymbolResolver resolver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResolvedSymbol>(
      future: resolver.resolve(ref),
      builder: (context, snapshot) {
        final image = snapshot.data?.image;

        return InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(4),
            child: image == null
                ? Center(
                    child: Text(
                      ref.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  )
                : _preview(image),
          ),
        );
      },
    );
  }

  Widget _preview(SymbolImage image) {
    final isSvg = image.uri.toLowerCase().endsWith('.svg');
    return switch ((image.kind, isSvg)) {
      (SymbolImageKind.asset, true) => SvgPicture.asset(image.uri),
      (SymbolImageKind.asset, false) => Image.asset(image.uri),
      (SymbolImageKind.file, true) => SvgPicture.file(File(image.uri)),
      (SymbolImageKind.file, false) => Image.file(File(image.uri)),
    };
  }
}
