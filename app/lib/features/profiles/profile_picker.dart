import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/seed/age_presets.dart';
import 'profile_repository.dart';
import 'profile_setup.dart';

/// Choosing who is using the device.
///
/// Reached only from caregiver mode. Handing another person's board to a user
/// who has learned this one is a motor-plan hazard on its own, and their usage
/// history is a transcript of somebody's private speech — neither belongs
/// behind a control the user can reach by accident.
class ProfilePicker extends StatefulWidget {
  const ProfilePicker({super.key, required this.db, required this.currentId});

  final WordbridgeDatabase db;
  final String currentId;

  /// Returns the profile to switch to, or null if nothing changed.
  static Future<Profile?> show(
    BuildContext context, {
    required WordbridgeDatabase db,
    required String currentId,
  }) => Navigator.of(context).push<Profile>(
    MaterialPageRoute(
      builder: (_) => ProfilePicker(db: db, currentId: currentId),
    ),
  );

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  late final _repository = ProfileRepository(widget.db);
  late Future<List<Profile>> _profiles = _repository.list();

  void _reload() => setState(() => _profiles = _repository.list());

  Future<void> _add() async {
    final created = await ProfileSetup.show(context, db: widget.db);
    if (created == null || !mounted) return;
    Navigator.of(context).pop(created);
  }

  Future<void> _choose(Profile profile) async {
    await _repository.remember(profile.id);
    if (mounted) Navigator.of(context).pop(profile);
  }

  Future<void> _archive(Profile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${profile.displayName}?'),
        content: const Text(
          'The board, its customisations and its history are kept, not '
          'destroyed. The profile stops appearing here, and it can be brought '
          'back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _repository.archive(profile.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      body: FutureBuilder<List<Profile>>(
        future: _profiles,
        builder: (context, snapshot) {
          final profiles = snapshot.data;
          if (profiles == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            children: [
              for (final profile in profiles)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      profile.displayName.characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text(profile.displayName),
                  subtitle: Text(_describe(profile)),
                  trailing: profile.id == widget.currentId
                      ? const Chip(label: Text('In use'))
                      : IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.archive_outlined),
                          onPressed: () => _archive(profile),
                        ),
                  onTap: profile.id == widget.currentId
                      ? null
                      : () => _choose(profile),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person_add_outlined),
                title: const Text('Add someone'),
                subtitle: const Text('Their own board, settings and history.'),
                onTap: _add,
              ),
            ],
          );
        },
      ),
    );
  }

  String _describe(Profile profile) {
    final birth = profile.birthDate;
    final band = AgeBand.forBirthDate(
      birth == null ? null : DateTime.fromMillisecondsSinceEpoch(birth),
    );
    return '${band.label} · showing words up to level ${profile.vocabLevel}';
  }
}
