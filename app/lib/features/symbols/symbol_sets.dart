/// The symbol sets more than one pack can serve, declared once.
///
/// Stellar and OpenMoji pictures ship inside the `core` pack *and* are
/// searchable through Global Symbols. Written out twice they would be two sets
/// with one name, and switching "OpenMoji" off would silence the search while
/// the shipped board carried on drawing OpenMoji. One record, referenced by
/// both packs, is what makes the switch mean what it says.
///
/// Everything here permits commercial use. The noncommercial sets stay with
/// the pack that reaches them — `GlobalSymbolsPack.nonCommercialSets`,
/// `ArasaacPack` — so a fork that is sold deletes those files whole rather
/// than editing a shared list correctly. See NOTICE.md.
library;

import 'symbol_pack.dart';

/// In preference order for search. Mulberry leads because it is a
/// purpose-built AAC set with a consistent drawn style, and its own two
/// extension sets follow it because they are drawn to match; the rest fill its
/// gaps in abstract core vocabulary. Mixing styles costs visual consistency,
/// and a blank button costs more.
const globalSymbolsCommercialSets = <SymbolSet>[
  mulberrySet,
  mulberryPlusSet,
  mulberryAdditionalSet,
  stellarSymbolsSet,
  tawasolSet,
  openmojiSet,
];

const mulberrySet = (
  slug: 'mulberry',
  name: 'Mulberry Symbols',
  attribution:
      'Mulberry Symbols © Garry Paxton 2008-2017, Steve Lee 2018-. '
      'CC BY-SA 4.0. https://mulberrysymbols.org',
  license: 'CC-BY-SA-4.0',
  allowsCommercialUse: true,
);

const mulberryPlusSet = (
  slug: 'corona-symbols',
  name: 'Mulberry Plus Collection',
  attribution:
      'Mulberry Plus Collection © Mulberry and Global Symbols. '
      'CC BY-SA 4.0. https://globalsymbols.com',
  license: 'CC-BY-SA-4.0',
  allowsCommercialUse: true,
);

const mulberryAdditionalSet = (
  slug: 'additional-mulberry-symbols',
  name: 'Mulberry Additional Symbols',
  attribution:
      'Mulberry Additional Symbols © Verlag Karin Kestner GmbH. '
      'CC BY-SA 4.0. https://www.kestner.de',
  license: 'CC-BY-SA-4.0',
  allowsCommercialUse: true,
);

/// Also bundled: `core` ships 111 of these, and the manifest files each of
/// them under this slug.
const stellarSymbolsSet = (
  slug: 'stellar-symbols',
  name: 'Stellar Symbols',
  attribution: 'Stellar Symbols © Colin McNamee. CC BY-SA 4.0.',
  license: 'CC-BY-SA-4.0',
  allowsCommercialUse: true,
);

const tawasolSet = (
  slug: 'tawasol',
  name: 'Tawasol',
  attribution:
      'Tawasol Symbols © Mada, Qatar. CC BY-SA 4.0. '
      'http://tawasolsymbols.org',
  license: 'CC-BY-SA-4.0',
  allowsCommercialUse: true,
);

/// Also bundled, as [stellarSymbolsSet] is: 153 of `core`'s pictures.
const openmojiSet = (
  slug: 'openmoji',
  name: 'OpenMoji',
  attribution:
      'OpenMoji © OpenMoji Project. CC BY-SA 4.0. https://openmoji.org',
  license: 'CC-BY-SA-4.0',
  allowsCommercialUse: true,
);
