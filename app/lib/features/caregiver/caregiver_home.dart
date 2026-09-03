import 'dart:async';

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
import '../interop/board_files.dart';
import '../prediction/word_prediction.dart';
import '../speech/neural/neural_engine.dart';
import '../speech/neural/neural_voice.dart';
import '../speech/speech_engine.dart';
import '../profiles/profile_picker.dart';
import '../profiles/profile_settings.dart';
import '../symbols/global_symbols_pack.dart';
import '../symbols/symbol_registry.dart';
import '../symbols/symbol_resolver.dart';
import '../talk/route_walk.dart';
import '../usage/logger.dart';
import '../usage/usage_queries.dart';
import '../utterance/morphology.dart';
import '../reporting/crash_store.dart';
import '../reporting/report_sender.dart';
import 'about_screen.dart';
import 'backups_screen.dart';
import 'board_files_screen.dart';
import 'picture_browser.dart';
import 'symbol_packs_screen.dart';
import 'telemetry_switches.dart';
import 'reports_screen.dart';
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
    this.boards,
    this.viewAll = false,
    this.onViewAll,
    this.crashes,
    this.sender,
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

  /// Where exported and imported board files are. Same arrangement, and the
  /// same reason: a widget test cannot be allowed to read the real folder.
  final BoardFileStore? boards;

  /// Where faults this tablet caught are waiting, and where a report goes.
  /// Both built by existing when nothing supplies one, on the same reasoning:
  /// a widget test may touch neither the documents directory nor the network.
  final CrashStore? crashes;
  final ReportSender? sender;

  /// Whether the board underneath is drawing every word (§4.42).
  ///
  /// Held by the talk screen rather than by a profile: it is a way of looking
  /// at a board, not a fact about a person, and it must not survive the app
  /// being closed. Absent where nothing can honor it, and the switch is then
  /// not offered rather than offered and inert.
  final bool viewAll;
  final ValueChanged<bool>? onViewAll;

  @override
  State<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends State<CaregiverHome> {
  int _tab = 0;
  late final _backup = widget.backup ?? BackupService(widget.db);
  late final _boards = widget.boards ?? BoardFileStore(widget.db);

  @override
  void initState() {
    super.initState();
    // A copy of the board as it was found, so everything done in here can be
    // taken back in one move (§4.41 part 4b). Not awaited and never fatal:
    // opening caregiver mode does not stop the board working, and a copy that
    // would not write must not stop somebody getting to the settings.
    unawaited(_backup.takeSessionSnapshot());
  }

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
        _ => _Settings(
          db: widget.db,
          vocabularyId: widget.vocabularyId,
          profileId: widget.profileId,
          logger: widget.logger,
          backup: _backup,
          boards: _boards,
          speech: widget.speech,
          settings: widget.settings,
          onSwitchProfile: widget.onSwitchProfile,
          userName: widget.userName,
          viewAll: widget.viewAll,
          onViewAll: widget.onViewAll,
          crashes: widget.crashes,
          sender: widget.sender,
          registry: widget.registry,
          resolver: widget.resolver,
          onChanged: () => setState(() {}),
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        // No Use tab (§4.71). What it showed — recent sentences, most used
        // words, a day chart — was one person's speech rendered for somebody
        // else to read. The counts still exist, for the one sentence in the
        // editor that says what moving a word will cost.
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Boards'),
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
                'For a subcategory, or another page of an existing one',
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
  /// Every location is materialized at once, so the board is a full grid of
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

    await materializeBoard(
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
    this.tiles,
    this.opens,
    this.state,
  }) : assert(
         tiles != null || opens != null,
         'a section is either a page of controls or a screen of its own',
       );

  final IconData icon;
  final String title;
  final String description;
  final String? state;

  /// Built on demand rather than held, so a switch thrown on the page redraws
  /// with the value it now has.
  final List<Widget> Function(BuildContext context, VoidCallback onChanged)?
  tiles;

  /// A section that is one screen rather than a list of controls.
  ///
  /// Without this, a section holding a single row costs two taps to reach one
  /// screen — a page whose entire content is a link to the next page. The row
  /// in the settings list is the affordance; a second identical row behind it
  /// is a stop on the way to somewhere, not a place.
  final Future<void> Function(BuildContext context)? opens;
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
        final labeled = boards.any((b) => b.bandMap != null);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: settings.regionLabels,
              title: const Text('Label each row'),
              subtitle: const Text(
                'Add a strip beside the grid naming each run of locations: '
                'who, doing, where, asking. Buttons are slightly shorter '
                'while it is on.',
              ),
              isThreeLine: true,
              onChanged: (v) async {
                await settings.set('regionLabels', v);
                onChanged();
              },
            ),
            if (settings.regionLabels && boards.isNotEmpty && !labeled)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'These boards were built before row groupings were '
                  'recorded, so there is nothing to label yet. Rebuilding from '
                  'the shipped vocabulary fills it in.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Who presses the keys on the way to a word the finder found (§4.47).
