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
