import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/db/database.dart';
import 'package:wordbridge/features/profiles/grid_choice.dart';
import 'package:wordbridge/features/profiles/profile_repository.dart';
import 'package:wordbridge/features/profiles/profile_settings.dart';
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
  late WordbridgeDatabase db;

  setUp(() async {
    db = WordbridgeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<String> makeProfile({bool? usageTracking}) async {
    final profile = await ProfileRepository(db).create(
      displayName: 'Maya',
      grid: GridChoice.derive(
        screen: const Size(2048, 1536),
        orientation: BoardOrientation.landscape,
        iconSize: IconSize.medium,
      ),
      usageTracking: usageTracking ?? false,
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

    test('nothing said means off', () async {
      final id = await makeProfile();
      final settings = ProfileSettings(db, id);
      await settings.load();

      expect(settings.usageTracking, isFalse);
      expect(ProfileSettings.usageTrackingForNewProfiles, isFalse);
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
