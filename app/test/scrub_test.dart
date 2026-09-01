import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/reporting/scrub.dart';

/// §4.52. A stack trace is not evidence that it is safe to send.
///
/// This codebase throws messages that quote board and word names on purpose,
/// because they are read by a caregiver looking at the screen. That makes an
/// exception message the easiest place in the project to leak a disabled
/// person's private speech, and the reason a trace is never forwarded as it
/// was thrown.
void main() {
  group('what is taken out', () {
    test('a board name a refusal quoted', () {
      // Real: refusalToMoveRow builds exactly this sentence.
      const thrown =
          'Bad state: Row 3 of "Maya’s favorites" already holds 4 words.';

      final out = scrubbed(thrown);
      expect(out, isNot(contains('favorites')));
      expect(out, contains('Bad state'), reason: 'the useful half went too');
      expect(out, contains(redacted));
    });

    test('a word name, wherever in the line it is', () {
      final out = scrubbed('refusalToPin: "grandma" is already pinned');
      expect(out, isNot(contains('grandma')));
    });

    test('and a single-quoted one, which Dart uses just as often', () {
      final out = scrubbed("Invalid argument(s): 'toilet' is not a verb");
      expect(out, isNot(contains('toilet')));
    });

    test('a path with the account name in it', () {
      const thrown =
          'FileSystemException: Cannot open file, path = '
          '/Users/someone/Library/wordbridge.sqlite';

      final out = scrubbed(thrown);
      expect(out, isNot(contains('someone')));
      expect(out, contains('<path>'));
    });

    test('and an iOS container path, UUID and all', () {
      final out = scrubbed(
        '/private/var/mobile/Containers/Data/Application/'
        'A1B2C3D4-0000-0000-0000-000000000000/Documents/backups',
      );
      expect(out, isNot(contains('A1B2C3D4')));
      expect(out, contains('<path>'));
    });
  });

  group('what survives, because a report of nothing helps nobody', () {
    test('the frames', () {
      const trace =
          '#0      moveRow (package:wordbridge/features/editor/row_move.dart:250)\n'
          '#1      _BoardEditorState.build (package:wordbridge/features/editor/board_editor.dart:88)';

      final out = scrubbed(trace);
      expect(out, contains('moveRow'));
      expect(out, contains('row_move.dart:250'));
      expect(out, contains('_BoardEditorState.build'));
    });

    test('and a package path is not mistaken for a filesystem one', () {
      // "package:" paths name our own code and contain nothing private. A
      // scrubber that ate them would leave a trace with no frames in it.
      final out = scrubbed(
        '#0 x (package:wordbridge/features/talk/talk_screen.dart:12)',
      );
      expect(
        out,
        contains('package:wordbridge/features/talk/talk_screen.dart'),
      );
    });
  });

  group('length', () {
    test('a long trace is cut, and says it was', () {
      final out = scrubbed('#0 frame\n' * 5000, limit: 200);
      expect(out.length, lessThan(300));
      expect(out, contains('truncated'));
    });

    test('a short one is left alone', () {
      expect(scrubbed('Bad state: no'), 'Bad state: no');
    });
  });

  group('the last check before the network', () {
    test('refuses a report that still names the person', () {
      expect(
        refusalToSend('something failed near Maya', names: ['Maya']),
        contains('name from this profile'),
      );
    });

    test('and does not care about capitalization', () {
      expect(refusalToSend('near MAYA', names: ['maya']), isNotNull);
    });

    test('but lets an ordinary trace through', () {
      expect(refusalToSend('Bad state: no route', names: ['Maya']), isNull);
    });

    test('and ignores a name too short to be one', () {
      // A two-letter profile name would match inside half the words in a
      // trace, and a report nobody can ever send is a report nobody sends.
      // The detail here contains "jo", so only the length guard lets it past.
      expect(refusalToSend('Bad state: join failed', names: ['Jo']), isNull);
    });

    test('and has nothing to say about a report with no detail', () {
      expect(refusalToSend(null, names: ['Maya']), isNull);
    });

    test('and checks every name it was given, not just the first', () {
      expect(refusalToSend('near Rosie', names: ['Maya', 'Rosie']), isNotNull);
    });
  });
}
