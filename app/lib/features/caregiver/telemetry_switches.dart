import 'package:flutter/material.dart';

import '../profiles/profile_settings.dart';

/// The two switches that decide what leaves this tablet on its own (§4.59).
///
/// One widget rather than two copies, because they appear in two places —
/// Reports, and the neural voice screen — and two renderings of one setting is
/// how the two come to disagree. Being in agreement is a property of there
/// being one implementation, not of anybody keeping them in step.
///
/// Both write straight to [ProfileSettings], which is the single stored
/// answer. A surface that showed a stale value would be lying about what the
/// app is going to do.

/// Whether faults this tablet caught are sent on the next launch.
class CrashReportSwitch extends StatelessWidget {
  const CrashReportSwitch({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ProfileSettings? settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final on = settings?.crashReports ?? false;
    return SwitchListTile(
      value: on,
      title: const Text('Send crash reports'),
      isThreeLine: true,
      subtitle: const Text(
        'If the app stops working, what went wrong is sent the next time it '
        'opens. It carries the version, the tablet model and the grid size. '
        'Never a board word or a name.',
      ),
      onChanged: settings == null
          ? null
          : (v) async {
              await settings!.set('crashReports', v);
              onChanged();
            },
    );
  }
}

/// Whether measurements of the neural voice travel with a report.
///
/// [available] is whether a neural voice is switched on at all. Off, this is
/// shown disabled rather than hidden: a switch that vanishes reads as a
/// feature that was removed, and one that is present and inert says what it
/// is waiting for.
class VoiceMeasurementSwitch extends StatelessWidget {
  const VoiceMeasurementSwitch({
    super.key,
    required this.settings,
    required this.available,
    required this.onChanged,
  });

  final ProfileSettings? settings;
  final bool available;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    // Reported off where nothing is producing measurements, whatever is
    // stored. A stored yes survives the voice being switched off and comes
    // back with it, so turning the voice off and on again does not quietly
    // discard an answer somebody gave.
    final on = available && (settings?.voiceMeasurements ?? false);

    return SwitchListTile(
      value: on,
      isThreeLine: true,
      title: const Text('Send how the neural voice is performing'),
      subtitle: Text(
        available
            ? 'Timings, which voice, and how often it fell back to the device '
                  'voice. Never what was said.'
            : 'Turn the neural voice on to send timings from it.',
      ),
      onChanged: settings == null || !available
          ? null
          : (v) async {
              await settings!.set('voiceMeasurements', v);
              onChanged();
            },
    );
  }
}
