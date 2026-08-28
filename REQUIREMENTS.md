# wordbridge — requirements

The durable record of what this is, why, and what it must do. Architecture
decisions live in [docs/adr/](docs/adr/); this is the product-level record.

Status keys: **done** · **agreed, not built** · **open question**

---

## 1. What this is

A free, open-source AAC app with **customizable motor planning**. Every word
has a permanent grid location that never moves as vocabulary grows; unlike
existing motor-planning systems, that layout is editable by the people who
know the user, and the app defends it rather than locking it away.

### The evidence behind that

Not a preference. The clinical literature is specific:

- **Johnson, Inglebret, Jones & Ray (2006)**, *AAC* 22(2):85-99 — the canonical
  AAC abandonment study, 275 ASHA AAC specialists. The **top-ranked** driver of
  inappropriate abandonment is *"Not Maintaining/Adjusting the System."*
  Failure to customize is the field's number-one named cause of AAC failure.
- **Yau et al. (2024)**, *Frontiers in Psychiatry* 15:1385947 — **73–100%** of
  stakeholders report poor customization, sensory overwhelm, or physical
  incompatibility. Parent-carers specifically struggle to adjust vocabulary.
  Also: when a prescribed system wasn't supported at school, switching was
  *"prohibitively expensive"* — **lock-in is itself an abandonment mechanism.**
- **Thistle, Holmes, Horn & Reum (2018)**, *AJSLP* 27(3):1010-1017 — the direct
  support for motor planning. 24 typically developing four-year-olds; consistent
  symbol location went 6.0s → 3.3s over five sessions while the variable-location
  group **did not improve at all**.
- **Light et al. (2004)**, *AAC* 20(2):63-88 — evidence *against* iconic
  encoding: children performed significantly worse with it than with three other
  organizations. Part of why we reject polysemous symbols ([ADR-0002](docs/adr/0002-no-polysemous-symbols.md)).

**Be honest about the evidence.** Motor planning rests on one study of 24
children without disabilities. We build as if it holds because the mechanism is
plausible and the cost of being wrong is low. We do not claim more, and our
materials must not either. LAMP's evidence is thinner than its marketing; a
project positioning itself as the honest alternative cannot inherit that habit.

### What parents actually complained about (App Store reviews, verbatim)

Ranked by how often it recurred:

1. **Data loss** — four independent parents. *"We lost months of custom button
   and phrase building... my wife was almost in tears."* One concluded: *"If
   your app doesn't seem to have problems or issues, don't update it."*
2. **Updates that reset or move things**, including an app-icon change:
   *"My son has been using lamp for eight years and now the poor kid can't find
   it with visual recognition."*
3. **Volume** — three parents over a decade. *"all of this motor planning is
   useless if I cannot hear him... I don't want my son to whisper, I want him
   to talk."*
4. **Crashes** — *"When it doesn't [work] it robs him of his voice."*
5. **Symbol gaps** — *"the word 'sun' has over 10 symbols while 'blueberry'
   does not have a symbol."*

---

## 2. The governing rule

> **Additive changes are safe. Displacing changes are not.**

A change is *displacing* if a word the user has already used moves, disappears,
or acquires a different access sequence. Everything else is additive.

Three consequences, all enforced in code:

- **Position is identity.** Grid locations are permanent rows that exist whether
  or not a word sits on them. Never computed from a button list.
- **Hiding never frees a cell.** This is what lets vocabulary grow without
  relocating anything.
- **Edits are measured against real use.** Usage is logged against the
  *location*, so the editor can say *"Maya has tapped this location 341 times
  in the last 90 days."*

`app/test/motor_plan_invariant_test.dart` enforces this and blocks CI.

---

## 3. Delivered

