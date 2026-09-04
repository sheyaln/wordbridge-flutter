import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/seed/age_presets.dart';
import '../auth/caregiver_gesture.dart';
import 'grid_choice.dart';
import 'profile_settings.dart';
import 'profile_repository.dart';

/// How much of the vocabulary starts out drawn, asked as what a person can do.
///
/// A caregiver knows whether words are being put together and does not know
/// what "level 2" means, so the question is about the person and the level is
/// what the answer sets. Each answer names what it costs: the first board
/// carries no copula and no endings, which is the Universal Core's own shape
/// and is also why it cannot say "are you ok?" or anything in the past.
enum _Readiness {
  single(
    1,
    'Single words',
    'Core vocabulary only: the Universal Core 36 plus “maybe”. No word '
        'endings and no am, is or are, so no past tense and no “are you ok?”.',
  ),
  combining(
    2,
    'Short sentences',
    'Adds the grammar keys: word endings, a and the, am, is and are. Plus '
        'everyday fringe vocabulary: food, feelings, places.',
  ),
  whole(
    3,
    'Full vocabulary',
    'Every word this board set carries, including any added later.',
  );

  const _Readiness(this.level, this.label, this.description);

  final int level;
  final String label;
  final String description;
}

/// Setting up a person.
///
/// Five questions, on one page, with their consequences visible. A wizard
/// would hide the fact that icon size and orientation decide each other's
/// answers, and this is the one moment where the grid is chosen — everything
/// after it is either additive or an explicit, warned migration.
class ProfileSetup extends StatefulWidget {
  const ProfileSetup({super.key, required this.db, this.isFirstRun = false});

  final WordbridgeDatabase db;
  final bool isFirstRun;

