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
| Word prediction in its own strip, learned per profile, on for new profiles | **done** |
| Breadcrumb trail of the route to a word, on for new profiles | **done** |
| Yes/no and wh-questions — "are you ok?", "what is that?" | **done** |
| A new shipped board reaches profiles already in use, moving nothing | **done** |
| Related verbs side by side, and a `doing` board for the rest | **done** |
| The picture chosen for a button is the picture drawn | **done** |
| Pictures visible in the editor, with "no picture" the loudest thing there | **done** |
| PIN recovery: hold, type RESET, set a new one. Board untouched | **done** |
| Voice choice, offline voices only, per profile | **done** |
| Tone, speed, pitch and volume, each previewed as a spoken sentence | **done** |

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

### 4.3 Word prediction — built

Behaves like a touchscreen keyboard's prediction, learned per profile, in its
own strip above the grid. It never rearranges the board — *(Nieder 2014 names
predictive reordering as a motor-planning killer)*.

Six rules hold it in place:

- **Only words already on this user's boards.** A suggestion is a shortcut to a
  word, never a source of new ones. Hidden words and words held back by level
  are never offered, or the level would stop meaning anything.
- **Fixed slots.** The strip's width is divided evenly and words are drawn
  inside their slot. Chips sized to their text would put the third suggestion
  somewhere different depending on how long the first two words were.
- **It settles.** The contents change after every word, so the strip ignores
  taps for the same delay the boards use (§ adjustable pause).
- **An empty slot is a hole, not a button.** It takes no tap and speaks
  nothing, exactly as a masked cell does not.
- **Deterministic order.** Equal counts break alphabetically, so two identical
  states give the same strip in the same order every time.
- **It ships knowing English.** `starter_predictions.dart` is a hand-written
  table of what usually follows what, over the shipped vocabulary. It is
  ranked *below* the user's own history and above nothing else — a shipped
  guess never displaces something a person actually said. Without it the strip
  showed the same five words after every word until enough whole sentences had
  been spoken to move it, which is a decoration that costs grid height, not a
  prediction. A fourth tier ranks by what part of speech can follow the last
  word, so the strip never repeats itself even for a word the table misses.
- **Suggestion taps are logged as `prediction`, not `touch`.** The remap
  warning counts how often a *location* was reached for, and a word taken from
  the strip was not reached for at all.

**Off by default, and it is not free.** The strip takes its height from the
grid, so every button is a little shorter while it is on. That is a change to
where things are, which is why it is a deliberate choice. Turning it back off
restores the previous layout exactly — nothing is rebuilt and no cell moves, so
it is the one layout change that costs nothing to undo.

**What it stores is counts, not a transcript.** `prediction_pairs` holds a pair
of words and how often one followed the other: no timestamp, no ordering beyond
the pair, nothing that says four words were one sentence. It is separate from
the usage log, which is consent-gated and exports. Turning prediction off
empties it.

Learning happens when a sentence is *spoken*, not as each word is added — what
is recorded is what the user meant to say, and nothing at all from a sentence
they built and then cleared. The shipped table is what makes the strip useful
in the meantime.

### 4.4 Voice and tone — built, and short of what was asked

**Delivered.** A voice screen behind the PIN: pick a voice, pick a tone, set
speed, pitch and volume, and every control speaks a whole sentence the moment
it moves — because a caregiver setting a voice for someone else cannot judge it
from a number, and the person it is for may not be able to say it is wrong. The
voice belongs to the profile, not the device, so switching profile on a shared
tablet changes who it sounds like.

Only voices that work without a connection are listed. A voice that works at
home and not in an ambulance is a trap, not a choice.

Tones multiply the profile's own settings rather than replacing them, so a user
who reads slowly gets a slower **urgent**, not everybody's urgent.

**Four tones ship, and the list stops exactly where the platform does.**

| Tone | What it does |
|---|---|
| Normal | The chosen voice, unmodified |
| Calm | Slower, a little lower |
| Urgent | Faster, higher, full volume |
| Quiet | The same voice turned down |

