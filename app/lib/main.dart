import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db/database.dart';
import 'features/auth/pin.dart';
import 'features/backup/backup_service.dart';
import 'features/backup/pre_migration.dart';
import 'features/profiles/grid_choice.dart';
import 'features/profiles/profile_repository.dart';
import 'features/profiles/profile_settings.dart';
import 'features/profiles/profile_setup.dart';
import 'features/speech/neural/neural_engine.dart';
import 'features/speech/speech_engine.dart';
import 'features/speech/voice_setup.dart';
import 'features/symbols/bundled_pack.dart';
import 'features/symbols/global_symbols_pack.dart';
import 'features/symbols/symbol_registry.dart';
import 'features/symbols/symbol_resolver.dart';
import 'features/symbols/system_emoji_pack.dart';
import 'features/talk/fallback_board.dart';
import 'features/talk/talk_screen.dart';
import 'features/usage/device_id.dart';
import 'features/usage/logger.dart';

/// The resolver every board on this device draws through.
///
/// Built here rather than inline so the one thing that is easy to leave out —
/// the symbol store — is stated once and can be checked. Without the store a
/// button falls back to the pack picture for its word, so a caregiver's chosen
/// picture is written and never drawn, and nothing says so.
SymbolResolver appSymbolResolver({
  required WordbridgeDatabase db,
  required SymbolRegistry registry,
}) => SymbolResolver(registry: registry, db: db);

/// Puts the fallback board behind every route a failure can take.
///
/// §5 non-negotiable 6. Flutter's own answer to a widget that throws is a red
/// box in debug and a grey one in release, which for a nonspeaking person is a
/// tablet that has stopped talking. Installed before [runApp] so a throw while
/// the first frame is being built is already covered.
///
/// The detail is passed through rather than swallowed: whoever is helping needs
/// something to report, and it is never the only thing on the screen.
void installFallbackBoard() {
  ErrorWidget.builder = (details) =>
      FallbackBoard(detail: details.exceptionAsString());
}

/// Waits for something the board cannot be drawn without, and ends at the
/// fallback board if it never arrives.
///
/// The app has two such waits — the database at startup, and a profile's
/// settings — and they fail the same way: a person holding a tablet that will
/// not talk. Written once so that neither can be given an error message
/// instead, which is what both of them used to do.
Widget awaiting<T>({
  required Future<T> future,
  required Widget Function(T value) then,
}) => FutureBuilder<T>(
  future: future,
  builder: (context, snapshot) {
    if (snapshot.hasError) return FallbackBoard(detail: '${snapshot.error}');
    if (snapshot.connectionState != ConnectionState.done) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return then(snapshot.data as T);
  },
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installFallbackBoard();
  runApp(const WordbridgeApp());
}

/// A profile's vocabulary level as it stands, not as it stood when the session
/// opened.
///
/// Every other per-user setting lives in `settingsJson` behind a
/// [ProfileSettings] listener, which the board is already subscribed to. This
/// one is a column, so it needs its own way in: raising it reveals words that
/// are already placed, and a caregiver who has to relaunch the app to see that
/// happen has no reason to believe it did.
///
/// Distinct because the same row carries every other setting, and a settings
/// write must not rebuild the board.
Stream<int> watchVocabLevel(WordbridgeDatabase db, String profileId) =>
    (db.select(db.profiles)..where((p) => p.id.equals(profileId)))
        .watchSingleOrNull()
        .where((profile) => profile != null)
        .map((profile) => profile!.vocabLevel)
        .distinct();

/// Puts a profile's stored voice on the engine.
///
/// Every field the caregiver chose travels together, the identifier included:
/// a device can carry two voices of the same name at different qualities, and
/// the identifier is the only thing that tells them apart. Left out, the
/// engine picks by quality order and the person is given a voice nobody
/// listened to.
Future<void> applyProfileVoice(
  SpeechEngine speech,
  ProfileSettings settings,
) async {
  await VoiceSetup(speech).apply(
    voiceName: settings.voiceName,
    voiceLocale: settings.voiceLocale,
    voiceIdentifier: settings.voiceIdentifier,
    rate: settings.speechRate,
    pitch: settings.speechPitch,
    volume: settings.speechVolume,
    tone: settings.tone,
  );

  // The neural voice sits on top of all of that rather than replacing it: what
  // it falls back to is the platform voice as configured above, so the two
  // have to be applied together and in this order. Opening a pack reads an
  // index file and loads no model, so a profile that has this on costs a
  // session no more to start than one that does not.
  if (speech is! NeuralSpeechEngine) return;
  try {
    await speech.useNeuralVoice(
      enabled: settings.neuralVoice,
      voiceId: settings.neuralVoiceId,
      speed: settings.speechRate,
    );
    speech.budget = settings.synthesisBudget;
  } catch (_) {
    // A cache that will not open is a board that speaks in the platform
    // voice, which is §4.4 and is a product. A session that will not start is
    // not.
  }
}

