import 'package:flutter/material.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/tables.dart';
import '../editor/board_editor.dart';
import '../profiles/profile_settings.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import '../usage/logger.dart';
import '../symbols/symbol_credits.dart';
import '../usage/usage_summary.dart';

/// Everything behind the PIN.
///
/// Reachable only through a sustained corner press plus a PIN, and never
/// persisted — backgrounding the app or a cold start returns to the
/// communication view.
class CaregiverHome extends StatefulWidget {
  const CaregiverHome({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    required this.logger,
    this.settings,
    this.registry,
    this.resolver,
    this.userName,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final UsageLogger logger;
  final ProfileSettings? settings;
  final SymbolRegistry? registry;
  final SymbolResolver? resolver;
  final String? userName;

  @override
  State<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends State<CaregiverHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Back to talking',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: switch (_tab) {
        0 => _Boards(
          db: widget.db,
          vocabularyId: widget.vocabularyId,
          registry: widget.registry,
          resolver: widget.resolver,
          userName: widget.userName,
        ),
        1 => UsageSummary(
          db: widget.db,
          profileId: widget.profileId,
          logger: widget.logger,
        ),
        _ => _Settings(
          logger: widget.logger,
          settings: widget.settings,
          onChanged: () => setState(() {}),
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Boards'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Use'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _Boards extends StatelessWidget {
  const _Boards({
    required this.db,
    required this.vocabularyId,
    this.registry,
    this.resolver,
    this.userName,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final SymbolRegistry? registry;
  final SymbolResolver? resolver;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Board>>(
      stream: (db.select(
        db.boards,
      )..where((b) => b.vocabularyId.equals(vocabularyId))).watch(),
      builder: (context, snapshot) {
        final boards = snapshot.data;
        if (boards == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New board'),
              subtitle: const Text(
                'For a sub-category, or another page of an existing one',
              ),
              onTap: () => _createBoard(context),
            ),
            const Divider(),
            for (final board in boards)
              ListTile(
                leading: Icon(
                  board.kind == BoardKind.root ? Icons.home : Icons.folder,
                ),
                title: Text(board.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BoardEditor(
                      db: db,
                      vocabularyId: vocabularyId,
                      boardId: board.id,
                      registry: registry,
                      resolver: resolver,
                      userName: userName,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

extension on _Boards {
  /// Creates an empty board.
  ///
  /// Every location is materialised at once, so the board is a full grid of
  /// reserved cells from the moment it exists. Nothing has to shuffle when
  /// words are added to it later — which is the point of creating one rather
  /// than packing more into an existing board.
  Future<void> _createBoard(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New board'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name, e.g. "breakfast"'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    await materialiseBoard(
      db,
      vocabularyId: vocabularyId,
      name: name.trim(),
      kind: BoardKind.category,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created "${name.trim()}". Put a word on another board and choose '
            '"Move to another board", or add a button that opens it.',
          ),
        ),
      );
    }
  }
}

class _Settings extends StatelessWidget {
  const _Settings({
    required this.logger,
    required this.settings,
    required this.onChanged,
  });

  final UsageLogger logger;
  final ProfileSettings? settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (settings != null)
          SwitchListTile(
            value: settings!.contextualGrammar,
            title: const Text('Show word endings only when they fit'),
            subtitle: const Text(
              'With this on, "+ed" appears once there is a verb to attach it '
              'to and is hidden otherwise. It always returns to the same '
              'place. Turn it off to keep every key visible at all times.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('contextualGrammar', v);
              onChanged();
            },
          ),
        if (settings != null)
          SwitchListTile(
            value: settings!.filterVerbs,
            title: const Text('Hide other verbs after a verb'),
            subtitle: const Text(
              'After "I want", the other verbs disappear until "to" or a '
              'modal makes a second verb possible. Less clutter mid-sentence, '
              'but the board changes shape while it is being used.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('filterVerbs', v);
              onChanged();
            },
          ),
        const Divider(),
        SwitchListTile(
          value: logger.enabled,
          title: const Text('Track word usage'),
          subtitle: const Text('Stays on this device. Off by default.'),
          onChanged: (v) {
            logger.enabled = v;
            onChanged();
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Recording is what lets wordbridge tell you how much practice a '
            'position has had before you move it. With it off, the editor '
            'still works but cannot warn you.',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text('Symbol credits'),
          subtitle: const Text('Who made the pictures, and their licences'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SymbolCredits()),
          ),
        ),
      ],
    );
  }
}
