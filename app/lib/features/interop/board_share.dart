import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

import 'board_files.dart';

/// Hands a board file to whatever this device offers for sending one somewhere,
/// answering with a sentence to show or null when there is nothing to say.
///
/// A function rather than a class so a widget test can pass one that records
/// the call. The real one reaches `UIActivityViewController` and Android's
/// chooser through a platform channel, and a test that touched it would wait on
/// a channel nothing answers.
typedef ShareBoardFile = Future<String?> Function(
  BoardFile file, {
  Rect? origin,
});

/// `.obf` and `.obz` have media types of their own and nothing on a tablet has
/// registered either, so a share target that filters on type drops the file
/// without saying why. Octet-stream is the type every target accepts; the
/// extension is what the receiving program actually reads.
const boardFileMimeType = 'application/octet-stream';

/// Opens the platform's share sheet on [file].
///
/// [origin] is where the sheet is anchored, which iPadOS requires — a popover
/// with nowhere to point is a crash rather than a sheet. Everything else
/// answers with a sentence: this is the one way off the tablet for a file
/// somebody has just spent an afternoon making, and a share sheet that cannot
/// open must not take the screen down with it.
Future<String?> shareBoardFile(BoardFile file, {Rect? origin}) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: boardFileMimeType)],
        subject: file.name,
        sharePositionOrigin: origin,
      ),
    );
    return result.status == ShareResultStatus.unavailable
        ? 'This device offered nowhere to send it. The file is still in the '
              'folder.'
        : null;
  } catch (e) {
    return 'That file could not be sent from here: $e';
  }
}