| | |
|---|---|
| Fixed motor-planning grid, positions stored not computed | **done** |
| Starter vocabulary — Universal Core 36 + ~330 fringe words, clean-room | **done** |
| Automatic paging — a board gets a second page when the grid needs one | **done** |
| Pinned question column and system row on every board, at every grid size | **done** |
| Bundled symbols across four CC BY-SA sets, generated from the vocabulary | **done** |
| On-device TTS, offline, iOS silent-switch handled | **done** |
| Caregiver mode: 2s corner hold → PIN | **done** |
| Board editor: add, move, hide, move between boards | **done** |
| Remap warning quantified in the user's own tap counts | **done** |
| Symbol choice: browse, search, own photo (EXIF stripped) | **done** |
| Usage tracking, off by default, with caregiver summary | **done** |
| Word endings (`+s`/`+ed`/`+ing`/`+'s`) with irregular verbs | **done** |
| Subject-agreeing copula (`am/is/are`, `was/were`) | **done** |
| Articles with `a`→`an` repair | **done** |
| Contextual grammar — endings shown only where valid, in place | **done** |
| Optional verb filtering after a verb | **done** |
| Board creation for subcategories | **done** |
| Symbol credits screen (licence obligation) | **done** |
| OBF/OBZ import and export | **done** |
| Layout derived from vocabulary bands, works at any grid size | **done** |
| Grid chosen at setup from orientation and icon size | **done** |
| Changing it later: measured, typed confirmation, reversible | **done** |
| Profiles with their own board, settings and history | **done** |
| Age presets, with strong language hidden in place rather than absent | **done** |
| Adjustable pause after the board changes | **done** |
| Question mark, using the speech engine's own question intonation | **done** |
| Category keys cycle in place instead of opening a board of categories | **done** |
| New shipped words reach existing boards without moving anything | **done** |
| `yes`, `no`, `don't` and `wait` on the root board | **done** |
| Greetings, toileting, safeguarding and money vocabulary | **done** |
| A picture is found automatically when a word is added | **done** |
| Pictures browsable and searchable, fetched on demand | **done** |

---

## 4. Agreed, not built

### 4.0 Board organisation — settled

**The root board groups by column; category boards group by row.**

On the root board a column encodes Fitzgerald sentence order — who, does, what,
where — so reading left to right builds a sentence. That ordering is fixed and
is not up for redesign.

Category boards have no sentence order to encode, so they group by **word
class** instead, one class per horizontal strip, ordered within the strip by
meaning. Three reasons, in descending order of how well evidenced they are:

- **Row-column scanning.** The first switch press selects a row. On a
  row-grouped board that narrows the choice to a word class; on a
  column-grouped board it narrows to nothing. This is architecture, not
  preference.
- **Word class as the grouping is measured.** Thistle & Wilkinson (2017),
  *AAC* 33(3):160-169 — arranging by word class made children significantly
  faster at building multi-symbol messages. Wilkinson, Gilmore & Qian (2022),
  *JSLHR* 65(2):710-726 — using position to cue grammatical category cut
  fixations on irrelevant symbols.
- **Horizontal adjacency is a preference with a plausible mechanism, not an
  AAC finding.** No study compares row-grouping to column-grouping on a grid.
  Visual performance is better along the horizontal meridian and visual span
  is wider horizontally, but those are foveal text effects and an eleven-cell
  row is scanned with saccades. Say this honestly.

> **Do not cite Light et al. (2004) for this.** It compared taxonomic grids,
> schematic grids, schematic scenes and iconic encoding, and found the first
> three did not differ from each other. It is evidence against iconic
> encoding, which is how §1 uses it, and says nothing about word-class
> arrangement.

Semantic clusters survive as the *ordering inside* a strip rather than as
strips of their own, because children group vocabulary in small event-based
groups rather than taxonomies (Fallon, Light & Achenbach 2003), and because a
strip per cluster costs a row each — eight clusters do not fit in six rows.

### 4.1 Grid geometry, chosen at setup

**Grid dimensions are derived from three explicit choices, not from the device.**

At profile setup the caregiver picks:

1. **Orientation** — landscape or portrait. Not sensed; chosen. The app locks
   to it.
2. **Icon size** — matched to motor ability. Larger targets for imprecise
   reach, smaller where accuracy allows more vocabulary on screen.

Rows and columns follow from `available space ÷ icon size` in the chosen
orientation. Both remain changeable in settings.

> **Re-derivation happens on a settings change and at no other time.**
>
> This is the whole design. Not on rotation, not on device change, not on an OS
> update that shifts the safe area. Exactly one trigger, and it is a person
> deliberately choosing it. Anything implicit would relayout a board someone is
> mid-sentence on, which is the failure this project exists to prevent — and an
> ambiguous trigger ("device change") is one nobody can audit afterwards.

Changing orientation or icon size later **is allowed and must be warned about**,
through the existing destructive-migration path: typed confirmation plus a full
report of every word that moves and how much practice it had. It is the same
warning as a remap, at the scale of a whole board.

Other rules:

- **Text truncates; it never shrinks the icon.** Minimum cell size is the icon
  size.
- **Settings and system icons stay a fixed size** regardless of the grid.

> ⚠️ **Blocker:** the starter vocabulary is a hardcoded 7×12 coordinate table.
> This needs restructuring into **ordered bands** (pronouns, determiners, verbs,
> prepositions, questions) placed deterministically by a layout function, so any
> chosen geometry yields a stable, reproducible layout. Hand-maintaining a
> coordinate table per size does not scale.

### 4.2 Profiles

