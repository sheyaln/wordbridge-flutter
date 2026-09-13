import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_vocabulary.dart';
import 'package:wordbridge/features/backup/recovery.dart';
import 'package:wordbridge/features/backup/snapshot.dart';
import 'package:wordbridge/features/speech/speech_engine.dart';
import 'package:wordbridge/features/talk/fallback_board.dart';
import 'package:wordbridge/main.dart';

class _RecordingSpeech implements SpeechEngine {
  final spoken = <String>[];
  var started = false;

  @override
  Future<void> init() async => started = true;
  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> speakUtterance(String text) => speak(text);
  @override
  Future<void> stop() async {}
  @override
  Future<List<VoiceOption>> voices() async => const [];
  @override
  Future<void> useVoice(VoiceOption voice) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVolume(double volume) async {}
}

/// A widget that throws where the board would be.
class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => throw StateError('the board broke');
}

/// §5 non-negotiable 6: a crash never leaves a user with nothing.
///
/// What Flutter does by default is a red box in debug and a gray one in
/// release. For a nonspeaking person that is a tablet that has stopped talking,
/// and there is no way for them to say so.
void main() {
  test('it speaks the words the board would never page away', () {
    // The two lists are written separately — this board cannot read the
    // vocabulary, because it exists for the case where reading things has
    // stopped working — so something has to hold them together. A word marked
    // essential is one a grid too small to hold it is refused over; that is the
    // same question this board is asking.
    final essential = {
      for (final band in homeBands)
        for (final item in band.items)
          if (item.essential) item.value.label,
      for (final item in pinnedQuestions)
        if (item.essential) item.value.label,
    };

    expect(
      fallbackWords.toSet(),
      essential,
      reason:
          'the crash board and the seed disagree about which words a person '
          'cannot be left without',
    );
  });

  testWidgets('a widget that throws is replaced, not reported', (tester) async {
    // Restored inside the body, not in a tearDown: the framework checks that a
    // test left ErrorWidget.builder alone, and it checks before tearDowns run.
    final was = ErrorWidget.builder;
    try {
      installFallbackBoard();
      await tester.pumpWidget(const MaterialApp(home: _Broken()));

      // The framework records the throw as well as rendering the replacement,
      // and an unconsumed record fails the test on its own.
      expect(tester.takeException(), isA<StateError>());

      expect(find.text('help'), findsOneWidget);
      expect(
        find.textContaining('Something went wrong'),
        findsOneWidget,
        reason:
            'an unfamiliar board with nothing said about it reads as a board '
            'that rearranged itself, which is the one thing this app never '
            'does',
      );
    } finally {
      ErrorWidget.builder = was;
    }
  });

  testWidgets('every word on it speaks', (tester) async {
    final speech = _RecordingSpeech();
    await tester.pumpWidget(FallbackBoard(speech: speech));

    for (final word in fallbackWords) {
      await tester.tap(find.text(word));
      await tester.pump();
    }

    expect(speech.spoken, fallbackWords);
    expect(speech.started, isTrue);
  });

  testWidgets('it draws with no ancestors at all', (tester) async {
    // ErrorWidget.builder inserts this wherever the throw happened, which can
    // be above the widget that would have provided a theme or a text
    // direction. A fallback board that needs a MaterialApp to render is one
    // that fails exactly when the MaterialApp is what failed.
    await tester.pumpWidget(FallbackBoard(speech: _RecordingSpeech()));

    expect(tester.takeException(), isNull);
    expect(find.text('stop'), findsOneWidget);
  });

  group('a wait the board cannot be drawn without', () {
    testWidgets('ends at the fallback board when it fails', (tester) async {
      // An error message where somebody's voice was is not an outcome this app
      // has. Every wait the board cannot be drawn without ends here.
      final failing = Future<int>.error(StateError('no database'));

      // Given something to catch it before the zone sees it as unhandled. The
      // rejection reaches the builder either way; without this the framework
      // records it and fails the test on the record alone.
      unawaited(failing.catchError((_) => 0));

      await tester.pumpWidget(
        MaterialApp(
          home: awaiting<int>(
            future: failing,
            then: (_) => const Text('the board'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('help'), findsOneWidget);
      expect(find.text('the board'), findsNothing);
    });

    testWidgets('shows the board when it arrives', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: awaiting<int>(
            future: Future<int>.value(1),
            then: (_) => const Text('the board'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('the board'), findsOneWidget);
      expect(find.text('help'), findsNothing);
    });
  });

  group('the way back to a backup', () {
    late _RecordingSpeech speech;

    setUp(() => speech = _RecordingSpeech());

    /// Inside the top left corner of a board drawn with no ancestors, which
    /// insets itself by 20 when there is no [MediaQuery] to ask.
    const corner = Offset(40, 40);

    Future<void> pumpBoard(
      WidgetTester tester,
      BoardRecovery? recovery, {
      VoidCallback? onRelaunch,
    }) async {
      await tester.pumpWidget(
        FallbackBoard(
          speech: speech,
          recovery: recovery,
          onRelaunch: onRelaunch,
        ),
      );
      await tester.pump();
    }

    Future<void> hold(WidgetTester tester, Duration duration) async {
      final gesture = await tester.startGesture(corner);
      // The first frame starts the clock the hold is counted against; the
      // second is the time passing.
      await tester.pump();
      await tester.pump(duration);
      await gesture.up();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('is not on a board that has none', (tester) async {
      await pumpBoard(tester, null);
      await hold(tester, recoveryHold * 2);

      expect(find.textContaining('hold the top left corner'), findsNothing);
      expect(find.text('Backups on this tablet'), findsNothing);
      expect(find.text('help'), findsOneWidget);
    });

    testWidgets('is on the board a failed database lands on', (tester) async {
      final failing = Future<int>.error(StateError('no database'));
      unawaited(failing.catchError((_) => 0));

      await tester.pumpWidget(
        MaterialApp(
          home: awaiting<int>(
            future: failing,
            then: (_) => const Text('the board'),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('hold the top left corner'),
        findsOneWidget,
        reason:
            'a caregiver who has never seen this screen has to be able to find '
            'the way back on it',
      );
    });

    testWidgets('stays shut for a touch that is not the gesture', (
      tester,
    ) async {
      final backups = _Backups(offering: [_option(DateTime.utc(2026, 8, 3))]);
      await pumpBoard(tester, backups);

      await tester.tapAt(corner);
      await tester.pump();
      await hold(tester, recoveryHold ~/ 2);

      expect(find.text('Backups on this tablet'), findsNothing);
      expect(
        find.text('help'),
        findsOneWidget,
        reason:
            'the person holding the tablet is using it to speak, and a way '
            'back they can reach mid-sentence is its own failure',
      );
    });

    testWidgets('opens on the held corner', (tester) async {
      final backups = _Backups(offering: [_option(DateTime.utc(2026, 8, 3))]);
      await pumpBoard(tester, backups);

      await hold(tester, recoveryHold + const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('Backups on this tablet'), findsOneWidget);
      expect(find.text('Back to the words'), findsOneWidget);
    });

    testWidgets('opens on the action assistive technology offers', (
      tester,
    ) async {
      // Switch access, VoiceOver and eye-gaze dwell cannot hold a corner, and
      // the way back must not be behind a hand some users do not have.
      final backups = _Backups(offering: [_option(DateTime.utc(2026, 8, 3))]);
      // Disposed inside the body: the framework checks that a test left no
      // semantics handle open, and it checks before tearDowns run.
      final handle = tester.ensureSemantics();
      try {
        await pumpBoard(tester, backups);

        tester.semantics.performAction(
          find.semantics.byLabel('Caregiver recovery'),
          SemanticsAction.customAction,
          args: CustomSemanticsAction.getIdentifier(recoveryAction),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Backups on this tablet'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('says there is nothing rather than offering nothing', (
      tester,
    ) async {
      await pumpBoard(tester, _Backups());
      await hold(tester, recoveryHold + const Duration(milliseconds: 50));
      await tester.pump();

      expect(
        find.textContaining('There are no backups on this tablet'),
        findsOneWidget,
      );
      expect(
        find.text('Build a new board'),
        findsOneWidget,
        reason: 'a board built from the seed beats fourteen words forever',
      );
    });

    testWidgets('names a backup this build cannot use, and will not take it', (
      tester,
    ) async {
      final backups = _Backups(
        offering: [_option(DateTime.utc(2026, 8, 3), version: 12)],
      );
      await pumpBoard(tester, backups);
      await hold(tester, recoveryHold + const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('Made by a newer version.'), findsOneWidget);

      await tester.tap(find.text(snapshotWhen(DateTime.utc(2026, 8, 3))));
      await tester.pump();

      expect(find.textContaining('Go back to'), findsNothing);
    });

    testWidgets('says which backup, from when, and what it replaces', (
      tester,
    ) async {
      final when = DateTime.utc(2026, 8, 3, 14, 22);
      await pumpBoard(tester, _Backups(offering: [_option(when)]));
      await hold(tester, recoveryHold + const Duration(milliseconds: 50));
      await tester.pump();

      await tester.tap(find.text(snapshotWhen(when)));
      await tester.pump();

      expect(find.text('Go back to ${snapshotWhen(when)}?'), findsOneWidget);
      expect(
        find.textContaining('is replaced by the one from'),
        findsOneWidget,
      );
      expect(find.textContaining('kept in the backups folder'), findsOneWidget);
    });

    testWidgets('puts the board back only on a second yes', (tester) async {
      final when = DateTime.utc(2026, 8, 3, 14, 22);
      final backups = _Backups(offering: [_option(when)]);
      var relaunched = 0;

      await pumpBoard(tester, backups, onRelaunch: () => relaunched++);
      await hold(tester, recoveryHold + const Duration(milliseconds: 50));
      await tester.pump();

      await tester.tap(find.text(snapshotWhen(when)));
      await tester.pump();
      expect(backups.restored, isEmpty);

      await tester.tap(find.text('Restore this backup'));
      await tester.pump();
      await tester.pump();

      expect(backups.restored, [when]);
      expect(find.textContaining('Restored the board from'), findsOneWidget);
      expect(
        find.textContaining('close Wordbridge AAC'),
        findsOneWidget,
        reason: 'the way back must not depend on the in-app relaunch working',
      );

      await tester.tap(find.text('Open the board'));
      expect(relaunched, 1);
    });

    testWidgets('reports a repair that will not happen', (tester) async {
      final backups = _Backups(refusal: 'The tablet is full.');
      await pumpBoard(tester, backups);
      await hold(tester, recoveryHold + const Duration(milliseconds: 50));
      await tester.pump();

      await tester.tap(find.text('Build a new board'));
      await tester.pump();
      await tester.tap(find.text('Build a new board').last);
      await tester.pump();
      await tester.pump();

      expect(backups.startedAgain, isTrue);
      expect(find.text('The tablet is full.'), findsOneWidget);
      expect(find.textContaining('Restored'), findsNothing);
    });

    testWidgets('leaves the words one tap away throughout', (tester) async {
      await pumpBoard(tester, _Unopenable());
      await hold(tester, recoveryHold + const Duration(milliseconds: 50));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the screen offering to repair the board may not be what takes it '
            'down',
      );
      expect(
        find.textContaining('could not be listed'),
        findsOneWidget,
        reason: 'a tablet that cannot even list its backups has to say so',
      );

      await tester.tap(find.text('Back to the words'));
      await tester.pump();
      await tester.tap(find.text('help'));
      await tester.pump();

      expect(speech.spoken, ['help']);
    });
  });

  group('a first run that cannot build a board', () {
    testWidgets('ends at the fallback board, not at the question', (
      tester,
    ) async {
      // The one moment §5 non-negotiable 6 has to cover without a board
      // behind it: nothing has been set up, so there is nothing to fall back
      // to but the words themselves.
      tester.view.physicalSize = const Size(2048, 1536);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // A full disk, a platform that will not say where documents live, a
      // read-only container: all of them arrive here as a board that cannot be
      // written.
      final db = WordbridgeDatabase.forTesting(
        NativeDatabase(File('/wordbridge-no-such-directory/board.sqlite')),
      );
      addTearDown(db.close);

      await tester.pumpWidget(
        MaterialApp(
          home: FirstRun(db: db, onCreated: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      final build = find.text('Build the board');
      await tester.ensureVisible(build);
      await tester.pumpAndSettle();
      await tester.tap(build);
      await tester.pumpAndSettle();

      expect(find.text('help'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
      expect(
        find.textContaining('hold the top left corner'),
        findsOneWidget,
        reason:
            'a board that was never built is the case a rebuild from scratch '
            'exists for',
      );
    });
  });

  testWidgets('a speech engine that throws does not take it down', (
    tester,
  ) async {
    await tester.pumpWidget(FallbackBoard(speech: _ThrowingSpeech()));
    await tester.tap(find.text('help'));
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'a crash inside the crash board leaves nowhere else to go',
    );
  });
}

/// The backups on a tablet, without the tablet.
///
/// `board_recovery_test.dart` is where the files themselves are tested. What
/// is being asked here is what a caregiver is shown, and when.
class _Backups extends BoardRecovery {
  _Backups({List<RecoveryOption>? offering, this.refusal})
    : offering = offering ?? const [],
      super(_noDatabase, appSchemaVersion: 9);

  static Future<File> _noDatabase() async => File('unused');

  final List<RecoveryOption> offering;

  /// What a repair comes back with, so a test can drive the refusal.
  final String? refusal;

  final restored = <DateTime>[];
  var startedAgain = false;

  @override
  Future<RecoveryOptions> options() async => (options: offering, problem: null);

  @override
  Future<RecoveryResult> restore(Snapshot snapshot) async {
    restored.add(snapshot.takenAt);
    return (done: refusal == null, problem: refusal);
  }

  @override
  Future<RecoveryResult> startAgain() async {
    startedAgain = true;
    return (done: refusal == null, problem: refusal);
  }
}

/// A backup that will not open, which is what makes it a way back.
class _Unopenable extends BoardRecovery {
  _Unopenable() : super(_Backups._noDatabase, appSchemaVersion: 9);

  @override
  Future<RecoveryOptions> options() => throw StateError('no documents');
}

RecoveryOption _option(DateTime takenAt, {int version = 9, int bytes = 4096}) {
  final snapshot = (
    path: '/backups/${snapshotFileName(takenAt)}',
    takenAt: takenAt,
    bytes: bytes,
    schemaVersion: version,
  );

  return version > 9
      ? (snapshot: snapshot, usable: false, refusal: 'Made by a newer version.')
      : (snapshot: snapshot, usable: true, refusal: null);
}

class _ThrowingSpeech extends _RecordingSpeech {
  @override
  Future<void> speak(String text) async => throw StateError('no voice');

  @override
  Future<void> speakUtterance(String text) => speak(text);
}
