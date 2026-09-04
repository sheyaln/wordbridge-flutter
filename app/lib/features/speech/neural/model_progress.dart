/// What installing the voice is doing, in the terms the screen says it in.
///
/// Shared by both hosts. A tablet downloads an archive, checks it against a
/// published digest and unpacks it; a browser fetches a directory of files
/// into its own cache. The phases are the same shape and the screen that shows
/// them is the same screen, so the enum belongs to neither side.
library;

enum ModelPhase {
  /// Bytes are arriving. Resumable — leaving the screen does not lose them.
  downloading,

  /// Checking what arrived is what was published, before it is unpacked.
  verifying,

  /// Decompressing. The slow half on an older tablet, and it cannot be
  /// resumed, only started again.
  unpacking,

  installed,

  /// Stopped with the reason in [ModelProgress.detail]. Whatever was
  /// downloaded is kept, so trying again does not start from nothing.
  failed,
}

typedef ModelProgress = ({
  ModelPhase phase,
  int bytes,
  int totalBytes,
  String? detail,
});