- Profile selection **on launch**.
- Each profile carries its own settings, vocabulary, and usage history.
- Profile switching stays caregiver-gated — a child must not reach another
  child's board (wrong layout is a motor-plan hazard; it is also another
  person's private history).
- **Creation asks for date of birth.** Vocabulary presets vary by age group.
- **Age-appropriate presets.** Teen and adult presets include profanity and
  adult vocabulary. Rationale is not novelty: autistic adults report commercial
  AAC feels *"infantilizing"*, and censoring vocabulary removes agency from
  people who cannot easily route around it (USSAAC 2022; Martin & Nagalakshmi
  2024, arXiv:2404.17730).
- **Profanity is disable-able** for the age groups that receive it. Default on
  for adult presets, off for child presets.

### 4.2a Pictures for words that have none

**Two jobs, two standards of proof.** They share a source and must not share a
rule.

**Choosing, with a person looking.** The picker searches the four bundled
CC BY-SA sets and fetches more from Global Symbols on demand. Results may be
near misses, because a caregiver deciding that a picture of a cup means
"drink" is judgement, and judgement is what a caregiver is for. A word with no
pictures of its own falls back to the longest word in it — "I need a break"
offers pictures for "break" — and says so, so nobody mistakes a related
picture for an exact one.

**Finding, with nobody looking.** When a word is added, a picture is attached
only if a label matches it *exactly*. The search behind both is a substring
match: "all" returns Ball, "not" returns Notebook, "she" returns Sheep. Nobody
is watching when this runs, so a near miss would be attached silently.

> Curated synonyms are allowed in the offline bundler — `mum`→mother,
> `he`→man, `bathroom`→toilet — and every one must be a **genuine synonym for
> the same referent**. A bus is not a bus stop; "turn" is not "my turn". Audit
> the manifest's `matched` column when adding candidates.

Nothing blocks: the picture is queued and the button shows its word until it
arrives, which is the same thing it shows if it never does.

### 4.3 Word prediction

- Behaves like a touchscreen keyboard's prediction.
- **Learns per profile** — this user's own history, not a global model.
- Must not relocate anything. Predictions appear in a dedicated region, never
  by rearranging grid cells. *(Nieder 2014 names predictive reordering as a
  motor-planning killer.)*

### 4.4 Voice and tone

- **Configurable voices:** male, female, and variations within each.
- **Tone presets:** calm, urgent, joking, sarcastic, and others.
- **In-app volume** independent of system volume: maximum is a *yell*, minimum
  audible is a *whisper*.

> ⚠️ **Honest limits of platform TTS.** `flutter_tts` exposes rate, pitch and
> volume, and nothing else. That genuinely supports **urgent** (faster, higher,
> louder) and **calm** (slower, lower, quieter). It does **not** support
> **sarcasm** — that needs prosodic contour control no platform TTS offers —
> and a true **whisper** needs breathiness, which is not a parameter. Low volume
> plus low pitch approximates it and will not sound like whispering.
>
> Real tone control means a bundled neural voice (Piper/Kokoro via
> `react-native-executorch`-equivalents, or on-device SSML where supported).
> That is a substantial piece of work. **Do not ship "sarcastic" as a preset
> that merely changes speed** — a preset that does not do what it says is worse
> than an absent one, particularly for a user who cannot hear the mismatch and
> correct it.

### 4.5 Neural voice — roadmap, not near-term

Real tone control and a convincing whisper need a bundled on-device neural
voice (Piper/Kokoro class) rather than platform TTS. That unlocks genuine
prosody, breathiness, and a voice that does not sound like every other AAC
user's — which autistic adults name directly: *"having the voice that matches
every other person who uses AAC is very disempowering."*

Substantial work: model size, licensing, per-locale coverage, and latency all
need answering. Keep `SpeechEngine` engine-agnostic so this stays a swap rather
than a rewrite. Until then, ship only the tones platform TTS can honestly
produce.

### 4.6 Still to do

Carried forward, in the order they matter:

- **Word prediction** (§4.3) and **voice and tone** (§4.4) are the two
  remaining features from the original scope. Neither is started.
- **Level does double duty** — it decides both what is drawn on day one and
  what a small grid sheds first. Those are different questions.
- **Word endings and articles shed first on a small grid**, because they are
  all level 2 with the highest shed ranks. So the users least able to afford
  an extra movement are the ones who lose the grammar engine. Worth a
  deliberate decision rather than leaving it as fallout.
- **`docs/starter-vocabulary.md` does not exist** though `core_vocabulary.dart`
  cites it and §7 calls the clean-room derivation "the evidence". Given the
  trademark position, that is the one document that should exist.
- **The root board has little slack left.** Two name cells beside the pronouns
  and one noun column. Further additions there displace something.

