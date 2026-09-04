import 'dart:async';

import 'package:flutter/material.dart';

import '../grid/symbol_view.dart';
import 'symbol_pack.dart';
import 'symbol_resolver.dart';

/// One search result: its picture, or its word until the picture exists.
///
/// Shared by the button picker, where choosing one assigns it, and the picture
/// browser, where choosing one only says what it is. A tile is the same object
/// either way — a picture, its name, and the set it came from — and what a tap
/// does belongs to the screen rather than to the tile.
///
/// A result from a downloading pack resolves to nothing on the first pass and
/// to a file once the download lands, so the tile watches for its own arrival.
/// Waiting for something else to rebuild the screen would leave a caregiver
/// choosing between words, and the whole reason to open one of these is to
/// choose between pictures.

/// What a tile in the picker can be showing, when it is not showing a picture.
///
/// A blank tile is three different facts wearing one face: the picture is on
/// its way, the picture is not coming, or there is no picture to have. Only the
/// first is worth waiting for and only the second is worth reporting, so a
/// person choosing between results has to be able to tell them apart.
enum SymbolTileState {
  /// The picture is drawn.
  showing,

  /// Being fetched, or queued behind a fetch. Worth waiting for.
  looking,

  /// The pack offers this symbol and the fetch has been given up on. The result
  /// stays listed on purpose: the picture exists, this device just cannot get
  /// it, and hiding it would misreport an outage as an empty catalog.
  unavailable,

  /// Nothing to draw and nothing on its way.
  none,
}

/// Which of those a tile is in.
///
/// Extracted so the distinction can be tested without building a sheet, and
/// because getting it wrong is invisible: every one of these renders as a word
/// on a tile, so a wrong answer looks exactly like a right one.
SymbolTileState symbolTileState({
  required bool hasImage,
  required bool pending,
  required SymbolPack? pack,
  required SymbolRef ref,
}) {
  if (hasImage) return SymbolTileState.showing;
  if (pending) return SymbolTileState.looking;

  if (pack is DownloadingSymbolPack) {
    return pack.failedFor(ref)
        ? SymbolTileState.unavailable
        : SymbolTileState.looking;
  }

  // A pack that ships its images has already answered: there is no later
  // arrival to wait for.
  return SymbolTileState.none;
}

/// Where a picture came from, in the fewest words that identify it again.
///
/// The bundled pack is assembled from several upstream sets, so its own name
/// says nothing useful: every tile read "Wordbridge AAC core symbols" whatever
/// set drew it. Where the set is known it is shown instead, because that plus the
/// label above it is what somebody needs to ask for a different picture by
/// name.
///
/// Numbered packs keep their id, which is the only stable handle those sets
/// have and the one they use themselves.
String? symbolOrigin(SymbolPack? pack, SymbolRef ref) {
  if (pack == null) return null;

  final source = pack is AssembledSymbolPack ? pack.sourceOf(ref) : null;
  if (source != null) return source;

  // A numeric external id is an upstream catalog number, worth showing. A
  // filename is not: it repeats the label with an extension on the end.
  final numbered = int.tryParse(ref.externalId) != null;
  return numbered ? '${pack.name} ${ref.externalId}' : pack.name;
}

class SymbolResultTile extends StatefulWidget {
  const SymbolResultTile({
    super.key,
    required this.ref,
    required this.resolver,
    required this.pack,
    required this.onTap,
  });

  /// The pack this result came from, or null where it is no longer registered.
  ///
  /// The pack rather than its name, because the tile also has to ask it whether
  /// a picture that has not arrived is still coming.
  final SymbolPack? pack;

  /// Which picture this is.
  ///
  /// A search puts several packs' answers to one word side by side, which is
  /// the point of searching them all — and leaves the caregiver choosing
  /// between house styles they cannot name. The label and the set are drawn
  /// under every tile so a picture can be asked for by name.
  final SymbolRef ref;
  final SymbolResolver resolver;
  final VoidCallback onTap;

  @override
  State<SymbolResultTile> createState() => _SymbolResultTileState();
}

class _SymbolResultTileState extends State<SymbolResultTile> {
  SymbolImage? _image;

  /// True while a resolution is outstanding, which is what separates a
  /// picture on its way from one that is not coming.
  bool _pending = false;

  /// Which resolution the picture on screen belongs to.
  int _generation = 0;

  StreamSubscription<SymbolRef>? _arrivals;

  @override
  void initState() {
    super.initState();
    _resolve();

    // Matched on the symbol rather than on its word, unlike a board: a search
    // deliberately puts several pictures of the same word side by side, and an
    // arrival belongs to exactly one of them.
    _arrivals = widget.resolver.ready
        .where((ref) => ref.key == widget.ref.key)
        .listen((_) => _resolve());
  }

  @override
  void didUpdateWidget(SymbolResultTile old) {
    super.didUpdateWidget(old);
    // A row is reused for whatever result now sits at its index, so a fresh
    // search hands this state a different symbol.
    if (old.ref.key != widget.ref.key) {
      _image = null;
      _resolve();
    }
  }

  @override
  void dispose() {
    _arrivals?.cancel();
    super.dispose();
  }

  /// Off the path of every tap in this sheet: a row that never resolves is a
  /// row showing its word, not a sheet that fails to open.
  Future<void> _resolve() async {
    final generation = ++_generation;
    if (mounted) setState(() => _pending = true);

    final resolved = await widget.resolver.resolve(widget.ref);

    // A resolution can land after the row has moved on to another result, and
    // only the most recent one may draw.
    if (!mounted || generation != _generation) return;
    setState(() {
      _image = resolved.image;
      _pending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final packName = symbolOrigin(widget.pack, widget.ref);
    final state = symbolTileState(
      hasImage: image != null,
      pending: _pending,
      pack: widget.pack,
      ref: widget.ref,
    );

    return InkWell(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Expanded(
              // The word stands in for a picture that has not arrived. A tile
              // with no picture is not worth choosing anyway, so the name is
              // the only useful thing it can carry.
              child: image == null
                  ? Center(
                      child: Text(
                        widget.ref.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    )
                  : SymbolPicture(image),
            ),
            // The picture's own name, above where it came from. Two tiles from
            // different sets are otherwise identical on screen, and a person
            // who wants a different one has no way to say which they mean.
            // Skipped where the picture is missing, because the word is
            // already standing in for it above.
            if (image != null)
              Text(
                widget.ref.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10),
              ),
            // Why there is a word here and not a picture. Listed either way:
            // the picture exists, and a device that cannot fetch it today is
            // an outage to report rather than a catalog to shorten.
            if (state != SymbolTileState.showing)
              Text(
                switch (state) {
                  SymbolTileState.looking => 'Loading',
                  SymbolTileState.unavailable => 'Did not load',
                  _ => 'No picture',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: state == SymbolTileState.unavailable
                      ? const Color(0xFFB3261E)
                      : Colors.black45,
                ),
              ),
            if (packName != null)
              Text(
                packName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: Colors.black45),
              ),
          ],
        ),
      ),
    );
  }
}
