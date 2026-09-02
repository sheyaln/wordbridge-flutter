import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
import 'package:wordbridge/features/usage/device_id.dart';
import 'package:wordbridge/features/usage/logger.dart';
import 'package:wordbridge/main.dart';

/// Consent to being recorded, and whether it survives the app closing.
///
/// A usage log is a transcript of one person's private speech (§7), so the
/// answer is theirs, per profile, and off unless somebody said yes.
///
/// It used to live only in the logger, which builds fresh at every launch —
/// so a caregiver who switched recording on lost it overnight, and the tap
/// counts the editor warns a move with never accumulated past one session.
void main() {
  _telemetryTests();

  late WordbridgeDatabase db;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  /// Omits the argument entirely when nothing is said, so "nobody answered"
  /// exercises the repository's own default rather than a default this helper
  /// invented. It passed `?? false` once, which made the test that claimed to
  /// check the default actually check that an explicit no is stored — true,
  /// but not the thing it was named for.
  Future<String> makeProfile({bool? usageTracking}) async {
    final grid = GridChoice.derive(
      screen: const Size(2048, 1536),
      orientation: BoardOrientation.landscape,
      iconSize: IconSize.medium,
    );
    final repository = ProfileRepository(db);
    final profile = usageTracking == null
        ? await repository.create(displayName: 'Maya', grid: grid)
        : await repository.create(
            displayName: 'Maya',
            grid: grid,
            usageTracking: usageTracking,
          );
    return profile.id;
  }

  group('what setup was told', () {
    test('is written down, including when the answer was no', () async {
      final id = await makeProfile(usageTracking: false);
      final settings = ProfileSettings(db, id);
      await settings.load();

      expect(settings.usageTracking, isFalse);

      // Written, not absent. "Nobody was asked" and "somebody said no" are the
      // same to a getter with a default, and only one of them is consent.
      final row = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.settingsJson, contains('usageTracking'));
    });

    test('a yes is kept', () async {
      final id = await makeProfile(usageTracking: true);
      final settings = ProfileSettings(db, id);
      await settings.load();

      expect(settings.usageTracking, isTrue);
    });

    test('nothing said means on, and setup agrees', () async {
      // The default and the getter have to answer alike. They were separate
      // constants once, and a profile could be created tracking while the
      // getter reported it off.
      final id = await makeProfile();
      final settings = ProfileSettings(db, id);
      await settings.load();

      expect(settings.usageTracking, isTrue);
      expect(ProfileSettings.usageTrackingForNewProfiles, isTrue);
    });

    test('a no is still a no, and survives being reloaded', () async {
      // The point of the default moving: it must not be able to overwrite an
      // answer somebody gave. Off is a stored value, not an absent one.
      final id = await makeProfile(usageTracking: false);
      final settings = ProfileSettings(db, id);
      await settings.load();
      expect(settings.usageTracking, isFalse);

      final reloaded = ProfileSettings(db, id);
      await reloaded.load();
      expect(
        reloaded.usageTracking,
        isFalse,
        reason: 'a stored no must beat the default on every load',
      );
    });
  });

  /// §4.49. Which tablet a recording was made on.
  group('the device this was logged on', () {
    test('is made once and kept', () async {
      final first = await deviceIdFor(db);
      final second = await deviceIdFor(db);

      // The reason this exists. It was `newId()` at every launch, so
      // `usage_events.device_id` answered "which tablet" with the number of
      // times the app had been opened.
      expect(second, first);
      expect(first, isNotEmpty);
    });

    test('and survives the app being closed', () async {
      final first = await deviceIdFor(db);

      // A second run of the app over the same file.
      final reopened = await deviceIdFor(db);
      expect(reopened, first);
    });

    test('belongs to the tablet, not to a profile', () async {
      // Which tablet this is is not a fact about the person speaking on it,
      // so it sits in `app_state` beside the caregiver gesture rather than in
      // anybody's settings.
      final id = await deviceIdFor(db);
      final row = await (db.select(
        db.appState,
      )..where((s) => s.key.equals(deviceIdKey))).getSingle();

      expect(row.value, id);
    });

    test('and two tablets do not share one', () async {
      final other = WordbridgeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);

      expect(await deviceIdFor(other), isNot(await deviceIdFor(db)));
    });
  });

  group('the logger', () {
    test('starts every launch off, whatever was said before', () {
      // The reason this file exists. A logger knows nothing about a profile.
      final logger = UsageLogger(db, deviceId: 'test');
      addTearDown(logger.dispose);

      expect(logger.enabled, isFalse);
    });

    test('is given the profile’s answer when a session opens', () async {
      final id = await makeProfile(usageTracking: true);
      final settings = ProfileSettings(db, id);
      await settings.load();

      final logger = UsageLogger(db, deviceId: 'test');
      addTearDown(logger.dispose);
      expect(logger.enabled, isFalse, reason: 'the premise');

      applyUsageConsent(logger, settings);
      expect(logger.enabled, isTrue);
    });

    test('is switched back off for a profile that said no', () async {
      final id = await makeProfile(usageTracking: false);
      final settings = ProfileSettings(db, id);
      await settings.load();

      final logger = UsageLogger(db, deviceId: 'test')..enabled = true;
      addTearDown(logger.dispose);

      // Switching profile has to be able to turn it off as well as on: the
      // answer belongs to the person, and the logger outlives the session.
      applyUsageConsent(logger, settings);
      expect(logger.enabled, isFalse);
    });

    test('survives the answer being changed later', () async {
      final id = await makeProfile(usageTracking: false);
      final settings = ProfileSettings(db, id);
      await settings.load();

      await settings.set('usageTracking', true);

      // Read back through a second instance, which is what the next launch is.
      final reopened = ProfileSettings(db, id);
      await reopened.load();
      expect(reopened.usageTracking, isTrue);

      final logger = UsageLogger(db, deviceId: 'test');
      addTearDown(logger.dispose);
      applyUsageConsent(logger, reopened);
      expect(logger.enabled, isTrue);
    });
  });
}

/// §4.59. The two switches that decide what leaves this tablet on its own.
void _telemetryTests() {
  group('telemetry defaults', () {
    test('crash reports are on, and the constant agrees with the getter', () {
      // They were two constants once for usage tracking, and a profile could
      // be created tracking while the getter reported it off.
      expect(ProfileSettings.crashReportsForNewProfiles, isTrue);
    });

    test('voice measurements are off until somebody says yes', () {
      // Deliberately not crashReports' answer. One is "tell us the app broke",
      // the other is "measurements about the voice travel with it".
      expect(ProfileSettings.voiceMeasurementsForNewProfiles, isFalse);
    });
  });
}