### 4.7 Everything above is toggleable

Every feature in §4 must be individually switchable per profile. Defaults
should favour the simplest, most stable board; complexity is opt-in.

---

## 5. Non-negotiables

Violating any of these is a bug regardless of what else it buys.

1. **Nothing stands between a user and speech.** Speech happens before logging;
   the logger cannot throw. A database failure must never cost a word.
2. **Never lose customizations.** Autosave, versioned, restorable. The most
   common parent complaint about the incumbent.
3. **Updates never move anything.** Board layout is user data, not app data.
   Layout changes are opt-in, previewable, reversible.
4. **Works fully offline.** No network for any core function.
5. **Audible in the real world** — output gain above system maximum.
6. **A crash never leaves a user with nothing.** Error boundary degrading to a
   minimal always-working core board.
7. **Usage tracking is off by default** and never leaves the device. An AAC log
   is a transcript of a disabled person's private speech.
8. **A location the user cannot see never speaks.** Whatever is behind a
   mask — a word above the current level, a word switched off, an ending that
   does not apply yet — a blank that says a word nobody chose is worse than
   one that does nothing.
9. **Never a wrong symbol.** A blank button says "no picture yet" honestly; a
   plausible wrong one teaches a false association to someone who cannot easily
   contradict it. *(The fetcher initially matched "not"→Notebook, "she"→Sheep.
   Exact matches only, no fuzzy fallback.)*
10. **Symbol licence boundary holds.** ARASAAC and Sclera are CC BY-**NC** and are
   never bundled — opt-in download only. CI enforces this
   (`tools/check_symbol_boundary.sh`).
11. **No polysemous symbols.** One button, one meaning
    ([ADR-0002](docs/adr/0002-no-polysemous-symbols.md)).

---

## 5.1 Standing decisions

- **Auto-return after a word is a setting, not a rule.** On by default,
  because it is what makes a word's motor path fixed rather than dependent on
  where the user happened to be. Off suits someone building longer utterances
  out of one category.
- **The board pauses briefly after it changes**, ignoring taps for an
  adjustable interval, default half a second, zero to switch it off. A finger
  already on its way down when the screen changes otherwise lands on whatever
  now occupies that location. This is the only place anything deliberately
  stands between a user and speech, which is why it is short and removable.
- **`more categories` turns the keys in place**; it never opens a board of
  categories. A board would put every category two movements away instead of
  one.
- **`more words` is the paging key.** Both keys say what they do.

- **A word may hold two locations on two different boards** where both are
  logical — `doctor` on people and on body, `outside` on play and on places.
  One word twice on *one* board is a defect, not a choice.
- **Vocabulary level does double duty**: it decides what is drawn on day one
  *and* what a small grid sheds first. Those are different questions and the
  conflation is known. Worth separating if it starts to bite.
- **Level 3 is "the grid decides"**: words seeded at level 3 shed to a later
  page on a tight grid and sit on the root board on a roomier one. The
  cognition verbs (know, think, say, tell, see, come, give, feel) live here,
  because the 7x12 verb band is exactly full and every alternative meant
  dropping a Universal Core word or reversing an explicit layout request.

## 6. Open questions

- **Does `back` earn its slot?** With auto-return and a pinned `home`, it may be
  redundant. Usage data will answer this; don't guess.
- **Is 7×12 right on a mini?** Resolved as "not too dense" by observation, but
  superseded by §4.1.
- **Free personal-team signing expires after 7 days.** Fine for development,
  unacceptable for a real user. Needs a paid account before anyone relies on it.
- **Irregular verbs added through the editor** get regular endings — `swim`
  would become `swimmed`. The table is developer-maintained; the editor does not
  prompt for it.
- **Grammar availability reads only the immediately preceding word.** "I want a
  drink" hides `+ed` even though you might want to inflect `want`. Fixing that
  needs a notion of which word is being edited.

---

## 7. Legal

- **Code:** MIT. Apache-2.0 has a live argument in its favour given the patent
  below; decide deliberately rather than by default.
- **Symbols:** bundled sets are CC BY-SA / CC BY (commercial use permitted).
  ARASAAC and Sclera are CC BY-NC and must never be bundled. See
  [NOTICE.md](NOTICE.md).
- **US9336198B2** (PRC, active to 2033) covers navigating *polysemous* symbols
  across linked overlays. We do not build that — see ADR-0002. The foundational
  Minspeak patents have expired. User has taken the legal question off the
  engineering track; do not re-litigate it.
- **"LAMP" is a PRC-Saltillo trademark.** Keep it out of the app name, bundle
  id, and store listing. The starter vocabulary is clean-room; its derivation is
  the evidence.
