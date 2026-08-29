import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/ids.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';

/// Setup must not offer a grid the seed will refuse.
///
/// The two used to ask different questions: setup asked whether the *frame*
/// fits, which is a size threshold, and the layout engine asks whether the
/// words a board must always reach have anywhere to go. They agreed at every
/// grid the app can produce but one — an iPad mini 5 or 10.2" held in
/// landscape with extra-large icons derives 4x6 — and there a caregiver
/// answered five questions, pressed "Build the board", and got an exception.
///
/// This is a whole-device sweep rather than a check of that one size, because
/// the failure was never about 4x6. It was about two rules for one question.
void main() {
  /// Real screens in logical pixels. The grid is derived from the device, so a
  /// combination that only exists on one tablet still ships to that tablet.
  const screens = <String, Size>{
    'iPad mini 5': Size(768, 1024),
    'iPad mini 6': Size(744, 1133),
    'iPad 10.2': Size(810, 1080),
    'iPad 10.9': Size(820, 1180),
    'iPad Pro 11': Size(834, 1194),
    'iPad Pro 12.9': Size(1024, 1366),
    'iPhone SE': Size(375, 667),
    'iPhone 15': Size(393, 852),
    'Pixel 7': Size(412, 915),
  };

  for (final screen in screens.entries) {
    for (final orientation in BoardOrientation.values) {
      for (final iconSize in IconSize.values) {
        final choice = GridChoice.derive(
          screen: screen.value,
          orientation: orientation,
          iconSize: iconSize,
        );

        test('${screen.key}, ${orientation.label.toLowerCase()}, '
            '${iconSize.label.toLowerCase()} icons '
            '(${choice.rows}x${choice.cols})', () async {
          final db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
          addTearDown(db.close);

          final ts = nowMs();
          await db
              .into(db.profiles)
              .insert(
                ProfilesCompanion.insert(
                  id: 'p1',
                  displayName: 'Maya',
                  createdAt: ts,
                  updatedAt: ts,
                ),
              );

          Object? thrown;
          try {
            await seedCoreBoardSet(
              db,
              rows: choice.rows,
              cols: choice.cols,
              profileId: 'p1',
            );
          } catch (error) {
            thrown = error;
          }

          expect(
            thrown,
            choice.isUsable ? isNull : isNotNull,
            reason: choice.isUsable
                ? 'setup offers ${choice.rows}x${choice.cols} and building the '
                      'board then throws: $thrown'
                : 'setup refuses ${choice.rows}x${choice.cols} that the seed '
                      'would have built, so a caregiver is denied a working '
                      'grid',
          );
        });
      }
    }
  }

  test('the refusal a caregiver reads names the size and the reason', () {
    final refused = GridChoice.derive(
      screen: const Size(768, 1024),
      orientation: BoardOrientation.landscape,
      iconSize: IconSize.extraLarge,
    );

    expect(refused.isUsable, isFalse);
    expect(refused.refusal, contains('4x6'));
    expect(refused.refusal, contains('Extra large'));
  });

  test('the fit check gives the same answer every time it is asked', () {
    // It is memoised, and the setup page asks it for every icon size on every
    // rebuild — including while a name is being typed.
    for (var i = 0; i < 3; i++) {
      expect(boardSetRefusal(rows: 4, cols: 6), isNotNull);
      expect(boardSetRefusal(rows: 7, cols: 12), isNull);
    }
  });
}
