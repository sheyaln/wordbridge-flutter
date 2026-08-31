import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/seed/age_presets.dart';
import '../profiles/grid_choice.dart';
import '../profiles/profile_settings.dart';
import 'grid_migration.dart';

/// Changing the grid after setup.
///
/// The one screen in the app that exists to talk somebody out of using it. The
/// choice is offered because a person's motor ability changes and a board
/// sized for who they were is worse than a rebuild — but a caregiver has to
/// see the cost in the user's own tap counts, and type a word, before it runs.
class GridChangeScreen extends StatefulWidget {
  const GridChangeScreen({
    super.key,
    required this.db,
    required this.profileId,
    required this.vocabularyId,
    required this.settings,
    this.userName,
    this.trackingEnabled = false,
  });

  final WordbridgeDatabase db;
  final String profileId;
  final String vocabularyId;
  final ProfileSettings settings;
  final String? userName;
  final bool trackingEnabled;

  /// Returns the id of the rebuilt vocabulary, or null if nothing changed.
  static Future<String?> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required String profileId,
    required String vocabularyId,
    required ProfileSettings settings,
    String? userName,
    bool trackingEnabled = false,
  }) => Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => GridChangeScreen(
        db: db,
        profileId: profileId,
        vocabularyId: vocabularyId,
        settings: settings,
        userName: userName,
        trackingEnabled: trackingEnabled,
      ),
    ),
  );

  @override
  State<GridChangeScreen> createState() => _GridChangeScreenState();
}

class _GridChangeScreenState extends State<GridChangeScreen> {
  late BoardOrientation _orientation = widget.settings.orientation;
  late IconSize _iconSize = widget.settings.iconSize;

  MigrationImpact? _impact;
  bool _working = false;

  GridChoice _choice(BuildContext context, [IconSize? size]) =>
      GridChoice.derive(
        screen: MediaQuery.sizeOf(context),
        orientation: _orientation,
        iconSize: size ?? _iconSize,
      );

  bool get _unchanged =>
      _orientation == widget.settings.orientation &&
      _iconSize == widget.settings.iconSize;

  Future<AgeBand> _band() async {
    final profile = await (widget.db.select(
      widget.db.profiles,
    )..where((p) => p.id.equals(widget.profileId))).getSingleOrNull();

    final birth = profile?.birthDate;
    return AgeBand.forBirthDate(
      birth == null ? null : DateTime.fromMillisecondsSinceEpoch(birth),
    );
  }

  Future<void> _measure() async {
    final choice = _choice(context);
    if (!choice.isUsable || _unchanged) {
      setState(() => _impact = null);
      return;
    }

    setState(() => _working = true);
    final impact = await GridMigration.preview(
      widget.db,
      vocabularyId: widget.vocabularyId,
      rows: choice.rows,
      cols: choice.cols,
      ageBand: await _band(),
      trackingEnabled: widget.trackingEnabled,
    );

    if (mounted) {
      setState(() {
        _impact = impact;
        _working = false;
      });
    }
  }

  Future<void> _rebuild() async {
    final impact = _impact;
    final choice = _choice(context);
    if (impact == null || !choice.isUsable) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _TypeToConfirm(impact: impact, userName: widget.userName),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);

    final rebuilt = await GridMigration.apply(
      widget.db,
      profileId: widget.profileId,
      vocabularyId: widget.vocabularyId,
      rows: choice.rows,
      cols: choice.cols,
      ageBand: await _band(),
      profanity: widget.settings.profanity,
    );

    await widget.settings.set('orientation', _orientation.name);
    await widget.settings.set('iconSize', _iconSize.name);

    if (mounted) Navigator.of(context).pop(rebuilt);
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice(context);
    final impact = _impact;

    return Scaffold(
      appBar: AppBar(title: const Text('Button size and orientation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'These two answers decide how many rows and columns there are, '
              'so changing either one rebuilds every board. Almost every word '
              'moves. Do this when the board no longer fits the person using '
              'it — not to tidy it up.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Currently ${widget.settings.iconSize.label.toLowerCase()} icons '
            'in ${widget.settings.orientation.label.toLowerCase()}',
            style: Theme.of(context).textTheme.titleSmall,
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              for (final option in BoardOrientation.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(option.label),
                      selected: _orientation == option,
                      onSelected: (_) {
                        setState(() => _orientation = option);
                        _measure();
                      },
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),
          for (final size in IconSize.values)
            ListTile(
              leading: Icon(
                _iconSize == size
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _choice(context, size).isUsable ? null : Colors.black26,
              ),
              title: Text(size.label),
              subtitle: Text(
                _choice(context, size).isUsable
                    ? '${_choice(context, size).rows} × '
                          '${_choice(context, size).cols}'
                    : _choice(context, size).refusal!,
              ),
              enabled: _choice(context, size).isUsable,
              onTap: () {
                setState(() => _iconSize = size);
                _measure();
              },
            ),

          const SizedBox(height: 20),
          if (_working)
            const Center(child: CircularProgressIndicator())
          else if (_unchanged)
            const Text(
              'Nothing selected yet. Choose a different size or orientation '
              'to see what changing it would cost.',
              style: TextStyle(color: Colors.black54),
            )
          else if (!choice.isUsable)
            Text(choice.refusal!, style: TextStyle(color: Colors.red.shade700))
          else if (impact != null)
            _ImpactReport(impact: impact, userName: widget.userName),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: impact == null || _working || !choice.isUsable
                ? null
                : _rebuild,
            child: const Text('Rebuild the board'),
          ),
        ),
      ),
    );
  }
}

class _ImpactReport extends StatelessWidget {
  const _ImpactReport({required this.impact, required this.userName});

  final MigrationImpact impact;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            impact.warningFor(userName),
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
        ),
        if (impact.mostPractised.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'The most practised of them',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final word in impact.mostPractised)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${word.label} — ${word.taps} taps, '
                '${word.from} → ${word.to}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        const SizedBox(height: 16),
        // §4.26. Names are per line, and this re-lays every line.
        const Text(
          'Any names you gave rows are dropped. Every row is laid out afresh, '
          'so a name kept would end up over a row you did not name.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        const Text(
          'The board as it is now is kept, not deleted. If this turns out to '
          'be the wrong call, it can be put back exactly as it was.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ],
    );
  }
}

/// Typing the word is the point.
///
/// A rebuild cannot be undone by reflex, so it should not be reachable by
/// reflex either. Anything less than typing is a button somebody taps while
/// thinking about something else.
class _TypeToConfirm extends StatefulWidget {
  const _TypeToConfirm({required this.impact, required this.userName});

  final MigrationImpact impact;
  final String? userName;

  @override
  State<_TypeToConfirm> createState() => _TypeToConfirmState();
}

class _TypeToConfirmState extends State<_TypeToConfirm> {
  final _typed = TextEditingController();
  static const _word = 'REBUILD';

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _typed.text.trim().toUpperCase() == _word;

    return AlertDialog(
      title: const Text('Rebuild the board?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.impact.warningFor(widget.userName),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Type REBUILD to continue.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _typed,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Leave it as it is'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Rebuild'),
        ),
      ],
    );
  }
}
