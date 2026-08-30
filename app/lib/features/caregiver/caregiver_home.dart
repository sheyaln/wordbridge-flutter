import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter/material.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/tables.dart';
import '../../db/ids.dart';
import '../../db/seed/age_presets.dart';
import '../../db/seed/vocabulary_top_up.dart';
import '../auth/caregiver_gesture.dart';
import '../backup/backup_service.dart';
import '../editor/board_delete.dart';
import '../editor/board_delete_sheet.dart';
import '../editor/board_editor.dart';
import '../editor/grid_change_screen.dart';
import '../editor/rebuild_sheet.dart';
import '../prediction/word_prediction.dart';
import '../speech/neural/neural_engine.dart';
import '../speech/neural/neural_voice.dart';
import '../speech/speech_engine.dart';
import '../profiles/profile_picker.dart';
import '../profiles/profile_settings.dart';
import '../symbols/global_symbols_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import '../usage/logger.dart';
import '../utterance/morphology.dart';
import '../symbols/symbol_credits.dart';
import '../usage/usage_summary.dart';
import 'backups_screen.dart';
import 'neural_voice_screen.dart';
import 'voice_screen.dart';

/// Everything behind the PIN.
///
/// Reachable only through a held gesture plus a PIN, and never persisted —
/// backgrounding the app or a cold start returns to the communication view.
class CaregiverHome extends StatefulWidget {
  const CaregiverHome({
    super.key,
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    required this.logger,
    this.speech,
    this.settings,
    this.registry,
    this.fetcher,
    this.resolver,
    this.userName,
    this.onSwitchProfile,
    this.backup,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final UsageLogger logger;
  final SpeechEngine? speech;
  final ProfileSettings? settings;
  final SymbolRegistry? registry;
  final GlobalSymbolsPack? fetcher;
  final SymbolResolver? resolver;
  final String? userName;
  final void Function(Profile)? onSwitchProfile;

  /// Where the backups are. Built from [db] when nothing supplies one, so the
  /// screen is wired by existing rather than by being passed down four levels;
  /// tests give it one pointed somewhere other than the documents directory.
  final BackupService? backup;

  @override
  State<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends State<CaregiverHome> {
  int _tab = 0;
  late final _backup = widget.backup ?? BackupService(widget.db);

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
          fetcher: widget.fetcher,
          resolver: widget.resolver,
          userName: widget.userName,
        ),
        1 => UsageSummary(
          db: widget.db,
          profileId: widget.profileId,
          logger: widget.logger,
        ),
        _ => _Settings(
          db: widget.db,
          vocabularyId: widget.vocabularyId,
          profileId: widget.profileId,
          logger: widget.logger,
          backup: _backup,
          speech: widget.speech,
          settings: widget.settings,
          onSwitchProfile: widget.onSwitchProfile,
          userName: widget.userName,
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
    this.fetcher,
    this.resolver,
    this.userName,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final SymbolRegistry? registry;
  final GlobalSymbolsPack? fetcher;
  final SymbolResolver? resolver;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Board>>(
      stream:
          (db.select(db.boards)
                ..where((b) => b.vocabularyId.equals(vocabularyId))
                ..where((b) => b.deletedAt.isNull()))
              .watch(),
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Offered on every board, including the ones that cannot
                    // go. The refusal names the reason; a control that is
                    // simply missing reads as a bug and explains nothing.
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove "${board.name}"',
                      onPressed: () => _deleteBoard(context, board),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BoardEditor(
                      db: db,
                      vocabularyId: vocabularyId,
                      boardId: board.id,
                      registry: registry,
                      fetcher: fetcher,
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

  /// Removes a board, or says why it cannot go.
  ///
  /// An empty board is one tap and a note afterwards: that is the case this
  /// exists for, and a confirmation for a board with nothing on it is a
  /// question with only one sensible answer. Everything else — words on it, a
  /// key that opens it, a board the frame depends on — goes through the sheet.
  Future<void> _deleteBoard(BuildContext context, Board board) async {
    final impact = await BoardDeletion.preview(db, boardId: board.id);
    if (!context.mounted) return;

    if (impact.canDelete && impact.isEmpty) {
      await BoardDeletion.apply(db, boardId: board.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Removed "${board.name}".')));
      return;
    }

    final proceed = await BoardDeleteSheet.show(
      context,
      impact: impact,
      userName: userName,
    );
    if (!proceed || !context.mounted) return;

    await BoardDeletion.apply(db, boardId: board.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed "${board.name}". Every recorded tap against its locations '
          'is still there.',
        ),
      ),
    );
  }
}

/// One section of the settings, and the row that stands for it in the list.
///
/// [description] is what makes the list worth reading: eight bare names say
/// little more than nothing, and a caregiver who has to guess opens all eight.
/// [state] carries the single fact a section is usually opened to check, where
/// there is one short enough to sit on the row — knowing which voice is set
/// should not cost a trip into a page and back.
class _Section {
  const _Section({
    required this.icon,
    required this.title,
    required this.description,
    required this.tiles,
    this.state,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? state;

  /// Built on demand rather than held, so a switch thrown on the page redraws
  /// with the value it now has.
  final List<Widget> Function(BuildContext context, VoidCallback onChanged)
  tiles;
}

/// One section, on a page of its own.
///
/// It redraws itself as well as telling the screen underneath, because the
/// list it was opened from is a route below and cannot redraw what sits on top
/// of it — a switch would otherwise stay where it was until the page was left.
///
/// Pops `true` when what was done on it took the board with it, which the list
/// follows out to the talk screen.
class _SectionPage extends StatefulWidget {
  const _SectionPage({
    required this.title,
    required this.tiles,
    required this.onChanged,
  });

  final String title;
  final List<Widget> Function(BuildContext context, VoidCallback onChanged)
  tiles;
  final VoidCallback onChanged;

  @override
  State<_SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<_SectionPage> {
  void _changed() {
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(children: widget.tiles(context, _changed)),
    );
  }
}

/// Which of the two ways the "am/is/are" and "was/were" keys behave.
///
/// One key holds three words, so something has to pick between them. Both
/// answers agree with a subject that is already there, and they part company
/// only at the start of a question, where there is nothing to agree with yet.
/// Naming each region of the board, and saying so when there is nothing to
/// name.
///
/// A board records which lines its bands own when it is built. One built
/// before that was recorded has nothing to read, so the switch would go on and
/// change nothing visible — which reads as a broken setting rather than as an
/// older board.
class _RegionLabels extends StatelessWidget {
  const _RegionLabels({
    required this.db,
    required this.vocabularyId,
    required this.settings,
    required this.onChanged,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final ProfileSettings settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Board>>(
      stream:
          (db.select(db.boards)
                ..where((b) => b.vocabularyId.equals(vocabularyId))
                ..where((b) => b.deletedAt.isNull()))
              .watch(),
      builder: (context, snapshot) {
        final boards = snapshot.data ?? const <Board>[];
        final labelled = boards.any((b) => b.bandMap != null);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: settings.regionLabels,
              title: const Text('Label what each part of the board is for'),
              subtitle: const Text(
                'A strip above the grid names each run of locations — who, '
                'doing, where, asking. The board groups words by their job '
                'and nothing on the grid says so, which is the first thing '
                'anyone teaching it has to explain. It takes its height from '
                'the grid, so every button is a little shorter while it is on.',
              ),
              isThreeLine: true,
              onChanged: (v) async {
                await settings.set('regionLabels', v);
                onChanged();
              },
            ),
            if (settings.regionLabels && boards.isNotEmpty && !labelled)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'These boards were built before they recorded which part is '
                  'which, so there is nothing yet to label. Rebuilding them '
                  'from the shipped vocabulary fills it in.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CopulaMode extends StatelessWidget {
  const _CopulaMode({required this.settings, required this.onChanged});

  final ProfileSettings settings;
  final VoidCallback onChanged;

  static const _descriptions = {
    CopulaMode.toggle:
        'The key gives "is", and pressing it again gives "are", then "am", '
        'each one spoken as it arrives and each one replacing the last. To '
        'ask "are you ok?", press it twice.',
    CopulaMode.agree:
        'The key gives "is" and corrects it once the subject arrives, so '
        '"is" then "you" becomes "are you" and the pair is spoken again. '
        'Fewer presses, but the word is heard before it is right.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          leading: Icon(Icons.change_history_outlined),
          title: Text('Choosing between "am", "is" and "are"'),
          subtitle: Text(
            'Both agree with a subject already in the sentence — "I" gives '
            '"am" either way. They differ when the question puts the verb '
            'first.',
          ),
          isThreeLine: true,
        ),
        RadioGroup<CopulaMode>(
          groupValue: settings.copulaMode,
          onChanged: (chosen) async {
            if (chosen == null) return;
            await settings.set('copulaMode', chosen.name);
            onChanged();
          },
          child: Column(
            children: [
              for (final mode in CopulaMode.values)
                RadioListTile<CopulaMode>(
                  value: mode,
                  title: Text(mode.label),
                  subtitle: Text(_descriptions[mode]!),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The settings, one section to a page.
///
/// Each control in here explains itself in a sentence or three, which is right
/// when you are reading one and hopeless when you are hunting for one. The
/// sections are already the shape a caregiver thinks in, so each is a page and
/// the top of the screen is eight lines that can be taken in at a glance —
/// which is what keeps it readable as more switches arrive.
class _Settings extends StatelessWidget {
  const _Settings({
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    required this.logger,
    required this.backup,
    required this.settings,
    required this.onChanged,
    this.speech,
    this.onSwitchProfile,
    this.userName,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final UsageLogger logger;
  final BackupService backup;
  final SpeechEngine? speech;
  final String? userName;
  final ProfileSettings? settings;
  final VoidCallback onChanged;
  final void Function(Profile)? onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // A section with nothing on it is not named. Several depend on a
        // profile, a speech engine, or more than one person existing, and a
        // row that opens onto an empty page is worse than no row.
        for (final section in _sections)
          if (section.tiles(context, onChanged).isNotEmpty)
            ListTile(
              leading: Icon(section.icon),
              title: Text(section.title),
              subtitle: Text(
                section.state == null
                    ? section.description
                    : '${section.description}\n${section.state}',
              ),
              isThreeLine: section.state != null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, section),
            ),
      ],
    );
  }

  /// Opens a section, and follows it out if what was done on it took the board
  /// with it.
  Future<void> _open(BuildContext context, _Section section) async {
    final boardGone = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _SectionPage(
          title: section.title,
          tiles: section.tiles,
          onChanged: onChanged,
        ),
      ),
    );

    if (boardGone == true && context.mounted) Navigator.of(context).pop();
  }

  /// The sections, in the order a caregiver has already learned to look in.
  ///
  /// Nothing moves between them and nothing is renamed. Where a switch lives
  /// is something people remember, and a rearrangement dressed up as a
  /// tidy-up costs them that for nothing.
  List<_Section> get _sections => [
    _Section(
      icon: Icons.people_outline,
      title: 'Who is using this',
      description:
          'Which person the board belongs to, how much of the vocabulary is '
          'drawn, and words that have shipped since it was built',
      tiles: (context, onChanged) => [
        if (onSwitchProfile != null)
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Profiles'),
            subtitle: const Text(
              'Switch to someone else, or set up a new person',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final chosen = await ProfilePicker.show(
                context,
                db: db,
                currentId: profileId,
              );
              if (chosen == null || !context.mounted) return;

              onSwitchProfile!(chosen);
              // The board underneath belongs to somebody else now.
              Navigator.of(context).pop(true);
            },
          ),
        _VocabularyLevel(db: db, profileId: profileId, onChanged: onChanged),
        _NewWords(
          db: db,
          vocabularyId: vocabularyId,
          profileId: profileId,
          onChanged: onChanged,
        ),
        if (settings != null)
          _StrongLanguage(
            db: db,
            vocabularyId: vocabularyId,
            profileId: profileId,
            settings: settings!,
            onChanged: onChanged,
          ),
      ],
    ),
    _Section(
      icon: Icons.grid_on_outlined,
      title: 'The board',
      description:
          'How big the buttons are, which way round the grid sits, and '
          'starting the whole board set again from the shipped words',
      state: settings == null
          ? null
          : '${settings!.iconSize.label} icons, '
                '${settings!.orientation.label.toLowerCase()}',
      tiles: (context, onChanged) => [
        if (settings != null)
          ListTile(
            leading: const Icon(Icons.grid_on_outlined),
            title: const Text('Button size and orientation'),
            subtitle: Text(
              '${settings!.iconSize.label} icons, '
              '${settings!.orientation.label.toLowerCase()}. Changing either '
              'one rebuilds every board and moves almost every word.',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final rebuilt = await GridChangeScreen.show(
                context,
                db: db,
                profileId: profileId,
                vocabularyId: vocabularyId,
                settings: settings!,
                userName: userName,
                trackingEnabled: logger.enabled,
              );
              if (rebuilt == null || !context.mounted) return;

              // The board this screen was opened over no longer exists, so
              // back out to the talk screen and let it load the rebuilt one.
              Navigator.of(context).pop(true);
            },
          ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: const Text('Rebuild from the shipped vocabulary'),
          subtitle: const Text(
            'Builds a new board set from the words this version of the app '
            'ships, at the same grid. Words added by hand are discarded, and '
            'every word lands where the current version puts it rather than '
            'where these boards do.',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final rebuilt = await RebuildSheet.show(
              context,
              db: db,
              profileId: profileId,
              vocabularyId: vocabularyId,
              userName: userName,
            );
            if (rebuilt == null || !context.mounted) return;

            Navigator.of(context).pop(true);
          },
        ),
      ],
    ),
    _Section(
      icon: Icons.history,
      title: 'Backups',
      description:
          'Copies of the whole board kept on this device, and getting one '
          'back. One is taken before every update.',
      tiles: (context, onChanged) => [
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Backups and restoring'),
          subtitle: const Text(
            'Every word, picture and location as it stood, and what has been '
            'used. Nothing leaves this device.',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BackupsScreen(db: db, backup: backup),
              ),
            );
            // A restore replaces every row in the database, the board this
            // screen was opened over included.
            onChanged();
          },
        ),
      ],
    ),
    _Section(
      icon: Icons.record_voice_over_outlined,
      title: 'How it sounds',
      description:
          'The voice that speaks, and how fast, how high and how loud it is',
      state: settings == null || speech == null
          ? null
          : '${settings!.voiceName ?? 'The device\'s own voice'} · '
                '${settings!.tone.label}',
      tiles: (context, onChanged) => [
        if (settings != null && speech != null)
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice'),
            subtitle: Text(
              '${settings!.voiceName ?? 'The device\'s own voice'} · '
              '${settings!.tone.label}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => VoiceScreen.show(
              context,
              speech: speech!,
              settings: settings!,
            ).then((_) => onChanged()),
          ),
        if (settings != null && speech is NeuralSpeechEngine)
          ListTile(
            leading: const Icon(Icons.graphic_eq_outlined),
            title: const Text('A voice of their own'),
            subtitle: Text(
              settings!.neuralVoice
                  ? 'Pre-alpha, may not sound correct · '
                        '${neuralVoiceById(settings!.neuralVoiceId).name} · '
                        'downloaded, and never leaves this tablet'
                  : 'Pre-alpha, may not sound correct · a downloadable voice '
                        'that runs on this tablet and sounds less like a '
                        'synthesiser. Off.',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => NeuralVoiceScreen.show(
              context,
              speech: speech! as NeuralSpeechEngine,
              settings: settings!,
              db: db,
              vocabularyId: vocabularyId,
            ).then((_) => onChanged()),
          ),
      ],
    ),
    _Section(
      icon: Icons.touch_app_outlined,
      title: 'How it behaves',
      description:
          'Going home after a word, the pause after the board changes, and '
          'the strips that name where a word is and how it was reached',
      tiles: (context, onChanged) => [
        if (settings != null)
          SwitchListTile(
            value: settings!.autoReturn,
            title: const Text('Go back to the home board after each word'),
            subtitle: const Text(
              'On, every word costs the same movements every time, because '
              'each one starts from the same place. Off suits someone '
              'building a longer sentence out of one category who would '
              'otherwise pay the trip back out for every word.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('autoReturn', v);
              onChanged();
            },
          ),
        if (settings != null)
          _SettleDelay(settings: settings!, onChanged: onChanged),
        if (settings != null)
          SwitchListTile(
            value: settings!.breadcrumbs,
            title: const Text('Show how a word was reached'),
            subtitle: const Text(
              'A strip along the bottom reads home → body → more words → '
              'dizzy, so you can see the route and help repeat it. It stays '
              'up after the board has gone back home, until the next word is '
              'started. It takes its height from the grid, so every button is '
              'a little shorter while it is on; turning it off puts them back '
              'exactly as they were.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('breadcrumbs', v);
              onChanged();
            },
          ),
        if (settings != null)
          _RegionLabels(
            db: db,
            vocabularyId: vocabularyId,
            settings: settings!,
            onChanged: onChanged,
          ),
      ],
    ),
    _Section(
      icon: Icons.spellcheck,
      title: 'Words and grammar',
      description:
          'Word endings, the choice between am, is and are, and the strip '
          'that suggests what comes next',
      tiles: (context, onChanged) => [
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
          _CopulaMode(settings: settings!, onChanged: onChanged),
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
        if (settings != null)
          SwitchListTile(
            value: settings!.prediction,
            title: const Text('Suggest the next word'),
            subtitle: const Text(
              'A strip above the board offers likely next words, learned from '
              'this profile\'s own sentences. It never rearranges the board. '
              'It does take its height from the grid, so every button is a '
              'little shorter while it is on; turning it off puts them back '
              'exactly as they were and forgets what it learned.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('prediction', v);
              if (!v) await forgetPredictions(db, profileId);
              onChanged();
            },
          ),
        if (settings != null && settings!.prediction)
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Start the suggestions over'),
            subtitle: const Text(
              'Forgets every pair of words learned so far. Worth doing after '
              'a stretch where somebody else was using the device.',
            ),
            onTap: () async {
              await forgetPredictions(db, profileId);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Suggestions start over.')),
              );
              onChanged();
            },
          ),
      ],
    ),
    _Section(
      icon: Icons.lock_outline,
      title: 'Getting in here',
      description:
          'The gesture that opens this screen, and how long it is held for',
      tiles: (context, onChanged) => [_CaregiverEntryTile(db: db)],
    ),
    _Section(
      icon: Icons.insights_outlined,
      title: 'Recording',
      description:
          'Whether taps are counted, so the editor can say how much practice '
          'a position has had',
      state: logger.enabled ? 'On' : 'Off',
      tiles: (context, onChanged) => [
        SwitchListTile(
          value: logger.enabled,
          title: const Text('Track word usage'),
          subtitle: const Text('Stays on this device. Off by default.'),
          onChanged: (v) {
            logger.enabled = v;
            onChanged();
          },
        ),
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
    ),
    _Section(
      icon: Icons.info_outline,
      title: 'About',
      description: 'Where the pictures came from, and what their licences ask',
      tiles: (context, onChanged) => [
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
    ),
  ];
}

/// Which gesture opens this screen, and how long it is held.
///
/// Safe to change from in here precisely because you are already inside. It is
/// the device's answer rather than the profile's: which hands hold the tablet
/// is not a fact about the person speaking on it.
class _CaregiverEntryTile extends StatefulWidget {
  const _CaregiverEntryTile({required this.db});

  final WordbridgeDatabase db;

  @override
  State<_CaregiverEntryTile> createState() => _CaregiverEntryTileState();
}

class _CaregiverEntryTileState extends State<_CaregiverEntryTile> {
  late final _store = CaregiverEntryStore(widget.db);
  CaregiverEntry? _entry;

  /// A hold nobody wants to sit through, and one nobody triggers by resting a
  /// hand. Both ends are the caregiver's call within that range.
  static const _shortest = 1;
  static const _longest = 20;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final entry = await _store.read();
    if (mounted) setState(() => _entry = entry);
  }

  Future<void> _save(CaregiverEntry entry) async {
    setState(() => _entry = entry);
    await _store.write(entry);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry == null) {
      return const ListTile(title: Text('Reading how this device is set up…'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<CaregiverGesture>(
          groupValue: entry.gesture,
          onChanged: (chosen) {
            if (chosen != null) _save(entry.withGesture(chosen));
          },
          child: Column(
            children: [
              for (final option in CaregiverGesture.values)
                RadioListTile<CaregiverGesture>(
                  value: option,
                  title: Text(option.label),
                  subtitle: Text(option.description),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
        ListTile(
          title: Text('Held for ${entry.hold.inSeconds} seconds'),
          subtitle: Slider(
            value: entry.hold.inSeconds.toDouble().clamp(
              _shortest.toDouble(),
              _longest.toDouble(),
            ),
            min: _shortest.toDouble(),
            max: _longest.toDouble(),
            divisions: _longest - _shortest,
            label: '${entry.hold.inSeconds}s',
            onChanged: (value) =>
                _save(entry.withHold(Duration(seconds: value.round()))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            entry.gesture == CaregiverGesture.twoCorners
                ? 'Holding the top-left corner of the sentence bar on its own '
                      'also still works, at '
                      '${CaregiverEntry.oneHandedFallback.inSeconds} seconds. '
                      'That way in cannot be switched off: two corners needs '
                      'two hands, and whoever picks this tablet up next may '
                      'not have them — including you, on a day you are holding '
                      'something else.'
                : 'One finger, one corner. Slower than the two-corner hold and '
                      'easier to stumble across, which is the trade: it is the '
                      'one gesture anybody can make.',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// How much of the vocabulary is currently drawn.
///
/// Raising this reveals words that have been seeded and hidden since the day
/// the profile was made, in the locations they have always occupied. It is the
/// one control here that adds vocabulary without moving anything, which is why
/// growing a board is a slider rather than an editing session.
class _VocabularyLevel extends StatelessWidget {
  const _VocabularyLevel({
    required this.db,
    required this.profileId,
    required this.onChanged,
  });

  final WordbridgeDatabase db;
  final String profileId;
  final VoidCallback onChanged;

  static const _descriptions = {
    1:
        'Learning single words. The Universal Core 36, plus “maybe” so an '
        'answer can be a hedge rather than a commitment. Never more than 37 '
        'on a page. No word endings and no am/is/are, so “are you ok?” and '
        'the past tense are out of reach at this level.',
    2:
        'Putting words together. Adds the word endings, a and the, and '
        'am/is/are — the keys a sentence needs — along with the words an '
        'ordinary day takes.',
    3: 'Using the whole board. Everything, including anything added since.',
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Profile?>(
      stream: (db.select(
        db.profiles,
      )..where((p) => p.id.equals(profileId))).watchSingleOrNull(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) return const SizedBox.shrink();

        final level = profile.vocabLevel.clamp(1, 3);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('How many words are shown'),
              subtitle: Text(_descriptions[level]!),
              isThreeLine: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider(
                value: level.toDouble(),
                min: 1,
                max: 3,
                divisions: 2,
                label: 'Level $level',
                onChanged: (v) async {
                  await (db.update(
                    db.profiles,
                  )..where((p) => p.id.equals(profileId))).write(
                    ProfilesCompanion(
                      vocabLevel: Value(v.round()),
                      updatedAt: Value(nowMs()),
                    ),
                  );
                  onChanged();
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Words that appear when you raise this have been holding their '
                'locations since the board was built. Nothing moves to make '
                'room for them, and lowering it again puts them back out of '
                'sight without losing them.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Reveals or hides the strong-language band as a unit.
///
/// Only shown when the profile's preset carries those words at all. Toggling
/// hides them in place rather than deleting them, so switching back on returns
/// them to the same locations.
class _StrongLanguage extends StatelessWidget {
  const _StrongLanguage({
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    required this.settings,
    required this.onChanged,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final ProfileSettings settings;
  final VoidCallback onChanged;

  Future<void> _apply(bool visible) async {
    final labels = [for (final i in swearingBand.items) i.value.label];

    await (db.update(db.buttons)..where(
          (b) => b.vocabularyId.equals(vocabularyId) & b.label.isIn(labels),
        ))
        .write(
          ButtonsCompanion(hidden: Value(!visible), updatedAt: Value(nowMs())),
        );

    await settings.set('profanity', visible);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: (db.select(
        db.profiles,
      )..where((p) => p.id.equals(profileId))).getSingleOrNull(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) return const SizedBox.shrink();

        final birth = profile.birthDate;
        final band = AgeBand.forBirthDate(
          birth == null ? null : DateTime.fromMillisecondsSinceEpoch(birth),
        );
        if (!band.canSwear) return const SizedBox.shrink();

        return SwitchListTile(
          value: settings.profanity,
          title: const Text('Include strong language'),
          subtitle: const Text(
            'Off hides these words where they are rather than removing them, '
            'so turning it back on moves nothing.',
          ),
          isThreeLine: true,
          onChanged: (v) async {
            await _apply(v);
            onChanged();
          },
        );
      },
    );
  }
}

/// How long the board ignores taps after it changes.
///
/// A user moving quickly through a learned sequence has a finger already
/// coming down as the new board arrives, and lands on whatever now occupies
/// that location. This is the only place in the app where something
/// deliberately delays speech, which is why it is short, adjustable, and can
/// be turned off entirely.
class _SettleDelay extends StatelessWidget {
  const _SettleDelay({required this.settings, required this.onChanged});

  final ProfileSettings settings;
  final VoidCallback onChanged;

  static String _describe(int ms) => switch (ms) {
    0 => 'Off. Taps are accepted the instant a new board appears.',
    _ => '${(ms / 1000).toStringAsFixed(2)} seconds',
  };

  @override
  Widget build(BuildContext context) {
    final ms = settings.settleDelay.inMilliseconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Pause after the board changes'),
          subtitle: Text(_describe(ms)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: ms.toDouble().clamp(0, 2000),
            max: 2000,
            divisions: 8,
            label: _describe(ms),
            onChanged: (v) async {
              await settings.set('settleDelayMs', v.round());
              onChanged();
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'During the pause the board is visible but does not respond, so a '
            'tap meant for the previous screen is dropped instead of speaking '
            'a word nobody chose. Raise it for someone who moves fast or has '
            'trouble lifting off; set it to zero for someone it gets in the '
            'way of.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

/// Words, and whole categories, that have shipped since this board was built.
///
/// A board is not rebuilt to receive them. Each one goes to the location the
/// layout rule already assigns it on this grid, and only if that location is
/// still free — so the board gains vocabulary without a single thing on it
/// moving. Anything whose place is taken is reported rather than forced.
///
/// A category is the larger arrival and the larger loss: a whole board with a
/// key of its own, or vocabulary that stays off the device because nothing on
/// the system row could be made to open it. Both are named rather than folded
/// into a word count, which would report the loss as silence.
class _NewWords extends StatefulWidget {
  const _NewWords({
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    required this.onChanged,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final VoidCallback onChanged;

  @override
  State<_NewWords> createState() => _NewWordsState();
}

class _NewWordsState extends State<_NewWords> {
  late Future<VocabularyTopUp> _preview = _check();
  bool _applying = false;

  Future<AgeBand> _band() async {
    final profile = await (widget.db.select(
      widget.db.profiles,
    )..where((p) => p.id.equals(widget.profileId))).getSingleOrNull();

    final birth = profile?.birthDate;
    return AgeBand.forBirthDate(
      birth == null ? null : DateTime.fromMillisecondsSinceEpoch(birth),
    );
  }

  Future<VocabularyTopUp> _check() async => topUpVocabulary(
    widget.db,
    vocabularyId: widget.vocabularyId,
    ageBand: await _band(),
    dryRun: true,
  );

  /// Names the categories arriving. A category is a board and a key of its
  /// own, so it is read out rather than counted among the words it holds.
  static String _arriving(List<String> boards) =>
      '${boards.length == 1 ? 'New category' : 'New categories'}: '
      '${boards.join(', ')}';

  /// Names the categories that could not arrive, and what that costs. Their
  /// words are nowhere on the device and no key would reach them, which a
  /// count of everything else would hide entirely.
  static String _refused(List<String> boards) =>
      '${boards.join(', ')} — no key could be made to open '
      '${boards.length == 1 ? 'it' : 'them'}, so those words are not on this '
      'board set at all.';

  Future<void> _apply(VocabularyTopUp preview) async {
    final categories = preview.addedBoards.length == 1
        ? 'a new category'
        : '${preview.addedBoards.length} new categories';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          preview.addedBoards.isEmpty
              ? 'Add ${preview.count} words?'
              : 'Add ${preview.count} words and $categories?',
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Each one goes to a location that is currently empty. Nothing '
                'already on the board moves.',
                style: TextStyle(fontSize: 13),
              ),
              if (preview.addedBoards.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${_arriving(preview.addedBoards)} — added at the end, so '
                  'every key already on the board keeps opening what it '
                  'always opened.',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    [
                      for (final a in preview.added)
                        '${a.label}  —  ${a.board}, row ${a.row + 1}, '
                            'column ${a.col + 1}',
                    ].join('\n'),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ),
              if (preview.blocked.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Not added, because those locations are already in use:\n'
                  '${[for (final b in preview.blocked) '${b.label} (behind "${b.occupant}")'].join(', ')}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
              if (preview.refusedBoards.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _refused(preview.refusedBoards),
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add them'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _applying = true);
    await topUpVocabulary(
      widget.db,
      vocabularyId: widget.vocabularyId,
      ageBand: await _band(),
    );

    if (!mounted) return;
    setState(() {
      _applying = false;
      _preview = _check();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VocabularyTopUp>(
      future: _preview,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        if (preview == null) {
          return const ListTile(
            leading: Icon(Icons.playlist_add),
            title: Text('New words'),
            subtitle: Text('Checking…'),
          );
        }

        if (preview.added.isEmpty && preview.refusedBoards.isEmpty) {
          return const ListTile(
            leading: Icon(Icons.playlist_add_check),
            title: Text('New words'),
            subtitle: Text('This board has everything wordbridge ships.'),
          );
        }

        // A refusal on its own still has to be said. There is nothing to press
        // here, and reporting "everything is here" over the top of it would
        // leave a caregiver sure of vocabulary the device does not carry.
        if (preview.added.isEmpty) {
          return ListTile(
            leading: const Icon(Icons.playlist_remove),
            title: Text(
              preview.refusedBoards.length == 1
                  ? 'A new category could not be added'
                  : 'New categories could not be added',
            ),
            subtitle: Text(_refused(preview.refusedBoards)),
            isThreeLine: true,
          );
        }

        final lines = [
          if (preview.addedBoards.isNotEmpty) _arriving(preview.addedBoards),
          if (preview.refusedBoards.isNotEmpty) _refused(preview.refusedBoards),
          [for (final a in preview.added.take(6)) a.label].join(', ') +
              (preview.count > 6 ? '…' : ''),
        ];

        return ListTile(
          leading: const Icon(Icons.playlist_add),
          title: Text('${preview.count} new words available'),
          subtitle: Text(lines.join('\n')),
          isThreeLine: lines.length > 1,
          trailing: _applying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _applying ? null : () => _apply(preview),
        );
      },
    );
  }
}
