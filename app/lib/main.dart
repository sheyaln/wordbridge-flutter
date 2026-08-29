import 'package:flutter/material.dart';

import 'db/database.dart';
import 'db/ids.dart';
import 'features/auth/pin.dart';
import 'features/profiles/profile_repository.dart';
import 'features/profiles/profile_settings.dart';
import 'features/profiles/profile_setup.dart';
import 'features/speech/speech_engine.dart';
import 'features/speech/voice_setup.dart';
import 'features/symbols/bundled_pack.dart';
import 'features/symbols/global_symbols_pack.dart';
import 'features/symbols/symbol_registry.dart';
import 'features/symbols/symbol_resolver.dart';
import 'features/talk/talk_screen.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
Future<void> applyProfileVoice(SpeechEngine speech, ProfileSettings settings) =>
    VoiceSetup(speech).apply(
      voiceName: settings.voiceName,
      voiceLocale: settings.voiceLocale,
      voiceIdentifier: settings.voiceIdentifier,
      rate: settings.speechRate,
      pitch: settings.speechPitch,
      volume: settings.speechVolume,
      tone: settings.tone,
    );

class WordbridgeApp extends StatefulWidget {
  const WordbridgeApp({super.key});

  @override
  State<WordbridgeApp> createState() => _WordbridgeAppState();
}

class _WordbridgeAppState extends State<WordbridgeApp>
    with WidgetsBindingObserver {
  final _db = WordbridgeDatabase();
  final _speech = FlutterTtsEngine();

  late final _logger = UsageLogger(_db, deviceId: newId());
  late final _auth = PinAuth(_db);
  late final _profiles = ProfileRepository(_db);

  // The bundled pack covers the shipped vocabulary. The fetching one covers
  // everything a caregiver adds afterwards, from the same four CC BY-SA sets,
  // so a word somebody types today can have a picture today.
  late final _globalSymbols = GlobalSymbolsPack();
  late final _symbols = SymbolRegistry(
    packs: [...bundledSymbolPacks(), _globalSymbols],
  );
  late final _resolver = appSymbolResolver(db: _db, registry: _symbols);

  late Future<Profile?> _ready = _bootstrap();

  Future<Profile?> _bootstrap() async {
    await _speech.init();
    return _profiles.resume();
  }

  /// Called after setup, and after a caregiver switches profile.
  void _use(Profile profile) {
    setState(() => _ready = Future.value(profile));
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
      _logger.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logger.dispose();
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
      home: FutureBuilder<Profile?>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text('Startup failed: ${snapshot.error}')),
            );
          }

          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final profile = snapshot.data;
          if (profile == null) return _FirstRun(db: _db, onCreated: _use);

          // Keyed on the profile so switching rebuilds the whole screen rather
          // than leaving one person's board holding another person's settings.
          return _Session(
            key: ValueKey(profile.id),
            db: _db,
            profile: profile,
            speech: _speech,
            logger: _logger,
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
                  'the your wordbridge board will be built.',
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
  late final Future<void> _loaded = _open();
  late final Stream<int> _vocabLevel = watchVocabLevel(
    widget.db,
    widget.profile.id,
  );

  /// Loads the settings and puts this profile's voice on the engine.
  ///
  /// Done here rather than at startup because the voice belongs to the person,
  /// not the device: switching profile has to change who the tablet sounds
  /// like, and a shared device that keeps the last user's voice is telling
  /// this one they are somebody else.
  Future<void> _open() async {
    await _settings.load();
    await applyProfileVoice(widget.speech, _settings);
  }

  @override
  Widget build(BuildContext context) {
    final vocabularyId = widget.profile.activeVocabularyId;

    if (vocabularyId == null) {
      return const Scaffold(
        body: Center(child: Text('This profile has no board set.')),
      );
    }

    return FutureBuilder<void>(
      future: _loaded,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

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