///
/// Two answers to one question, so a pair of options rather than a switch: a
/// switch would name one of them and leave the other one unnamed, and both are
/// things somebody deliberately wants.
class _WalkMode extends StatelessWidget {
  const _WalkMode({required this.settings, required this.onChanged});

  final ProfileSettings settings;
  final VoidCallback onChanged;

  static const _descriptions = {
    WalkMode.presses:
        'The board presses each key on the route itself, about a second on '
        'each, and stops on the word.',
    // TODO: Make this configurable, not just a second unilaterially
    WalkMode.waits:
        'each key is highlighted until it is selected, then the next key '
        'is highlighted',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          leading: Icon(Icons.travel_explore_outlined),
          title: Text('After choosing a word in Find a word'),
          subtitle: Text(
            'Whether the board walks the route itself, or waits for each key '
            'to be selected. Neither speaks the word.',
          ),
          isThreeLine: true,
        ),
        RadioGroup<WalkMode>(
          groupValue: settings.walkMode,
          onChanged: (chosen) async {
            if (chosen == null) return;
            await settings.set('walkMode', chosen.name);
            onChanged();
          },
          child: Column(
            children: [
              for (final mode in WalkMode.values)
                RadioListTile<WalkMode>(
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

class _CopulaMode extends StatelessWidget {
  const _CopulaMode({required this.settings, required this.onChanged});

  final ProfileSettings settings;
  final VoidCallback onChanged;

  static const _descriptions = {
    CopulaMode.toggle:
        'The key gives "is". Selecting it again gives "are", then "am", each '
        'replacing the last. To ask "are you ok?", select it twice.',
    CopulaMode.agree:
        'The key gives "is" and corrects it once the subject arrives, so "is" '
        'then "you" becomes "are you".',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          leading: Icon(Icons.change_history_outlined),
          title: Text('Choosing between am, is and are'),
          subtitle: Text(
            'How the key decides which one to use. Both give "am" after "I"; '
            'they differ when a question puts the verb first.',
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
    required this.boards,
    required this.settings,
    required this.onChanged,
    required this.viewAll,
    required this.onViewAll,
    this.speech,
    this.onSwitchProfile,
    this.userName,
    this.crashes,
    this.sender,
    this.registry,
    this.resolver,
  });

  final WordbridgeDatabase db;
  final String vocabularyId;
  final String profileId;
  final UsageLogger logger;
  final SymbolRegistry? registry;

  /// Turns a search result into a picture. Only the browser needs it here, and
  /// without one that screen lists words rather than pictures, so the row is
  /// not offered.
  final SymbolResolver? resolver;
  final BackupService backup;
  final BoardFileStore boards;
  final CrashStore? crashes;
  final ReportSender? sender;
  final SpeechEngine? speech;
  final String? userName;
  final ProfileSettings? settings;
  final VoidCallback onChanged;
  final bool viewAll;
  final ValueChanged<bool>? onViewAll;
  final void Function(Profile)? onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // Whose board this is, above everything else and not inside a section.
        //
        // Every control below it applies to one person, and on a tablet with
        // more than one profile there is nothing else on this screen that says
        // which. A caregiver who changes a setting for the wrong child has to
        // find that out by noticing it, so the answer goes where they cannot
        // miss it rather than one tap inside "Who is using this".
        if (userName != null || onSwitchProfile != null)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined, size: 36),
              title: Text(
                userName ?? 'This board',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                onSwitchProfile == null
                    ? 'These settings apply to this person'
                    : 'These settings apply to this person · tap to switch',
              ),
              trailing: onSwitchProfile == null
                  ? null
                  : const Icon(Icons.swap_horiz),
              onTap: onSwitchProfile == null
                  ? null
                  : () => _switchProfile(context),
            ),
          ),

        // A section with nothing on it is not named. Several depend on a
        // profile, a speech engine, or more than one person existing, and a
        // row that opens onto an empty page is worse than no row.
        for (final section in _sections)
          if (section.opens != null ||
              section.tiles!(context, onChanged).isNotEmpty)
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

  /// Hands the tablet to somebody else.
  ///
  /// One route, reached from the card at the top and from the row inside "Who
  /// is using this", so the two cannot come to behave differently.
  Future<void> _switchProfile(BuildContext context) async {
    final chosen = await ProfilePicker.show(
      context,
      db: db,
      currentId: profileId,
    );
    if (chosen == null || !context.mounted) return;

    onSwitchProfile!(chosen);
    // The board underneath belongs to somebody else now.
    Navigator.of(context).pop(true);
  }

  /// Opens a section, and follows it out if what was done on it took the board
  /// with it.
  Future<void> _open(BuildContext context, _Section section) async {
    final opens = section.opens;
    if (opens != null) {
      await opens(context);
      onChanged();
      return;
    }

    final boardGone = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _SectionPage(
          title: section.title,
          tiles: section.tiles!,
          onChanged: onChanged,
        ),
      ),
    );

    if (boardGone == true && context.mounted) Navigator.of(context).pop();
  }

