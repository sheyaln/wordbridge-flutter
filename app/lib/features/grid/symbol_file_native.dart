import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The picture at [path], or nothing where it will not draw.
///
/// A symbol that fails to parse or to load leaves the label doing the work. A
/// broken image glyph is never acceptable — it tells an AAC user their word is
/// damaged.
Widget symbolFromFile(String path, {required bool isSvg}) => isSvg
    ? SvgPicture.file(
        File(path),
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox.shrink(),
      )
    : Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