  static Future<Profile?> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    bool isFirstRun = false,
  }) => Navigator.of(context).push<Profile>(
    MaterialPageRoute(
      builder: (_) => ProfileSetup(db: db, isFirstRun: isFirstRun),
    ),
  );

  @override
  State<ProfileSetup> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<ProfileSetup> {
  final _name = TextEditingController();

  DateTime? _birthDate;
  BoardOrientation _orientation = BoardOrientation.landscape;
  IconSize _iconSize = IconSize.medium;
  bool? _profanity;
  int? _vocabLevel;

  /// On unless somebody says otherwise, and asked at setup either way (§7).
  bool _usageTracking = ProfileSettings.usageTrackingForNewProfiles;

  /// Whether a fault this tablet catches is sent on the next launch (§4.59).
  bool _crashReports = ProfileSettings.crashReportsForNewProfiles;
  bool _creating = false;

  /// Asked on the first run and nowhere else.
  ///
  /// It belongs to the device, not to the person speaking on it, so a
  /// caregiver setting up a fourth profile has already answered it. Asking
  /// again would imply the answer could differ per person, which would mean
  /// four gestures on one tablet and none of them reliable.
  CaregiverGesture _gesture = CaregiverGesture.cornerHold;

  /// How long that gesture is held for.
  ///
  /// Adjustable here rather than only in caregiver settings, which are behind
  /// the gesture being configured: a caregiver who finds two seconds too easy
  /// to trigger by accident, or too hard to hold, had to get through the door
  /// to change the door.
  Duration _hold = CaregiverEntry.defaultCornerHold;

  /// The range in caregiver settings, and the same reasoning: a hold nobody
  /// wants to sit through at one end, one nobody produces by resting a hand at
  /// the other.
  static const _shortestHold = 1;
  static const _longestHold = 20;

  AgeBand get _band => AgeBand.forBirthDate(_birthDate);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Size _screen(BuildContext context) => MediaQuery.sizeOf(context);

  GridChoice _choiceFor(BuildContext context, IconSize size) =>
      GridChoice.derive(
        screen: _screen(context),
        orientation: _orientation,
        iconSize: size,
      );

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 8, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Date of birth',
    );

    if (picked != null) {
      setState(() {
        _birthDate = picked;
        // The default follows the new band unless it has been set by hand.
        _profanity = null;
        _vocabLevel = null;
      });
    }
  }

  Future<void> _create() async {
    final choice = _choiceFor(context, _iconSize);
    if (!choice.isUsable || _creating) return;

    setState(() => _creating = true);

    try {
      if (widget.isFirstRun) {
        await CaregiverEntryStore(widget.db).write(
          const CaregiverEntry.standard().withGesture(_gesture).withHold(_hold),
        );
      }

      final profile = await ProfileRepository(widget.db).create(
        displayName: _name.text.trim().isEmpty
            ? 'wordbridge'
            : _name.text.trim(),
        grid: choice,
        birthDate: _birthDate,
        profanity: _profanity,
        vocabLevel: _vocabLevel,
        usageTracking: _usageTracking,
        crashReports: _crashReports,
      );

      if (mounted) Navigator.of(context).pop(profile);
    } catch (error) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not set up: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choiceFor(context, _iconSize);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isFirstRun ? 'Set up Wordbridge AAC' : 'New profile',
        ),
        automaticallyImplyLeading: !widget.isFirstRun,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          _Section(
            title: 'Who is this for?',
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText:
                    'Added to the home board as a button, so it is spoken '
                    'aloud. It also names this profile in settings.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          _Section(
            title: 'Date of birth',
            note:
                'Sets the starting vocabulary level and the fringe vocabulary '
                'for that age.',
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cake_outlined),
                    label: Text(
                      _birthDate == null
                          ? 'Choose a date (optional)'
                          : '${_birthDate!.day}/${_birthDate!.month}/'
                                '${_birthDate!.year}',
                    ),
                    onPressed: _pickBirthday,
                  ),
                ),
                if (_birthDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _birthDate = null;
                      _profanity = null;
                      _vocabLevel = null;
                    }),
                  ),
                ],
              ],
            ),
          ),

          _Chip(label: _band.label, description: _band.description),

          _Section(
            title: 'How is the device held?',
            note:
                'The board locks to this, so rotating the device never '
                'rearranges it.',
            child: Row(
              children: [
                for (final option in BoardOrientation.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _OptionCard(
                        title: option.label,
                        subtitle: option.description,
                        selected: _orientation == option,
                        onTap: () => setState(() => _orientation = option),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          _Section(
            title: 'Button size',
            note:
                'Match this to how accurately they can point. Larger buttons '
                'fit fewer words on each page.',
            child: Column(
              children: [
                for (final size in IconSize.values)
                  _SizeOption(
                    size: size,
                    choice: _choiceFor(context, size),
                    selected: _iconSize == size,
                    onTap: () => setState(() => _iconSize = size),
                  ),
              ],
            ),
          ),

          _Section(
            title: 'Vocabulary level',
            note:
                'Adjustable at any time. Raising or lowering it moves '
                'nothing, so motor planning is preserved.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final option in _Readiness.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _OptionCard(
                      title: option.label,
                      subtitle: option.description,
                      selected:
                          (_vocabLevel ?? _band.startingLevel) == option.level,
                      onTap: () => setState(() => _vocabLevel = option.level),
                    ),
                  ),
              ],
            ),
          ),

          if (_band.canSwear)
            _Section(
              title: 'Strong language',
              note:
                  'Turning this off hides these words in place. Turning it '
                  'back on shows them in the same locations.',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include swearing'),
                value: _profanity ?? _band.swearsByDefault,
                onChanged: (v) => setState(() => _profanity = v),
              ),
            ),

          if (widget.isFirstRun)
            _Section(
              title: 'Access to settings',
              note:
                  'Set once for this device, not per profile. The board '
                  'carries no settings button, so this is the way in.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final option in CaregiverGesture.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OptionCard(
                        title: option.label,
                        subtitle: option.description,
                        selected: _gesture == option,
                        // Each gesture has its own sensible length, and
                        // switching between them is choosing a gesture rather
                        // than carrying a number across.
                        onTap: () => setState(() {
                          _gesture = option;
                          _hold = const CaregiverEntry.standard()
                              .withGesture(option)
                              .hold;
                        }),
                      ),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Held for ${_hold.inSeconds} seconds'),
                    subtitle: Slider(
                      value: _hold.inSeconds.toDouble().clamp(
                        _shortestHold.toDouble(),
                        _longestHold.toDouble(),
                      ),
                      min: _shortestHold.toDouble(),
                      max: _longestHold.toDouble(),
                      divisions: _longestHold - _shortestHold,
                      label: '${_hold.inSeconds}s',
                      onChanged: (value) => setState(
                        () => _hold = Duration(seconds: value.round()),
                      ),
                    ),
                  ),
                  if (_gesture == CaregiverGesture.twoCorners)
                    _Note(
                      'Holding one corner on its own also works, at '
                      '${CaregiverEntry.oneHandedFallback.inSeconds} seconds '
                      'rather than ${_hold.inSeconds}. That route cannot be '
                      'turned off: two corners needs two hands, and whoever '
                      'picks this device up next may not have them.',
                    ),
                ],
              ),
            ),

          // Asked here rather than left to be found in settings. A usage log
          // is a transcript of this person's private speech (§7), so it is
          // consent, and consent that is opt-in by silence is not consent.
          //
          // It is also the setting most worth having on from day one: it is
          // what lets the editor say "this location has 341 taps" before a
          // caregiver moves a word, and switched on a year late it can only
          // speak for the year it has seen.
          _Section(
            title: 'Usage tracking',
            note:
                'A record of which locations are selected, kept on this '
                'device. You can turn it off or delete it at any time.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OptionCard(
                  title: 'Track usage',
                  subtitle:
                      'Shows how much practice a location has had before you '
                      'move a word, and what has been said.',
                  selected: _usageTracking,
                  onTap: () => setState(() => _usageTracking = true),
                ),
                const SizedBox(height: 8),
                _OptionCard(
                  title: 'Do not track usage',
                  subtitle:
                      'The board behaves identically. The editor cannot tell '
                      'you what moving a word will cost.',
                  selected: !_usageTracking,
                  onTap: () => setState(() => _usageTracking = false),
                ),
              ],
            ),
          ),

          // The other half of the question, and a different one: the log above
          // never leaves the tablet, and this does (§4.59).
          _Section(
            title: 'Crash reports',
            note:
                'Sent the next time the app opens, never while it is being '
                'used. Changeable later under Reports.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OptionCard(
                  title: 'Send crash reports',
                  subtitle:
                      'The version, the device model, the grid size and what '
                      'went wrong. Never a board word or a name.',
                  selected: _crashReports,
                  onTap: () => setState(() => _crashReports = true),
                ),
                const SizedBox(height: 8),
                _OptionCard(
                  title: 'Do not send crash reports',
                  subtitle:
                      'Faults are still recorded on the device, and can be '
                      'sent by hand from Reports.',
                  selected: !_crashReports,
                  onTap: () => setState(() => _crashReports = false),
                ),
              ],
            ),
          ),

          // A rule, not a gap. Everything above is a question being asked;
          // the summary below is the answer the board was already built from,
          // and eight pixels of air read as one more question somebody forgot
          // to answer.
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(height: 1),
          ),
          _GridSummary(choice: choice),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: choice.isUsable && !_creating ? _create : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _creating
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Build the board'),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.note});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A consequence of the answer just given, shown under the answer.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.description});

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF33691E)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label. $description',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF1B5E20) : Colors.black12,
            width: selected ? 2 : 1,
          ),
          color: selected ? const Color(0xFFF1F8E9) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