  /// The sections, in the order the decisions are actually made.
  ///
  /// Who it is for, then how they sound, then what is on the board and how it
  /// looks, then how it responds, then the guardrails, then data and support.
  /// Somebody setting a tablet up for the first time works down this list, so
  /// the things that make it theirs come before the things that keep it safe.
  List<_Section> get _sections => [
    _Section(
      icon: Icons.people_outline,
      title: 'Profile',
      description: 'Who this device is set up for',
      tiles: (context, onChanged) => [
        if (onSwitchProfile != null)
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Profiles'),
            subtitle: const Text('Switch profile, or add a new one'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _switchProfile(context),
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
    // Second, because the whole device exists to talk. One screen holding both
    // voices, so the row opens it directly (§4.43a): which voice speaks is one
    // question and belongs on one page.
    if (settings != null && speech != null)
      _Section(
        icon: Icons.record_voice_over_outlined,
        title: 'Speech',
        description: 'How the device sounds when it talks',
        // A profile can carry `neuralVoice` on a build that has no neural
        // engine — the setting outlives the binary. The row names the voice
        // that is actually speaking, which in that case is the device's.
        state:
            settings!.neuralVoice &&
                showsNeuralVoice(speech!, db: db, vocabularyId: vocabularyId)
            ? 'Neural voice· '
                  '${neuralVoiceById(settings!.neuralVoiceId).name}'
            : '${settings!.voiceName ?? 'The device\'s own voice'} · '
                  '${settings!.tone.label}',
        opens: (context) => VoiceScreen.show(
          context,
          speech: speech!,
          settings: settings!,
          db: db,
          vocabularyId: vocabularyId,
        ),
      ),
    _Section(
      icon: Icons.grid_on_outlined,
      title: 'Board',
      description: 'The size and shape of the grid',
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
              'rebuilds the board set and moves almost every word.',
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
          title: const Text('Rebuild from shipped vocabulary'),
          subtitle: const Text(
            'Build a new board set at the same grid size from the vocabulary '
            'this version ships. Words you added are discarded.',
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
    // Beside Board, because a picture set changes what every cell looks like.
    // Only where a registry was supplied: a build without one has no packs to
    // offer and the row would open onto nothing.
    if (registry != null)
      _Section(
        icon: Icons.image_outlined,
        title: 'Pictures',
        description: 'Where the pictures on the buttons come from',
        tiles: (context, onChanged) => [
          ListTile(
            leading: const Icon(Icons.collections_outlined),
            title: const Text('Picture sets'),
            subtitle: const Text('Which sets this device may draw from'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SymbolPacksScreen(db: db, registry: registry!),
              ),
            ),
          ),
          // Only where something can resolve a picture. A browser that can
          // search but not draw is a page of words.
          if (resolver != null)
            ListTile(
              leading: const Icon(Icons.image_search_outlined),
              title: const Text('Browse pictures'),
              subtitle: const Text('Search the sets without changing a button'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PictureBrowser(registry: registry!, resolver: resolver!),
                ),
              ),
            ),
        ],
      ),
    _Section(
      icon: Icons.touch_app_outlined,
      title: 'Board behavior',
      description: 'How the app behaves during daily use',
      tiles: (context, onChanged) => [
        if (settings != null)
          SwitchListTile(
            value: settings!.autoReturn,
            title: const Text('Return to the home board after each word'),
            subtitle: const Text(
              'When enabled, the board will return to the home page after a word '
              'is selected. When disabled, the board will remain on the same '
              'page after a word is selected',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('autoReturn', v);
              onChanged();
            },
          ),
        if (settings != null)
          SwitchListTile(
            value: settings!.speakEachWord,
            title: const Text('Speak each word as it is selected'),
            subtitle: const Text(
              'When enabled, every key speaks as it is selected. '
              'When disabled, the device will only speak when the utterance bar '
              'is tapped.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('speakEachWord', v);
              onChanged();
            },
          ),
        if (settings != null)
          _SettleDelay(settings: settings!, onChanged: onChanged),
        if (settings != null)
          SwitchListTile(
            value: settings!.breadcrumbs,
            title: const Text('Show the route to each word'),
            subtitle: const Text(
              'Add a strip at the bottom of the screen that shows the steps '
              'taken to reach a given word when it is selected.',
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
        if (settings != null)
          _WalkMode(settings: settings!, onChanged: onChanged),
        // TODO: Commented out until we confirm that strong language will not
        // appear on a child's profile
        //
        // if (onViewAll != null)
        //   SwitchListTile(
        //     value: viewAll,
        //     title: const Text('Show every word, including hidden ones'),
        //     subtitle: const Text(
        //       'Draws the whole board set, including words above this '
        //       'profile\'s vocabulary level and words that have been hidden. '
        //       'The board displays a banner while this is on, and closing the '
        //       'app turns it off.',
        //     ),
        //     isThreeLine: true,
        //     onChanged: (v) {
        //       onViewAll!(v);
        //       onChanged();
        //     },
        //   ),
      ],
    ),
    _Section(
      icon: Icons.spellcheck,
      title: 'Grammar',
      description: 'How words change as a sentence is built',
      tiles: (context, onChanged) => [
        if (settings != null)
          SwitchListTile(
            value: settings!.contextualGrammar,
            title: const Text('Show word endings only where they apply'),
            subtitle: const Text(
              'When enabled, an ending appears once there is a word to '
              'attach it to, always in the same location. When disabled, '
              'every ending stays visible.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('contextualGrammar', v);
              onChanged();
            },
          ),
        if (settings != null)
          SwitchListTile(
            value: settings!.contractions,
            title: const Text('Contract not with the word before it'),
            subtitle: const Text(
              'When enabled, "can" then "not" is spoken as "can\'t". When '
              'disabled, both words are spoken as selected. No key moves '
              'either way.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('contractions', v);
              onChanged();
            },
          ),
        if (settings != null)
          SwitchListTile(
            value: settings!.joinNumbers,
            title: const Text('Read numbers next to each other as one number'),
            subtitle: const Text(
              'When enabled, 1 then 2 is spoken as "twelve". When disabled, '
              'they are spoken as "one two". No key moves either way.',
            ),
            isThreeLine: true,
            onChanged: (v) async {
              await settings!.set('joinNumbers', v);
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
              'When enabled, the other verbs are hidden after a verb until '
              '"to" or a modal makes a second one possible. When disabled, '
              'every verb stays visible.',
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
            title: const Text('Word prediction'),
            subtitle: const Text(
              'Add a strip above the board offering likely next words, '
              'learned from this profile\'s own sentences. No key moves, and '
              'buttons are slightly shorter while it is on.',
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
            title: const Text('Reset word prediction'),
            subtitle: const Text('Discard every word pair learned so far.'),
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
      title: 'Access to settings',
      description: 'How this screen is reached',
      tiles: (context, onChanged) => [_CaregiverEntryTile(db: db)],
    ),
    _Section(
      icon: Icons.insights_outlined,
      title: 'Usage tracking',
      description: 'What this device records about how it is used',
      state: logger.enabled ? 'On' : 'Off',
      tiles: (context, onChanged) => [
        SwitchListTile(
          value: logger.enabled,
          title: const Text('Track usage'),
          subtitle: const Text(
            'Records which locations are selected, on this device.',
          ),
          onChanged: settings == null
              ? null
              : (v) async {
                  // Written to the profile, not just to the logger. The
                  // logger forgets on every launch; the profile is where the
                  // answer has to live to still be true tomorrow.
                  await settings!.set('usageTracking', v);
                  logger.enabled = v;
                  onChanged();
                },
        ),
        _ForgetUsageTile(db: db, profileId: profileId, onChanged: onChanged),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Usage tracking is what lets the editor report how much practice '
            'a location has had before you move it. With it off the editor '
            'still works, but cannot tell you what a move costs.',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
          ),
        ),
      ],
    ),
    // Durability rather than setup, so it sits below the decisions that make
    // the tablet somebody's. One screen, and the row on this list opens it: a
    // section page in between would hold a single row saying the same thing.
    _Section(
      icon: Icons.history,
      title: 'Backups',
      description: 'Keeping and restoring copies of this board set',
      opens: (context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BackupsScreen(db: db, backup: backup),
        ),
      ),
    ),
    // Also one screen. Next to Backups because that is where somebody looks
    // for it, and separate from Backups because it is not one: an exported
    // file carries the words and not what makes them a motor plan.
    _Section(
      icon: Icons.swap_horiz,
      title: 'Import and export',
      description: 'Moving a board set to and from other programs',
      opens: (context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BoardFilesScreen(
            db: db,
            vocabularyId: vocabularyId,
            store: boards,
            onImported: onChanged,
          ),
        ),
      ),
    ),
    // One screen, so the row opens it directly (§4.43a). What the page in
    // A page of controls now rather than a straight jump to the screen
    // (§4.59): what leaves this tablet on its own is decided here, and writing
    // a report is one row on the same page.
    _Section(
      icon: Icons.outgoing_mail,
      title: 'Reports',
      description: 'Telling us when something is wrong',
      state: settings == null
          ? null
          : switch ((settings!.crashReports, settings!.voiceMeasurements)) {
              (false, _) => 'Off',
              (true, true) => 'Crashes and voice',
              (true, false) => 'Crashes',
            },
      tiles: (context, onChanged) => [
        CrashReportSwitch(settings: settings, onChanged: onChanged),
        VoiceMeasurementSwitch(
          settings: settings,
          available:
              speech is NeuralSpeechEngine && (settings?.neuralVoice ?? false),
          onChanged: onChanged,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Write a report'),
          subtitle: const Text(
            'Tell us something is wrong or missing, and send faults this '
            'device caught',
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReportsScreen(
                db: db,
                vocabularyId: vocabularyId,
                profileId: profileId,
                settings: settings,
                speech: speech,
                crashes: crashes,
                sender: sender,
                userName: userName,
              ),
            ),
          ),
        ),
      ],
    ),
    // One screen of its own (§4.43a). What is on it is prose rather than
    // controls, and the one thing there is to press on it opens the credits.
    _Section(
      icon: Icons.info_outline,
      title: 'About',
      description: 'This version of the app, and its credits',
      opens: (context) => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
    ),
  ];
}

/// Which gesture opens this screen, and how long it is held.
///
/// Safe to change from in here precisely because you are already inside. It is
/// the device's answer rather than the profile's: which hands hold the tablet
/// is not a fact about the person speaking on it.
/// Deleting what has already been recorded, beside the switch that stops more
/// being recorded (§4.78).
///
/// Two halves of one thing and deliberately two controls: stopping is
/// reversible and this is not. It shows the count before asking, because a
/// button that deletes an unknown quantity of somebody's history is a button
/// nobody can weigh.
class _ForgetUsageTile extends StatefulWidget {
  const _ForgetUsageTile({
    required this.db,
    required this.profileId,
    required this.onChanged,
  });

  final WordbridgeDatabase db;
  final String profileId;
  final VoidCallback onChanged;

  @override
  State<_ForgetUsageTile> createState() => _ForgetUsageTileState();
}

class _ForgetUsageTileState extends State<_ForgetUsageTile> {
  late final _usage = UsageQueries(widget.db);
  int? _recorded;

  @override
  void initState() {
    super.initState();
    unawaited(_count());
  }

  Future<void> _count() async {
    final recorded = await _usage.recordedFor(widget.profileId);
    if (mounted) setState(() => _recorded = recorded);
  }

  Future<void> _confirm() async {
    final recorded = _recorded ?? 0;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete usage history?'),
        content: Text(usageDeletionWarning(recorded)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete it'),
          ),
        ],
      ),
    );
    if (go != true) return;

    final gone = await _usage.forgetProfile(widget.profileId);
    if (!mounted) return;

    setState(() => _recorded = 0);
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          gone == 1 ? 'One selection deleted' : '$gone selections deleted',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recorded = _recorded;

    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: const Text('Delete usage history'),
      isThreeLine: true,
      subtitle: Text(
        recorded == null
            ? 'Removes every location count recorded for this profile.'
            : recorded == 0
            ? 'Nothing is recorded for this profile.'
            : 'Removes the $recorded ${recorded == 1 ? 'selection' : 'selections'} '
                  'recorded for this profile. Switching tracking off stops new '
                  'ones; this deletes the old ones.',
      ),
      onTap: recorded == null || recorded == 0 ? null : _confirm,
    );
  }
}

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
                ? 'Holding the top left corner of the sentence bar on its '
                      'own also works, at '
                      '${CaregiverEntry.oneHandedFallback.inSeconds} seconds. '
                      'That route cannot be turned off: two corners requires '
                      'two hands, and whoever picks this device up next may '
                      'not have them, including you on a day you are holding '
                      'something else.'
                : 'One finger, one corner. Slower than the two corner hold and '
                      'easier to trigger by accident. It is the one gesture '
                      'anybody can make.',
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
        'Single words. Core vocabulary only: the Universal Core 36 plus '
        '“maybe”. At most 37 words on a page. No word endings and no am, is '
        'or are, so the past tense and “are you ok?” wait for level 2.',
    2:
        'Short sentences. Adds the grammar keys, plus the fringe vocabulary '
        'an ordinary day needs, such as food, feelings and places.',
    3:
        'Full vocabulary. Every word this board set carries, including any '
        'added since.',
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
              title: const Text('Vocabulary level'),
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
                'Words revealed by raising this have held their locations '
                'since the board set was built. Lowering it hides them again '
                'in place.',
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
            'Toggles whether strong language should be shown or not',
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
      '${boards.join(', ')}: no key could be made to open '
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
                  '${_arriving(preview.addedBoards)}. Added at the end, so '
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
                        '${a.label}:  ${a.board}, row ${a.row + 1}, '
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
            subtitle: Text('This board has everything Wordbridge AAC ships.'),
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
