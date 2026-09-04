import 'package:flutter/material.dart';

import '../auth/hold_ring.dart';
import '../developer/developer_mode.dart';
import '../reporting/report.dart';
import '../symbols/symbol_credits.dart';
import '../symbols/symbol_registry.dart';

/// Who made this app, what it may be used under, and how it was built.
///
/// The people deciding whether to trust this with a child read the app, not the
/// repository, so everything they would have to take somebody's word for is on
/// one screen inside it: the version in front of them, the license, and the
/// fact that generative AI was used to build it.
///
/// Prose rather than a page of controls, which is why the settings row opens it
/// directly (§4.43a). There is one thing to press on it, and that is a second
/// screen rather than a hop to one.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.developerMode, this.registry});

  /// Where developer mode is switched on, or null on a build that has no such
  /// thing.
  ///
  /// It lives here rather than as a row in the settings list because a row is
  /// a thing a caregiver reads on their way past, and this is not for them. It
  /// is behind the gesture and the PIN already; what the hold on the version
  /// adds is that nobody arrives at it while looking for something else.
  final DeveloperMode? developerMode;

  /// Passed through to the credits, which need it to name the sets a fetching
  /// pack reaches. Those ship no manifest, so without it they are credited
  /// nowhere a person can reach and every one of them is CC BY-SA.
  final SymbolRegistry? registry;

  /// The people, not the account. The commit history carries a handle; a
  /// caregiver deciding whether to trust this with a child is owed names.
  static const developer = 'Shey Al and Haley Dalrymple';

  /// Said plainly, and not softened by anything around it. A caregiver, a
  /// teacher or a therapist is entitled to know how the thing was built before
  /// they decide what it is allowed to do, and a disclaimer they have to go
  /// looking for is one they will not find.
  static const disclaimer =
      'This app was developed with the assistance of generative AI.';

  /// Where the core list came from, credited as its publisher asks.
  ///
  /// The paragraph this replaced also said which of the *other* words are
  /// research and which are judgment. True, and it belongs in
  /// `starter-vocabulary.md` where the derivation actually is — a credit line
  /// is for saying who to credit.
  static const vocabulary =
      'Universal Core 36, by Center for Literacy and Disability Studies, '
      'University of North Carolina';

  /// Where the board's arrangement comes from.
  ///
  /// The colors and the left to right sentence order are not this project's
  /// invention: they are the Modified Fitzgerald Key, which descends from a
  /// scheme Edith Fitzgerald built for deaf education in the 1920s and which
  /// most of the AAC field has used since. `lib/theme/fitzgerald.dart` carries
  /// the same attribution beside the colors themselves.
  static const layout =
      'Modified Fitzgerald Key, after Edith Fitzgerald, for the colors and '
      'the left to right sentence order';

  static const _body = TextStyle(height: 1.5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wordbridge AAC',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                // Read from the constants the reports carry, so a version on
                // this screen and a version in a report cannot disagree.
                //
                // It is also the way into developer mode, held. Nothing says
                // so, on the principle the corner target is built on: an
                // affordance is an invitation, and this one is not addressed
                // to whoever is reading the page.
                if (developerMode case final mode?)
                  _HoldTheVersion(developer: mode)
                else
                  const Text(
                    'Version $appVersion, build $appBuild',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                const SizedBox(height: 28),
                const _Fact('Developed by', developer),
                const _Fact('License', 'MIT'),
                const _Fact('Core vocabulary', vocabulary),
                const _Fact('Home board layout', layout),
                const SizedBox(height: 16),
                const Text(disclaimer, style: _body),
              ],
            ),
          ),
          const Divider(height: 40),
          // Said out loud once it is on, because a mode that draws on somebody
          // else's board has to be visible from inside the settings as well as
          // from the board itself.
          if (developerMode != null && developerMode!.enabled)
            ListTile(
              leading: const Icon(Icons.developer_mode),
              title: const Text('Developer mode is on'),
              subtitle: const Text('The board says so while it is'),
              trailing: TextButton(
                onPressed: () => developerMode!.setEnabled(false),
                child: const Text('Turn it off'),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Symbol credits'),
            subtitle: const Text('Who made the pictures, and their licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SymbolCredits(registry: registry),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled fact, in the shape somebody scans rather than reads.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
      ],
    ),
  );
}

/// The version, and a five second hold on it.
///
/// The convention every Android tablet already carries, in the shape this app
/// uses for a hold: nothing drawn until it is underway, every press starting
/// the count over, and a question at the end rather than a mode that simply
/// arrives. Five seconds accumulated across a morning of touches is not a
/// decision anybody made.
class _HoldTheVersion extends StatefulWidget {
  const _HoldTheVersion({required this.developer});

  final DeveloperMode developer;

  static const holdDuration = Duration(seconds: 5);

  @override
  State<_HoldTheVersion> createState() => _HoldTheVersionState();
}

class _HoldTheVersionState extends State<_HoldTheVersion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _HoldTheVersion.holdDuration)
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          _release();
          _ask();
        });

  bool _holding = false;

  void _start(_) {
    setState(() => _holding = true);
    _controller.forward(from: 0);
  }

  void _release([_]) {
    _controller.stop();
    _controller.value = 0;
    if (mounted && _holding) setState(() => _holding = false);
  }

  Future<void> _ask() async {
    if (widget.developer.enabled) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn developer mode on?'),
        content: const Text(
          'Draws what the board knows about itself over the top of it, and '
          'lets a location be held to open what is behind it. It does not '
          'change a word, a location or a voice.\n\n'
          'The board says so in a strip while it is on, and that strip turns '
          'it off again.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn it on'),
          ),
        ],
      ),
    );

    if (yes == true) await widget.developer.setEnabled(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _start,
      onPointerUp: _release,
      onPointerCancel: _release,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          const Text(
            'Version $appVersion, build $appBuild',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          // Reserved whether or not anything is drawn in it, so the line does
          // not move under a finger halfway through the hold.
          SizedBox(
            width: 28,
            height: 28,
            child: _holding
                ? AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) =>
                        HoldRing(progress: _controller.value),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
