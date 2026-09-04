import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'model_progress.dart';

/// The engine, in a thread that is not the one drawing the board.
///
/// **This exists for the same reason `Isolate.run` does on a tablet.**
/// Synthesis is a blocking call into WebAssembly: measured on this model it
/// holds the thread for two to three seconds a word, and a page has one
/// thread. Run on it, the board stops drawing, stops taking taps, and — the
/// part that decides the architecture — cannot run the timer that gives up and
/// falls back to the browser's own voice. A board that will not answer and
/// will not give up either is worse than a slow one.
///
/// So the whole engine lives in a dedicated worker: the WebAssembly module,
/// the model in its filesystem, and the synthesis. Nothing crosses back but
/// samples, and those cross as a transferable rather than a copy.
///
/// One worker for the app, not one per caller. The installer and the voice are
/// the same 140 MB and the same engine, and a second copy of either would not
/// fit beside the first.
class KokoroWorker {
  KokoroWorker._();

  static final KokoroWorker instance = KokoroWorker._();

  /// Where the model is served from, as the page sees it.
  ///
  /// A release asset cannot be fetched directly: it is a `.tar.bz2` and
  /// nothing in a browser decompresses bzip2. `tools/fetch_web_voice.sh`
  /// unpacks it beside the build, and whoever serves the app serves these
  /// files too.
  static const manifestPath = String.fromEnvironment(
    'WORDBRIDGE_VOICE_URL',
    defaultValue: 'voice/kokoro-int8-en-v0_19/manifest.json',
  );

  /// The WebAssembly build and its wrappers, as Flutter lays a package's
  /// assets out. Fetched by the worker, not by this side.
  static const _sherpaAssets = 'assets/packages/sherpa_onnx_web/assets/';

  web.Worker? _worker;
  bool _loaded = false;
  int _nextId = 0;

  /// Requests waiting on a reply, by the id they were sent under.
  final _pending = <String, Completer<JSObject>>{};

  /// Whatever is listening to `progress` right now, if anything is.
  StreamController<ModelProgress>? _progress;

  bool get isLoaded => _loaded;

  /// The URL the worker resolves every model file against.
  ///
  /// Absolute, from the page's own base. A worker resolves a relative URL
  /// against its own script rather than against the document, and the two are
  /// only the same while the app sits at the root of an origin.
  static String get manifestUrl =>
      Uri.parse(web.document.baseURI).resolve(manifestPath).toString();

  static String get _sherpaBase =>
      Uri.parse(web.document.baseURI).resolve(_sherpaAssets).toString();

  web.Worker _open() {
    final existing = _worker;
    if (existing != null) return existing;

    final worker = web.Worker('kokoro_worker.js'.toJS);
    worker.onmessage = (web.MessageEvent event) {
      _receive(event.data as JSObject);
    }.toJS;
    // A worker that will not start answers here rather than by leaving every
    // request hanging.
    worker.onerror = (web.Event event) {
      _failAll('The neural voice worker could not be started.');
    }.toJS;
    return _worker = worker;
  }

  void _receive(JSObject message) {
    final type = (message.getProperty('type'.toJS) as JSString?)?.toDart;

    if (type == 'progress') {
      _progress?.add((
        phase:
            switch ((message.getProperty('phase'.toJS) as JSString?)?.toDart) {
              'installing' => ModelPhase.unpacking,
              _ => ModelPhase.downloading,
            },
        bytes: _int(message, 'bytes'),
        totalBytes: _int(message, 'totalBytes'),
        detail: null,
      ));
      return;
    }

    final id = (message.getProperty('id'.toJS) as JSString?)?.toDart;
    final waiting = id == null ? null : _pending.remove(id);
    if (waiting == null || waiting.isCompleted) return;

    if (type == 'error') {
      final detail =
          (message.getProperty('message'.toJS) as JSString?)?.toDart ??
          'The neural voice failed.';
      waiting.completeError(StateError(detail));
      return;
    }
    waiting.complete(message);
  }

  void _failAll(String reason) {
    for (final waiting in _pending.values) {
      if (!waiting.isCompleted) waiting.completeError(StateError(reason));
    }
    _pending.clear();
    _progress?.addError(StateError(reason));
    _loaded = false;
  }

  Future<JSObject> _send(String type, Map<String, JSAny?> fields) {
    final id = '${_nextId++}';
    final message = JSObject();
    message['type'] = type.toJS;
    message['id'] = id.toJS;
    for (final field in fields.entries) {
      message[field.key] = field.value;
    }

    final waiting = Completer<JSObject>();
    _pending[id] = waiting;
    _open().postMessage(message);
    return waiting.future;
  }

  /// How much of the model this browser is already holding.
  Future<({int cachedBytes, int totalBytes, bool complete})> status() async {
    final reply = await _send('status', {'manifestUrl': manifestUrl.toJS});
    return (
      cachedBytes: _int(reply, 'cachedBytes'),
      totalBytes: _int(reply, 'totalBytes'),
      complete:
          (reply.getProperty('complete'.toJS) as JSBoolean?)?.toDart ?? false,
    );
  }

  /// Fetches every file into the browser's cache, and stops there.
  ///
  /// Deliberately not a load. Somebody pressing download on a settings screen
  /// is paying for the bytes, not asking for 512 MB of engine to be stood up
  /// behind a screen they are about to leave.
  Stream<ModelProgress> warm() {
    final progress = _progress = StreamController<ModelProgress>.broadcast();

    unawaited(
      _send('warm', {'manifestUrl': manifestUrl.toJS})
          .then(
            (_) => progress.add((
              phase: ModelPhase.installed,
              bytes: 0,
              totalBytes: 0,
              detail: null,
            )),
          )
          .catchError((Object error) {
            progress.add((
              phase: ModelPhase.failed,
              bytes: 0,
              totalBytes: 0,
              detail: '$error',
            ));
          })
          .whenComplete(() {
            if (identical(_progress, progress)) _progress = null;
            progress.close();
          }),
    );

    return progress.stream;
  }

  /// Stands the engine up: module, model, filesystem, voice.
  Future<({int sampleRate, int numSpeakers})> load() async {
    final reply = await _send('load', {
      'manifestUrl': manifestUrl.toJS,
      'sherpaBase': _sherpaBase.toJS,
    });
    _loaded = true;
    return (
      sampleRate: _int(reply, 'sampleRate'),
      numSpeakers: _int(reply, 'numSpeakers'),
    );
  }

  /// One synthesis. Queued in the worker; answered in order.
  Future<({Float32List samples, int sampleRate})> generate({
    required String text,
    required int sid,
    required double speed,
  }) async {
    final reply = await _send('generate', {
      'text': text.toJS,
      'sid': sid.toJS,
      'speed': speed.toJS,
    });
    return (
      samples: (reply.getProperty('samples'.toJS) as JSFloat32Array).toDart,
      sampleRate: _int(reply, 'sampleRate'),
    );
  }

  /// Gives the engine's memory back, and keeps the download.
  Future<void> unload() async {
    if (!_loaded) return;
    _loaded = false;
    try {
      await _send('unload', const {});
    } catch (_) {
      // Nothing above this can do anything about a worker that will not let
      // go, and the memory comes back when the page does.
    }
  }

  /// Throws the download away.
  Future<void> evict() async {
    _loaded = false;
    await _send('evict', const {});
  }

  static int _int(JSObject message, String field) =>
      (message.getProperty(field.toJS) as JSNumber?)?.toDartInt ?? 0;
}
