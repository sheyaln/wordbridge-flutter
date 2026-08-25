import 'package:flutter/material.dart';

import 'db/database.dart';
import 'db/ids.dart';
import 'db/seed/core_board_set.dart';
import 'features/auth/pin.dart';
import 'features/profiles/profile_settings.dart';
import 'features/speech/speech_engine.dart';
import 'features/symbols/bundled_pack.dart';
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
  late final _settings = ProfileSettings(_db, 'default');

  late final _symbols = SymbolRegistry(packs: bundledSymbolPacks());
  late final _resolver = SymbolResolver(registry: _symbols);

  late final Future<String> _ready = _bootstrap();

  Future<String> _bootstrap() async {
    await _speech.init();

    final existing = await _db.select(_db.vocabularies).get();
    final vocabId = existing.isNotEmpty
        ? existing.first.id
        : await seedCoreBoardSet(_db);

    await _settings.load();
    return vocabId;
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
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wordbridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: FutureBuilder<String>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text('Startup failed: ${snapshot.error}')),
            );
          }
          final vocabId = snapshot.data;
          if (vocabId == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return TalkScreen(
            db: _db,
            speech: _speech,
            vocabularyId: vocabId,
            logger: _logger,
            auth: _auth,
            resolver: _resolver,
            registry: _symbols,
            settings: _settings,
          );
        },
      ),
    );
  }
}