/// One icon size, showing what it actually costs.
///
/// The grid it produces and the number of locations are both shown, because
/// "large" and "extra large" mean nothing on their own — the decision is
/// between target size and how much vocabulary is visible, and a caregiver
/// cannot weigh that without the numbers.
class _SizeOption extends StatelessWidget {
  const _SizeOption({
    required this.size,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final IconSize size;
  final GridChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final usable = choice.isUsable;

    return Opacity(
      opacity: usable ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: usable ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0xFF1B5E20) : Colors.black12,
                width: selected ? 2 : 1,
              ),
              color: selected ? const Color(0xFFF1F8E9) : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 8.0 + IconSize.values.indexOf(size) * 9,
                    height: 8.0 + IconSize.values.indexOf(size) * 9,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        size.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        usable
                            ? '${size.description}  ·  ${choice.rows} × '
                                  '${choice.cols}, ${choice.locationsPerBoard} '
                                  'locations a board'
                            : choice.refusal!,
                        style: TextStyle(
                          fontSize: 12,
                          color: usable ? Colors.black54 : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridSummary extends StatelessWidget {
  const _GridSummary({required this.choice});

  final GridChoice choice;

  @override
  Widget build(BuildContext context) {
    if (!choice.isUsable) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          choice.refusal!,
          style: TextStyle(fontSize: 13, color: Colors.red.shade900),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${choice.rows} rows × ${choice.cols} columns',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Every word takes a permanent location on this grid. Changing the '
            'orientation or button size later rebuilds the board set and '
            'moves every word.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
