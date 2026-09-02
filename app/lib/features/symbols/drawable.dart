import 'dart:typed_data';

import 'package:xml/xml_events.dart';

/// Whether these bytes are something the renderer can actually draw.
///
/// §4.67. A downloading pack checked for HTTP 200 and a non-empty body and
/// filed whatever came back. A 200 carrying an error page, or a body cut short
/// by a connection that dropped after the headers, was written to disk and
/// renamed into place — where it then *looks cached* forever. Every attempt to
/// draw it threw inside `flutter_svg`'s parse isolate, was caught, and became
/// a crash report. Ten of them arrived from one device in one flush.
///
/// The comment beside that write already worried about a truncated file
/// looking cached; it guarded the process being killed mid-write and not the
/// server handing over something that was never an image.
///
/// Cheap and answered before the file is filed, so a bad response costs one
/// failed download rather than a fault on every draw for the life of the
/// install.
bool looksDrawable(Uint8List bytes, {required bool asSvg}) {
  if (bytes.isEmpty) return false;
  return asSvg ? _isSvg(bytes) : _isRaster(bytes);
}

/// Parsed with the same event parser `flutter_svg` uses, because that is the
/// one whose opinion matters. A document-level well formedness check is a
/// different, more forgiving question, and passing it is not evidence.
///
/// Drained rather than merely created: the events are lazy, and an iterator
/// nobody reads throws nothing.
bool _isSvg(Uint8List bytes) {
  final String text;
  try {
    text = String.fromCharCodes(bytes);
  } catch (_) {
    return false;
  }

  try {
    var sawSvg = false;
    for (final event in parseEvents(text)) {
      // An HTML error page parses perfectly well and draws nothing, so being
      // readable XML is not enough — it has to be the right document.
      if (event is XmlStartElementEvent && event.localName == 'svg') {
        sawSvg = true;
      }
    }
    return sawSvg;
  } catch (_) {
    return false;
  }
}

/// The first bytes of the formats Flutter can decode.
///
/// By content rather than by extension, deliberately: nine bundled files are
/// named `.png` and hold JPEG data, and they render, because the decoder reads
/// the bytes. What must be refused is a body that is not an image at all.
bool _isRaster(Uint8List b) {
  bool starts(List<int> magic) {
    if (b.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[i] != magic[i]) return false;
    }
    return true;
  }

  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return true; // PNG
  if (starts(const [0xFF, 0xD8, 0xFF])) return true; // JPEG
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return true; // GIF
  if (starts(const [0x42, 0x4D])) return true; // BMP
  // WEBP is "RIFF" .... "WEBP".
  if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
      b.length >= 12 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return true;
  }
  return false;
}