/// Holds the device to the aspect the board was built for.
///
/// The grid is derived once, from the orientation chosen at setup, and every
/// location is a permanent row from then on. Turning the tablet does not
/// re-derive it — it draws the same grid into a box of the opposite aspect, so
/// every cell changes width, height and position while keeping its row and its
/// column. That is the motor plan broken in the only units a hand knows, and it
/// arrives by the one route the invariant test cannot see, because not a word
/// has moved in the database.
///
/// Both ways up on the chosen axis. A left-handed mount and a right-handed one
/// are both landscape; it is the aspect that must not change, not which way up.
Future<void> applyProfileOrientation(ProfileSettings settings) =>
    SystemChrome.setPreferredOrientations(switch (settings.orientation) {
      BoardOrientation.landscape => const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      BoardOrientation.portrait => const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
    });

/// Everything a session puts on the device, and keeps on it.
///
/// One function rather than three lines in a State, because these are the
/// things that are inert if they are simply left out: the voice falls back to
/// whatever the OS picked and the tablet stays free to rotate, neither of which
/// reports a problem. Returns what undoes the part that outlives the call.
///
/// The lock is re-applied on every settings change, not set once. A caregiver
/// who changes the orientation rebuilds the board for the other aspect without
/// the session ending, and a device still held to the old one is the original
/// bug arrived at from the other direction.
Future<VoidCallback> openSession(
  SpeechEngine speech,
  ProfileSettings settings, {
  UsageLogger? logger,
}) async {
  await settings.load();
  await applyProfileVoice(speech, settings);
  await applyProfileOrientation(settings);
  applyUsageConsent(logger, settings);

  void reapply() {
    applyProfileOrientation(settings);
    applyUsageConsent(logger, settings);
  }

  settings.addListener(reapply);
  return () => settings.removeListener(reapply);
}

/// Puts the profile's recorded answer about usage onto the logger.
///
/// The logger holds consent in memory and starts every launch at off, so
/// without this a caregiver who switched recording on lost it the next time
/// the app opened — and the tap counts the editor warns with never accumulated
/// past a single session. The answer belongs to the profile (§7): it is one
/// person's speech, and switching profile switches it.
void applyUsageConsent(UsageLogger? logger, ProfileSettings settings) {
  if (logger == null) return;
  logger.enabled = settings.usageTracking;
}

class WordbridgeApp extends StatefulWidget {
  const WordbridgeApp({super.key});

  @override
  State<WordbridgeApp> createState() => _WordbridgeAppState();
}

