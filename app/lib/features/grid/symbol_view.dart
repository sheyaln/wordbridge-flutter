import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../symbols/symbol_resolver.dart';

/// Draws a button's picture, or nothing at all.
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
    this.packIds = const ['core'],
  });

  final SymbolResolver resolver;

  /// Rendered when no picture resolves, which is most of the time early on.
  final String label;

  /// Packs to look in, in order.
  final List<String> packIds;

  @override
  State<SymbolView> createState() => _SymbolViewState();
}

class _SymbolViewState extends State<SymbolView> {
  SymbolImage? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(SymbolView old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) _resolve();
  }

  Future<void> _resolve() async {
    if (widget.packIds.isEmpty) return;

    final resolved = await widget.resolver.resolveLabel(
      widget.label,
      widget.packIds,
    );
    if (mounted && resolved.image != null) {
      setState(() => _image = resolved.image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return _Label(widget.label, large: true);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _Picture(image: image, label: widget.label),
        ),
        const SizedBox(height: 2),
        _Label(widget.label, large: false),
      ],
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.image, required this.label});

  final SymbolImage image;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isSvg = image.uri.toLowerCase().endsWith('.svg');

    return switch ((image.kind, isSvg)) {
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
