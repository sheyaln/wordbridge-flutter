import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';

/// The device this is developed and tested against.
const iPadMini = Size(744, 1133);

/// A large tablet, where every icon size should be available.
const iPad13 = Size(1032, 1376);

/// A phone. Small enough that the largest icons cannot work.
const phone = Size(390, 844);

void main() {
  GridChoice choose(
    Size screen,
    BoardOrientation orientation,
    IconSize iconSize,
  ) => GridChoice.derive(
    screen: screen,
    orientation: orientation,
    iconSize: iconSize,
  );

  group('the shipped default', () {
    test('medium icons in landscape on an iPad mini give 7x12', () async {
      // The grid the app has always used, and the one the golden layout test
      // pins. Deriving it rather than hardcoding it has to land on the same
      // answer, or the default board moves for everyone.
      final choice = choose(
        iPadMini,
        BoardOrientation.landscape,
        IconSize.medium,
      );

      expect(choice.rows, defaultGridRows);
      expect(choice.cols, defaultGridCols);
      expect(choice.isUsable, isTrue);
    });
  });

  group('icon size trades vocabulary for target size', () {
    test('smaller icons fit more words', () {
      var previous = 0;
      for (final size in [
        IconSize.extraLarge,
        IconSize.large,
        IconSize.medium,
        IconSize.small,
      ]) {
        final choice = choose(iPadMini, BoardOrientation.landscape, size);
        expect(
          choice.locationsPerBoard,
          greaterThan(previous),
          reason: '${size.label} should hold more than the size above it',
        );
        previous = choice.locationsPerBoard;
      }
    });

    test('every size on an iPad mini in landscape is usable', () {
      for (final size in IconSize.values) {
        final choice = choose(iPadMini, BoardOrientation.landscape, size);
        expect(choice.isUsable, isTrue, reason: choice.refusal);
      }
    });
  });

  group('orientation is chosen, not sensed', () {
    test('the same device gives different grids for each orientation', () {
      final landscape = choose(
        iPadMini,
        BoardOrientation.landscape,
        IconSize.medium,
      );
      final portrait = choose(
        iPadMini,
        BoardOrientation.portrait,
        IconSize.medium,
      );

      expect(portrait.rows, greaterThan(landscape.rows));
      expect(portrait.cols, lessThan(landscape.cols));
    });

    test('holding the tablet the other way does not change the answer', () {
      // Orientation comes from the choice, never from the device. Answering
      // the setup question while holding the tablet upright must not silently
      // produce a different board.
      final asGiven = choose(
        iPadMini,
        BoardOrientation.landscape,
        IconSize.medium,
      );
      final rotated = choose(
        Size(iPadMini.height, iPadMini.width),
        BoardOrientation.landscape,
        IconSize.medium,
      );

      expect((rotated.rows, rotated.cols), (asGiven.rows, asGiven.cols));
    });
  });

  group('a combination that cannot work is refused', () {
    test('the largest icons do not fit an iPad mini in portrait', () {
      final choice = choose(
        iPadMini,
        BoardOrientation.portrait,
        IconSize.extraLarge,
      );

      expect(choice.isUsable, isFalse);
      expect(choice.refusal, contains('too small'));
    });

    test('the refusal names both the size and the orientation', () {
      // The caregiver has to know which of their two answers to change.
      final choice = choose(
        phone,
        BoardOrientation.portrait,
        IconSize.extraLarge,
      );

      expect(choice.refusal, contains('Extra large'));
      expect(choice.refusal, contains('portrait'));
    });

    test('a phone in landscape still manages the smaller sizes', () {
      expect(
        choose(phone, BoardOrientation.landscape, IconSize.small).isUsable,
        isTrue,
      );
    });
  });

  test('a large tablet offers every combination', () {
    for (final choice in GridChoice.options(iPad13)) {
      expect(choice.isUsable, isTrue, reason: choice.refusal);
    }
  });

  test('options covers every orientation and size', () {
    final options = GridChoice.options(iPadMini);
    expect(
      options,
      hasLength(BoardOrientation.values.length * IconSize.values.length),
    );
  });

  group('every device the app is offered on can build a board', () {
    // The app declares TARGETED_DEVICE_FAMILY "1,2", so the store offers it
    // to phones. A phone that installs it, walks a caregiver through setup and
    // then refuses every icon size is worse than one the store called
    // incompatible: the second is a disappointment in the App Store, the first
    // is a person who has been told this is their voice and cannot get a board
    // out of it.
    //
    // The floor is four rows by six columns. At 68pt an iPhone SE lays out
    // 3x9 in landscape and fails by exactly one row, which is why `extraSmall`
    // exists and why this group is the test that keeps it.
    const phones = {
      'iPhone SE 3': Size(375, 667),
      'iPhone 13 mini': Size(375, 812),
      'iPhone 15/16': Size(393, 852),
      'iPhone 16 Pro': Size(402, 874),
      'iPhone 16 Pro Max': Size(430, 932),
    };

    for (final entry in phones.entries) {
      test('${entry.key} has one it can use', () {
        final usable = GridChoice.options(entry.value)
            .where((o) => o.isUsable)
            .toList();

        expect(
          usable,
          isNotEmpty,
          reason:
              'setup on a ${entry.key} refuses every option, so the app '
              'installs and cannot produce a board',
        );
      });
    }

    test('and the smallest phone needs the smallest tier to get there', () {
      // Names why `extraSmall` is in the enum. If a later change makes 68pt
      // fit an SE, this fails and the tier can be reconsidered — which is the
      // only honest way to retire it.
      const se = Size(375, 667);
      final withoutExtraSmall = GridChoice.options(se)
          .where((o) => o.isUsable && o.iconSize != IconSize.extraSmall);

      expect(
        withoutExtraSmall,
        isEmpty,
        reason:
            'an iPhone SE can now build a board without the extra small tier',
      );
    });
  });

  test('cells end up at least as big as the size that was chosen', () {
    // The target is a floor, not a ceiling: leftover space is shared out
    // between the cells rather than left as margin, so the buttons a caregiver
    // asked for are never smaller than they asked for.
    for (final orientation in BoardOrientation.values) {
      for (final size in IconSize.values) {
        final choice = choose(iPadMini, orientation, size);
        if (!choice.isUsable) continue;

        expect(
          choice.cellEdge(iPadMini),
          greaterThanOrEqualTo(size.targetLogicalPixels - 1),
          reason: '${size.label} in ${orientation.label} came out too small',
        );
      }
    }
  });
}
