import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';

/// Longest edge of a stored custom symbol. A grid cell is at most a few
/// hundred points; anything larger is a full-resolution photograph of a child
/// sitting on disk for no benefit.
const customSymbolMaxEdge = 512;

const customSymbolLicense = 'user-owned';
const customSymbolAttribution = 'Supplied by the device owner.';

/// A photo normalized for storage: oriented, resized, re-encoded, stripped.
typedef NormalizedImage = ({Uint8List bytes, int width, int height});

/// Resizes to [customSymbolMaxEdge] and returns PNG bytes carrying no metadata.
///
/// Stripping EXIF is the reason this function exists rather than the resize.
/// These are photographs of children taken on a parent's phone, and EXIF
/// carries GPS coordinates — usually the family home. The `image` package
/// copies EXIF across a resize, and the JPEG encoder writes it back out; only
/// the PNG encoder happens to drop it, and "happens to" is not a guarantee
/// worth resting a child's home address on. So it is cleared explicitly.
///
/// Returns null if the bytes are not a decodable image.
NormalizedImage? normalizeSymbolImage(Uint8List bytes) {
  // decodeImage is documented to return null for unrecognized data but throws
  // a RangeError on anything short enough that its format sniffing reads off
  // the end. A truncated download or a file the picker mis-reports must be a
  // declined import, not a crash.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;

  // Bake before stripping. EXIF orientation is the only record that a photo is
  // rotated, so discarding it without applying it stores the picture sideways.
  var image = img.bakeOrientation(decoded);

  final longestEdge = image.width > image.height ? image.width : image.height;
  if (longestEdge > customSymbolMaxEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: customSymbolMaxEdge)
        : img.copyResize(image, height: customSymbolMaxEdge);
  }

  image.exif = img.ExifData();
  // PNG carries arbitrary tEXt chunks through re-encoding too, and a phone
  // gallery export can put author or location strings in them.
  image.textData = null;

  return (
    bytes: img.encodePng(image),
    width: image.width,
    height: image.height,
  );
}

/// Imports a photograph from the device as a symbol.
///
/// Caregivers use this for the things no pack has: this cup, this dog, this
/// support worker. Files land in application documents rather than the cache,
/// because the OS evicts caches and a personal symbol cannot be re-fetched
/// from anywhere.
class CustomSymbolImporter {
  CustomSymbolImporter({
    required this.db,
    ImagePicker? picker,
    Future<Directory> Function()? documentsDirectory,
  }) : _picker = picker ?? ImagePicker(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final WordbridgeDatabase db;
  final ImagePicker _picker;
  final Future<Directory> Function() _documentsDirectory;

  /// Returns null if the caregiver canceled or the file could not be read.
  ///
  /// No `maxWidth` is passed to the picker: platform implementations differ on
  /// whether their own resize preserves EXIF, and the one part of this that
  /// must not vary by platform is the stripping.
  Future<Symbol?> importFrom(
    ImageSource source, {
    required String label,
  }) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return null;
    return store(await picked.readAsBytes(), label: label);
  }

  /// Normalizes, de-duplicates and records the image. Returns null if the
  /// bytes are not a decodable image.
  Future<Symbol?> store(Uint8List bytes, {required String label}) async {
    final normalized = normalizeSymbolImage(bytes);
    if (normalized == null) return null;

    // Hashing the normalized output rather than the original: the same photo
    // imported twice produces byte-identical output, so the hash both
    // de-duplicates and names the file.
    final hash = sha256.convert(normalized.bytes).toString();

    final existing =
        await (db.select(db.symbols)..where(
              (s) =>
                  s.contentHash.equals(hash) &
                  s.label.equals(label) &
                  s.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return existing;

    final directory = Directory(
      p.join((await _documentsDirectory()).path, 'symbols', 'custom'),
    );
    await directory.create(recursive: true);

    final file = File(p.join(directory.path, '$hash.png'));
    if (!await file.exists()) {
      await file.writeAsBytes(normalized.bytes, flush: true);
    }

    // A second row over the same file is intentional when the label differs:
    // one photograph can be both "Nana" and "grandma" without storing it twice.
    return db
        .into(db.symbols)
        .insertReturning(
          SymbolsCompanion.insert(
            id: newId(),
            source: SymbolSource.custom,
            localUri: Value(file.path),
            label: label,
            license: customSymbolLicense,
            attribution: customSymbolAttribution,
            contentHash: Value(hash),
            width: Value(normalized.width),
            height: Value(normalized.height),
            createdAt: nowMs(),
          ),
        );
  }
}
