import 'package:flutter/material.dart';

import 'db/database.dart';
import 'db/seed/core_board_set.dart';
import 'features/speech/speech_engine.dart';
import 'features/talk/talk_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WordbridgeApp());
}

class WordbridgeApp extends StatefulWidget {
  const WordbridgeApp({super.key});

  @override
  State<WordbridgeApp> createState() => _WordbridgeAppState();
}

class _WordbridgeAppState extends State<WordbridgeApp> {
  final _db = WordbridgeDatabase();
  final _speech = FlutterTtsEngine();

  late final Future<String> _ready = _bootstrap();

  Future<String> _bootstrap() async {
    await _speech.init();

    final existing = await _db.select(_db.vocabularies).get();
    if (existing.isNotEmpty) return existing.first.id;

    return seedCoreBoardSet(_db);
  }

  @override
  void dispose() {
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
          return TalkScreen(db: _db, speech: _speech, vocabularyId: vocabId);
        },
      ),
    );
  }
}