class _WordbridgeAppState extends State<WordbridgeApp>
    with WidgetsBindingObserver {
  final _db = WordbridgeDatabase();
  // The platform engine is not replaced, it becomes the floor. Every profile
  // holds one of these; whether it has a neural voice on top is a per-profile
  // setting applied at session open.
  final _speech = NeuralSpeechEngine(FlutterTtsEngine());

  /// Built once the database is open, because the id it logs under is read
  /// from it. Nothing is offered a logger before `_bootstrap` has finished:
  /// the screen holds a spinner until it does.
  UsageLogger? _logger;
  late final _auth = PinAuth(_db);
  late final _profiles = ProfileRepository(_db);
  late final _backup = BackupService(_db);

  // The bundled pack covers the shipped vocabulary. The fetching one covers
  // everything a caregiver adds afterwards, from the same four CC BY-SA sets,
  // so a word somebody types today can have a picture today.
  //
  // The device's own emoji sit between the two: thousands of pictures, offline
  // and at no bundle cost, for the words nothing local covers. Ahead of the
  // fetching pack because a picture already on the device beats one that needs
  // a network to arrive.
  late final _globalSymbols = GlobalSymbolsPack();
  late final _symbols = SymbolRegistry(
    packs: [...bundledSymbolPacks(), SystemEmojiPack(), _globalSymbols],
  );
  late final _resolver = appSymbolResolver(db: _db, registry: _symbols);

  late Future<Profile?> _ready = _bootstrap();

  Future<Profile?> _bootstrap() async {
    await _speech.init();

    // Before `resume()`, which is the first query and therefore the thing that
    // opens the database and runs any migration due. Nothing has touched the
    // file yet, which is the condition `snapshotFile` cannot check for itself.
    await snapshotBeforeMigration(
      database: boardDatabaseFile,
      appVersion: _db.schemaVersion,
      backup: _backup,
    );

    // After the snapshot, because this is the first query and therefore the
    // thing that opens the database.
    _logger = UsageLogger(_db, deviceId: await deviceIdFor(_db));

    return _profiles.resume();
  }

  /// Called after setup, and after a caregiver switches profile.
  ///
  /// A block body, not an arrow: an arrow returns the value it assigned, and
  /// assigning a future makes the closure look asynchronous to `setState`,
  /// which then refuses it and leaves the app on whatever it was showing.
  void _use(Profile profile) {
    setState(() {
      _ready = Future.value(profile);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Anything buffered goes to disk before the OS can suspend or kill us.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _logger?.flush();
      // 833 MB resident, for a feature nothing in the background is using, on
      // a tablet with 3 GB. Holding it is how a communication device becomes
      // the app the OS kills to make room for something else. The cache does
      // not need it, so the board still speaks in the chosen voice when it
      // comes back.
      unawaited(_speech.releaseModel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logger?.dispose();
    _resolver.dispose();
    _globalSymbols.dispose();
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wordbridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      // The database would not open, or the speech engine would not start.
      // Printing the reason and stopping there hands somebody a tablet with an
      // error message where their voice was.
      home: awaiting<Profile?>(
        future: _ready,
        then: (profile) {
          if (profile == null) return _FirstRun(db: _db, onCreated: _use);

          // Keyed on the profile so switching rebuilds the whole screen rather
          // than leaving one person's board holding another person's settings.
          return _Session(
            key: ValueKey(profile.id),
            db: _db,
            profile: profile,
            speech: _speech,
            logger: _logger!,
            auth: _auth,
            resolver: _resolver,
            registry: _symbols,
            fetcher: _globalSymbols,
            onSwitchProfile: _use,
          );
        },
      ),
    );
  }
}

/// Nothing has been set up yet, so there is nobody to hand the device to.
class _FirstRun extends StatelessWidget {
  const _FirstRun({required this.db, required this.onCreated});

  final WordbridgeDatabase db;
  final void Function(Profile) onCreated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'wordbridge',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'A few questions about how this device will be used, then '
                  'your wordbridge board will be built.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () async {
                  final profile = await ProfileSetup.show(
                    context,
                    db: db,
                    isFirstRun: true,
                  );
                  if (profile != null) onCreated(profile);
                },
                child: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One profile's session: its own settings object, its own vocabulary.
class _Session extends StatefulWidget {
  const _Session({
    super.key,
    required this.db,
    required this.profile,
    required this.speech,
    required this.logger,
    required this.auth,
    required this.resolver,
    required this.registry,
    required this.fetcher,
    required this.onSwitchProfile,
  });

  final WordbridgeDatabase db;
  final Profile profile;
  final SpeechEngine speech;
  final UsageLogger logger;
  final PinAuth auth;
  final SymbolResolver resolver;
  final SymbolRegistry registry;
  final GlobalSymbolsPack fetcher;
  final void Function(Profile) onSwitchProfile;

  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  late final _settings = ProfileSettings(widget.db, widget.profile.id);
  late final Future<VoidCallback> _loaded = openSession(
    widget.speech,
    _settings,
    logger: widget.logger,
  );
  late final Stream<int> _vocabLevel = watchVocabLevel(
    widget.db,
    widget.profile.id,
  );

  @override
  void dispose() {
    // Already complete by the time a session ends. If it somehow is not, the
    // listener comes off a settings object nobody is holding any more.
    _loaded.then((close) => close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vocabularyId = widget.profile.activeVocabularyId;

    if (vocabularyId == null) {
      return const FallbackBoard(detail: 'This profile has no board set.');
    }

    // The settings would not load. Carrying on into the board from here draws
    // it against half-applied state, which is a worse failure than this one
    // because it looks like it worked.
    return awaiting<VoidCallback>(
      future: _loaded,
      then: (_) {
        return StreamBuilder<int>(
          stream: _vocabLevel,
          initialData: widget.profile.vocabLevel,
          builder: (context, level) => TalkScreen(
            db: widget.db,
            speech: widget.speech,
            vocabularyId: vocabularyId,
            logger: widget.logger,
            auth: widget.auth,
            resolver: widget.resolver,
            registry: widget.registry,
            fetcher: widget.fetcher,
            settings: _settings,
            profileId: widget.profile.id,
            userName: widget.profile.displayName,
            vocabLevel: level.data ?? widget.profile.vocabLevel,
            onSwitchProfile: widget.onSwitchProfile,
          ),
        );
      },
    );
  }
}
