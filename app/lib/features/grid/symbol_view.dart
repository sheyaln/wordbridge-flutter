import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../symbols/symbol_pack.dart';
import '../symbols/symbol_resolver.dart';

/// Draws a button's picture, or nothing at all.
///
/// The picture is the one chosen for this button; only a button that has none
/// takes whatever the packs offer for its word.
///
/// Nothing here is on the path between a tap and speech. Resolution is
/// asynchronous, failure is silent, and the absence of a picture is a normal
/// state rather than an error: the label alone is a working button. A broken
/// image glyph is never acceptable — it tells an AAC user their word is
/// damaged.
class SymbolView extends StatefulWidget {
  const SymbolView({
    super.key,
    required this.resolver,
    required this.label,
    this.symbolId,
    this.packIds = const ['core'],
  });

  final SymbolResolver resolver;

  /// Rendered when no picture resolves, which is most of the time early on.
  final String label;

  /// The symbol chosen for this button. It outranks anything the packs offer
  /// for [label], and a button carrying one never falls back to them.
  final String? symbolId;

  /// Packs to look in, in order. Consulted only for a button with no symbol
  /// of its own.
  final List<String> packIds;

  @override
  State<SymbolView> createState() => _SymbolViewState();
}

class _SymbolViewState extends State<SymbolView> {
  SymbolImage? _image;

  /// Which resolution the picture on screen belongs to.
  int _generation = 0;

  StreamSubscription<SymbolRef>? _arrivals;

  @override
  void initState() {
    super.initState();
    _resolve();

    // A download queued by the first resolution lands after the grid is
    // drawn. Auto-attached symbols carry the word they illustrate, so the word
    // is what marks an arrival worth re-reading.
    _arrivals = widget.resolver.ready
        .where((ref) => _sameWord(ref.label, widget.label))
        .listen((_) => _resolve());
  }

  @override
  void didUpdateWidget(SymbolView old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label || old.symbolId != widget.symbolId) {
      _resolve();
    }
  }

  @override
  void dispose() {
    _arrivals?.cancel();
    super.dispose();
  }

  static bool _sameWord(String a, String b) =>
      a.toLowerCase().trim() == b.toLowerCase().trim();

  Future<void> _resolve() async {
    final generation = ++_generation;

    final resolved = await widget.resolver.resolveButton(
      symbolId: widget.symbolId,
      label: widget.label,
      packIds: widget.packIds,
    );

    // A location outlives the words on it and a word outlives its pictures, so
    // a resolution can land on a button it no longer describes. Only the most
    // recent one may draw.
    if (!mounted || generation != _generation) return;
    setState(() => _image = resolved.image);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return _Label(widget.label, large: true);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: SymbolPicture(image)),
        const SizedBox(height: 2),
        _Label(widget.label, large: false),
      ],
    );
  }
}

/// Draws one resolved picture: asset, file or glyph — vector, raster or text.
///
/// Shared by every board so that a caregiver auditing pictures and the person
/// using the device are looking at the same thing, drawn the same way.
class SymbolPicture extends StatelessWidget {
  const SymbolPicture(this.image, {super.key});

  final SymbolImage image;

  @override
  Widget build(BuildContext context) {
    final isSvg = image.uri.toLowerCase().endsWith('.svg');

    return switch ((image.kind, isSvg)) {
      // A glyph is text and is drawn as text, in whatever font the platform
      // supplies. That is the whole of the arrangement and it must stay that
      // way: the system emoji fonts are proprietary, so nothing here may ever
      // rasterise one into an image — no capture, no cache, no file. The
      // codepoint travels with the board; the picture never does.
      //
      // The size is only what the fit scales from, and `height: 1` drops the
      // line spacing an emoji does not need, so the character fills its cell
      // rather than floating in the middle of one.
      (SymbolImageKind.glyph, _) => FittedBox(
        fit: BoxFit.contain,
        child: Text(
          image.uri,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 48, height: 1),
        ),
      ),
      (SymbolImageKind.asset, true) => SvgPicture.asset(
        image.uri,
        fit: BoxFit.contain,
        // A symbol that fails to parse leaves the label doing the work
        // rather than putting an error in front of the user.
        placeholderBuilder: (_) => const SizedBox.shrink(),
      ),
      (SymbolImageKind.asset, false) => Image.asset(
        image.uri,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      (SymbolImageKind.file, true) => SvgPicture.file(
        File(image.uri),
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox.shrink(),
      ),
      (SymbolImageKind.file, false) => Image.file(
        File(image.uri),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    };
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.large});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          // Without a picture the word carries the whole button, so it is set
          // larger rather than left floating at caption size.
          fontSize: large ? 22 : 13,
          fontWeight: large ? FontWeight.w600 : FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }
}
