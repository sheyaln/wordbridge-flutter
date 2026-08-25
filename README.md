# wordbridge

A free, open-source AAC app with **customizable motor planning**.

Every word lives at a permanent grid location that never moves as vocabulary grows — the mechanism behind LAMP-style motor planning. Unlike existing motor-planning systems, that layout is customizable by the people who actually know the user, and the app defends the layout from careless edits instead of locking it away.

**Status: pre-alpha. Nothing works yet.** Don't put this on a device anyone depends on.

## Why

The dominant motor-planning AAC app costs $299.99, is iPad-only, ties its licence to a single non-transferable Apple ID, and stores boards in a closed format. Families who need a word that isn't there — a sibling's name, a food from their culture, a special interest, a second language — often can't add it where it belongs.

The clinical literature is blunt about the cost of that. Johnson et al. (2006), the canonical AAC abandonment study of 275 AAC specialists, found the top-ranked driver of abandonment is **"Not Maintaining/Adjusting the System."** Failure to customize is the field's number-one named cause of AAC failure. Yau et al. (2024) found 73–100% of stakeholders reporting poor customization, with parents specifically struggling to adjust vocabulary.

So the goal isn't "editable boards" — every generic grid app has those. It's an editor that understands the difference between a safe edit and a harmful one.

## The core idea

> **Additive changes are safe. Displacing changes are not.**

A change is *displacing* if a word the user has already learned moves, disappears, or gets a different access sequence. Everything else — filling an empty cell, revealing a hidden one, changing a label or symbol or voice — is additive and clinically fine.

Three consequences shape the whole codebase:

1. **Position is identity.** Every grid location is a permanent database row that exists whether or not a word sits on it. Positions are never computed from a list of buttons, because computed positions are exactly how grid apps end up silently reshuffling.
2. **Hiding a word never frees its cell.** This single rule is what lets vocabulary grow over time *and* never relocate. Unhide a word after six months and it appears exactly where it always was.
3. **Edits are measured against real use.** Usage is logged against the *location*, not the word, so the editor can say: *"Maya has tapped this location 341 times in the last 90 days. Moving it may take weeks to relearn."*

There's a CI-blocking test that simulates full vocabulary growth and fails the build if any existing word's motor path changes by a single byte.

## Scope

**In scope for v1**

- Fixed motor-planning grid with caregiver-customizable layout
- Multiple user profiles, PIN-gated caregiver mode, device lockdown
- On-device text-to-speech, fully offline
- Consent-gated usage logging with a caregiver summary
- Open Board Format (`.obf` / `.obz`) import and export

**Not in v1:** cloud sync, goal tracking, eye-gaze and head tracking, visual scene displays, message banking, AI sentence generation.

**Deliberately never:** semantic compaction with on-button destination indicators.

## Evidence, honestly

The evidence for motor planning is thinner than the marketing around it. The direct experimental support is essentially one study — Thistle et al. (2018), 24 typically developing four-year-olds — where consistent symbol location nearly halved selection time (6.0s → 3.3s) while the variable-location group did not improve at all. There is also a peer-reviewed result, Light et al. (2004), where iconic encoding performed *worse* than three other layout strategies for children of the same age.

We build as if consistent location matters, because the mechanism is plausible and the cost of being wrong is low. We are not going to claim more than that, and neither should anyone shipping a fork.

## Licensing

Code is MIT — see [LICENSE](LICENSE).

Symbol libraries are **not** covered by that and carry their own terms. The bundled sets (Mulberry, OpenMoji, Twemoji, Tawasol) are CC BY-SA or CC BY and permit commercial use with attribution. ARASAAC and Sclera are **CC BY-NC — non-commercial only** — and are therefore *never bundled*; they are opt-in downloads, so the restriction attaches to a user's choice rather than to this project's distribution.

See [NOTICE.md](NOTICE.md) for full attribution and [docs/symbol-packs.md](docs/symbol-packs.md) for what that means if you fork this commercially.

"LAMP" and "LAMP Words for Life" are trademarks of PRC-Saltillo. This project is not affiliated with, endorsed by, or derived from them, and its vocabulary layout is independently designed — see [docs/starter-vocabulary.md](docs/starter-vocabulary.md).

## Development

Requires Flutter 3.44+ / Dart 3.12+. See [CONTRIBUTING.md](CONTRIBUTING.md).

```
flutter pub get
flutter test
flutter run
```

Architecture decisions live in [docs/adr/](docs/adr/). Start with [ADR-0001](docs/adr/0001-project-thesis.md).
