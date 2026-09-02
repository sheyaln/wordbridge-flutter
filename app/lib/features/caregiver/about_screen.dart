import 'package:flutter/material.dart';

import '../reporting/report.dart';
import '../symbols/symbol_credits.dart';

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
  const AboutScreen({super.key});

  /// The name the commit history carries. One value, so crediting the project
  /// differently is a single change rather than an edit in three places.
  static const developer = 'sheyaln';

  /// Said plainly, and not softened by anything around it. A caregiver, a
  /// teacher or a therapist is entitled to know how the thing was built before
  /// they decide what it is allowed to do, and a disclaimer they have to go
  /// looking for is one they will not find.
  static const disclaimer =
      'This app was developed with the assistance of generative AI.';

  /// What that does and does not cover, said only as far as the repository can
  /// support it. `docs/starter-vocabulary.md` records the core list and its
  /// source, and is equally explicit that most of the remaining words are
  /// judgment rather than evidence. Both halves are stated here for the same
  /// reason they are stated there.
  static const vocabulary =
      'The starter vocabulary is documented. Its core is the Universal Core '
      '36, published by the Center for Literacy and Disability Studies at the '
      'University of North Carolina at Chapel Hill, and the project records '
      'which of the other words come from published research and which are '
      'editorial judgment.';

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
                  'wordbridge',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                // Read from the constants the reports carry, so a version on
                // this screen and a version in a report cannot disagree.
                const Text(
                  'Version $appVersion, build $appBuild',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 28),
                const Text(
                  'wordbridge is written by $developer. It is open source '
                  'under the MIT license. That license covers the app. '
                  'The symbols on the buttons keep their own.',
                  style: _body,
                ),
                const SizedBox(height: 20),
                const Text(disclaimer, style: _body),
                const SizedBox(height: 12),
                const Text(vocabulary, style: _body),
              ],
            ),
          ),
          const Divider(height: 40),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Symbol credits'),
            subtitle: const Text('Who made the pictures, and their licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SymbolCredits()),
            ),
          ),
        ],
      ),
    );
  }
}
