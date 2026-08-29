import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter/material.dart';

import '../../db/board_builder.dart';
import '../../db/database.dart';
import '../../db/tables.dart';
import '../../db/ids.dart';
import '../../db/seed/age_presets.dart';
import '../../db/seed/vocabulary_top_up.dart';
import '../editor/board_delete.dart';
import '../editor/board_delete_sheet.dart';
import '../editor/board_editor.dart';
import '../editor/grid_change_screen.dart';
import '../editor/rebuild_sheet.dart';
import '../prediction/word_prediction.dart';
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
import 'voice_screen.dart';

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
    this.speech,
    this.settings,
    this.registry,
    this.fetcher,
    this.resolver,
    this.userName,
    this.onSwitchProfile,
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

/// A heading in the settings list.
///
/// The list had grown to twenty-odd controls in one column, which is a wall
/// rather than a page: a caregiver looking for the voice had to read every
/// switch about grammar to be sure it was not there. Grouping does not remove
/// anything, it just means a person can skip four-fifths of it.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// Which of the two ways the "am/is/are" and "was/were" keys behave.
///
/// One key holds three words, so something has to pick between them. Both
/// answers agree with a subject that is already there, and they part company
/// only at the start of a question, where there is nothing to agree with yet.
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

class _Settings extends StatelessWidget {
  const _Settings({
    required this.db,
    required this.vocabularyId,
    required this.profileId,
    required this.logger,
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
  final SpeechEngine? speech;
  final String? userName;
  final ProfileSettings? settings;
  final VoidCallback onChanged;
  final void Function(Profile)? onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (onSwitchProfile != null)
          const _SettingsSection('Who is using this'),
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
              Navigator.of(context).pop();
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
        if (settings != null) const _SettingsSection('The board'),
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
              Navigator.of(context).pop();
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

            Navigator.of(context).pop();
          },
        ),
        if (settings != null && speech != null)
          const _SettingsSection('How it sounds'),
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
        if (settings != null) const _SettingsSection('How it behaves'),
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
              'buttocks, so you can see the route and help repeat it. It stays '
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
        if (settings != null) const _SettingsSection('Words and grammar'),
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
        const _SettingsSection('Recording'),
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
        const _SettingsSection('About'),
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
        'Learning single words. The Universal Core 36, and never more than 36 '
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

/// Words that have shipped since this board was built.
///
/// A board is not rebuilt to receive them. Each one goes to the location the
/// layout rule already assigns it on this grid, and only if that location is
/// still free — so the board gains vocabulary without a single thing on it
/// moving. Anything whose place is taken is reported rather than forced.
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

  Future<void> _apply(VocabularyTopUp preview) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${preview.count} words?'),
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

        if (preview.added.isEmpty) {
          return const ListTile(
            leading: Icon(Icons.playlist_add_check),
            title: Text('New words'),
            subtitle: Text('This board has everything wordbridge ships.'),
          );
        }

        return ListTile(
          leading: const Icon(Icons.playlist_add),
          title: Text('${preview.count} new words available'),
          subtitle: Text(
            [for (final a in preview.added.take(6)) a.label].join(', ') +
                (preview.count > 6 ? '…' : ''),
          ),
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
