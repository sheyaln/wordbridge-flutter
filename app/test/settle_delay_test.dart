import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/db/seed/core_board_set.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';

void main() {
  late WordbridgeDatabase db;
  late ProfileSettings settings;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
    await seedCoreBoardSet(db);
    settings = ProfileSettings(db, 'default');
    await settings.load();
  });

  tearDown(() async => db.close());

  test('a quarter of a second by default', () {
    // Long enough to catch a finger already on its way down, short enough not
    // to be felt by someone using the board at a normal pace. Half a second
    // was the first guess and read as the device thinking.
    expect(settings.settleDelay, const Duration(milliseconds: 250));
  });

  test('and every fallback agrees with it', () {
    // The number lives in four places: this getter and three widgets that
    // take it as a default for a build with no settings object. Written out
    // four times, changing one of them left a board pausing for one length
    // and its prediction strip for another.
    expect(settings.settleDelay, ProfileSettings.defaultSettleDelay);
  });

  test('zero turns it off completely', () async {
    // This is the one place something deliberately stands between a user and
    // speech. It has to be possible to remove it entirely, not merely to make
    // it small.
    await settings.set('settleDelayMs', 0);
    expect(settings.settleDelay, Duration.zero);
  });

  test('it is set in milliseconds and read back exactly', () async {
    await settings.set('settleDelayMs', 1250);
    expect(settings.settleDelay, const Duration(milliseconds: 1250));
  });

  test('it survives a reload', () async {
    await settings.set('settleDelayMs', 750);

    final reopened = ProfileSettings(db, 'default');
    await reopened.load();

    expect(reopened.settleDelay, const Duration(milliseconds: 750));
  });

  test('a setting that cannot be stored fails loudly', () async {
    // An update against a profile that is not there writes nothing and reports
    // success. Quietly discarding a caregiver's setting is the failure this
    // whole project is a reaction to.
    final orphan = ProfileSettings(db, 'nobody');
    await orphan.load();

    await expectLater(orphan.set('settleDelayMs', 250), throwsStateError);
  });

  test('going home after each word stays on unless it is turned off', () async {
    expect(settings.autoReturn, isTrue);

    await settings.set('autoReturn', false);
    expect(settings.autoReturn, isFalse);

    final reopened = ProfileSettings(db, 'default');
    await reopened.load();
    expect(reopened.autoReturn, isFalse);
  });
}