**Each dial shows what the voice is actually given.** A tone multiplies the
profile's own setting, so with Quiet selected a volume dial at maximum reads
`100% · 35% with Quiet`. Showing only the setting made the number on screen
disagree with what a caregiver was hearing, which is exactly the state in which
a wrong voice goes unnoticed — the person it is set for cannot say it sounds
wrong. Where a tone would take a dial past what the engine accepts, the dial
says so rather than letting the last stretch of its travel do nothing.

> ⚠️ **`setPitch` is gated on volume, not pitch, in the plugin's iOS and macOS
> code**, and it drops the write whenever the volume it currently holds is
> under 0.5 — reporting that only in a status code the Dart wrapper discards.
> Quiet's 0.35 sits under it, as does any volume dial below half. So
> `FlutterTtsEngine.setPitch` raises the volume to full for the duration of the
> write and restores it in a `finally`. Nothing is speaking at that moment, so
> the raised volume is inaudible; the `finally` matters because leaving a
> profile set to 0.35 at full volume would be loud, in a room somebody chose
> quiet for.

**Speed is a real dial, and 1.0 means normal.** `SpeechEngine` takes a
multiplier of the engine's ordinary rate and the adapter translates. It has to:
`flutter_tts` puts normal speech at **0.5** on both platforms — iOS passes the
number to `AVSpeechUtterance.rate` (default 0.5) and Android doubles it before
a synthesiser whose normal is 1.0 — so a caller that passes 1.0 meaning
"normal" gets double speed and an unintelligible board.

**The joke voices are hidden by default**, behind a switch that says how many
there are. Apple files them under their own identifier prefix
(`com.apple.speech.synthesis.voice.*`), which is a steadier test than a list of
names that changes each OS release. They stay reachable: it is not this app's
place to rule that somebody may not sound like a robot if they want to.

**Voices are grouped male / female** where the device says which is which, with
the better-sounding ones first inside each group and an `Enhanced`/`Premium`
marker so two voices of the same name can be told apart. Selection is keyed on
the platform identifier, not the name, because a device can carry two voices
called "Daniel" at different qualities.

> Gender and quality are **iOS-only and not contractual**. Android's voice maps
> carry neither, and an iOS build can report "unspecified" throughout. Where the
> device labels nothing the list comes back plain and unheaded and says so,
> rather than leaving a caregiver hunting for a grouping that is not coming.
> Anything other than a recognised `male`/`female` is treated as unsaid rather
> than shown raw.

