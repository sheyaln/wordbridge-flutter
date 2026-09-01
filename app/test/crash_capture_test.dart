import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/reporting/crash_store.dart';
import 'package:wordbridge/main.dart';

/// §4.52. A fault is written down. Nothing else happens about it.
///
/// `installFallbackBoard` means a crash does not end the session — the person
/// holding this tablet still has a board. So there is no dialog, no upload and
/// no interruption: the record waits for the next time an adult opens
/// settings, which is the only moment when asking about a stack trace is not
/// the wrong thing at the wrong moment.
void main() {
  late _Recorded store;
  late FlutterExceptionHandler? wasFlutterError;
  late bool Function(Object, StackTrace)? wasPlatformError;

  setUp(() {
    store = _Recorded();
    wasFlutterError = FlutterError.onError;
    wasPlatformError = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = wasFlutterError;
    PlatformDispatcher.instance.onError = wasPlatformError;
  });

  test('a framework fault is recorded', () async {
    recordCaughtFaults(store);

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('no route'),
        stack: StackTrace.current,
      ),
    );
    await pumpEventQueue();

    expect(store.recorded, hasLength(1));
    expect('${store.recorded.single}', contains('no route'));
  });

  test('and so is one that escaped an async gap', () async {
    // The two handlers catch different things. A crash reporter wired only to
    // FlutterError.onError misses every unawaited future in the app, which is
    // most of the ones that matter here — speech, file writes, downloads.
    recordCaughtFaults(store);

    PlatformDispatcher.instance.onError!(
      StateError('nothing awaited this'),
      StackTrace.current,
    );
    await pumpEventQueue();

    expect('${store.recorded.single}', contains('nothing awaited this'));
  });

  test('the handler that was there still runs', () async {
    // Flutter's default handler is what prints a fault to the console during
    // development. Replacing it would trade a debugging tool for a file
    // nobody is looking at yet.
    var printed = 0;
    FlutterError.onError = (_) => printed++;

    recordCaughtFaults(store);
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
    await pumpEventQueue();

    expect(printed, 1);
    expect(store.recorded, hasLength(1));
  });

  test('and so does the platform one, with its answer kept', () async {
    var seen = 0;
    PlatformDispatcher.instance.onError = (_, _) {
      seen++;
      return false;
    };

    recordCaughtFaults(store);
    final handled = PlatformDispatcher.instance.onError!(
      StateError('x'),
      StackTrace.current,
    );
    await pumpEventQueue();

    expect(seen, 1);
    expect(
      handled,
      isFalse,
      reason: 'the answer of the handler underneath was overwritten',
    );
  });

  test('with nothing underneath, the fault counts as handled', () async {
    // Returning false here would let the fault go on to crash the isolate,
    // which for a nonspeaking person is a tablet that stopped talking.
    PlatformDispatcher.instance.onError = null;
    recordCaughtFaults(store);

    expect(
      PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.current),
      isTrue,
    );
  });
}

class _Recorded extends CrashStore {
  final recorded = <Object>[];

  @override
  Future<void> record(Object error, StackTrace? trace, {DateTime? at}) async =>
      recorded.add(error);
}
