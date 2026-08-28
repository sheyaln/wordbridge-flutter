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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WordbridgeApp());
}

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
  late final _resolver = SymbolResolver(registry: _symbols);

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

  /// Loads the settings and puts this profile's voice on the engine.
  ///
  /// Done here rather than at startup because the voice belongs to the person,
  /// not the device: switching profile has to change who the tablet sounds
  /// like, and a shared device that keeps the last user's voice is telling
  /// this one they are somebody else.
  Future<void> _open() async {
    await _settings.load();
    await VoiceSetup(widget.speech).apply(
      voiceName: _settings.voiceName,
      voiceLocale: _settings.voiceLocale,
      rate: _settings.speechRate,
      pitch: _settings.speechPitch,
      volume: _settings.speechVolume,
      tone: _settings.tone,
    );
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

        return TalkScreen(
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
          vocabLevel: widget.profile.vocabLevel,
          onSwitchProfile: widget.onSwitchProfile,
        );
      },
    );
  }
}