> ⚠️ **Two things asked for are absent, deliberately.**
>
> **Sarcasm** needs a prosodic contour — a particular rise and fall across a
> sentence — that no platform engine lets an app specify. **A whisper** needs
> breathiness, which is not a parameter at all. The fourth tone is called
> *Quiet* and not *Whisper* for exactly that reason: it is the same voice with
> the volume down, and that is what you will hear.
>
> A preset that does not do what its name says is worse than a missing one,
> most of all for someone who cannot hear the mismatch and correct it, and who
> will be taken to mean whatever came out.
>
> **The loudness ask is the one genuinely unmet.** In-app volume is a *share*
> of the device's own volume and cannot exceed it — `flutter_tts` plays through
> the platform and offers no gain stage. So "maximum is a yell" is not
> delivered, and the parent complaint that motivated it ("all of this motor
> planning is useless if I cannot hear him") still stands. Getting past it
> means synthesising to a file and playing it through an audio graph with gain,
> which puts a file write between a tap and a word — a straight violation of
> §5. The honest fix is the neural voice in §4.5. The screen says so plainly
> rather than pretending the slider goes further than it does.

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

### 4.5a Futures and streams are held, not built in `build`

Two screens created their database work inside `build`. Both are fixed, and
both were less dramatic than they first looked — worth recording, because the
measurements are the useful part:

- **The board's query stream is cached per board**, and the category-wheel
  substitution moved to render time so a page change rides the ordinary rebuild
  instead of needing a new subscription. It was *not* re-querying per tap:
  drift caches query streams by SQL and defers closing a dropped one by an
  event-loop turn, so the resubscribe hit the cache. The real per-tap cost was
  SQL generation, a subscription teardown and rebuild, and a timer — and it
  stayed cheap only through a drift implementation detail the widget has no
  contract with.
- **The usage summary reads once into one combined future.** There was **no
  rebuild loop**: a `FutureBuilder` completing marks its own element dirty, not
  its parent's, so the parent's `build` is never re-entered. The real defect is
  that futures built in `build` are rebuilt by *any* ancestor rebuild — a tab
  returning, a text-size change — and that three futures are three snapshots of
  a log still being written to, on a screen whose panels get read against each
  other and copied into funding paperwork.

**The settle gate is a flag the timer clears**, not a deadline compared against
`DateTime.now()`. The timer and the wall clock are the same thing in production
and two different things under a test harness, and a gate on the tap path has to
be testable.

### 4.8 Breadcrumbs — agreed, not built

A strip at the bottom of the screen showing the path taken to reach a word:
`home → body → more words → buttocks`. **Toggleable, default on.**

The crumbs read what the keys read — the paging key says `more words` and the
wheel key says `more categories` — because a crumb naming something the board
does not is a route nobody can follow. The trail starts at `home`, which is
what makes a one-step route read as a route.

What it is for: a word two or three movements deep is reached by a sequence,
and the sequence is the thing being learned. Showing it makes the route legible
to whoever is sitting alongside — so a caregiver can see how a word was found
and help repeat it, rather than watching a word appear and not knowing where
from.

Constraints it inherits:

- **It costs grid height**, like the prediction strip, so it is subject to the
  same rule: turning it on shrinks every button. New profiles get it on;
  existing boards keep their geometry until a caregiver chooses otherwise, and
  the toggle is instantly reversible with nothing rebuilt.
- Auto-return is on by default, so most trails are one or two steps. The strip
  has to read well at length 1 and not jump about between lengths.
- It must never become a navigation control. Tapping a crumb to jump back would
  be a second route to a board, and a word's motor path has to be one sequence,
  not two.

### 4.9 Word prediction on by default — agreed, not built

Prediction (§4.3) currently defaults off. It should default **on**.

⚠️ **The default cannot simply be flipped.** `ProfileSettings.prediction`
falls back to `false` when no value is stored, so changing the fallback would
switch it on for every existing profile that never chose — shrinking every
button on a board somebody has already learned, silently, on update. That is
the exact failure this project exists to prevent.

So: on by default for profiles created from here, and a migration that writes
the current effective value explicitly for profiles that already exist, leaving
their boards untouched. Turning it on afterwards stays a caregiver's choice and
stays instantly reversible.

### 4.10 Two ways to choose a form of "to be" — agreed, not built

The copula keys (`am/is/are`, `was/were`) hold one location each and produce a
form that agrees with the subject. Two ways of choosing between the forms, as a
per-profile setting.

**Toggle — the default.** The first tap gives the form that agrees with
whatever subject is already there, and each further tap cycles to the next form
of the same tense, replacing the one before it rather than appending. Every tap
speaks the new form, so the choice is made by ear. Nothing is repaired
afterwards: the user has chosen, and a repair would overwrite them.

The first tap staying agreement-driven is what makes this cheap — mid-sentence
it is right first time and the cycle is never needed. It only earns its keep at
the start of a question, where there is nothing to agree with yet.

**Agree — the existing behaviour.** A provisional form goes in and settles once
the subject arrives: "is" then "you" becomes "are you", the same way `a` becomes
`an`.

⚠️ **The repair has to re-speak.** Every word speaks as it is tapped, so the
user hears "is", then "you" — and never hears the correction. The sentence they
heard themselves say is not the sentence in the bar. When a repair changes the
form, the corrected pair has to be spoken.

That gap is the reason toggle is the default: it never says a word it then has
to take back.

### 4.11 Vocabulary level — recalibrated; setup question outstanding

**Recalibrated.** Level 1 is 99 words drawing **at most 36 on any page at any
geometry**, which is the density Project Core publishes for a beginner's
whole-day board. Level 2 is 241 — the 200-250 that Hattingh & Tönsing put at
~80% of spoken communication. Level 3 is everything. Step sizes went from
145 / **8** to 142 / **131**.

The level-1 home board is the Universal Core 36's home portion plus five the
Universal Core has no answer for: `yes`, `no`, `don't`, `wait`, `me`. It carries
`not`, which negates inside a sentence but can neither answer a question nor
make an imperative, and its possessive key fires after `I` to give "I's".

**No copula, no endings, no articles at level 1** — decided deliberately, and
confirmed. The Universal Core 36 carries no copula, and a first board is
telegraphic: "what that?" is understood. The price, stated plainly: a level-1
board cannot build "are you ok?" or any past tense. They arrive together at
level 2, in the locations they have held since day one, so nothing is
relearned.

`will` moved to level 2 with them, so tense arrives as one set rather than
leaving level 1 with a future and no past.

**Still to build: the setup question.** Ask at profile creation alongside
orientation and icon size, phrased as what a person is ready for rather than a
level number, noting it is adjustable and that changing it moves nothing —
words appear and disappear where they always were. Copy has three true things
to say: level 1 *is* the Universal Core 36 at the published beginner density;
**level 2 is where the grammar keys arrive**, which a caregiver who wants
sentences needs to know; level 3 is everything.

Verified safe for existing boards: `vocab_level` is written only on insert, no
`UPDATE` on `buttons` anywhere names it, and `topUpVocabulary` returns early
rather than rewriting a word already placed. New profiles at 7×12 get a
byte-identical home board; teen and adult category pages change, in the
direction of keeping higher-payload words on page 1.

### 4.11-old Vocabulary level — the original brief

**The levels do not currently mean anything.** Measured on the shipped
vocabulary:

| Level | Words drawn | Description shown |
|---|---|---|
| 1 | 236 of 408 | "Core words only. The rest of the board stays reserved." |
| 2 | 400 of 408 | "Core words and the starter fringe vocabulary." |
| 3 | 408 of 408 | "Everything, including anything added since." |

Level 2 to 3 is **eight words**. Level 1 draws 58% of the vocabulary and is not
a beginner board by any reading. Two of the three positions are
indistinguishable and the third does not do what its own description claims.

This is a calibration failure, not a design failure. The mechanism is the
best-attested practice in the customization literature — Ekis, Klein,
AssistiveWare's Progressive Language and LAMP's own Vocabulary Builder all say
the same thing: **start at the final grid size and hide, never resize.** Every
cell is materialised from day one and most are simply not drawn, so revealing a
word months later puts it exactly where it always was. Levels were assigned word
by word as vocabulary was added, and the total was never counted.

**To do:**

- **Recalibrate.** Level 1 a genuine one-hit board, level 2 a real transition,
  level 3 everything. The counts have to match the descriptions, or the
  descriptions have to change.
- **Ask at profile setup**, alongside orientation and icon size, rather than
  leaving it as a slider a caregiver has to go looking for. Phrase it as what a
  person is ready for, not as a level number.
- **Say it is reversible.** The setup copy should note that if the board looks
  overwhelming it can be changed in settings, and that changing it moves
  nothing — words appear and disappear where they always were.

Safe for existing profiles by construction: `buttons.vocab_level` is a stored
column per vocabulary, so recalibrating the seed changes what *new* boards get
and cannot take a word off a board already in use.

### 4.12 Search results show no pictures until one is chosen

In "Change the picture", searching lists results as **alt text only**. Pick one,
and the pictures for the whole result set appear at once — as though nothing is
fetched until something *has* to be, and then everything is.

Which makes the picker close to unusable for its actual purpose: choosing
between pictures by looking at them. A caregiver reading a list of words is
choosing blind, and the one thing this screen exists for is to see the picture
before committing to it.

Suspected: the picker never subscribes to `SymbolResolver.ready`, so a queued
download that lands does not repaint the row that asked for it. Assigning a
symbol rebuilds the sheet, which is why everything appears at once. `SymbolView`
was given that subscription; the picker was not. Confirm before fixing — the
symptom also fits a resolver that only queues on a *visible* row.

### 4.13 Levels as words per page, and an evidenced first level

Two corrections to §4.11, which framed the levels as totals across the whole
vocabulary:

- **Think in words per page, not words in total.** What a person faces is one
  board at a time. "236 words" says nothing about whether the home board is
  approachable; forty words on a page is a different experience at 7×12 than at
  12×18, and the same total spread over seven boards is not the same thing
  twice. The level bands should be expressed and tested per page.
- **The first level should be evidenced, not assembled by taste.** There is
  published work on what a starting AAC vocabulary should contain, and it
  should decide this rather than a judgement call:
  - **Project Core Universal Core 36** (CLDS, UNC-Chapel Hill) — the
    evidence-based floor already cited in §7. Verified from the primary source.
  - **Project Core's own published densities** — the *same* 36 words are
    published at 4, 6, 9 and 36 per page, the vocabulary held constant while
    pagination follows access method. A published ladder, and the direct
    evidence for a per-page ceiling.
  - **Laubscher & Light (2020)**, *AAC* 36(1):43-53 — core word lists
    "may under-emphasize many of the types of words that predominate in early
    expressive vocabulary". A first board should therefore be more noun- and
    social-heavy than a core list alone would make it.
  - **Hattingh & Tönsing (2020)**, PMC7433287 — 200-250 spoken words account
    for roughly 80% of spoken communication. Sets the level 2 band.
  - **Light et al. (2019)**, PMC6436972 — array size costs accuracy and
    latency, and so does navigating more levels. Names the tradeoff, gives no
    threshold.

  > ⚠️ **Two citations in an earlier draft of this section were wrong, and the
  > corrections matter more than the originals did.**
  >
  > **Thistle & Wilkinson (2013)** is *"Working memory demands of aided
  > augmentative and alternative communication"*, *AAC* 29(3):235-245 — a
  > theoretical review of memory load. It names the tradeoff but **contains no
  > number** for how many symbols a display should carry. A per-page ceiling
  > was attributed to it that it does not have.
  >
  > **Boenisch & Soto (2015)**, *AAC* 31(1):77-84, is the oral core vocabulary
  > of ***typically developing*** school-aged children — a proxy population,
  > and the earlier draft described it as the opposite and said to prefer it on
  > that basis.
  >
  > **Banajee, DiCarlo & Buras-Stricklin (2003)** and **Marvin, Beukelman &
  > Bilyeu (1994)** are real papers (DOIs confirmed via Crossref) whose word
  > lists sit behind a paywall and could not be obtained. **Nothing is placed on
  > the strength of them**, and no list was reconstructed from memory. A
  > plausible word list attributed to a study nobody checked is exactly what
  > this project must not ship.

  Where the sources disagree, say so and pick with the reason stated.

### 4.6 Still to do

Carried forward, in the order they matter:

- **Volume above the device's own maximum** (§4.4) is the one part of the
  original scope that platform speech cannot deliver. It needs §4.5.
- **Level does double duty** — it decides both what is drawn on day one and
  what a small grid sheds first. `_shedLeastImportant` sorts by
  `[level, shedRank, index]`, so level dominates what pages off.

  Its concrete shape: the eight verbs at the end of the home verb band
  (`know think say tell see come give feel`) sit at level 3 for a **layout**
  reason — they are the run a 7×12 grid pages off, and level is the only lever
  that picks it. Consequently **nothing else on the root board may go above
  level 2**, or it sheds ahead of them and relocates everything around it.
  Pinned by a test that fires before the golden, with a message saying why.

  The fix is a `pageRank` in `band_layout.dart` separate from `level`, which
  would let those eight be level 2 — drawn, on page 2 — while still being the
  run that pages off.
- **Word endings and articles shed first on a small grid**, because they are
  all level 2 with the highest shed ranks. So the users least able to afford
  an extra movement are the ones who lose the grammar engine. Worth a
  deliberate decision rather than leaving it as fallout.
- **`docs/starter-vocabulary.md` does not exist** though `core_vocabulary.dart`
  cites it and §7 calls the clean-room derivation "the evidence". Given the
  trademark position, that is the one document that should exist.
- **The root board has little slack left.** Two name cells beside the pronouns
  and one noun column. Further additions there displace something.
- **The verb band is exactly full at 7×12** — 18 kept verbs in three columns of
  six. Because that band fills across, the next verb added to it widens the
  band to four columns and reflows every verb *and* every band to its right.
  Adding a home-board verb is a rebuild-class change now, not an append. New
  verbs belong on the `doing` board.

### 4.6a Sentences the board still cannot build

Each of these is a real utterance a person would want, named rather than
quietly absent:

- **A plural subject behind a determiner.** "where are the people?" comes out
  *"where is the people"*. The copula settles against the word immediately
  after it, so a determiner in between blocks the agreement. Deferring past
  determiners only helps for the handful of words known to be plural —
  `copulaFor` has no morphological plural detection, so "where is my shoes"
  would stay wrong either way. The honest fix is plural detection, not a
  smarter repair.
- **A second sentence in one bar.** After a punctuation mark every grammar key
  is hidden, so "are you ok? is it my turn?" needs a clear in between.
- **Contracted negatives** — "isn't it my turn?", "aren't you coming?". `not`
  is on the board, so only the contraction is missing.
- **"some is left."** Deliberately traded: the copula key is hidden after
  determiners that stand in for a noun not yet tapped, which is what stops the
  board producing "an is", "the is" and "more is". Demonstratives still take
  one, so "this is mine" survives.

### 4.6b Loose ends, logged

Small, real, and none of them urgent:

- **`symbol_picker` writes a null on removal** and `board_editor` translates
  that into the removal marker after the sheet closes, so the knowledge sits
  one file from the write. The picker also still offers "Remove the picture"
  on a button already marked as having none.
- **`resolveLabel` honours no timeout**, unlike `resolve`. A pack that hangs
  leaves cells marked "still looking" for good rather than for a second.
- **`GridSurface` cannot render a cell differently**, so the editor carries its
  own board — roughly eighty parallel lines, and a new image kind has to be
  handled in two places. A `cellBuilder` hook would let both share one surface.
- **The bundled pack list is written twice**, in `GridSurface.symbolPackIds`
  and again in the editor. If they diverge a caregiver audits pictures the user
  is not looking at.
- **Nothing writes `UsageSource.switchAccess`.** The reports count it
  correctly, but no scanning input path exists yet, so a switch user's
  selections are still recorded as touches. The reporting is correct ahead of
  the producer; the producer is Phase 8.
- **The usage screen has no error branch.** A failed read leaves a spinner and
  an em-dash for ever, with no retry, and one combined future means one failure
  blanks all three panels.
- **`logger.enabled` is a plain mutable bool** with no notification, so the
  usage screen only notices a change when something else rebuilds it.
- **The paging key is drawn whether or not the next page has anything on it at
  the current level.** A level-2 profile at 7×12 pages forward from home onto a
  board that draws nothing, because home page 2 holds only the eight level-3
  verbs.
- **`docs/starter-vocabulary.md` is now more worth writing, not less.**
  Universal Core 36 is verifiable from its primary source; the Banajee and
  Marvin lists are paywalled and were not used. That distinction is the
  clean-room evidence and should live in the repo, not in a chat log.
- **The caregiver screen does not surface `addedBoards` or `refusedBoards`**
  from a top-up. A whole new board arriving, or being refused for want of a
  free system-row column, is worth a line of its own rather than being folded
  into a word count.

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
