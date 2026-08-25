import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/tables.dart';
import '../editor/board_editor.dart';
import '../usage/logger.dart';
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
    this.userName,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final UsageLogger logger;
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
          userName: widget.userName,
        ),
        1 => UsageSummary(
          db: widget.db,
          profileId: widget.profileId,
          logger: widget.logger,
        ),
        _ => _Settings(logger: widget.logger, onChanged: () => setState(() {})),
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
  const _Boards({required this.db, required this.vocabularyId, this.userName});

  final WordbridgeDatabase db;
  final String vocabularyId;
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

class _Settings extends StatelessWidget {
  const _Settings({required this.logger, required this.onChanged});

  final UsageLogger logger;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SwitchListTile(
          value: logger.enabled,
          title: const Text('Record what gets said'),
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
      ],
    );
  }
}
