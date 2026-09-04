import 'dart:async';

import 'kokoro_worker.dart';
import 'model_progress.dart';

/// A model release, named rather than assumed.
///
/// The tablet's record carries a URL, a digest and an archive root because it
/// fetches one file and has to prove what arrived. A browser fetches a
/// directory listed by its own manifest, and the manifest is what says which
/// files those are — so what is left to state here is the two numbers a person
/// deciding needs before they start.
typedef PublishedModel = ({
  /// Which release these numbers describe. Shown nowhere; it is here so a
  /// mismatch between this and the manifest is greppable rather than
  /// mysterious.
  String release,

  /// What it costs somebody's data allowance. Less where the files are served
  /// with compression, which the ONNX weights take well.
  int downloadBytes,

  /// What the browser then holds. The same bytes — nothing is unpacked here,
  /// because `tools/fetch_web_voice.sh` already did that.
  int installedBytes,
});

/// Kokoro-82M v0.19 at int8, unpacked beside the app.
///
/// **int8 rather than the tablet's fp32, and the reason is the network.** The
/// fp32 weights are 319 MB compressed and are measurably *faster* to run —
/// wasm has no int8 dot product, so quantisation costs more than it saves. But
/// the first-run download is what decides whether somebody sees the app at
/// all, and 141 MB against 352 MB is the difference between trying it and
/// closing the tab. The eleven voices are the same eleven.
const kokoroInt8V019 = (
  release: 'kokoro-int8-en-v0_19',
  downloadBytes: 140800000,
  installedBytes: 140800000,
);

/// Whether the voice is here. There are no paths to hand anybody.
///
/// The engine reads its own files, in the worker, straight into the module's
/// filesystem — so nothing on this side ever holds one. What the engine needs
/// from this type is the single fact that the download finished.
class VoiceModelFiles {
  const VoiceModelFiles({required this.arePresent});

  final bool arePresent;
}

/// Fetches the voice into the browser's cache, and reports on it.
///
/// **The cache, not a file, and it is the browser's.** Everything else here is
/// a consequence of that: nothing can be resumed byte by byte, nothing can be
/// checked against a digest after the fact, and clearing site data takes it
/// away without asking. The upside is that the second visit costs nothing,
/// which on 141 MB is the difference that matters.
///
/// The work happens in the worker rather than here, because the worker is
/// where the files are wanted and a second copy of the fetch on this side
/// would be 141 MB the page held for no reason.
class VoiceModelStore {
  VoiceModelStore({this.published = kokoroInt8V019});

  final PublishedModel published;

  final _worker = KokoroWorker.instance;

  Future<VoiceModelFiles> files() async =>
      VoiceModelFiles(arePresent: await isInstalled());

  Future<bool> isInstalled() async {
    try {
      return (await _worker.status()).complete;
    } catch (_) {
      return false;
    }
  }

  /// How much of the download this browser is already holding.
  ///
  /// Zero once it is complete, matching the tablet: the number is shown beside
  /// "resume", and a finished download has nothing to resume.
  Future<int> downloadedBytes() async {
    try {
      final status = await _worker.status();
      return status.complete ? 0 : status.cachedBytes;
    } catch (_) {
      return 0;
    }
  }

  Future<int> bytesOnDisk() async {
    try {
      return (await _worker.status()).cachedBytes;
    } catch (_) {
      return 0;
    }
  }

  Future<void> deleteModel() async {
    try {
      await _worker.evict();
    } catch (_) {
      // A cache that will not empty is disk somebody wanted back and did not
      // get. It is not a voice that has stopped working, and there is nothing
      // further this can do about it.
    }
  }

  /// The install running right now, if one is.
  bool get isInstalling => _running != null;
  Stream<ModelProgress>? _running;

  /// The last thing the running install said, for a screen that arrived late.
  ModelProgress? get installProgress => _last;
  ModelProgress? _last;

  /// Fetches every file into the cache.
  ///
  /// Owned here rather than by whoever asked for it, and broadcast, so that a
  /// caregiver leaving the screen does not cancel a download the same screen
  /// told them was safe to leave.
  Stream<ModelProgress> install() {
    final running = _running;
    if (running != null) return running;

    final controller = StreamController<ModelProgress>.broadcast();
    _running = controller.stream;

    _worker.warm().listen(
      (progress) {
        _last = progress;
        controller.add(progress);
        if (progress.phase == ModelPhase.installed ||
            progress.phase == ModelPhase.failed) {
          _running = null;
          controller.close();
        }
      },
      onError: (Object error) {
        _last = (
          phase: ModelPhase.failed,
          bytes: 0,
          totalBytes: 0,
          detail: 'The voice could not be downloaded. $error',
        );
        controller.add(_last!);
        _running = null;
        controller.close();
      },
    );

    return controller.stream;
  }
}
