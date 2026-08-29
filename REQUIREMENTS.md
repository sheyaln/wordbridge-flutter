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

Within that class order, **a strip is one semantic cluster** — drinks, meals,
fruit, treats — because children group vocabulary in small event-based groups
rather than taxonomies (Fallon, Light & Achenbach 2003), and because a row is
what a person reads in one sweep. A strip per cluster costs a row each and
eight clusters do not fit in six rows, so the clusters a day needs least read
on page two. See §4.24 for what that costs and why it is the right way round.

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
`home → body → more words → face`. **Toggleable, default on.**

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

### 4.10 Two ways to choose a form of "to be" — delivered

Both modes ship, as a per-profile radio choice under **Words and grammar**,
defaulting to toggle.

**Shipped as specified, with three things worth writing down:**

- **The cycle is a fixed ring — `is → are → am` and `was → were`** — rather
  than an order that reshuffles to put the likely form first. The number of
  presses between any two forms is then the same every time, which is the
  promise the rest of the board makes. `are` sits second because a sentence
  that opens with the copula is far more often "are you…?" than "am I…?", so
  the second press is the one worth making cheap. **"are you ok?" is two
  presses.**
- **Pressing the other tense switches rather than stacks.** "I am" on the past
  key is "I was", agreeing with the subject in front of it, not "I am was".
- **Cycling needed a hole cut in the availability rule.** `grammarHelperApplies`
  hides the copula key after a verb, and a copula *is* a verb — so with the
  contextual-grammar setting on, which is the default, the second press had
  nowhere to land and toggle mode would have been dead on arrival while every
  unit test passed. The key now stays reachable while a form of "to be" is the
  last word, and only then. This is the one rule in that function that opens a
  key rather than withholding one.

**The repair now speaks, in both directions.** `UtteranceBar.add` returns the
word it corrected, and the talk screen speaks the corrected pair in place of
the word's own utterance — "is" then "you" is heard as "are you". Nothing is
said twice.

The same channel fixed the identical silent repair on the article, which was
not in the brief: "a" then "apple" was heard as "a", then "apple", while the
bar read "an apple". It is the same defect and the same three lines, so it was
fixed rather than logged.

**No migration, deliberately.** Unlike the two strips, this default lives in
the getter and reaches profiles that predate it. Nothing moves, no button
changes size, and the first press produces the same word under either answer —
the two differ only from the second press onwards, which under the other answer
did nothing anyone would want. Schema stays at 5.

**Not done:** §4.6a's "where are the people?" is untouched. The copula still
settles against the word immediately after it, so a determiner in between
blocks the agreement, and toggle mode does not help — the fix is plural
detection, not a smarter repair.

### 4.10-old The original brief

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

### 4.11 Vocabulary level — recalibrated, and asked at setup

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

**Asked at setup.** "What are they ready for?" sits between the icon-size
question and strong language, as three cards. No level number appears on the
page. Under the heading: *"Changeable at any time, in settings. Changing it
moves nothing — words appear and disappear where they have always been, so a
movement learned once is learned for good."*

| Answer | What it says |
|---|---|
| Learning single words | "The Universal Core 36, plus “maybe” so an answer can be a hedge rather than a commitment. Never more than 37 on a page. No word endings and no am/is/are, so “are you ok?” and the past tense are out of reach until the next step." |
| Putting words together | "Adds the word endings, a and the, and am/is/are — the keys a sentence needs — along with the words an ordinary day takes." |
| Using the whole board | "Everything, including anything added later." |

The birthday still proposes the answer — `AgeBand.startingLevel`, under 6 to
level 1 and everything else to level 2 — and an explicit choice overrides it,
on the same nullable-field pattern the profanity switch uses: null means
"follow the band", and changing the birthday returns to the new band's
proposal. `ProfileRepository.create` takes `vocabLevel` beside `profanity` and
falls back to the band when it is null. Nothing else in the app writes a
level at creation.

The caregiver slider's three descriptions were still describing the old
236 / 400 / 408 split and now carry the same three sentences, each opening with
the same readiness phrase, so the setting found later is recognisably the
question already answered.

**No totals in the copy.** 100 / 252 / 377 counts the shipped vocabulary; the
teen and adult presets add their own extras on top (109 / 273 / 404 and
112 / 281 / 408), so a total printed on the setup page would be wrong for two
of the four bands. The density — never more than 36 on a page on a category
board, 37 on the root board — holds for every band at every geometry and is
what the copy claims instead.

The root board's extra one is `maybe` (§4.28). Project Core's published figure
is a board somebody built, not a threshold anything was measured against, and a
beginner is not served differently by thirty-six locations than by
thirty-seven. What the calibration test guards is that the number stays one
somebody argued for word by word, so the additions are named in a set rather
than counted — see `docs/starter-vocabulary.md` §2.5, which now lists seven.

**Not claimed: -er/-est.** The endings band is `+s`, `+ed`, `+ing`, `+'s`,
`am/is/are`, `was/were`. `MorphemeKind` has `comparativeEr` and
`superlativeEst` and the morphology engine applies them, but no seeded button
carries either, so the level-2 copy does not offer them.

Covered by `test/setup_vocab_level_test.dart`: the level given to `create()` is
the level stored, a level given with a birthday outranks the band, no level
given follows the band, and the question on the page reaches the created
profile.

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

**Delivered.** The suspicion was right, and the mechanism is one step more
specific. Each result was a `StatelessWidget` whose `FutureBuilder` re-ran
`resolver.resolve` on every build. The first pass returns nothing and queues the
download; the arrival then reaches nobody, so the row keeps drawing its word
until something else rebuilds the sheet. Choosing a symbol calls `setState` for
the fetch spinner, which rebuilds every row against a fresh future — over files
that have since landed. Hence all at once. The second reading was wrong:
resolution is queued for every row `GridView.builder` builds, and building
lazily is what stops one search pulling sixty images.

The row now holds its own resolution and watches `SymbolResolver.ready` for its
own symbol, matched on `SymbolRef.key` rather than on the word — a board can
match on the word because an auto-attached symbol carries it, but a search
deliberately lists several pictures of one word and only the arrival may redraw.
The subscription is cancelled in `dispose()`; the resolver outlives the sheet.

It also draws through the shared `SymbolPicture` instead of a private copy of
the same switch, which brings with it the `errorBuilder` and `placeholderBuilder`
the copy lacked: a file that arrives corrupt leaves the word doing the work
rather than putting a broken-image glyph in front of a caregiver.

Covered by `test/symbol_picker_repaint_test.dart`: a download that lands draws
itself with no further interaction, an arrival redraws only the row that asked
for it, and a closed sheet stops resolving.

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

  > **Being built now, as `pageRank`.** A second, independent rank on
  > `BandItem` deciding what pages off, leaving `level` to decide only what is
  > drawn. Default `level * 10`, so an item can be placed between two levels
  > without renumbering anything: level 1 is 10, level 2 is 20, level 3 is 30.
  >
  > It buys the two fixes named directly below this one. The eight home verbs
  > become **level 2, pageRank 30** — drawn a level earlier, still the run a
  > 7×12 grid pages off, so not one of them moves. The endings and articles
  > become **pageRank 15** — after the level-1 core, ahead of ordinary level-2
  > vocabulary — so a small grid keeps the grammar engine on page 1.
  >
  > **This is a rebuild-class change** and the first one taken deliberately.
  > Placement at 7×12 changes: the endings hold page-1 locations that ordinary
  > level-2 words held. Existing boards are untouched by construction — the
  > layout is materialised once at profile creation and nothing re-runs it —
  > so this reaches new profiles only, and an existing profile sees it by
  > being rebuilt. That is now an acceptable price (§5.1).
  >
  > It costs a level-1 user nothing: the spare page-1 capacity it moves was
  > going to hold level-2 words that a level-1 board does not draw either.

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
- **`docs/starter-vocabulary.md` — delivered.** The clean-room derivation the
  `core_vocabulary.dart` header and §7 both point at: counts per level measured
  from the code at `91df220`, every source named with how it was verified, what
  was deliberately not done, and the words chosen on judgement labelled as
  judgement rather than dressed up as evidence.
- **The root board has little slack left.** Two name cells beside the pronouns
  and one noun column. Further additions there displace something.
- **The verb band is exactly full at 7×12** — 18 kept verbs in three columns of
  six. Because that band fills across, the next verb added to it widens the
  band to four columns and reflows every verb *and* every band to its right.
  Adding a home-board verb is a rebuild-class change now, not an append. New
  verbs belong on the `doing` board.

### 4.14 "how" joins the pinned question column

Requested: `how` should be pinned alongside the other wh-words. It was not in
the vocabulary at all.

**The column holds exactly `rows - 1` words**, and at 7×12 those six were
already spoken for: `what where who when why ?`. Adding a seventh means one of
them spills onto the root board as an ordinary word. Three ways to pay for it
were put up, and the answer chosen — pin `how`, spill `?` — was priced wrong
when it was offered. Measured, it costs about **fifteen words off page one**,
the whole articles band among them.

> ⚠️ **A spilled word does not cost a cell. It costs a line.** Bands own whole
> lines, and at 7×12 every band ends flush with zero slack, so the layout frees
> a line only by shedding every word that shares it. One extra item took
> `we they my`, `need take will close`, `this`, `to out` and
> `a the and but because so` to page two — including `because`, which the seed
> defends by name as the word that turns a refusal into a reason. Declaring the
> spilled band `startsLine: false` does not help: with no ragged tail anywhere
> there is nothing for it to fill.
>
> This is worth knowing beyond this change. **Any single addition to a full
> root board is a fifteen-word change, not a one-word change.**

**So `?` moved to the utterance bar instead, and the board is byte-identical to
what it was apart from the one pinned slot.** It costs no location on any
board, which is the right price for it: punctuation marks the sentence rather
than adding a word to it, and the sentence lives on the bar. The seed already
made this argument for the undo and clear keys — *"every duplicate costs a
permanent location on every board"* — and the question mark had simply never
been held to it. It sits beside Speak and well away from the destructive pair,
because like Speak it produces speech.

`pinnedQuestions` is now six question words and no punctuation, which is
exactly `rows - 1` at the default grid, so nothing spills at all.

**`how` draws at level 1**, with `who`, `when` and `why`. It is the sixth
addition to the Universal Core 36, after `yes`, `no`, `don't`, `wait` and `me`,
and the argument for it is narrower than theirs: the Universal Core carries
five of the six English wh-words and omits this one, and a board that offers
five of six reads as having a hole in a group a user takes to be complete.
Level 1 goes from 99 words to 100, and the 36-per-page ceiling is untouched
because the column is pinned rather than drawn from the content area.

### 4.22 "wait" sits with the verbs — delivered

It was in the yes/no band, at the bottom of the last column, under `don't`. It
is a verb and it does a verb's job, so it now reads `go stop wait` across one
row of the verb band.

**The verb band was exactly full at 7×12**, so adding one paged one off. Every
candidate but one is half of a pair the board deliberately keeps side by side —
`open`/`close`, `go`/`stop`, `get`/`take`, `want`/`need`/`like`, all asserted in
`core_board_set_test`. So **`will` goes to page two**. Its level is unchanged; it
is drawn wherever it lands.

`will` is also **declared last in the band** rather than among the modals. Page
two is rebuilt in declaration order, and a word inserted into the middle of the
overflow pushes every pair after it apart — which is exactly what happened
first time round, splitting `know`/`think` and `say`/`tell` across rows.

Two things this cost, stated plainly:

- **`a` and `the` now page off at 8×10.** One more verb on a board that was
  already full is one more column of pressure. The endings and the copula still
  hold page one there, which is the right half to keep: a suffix key multiplies
  every verb on the board, and a sentence missing its article is still
  understood.
- The yes/no column has a spare location where `wait` used to be. It is
  reserved, not missing.

A second defect surfaced while doing this. **The overflow list was ordered by
when the grid ran out of room, not by how the words read.** It happened to work
while shedding was one word at a time; §4.21 made it a batch per band, and page
two immediately came apart. Page two is now rebuilt by looking each word up in
the band's own declaration, so it reads the way page one does regardless of the
order the shedding happened to take.

### 4.27 Two corners held together opens caregiver mode — delivered

Offered alongside the sustained press on an invisible target in the corner of
the utterance bar. It does not replace it; see the lockout section below for
why that turned out to be the whole design.

**Hold the bottom-left and bottom-right locations of the grid at once**, for a
configurable time, **default 5 seconds**. On the shipped frame those are `home`
and the forward-paging key — the two ends of the system row, as far apart as
the grid allows.

Why it is better than what it replaces: an invisible target is a thing a user
finds by accident and a caregiver cannot find on purpose. Two locations at
opposite ends of the board, held together for five seconds, is a gesture a
hand resting on the device cannot produce, and one that can be written down in
a sentence and taught.

To settle when building it:

- **Neither key may fire.** `home` resets the board and the paging key changes
  it. Both currently act on touch-down. They have to hold their action until
  the gesture is resolved, and drop it if the hold completes — a caregiver
  opening settings must not also send the user somewhere.
- **The bottom-right is not always a key.** The forward-paging key is drawn
  only where there is a page to go to, so on a single-page board that location
  is an empty reserved cell. That is fine and possibly better — an empty cell
  has nothing to suppress — but the gesture has to be anchored to the
  *location*, not to whatever button happens to occupy it.
- **⚠️ It is a two-point gesture, and that excludes people.** Anyone using one
  hand, a head pointer, a stylus or switch access cannot make it. The corner
  hold it replaces had the same problem less severely. So the old gesture, or
  another single-point route, has to remain available for those cases — this
  cannot be the only door.
- **Chosen once, at first setup, and it belongs to the device.** Which gesture
  opens caregiver mode is a fact about who is holding the tablet, not about the
  person speaking on it, so it lives in `app_state` beside the PIN rather than
  in a profile's settings. **Asked on the very first run only** — a caregiver
  setting up a fourth profile has already answered it, and asking again would
  imply the answer could differ per person, which would mean four gestures on
  one device and none of them reliable.

  Changeable afterwards from caregiver settings, which is safe precisely
  because you are already inside when you change it.
- **⚠️ Whatever is chosen must have a way back in.** A caregiver who picks the
  two-point hold and later hands the device to somebody who cannot make it has
  locked themselves out of their own settings — and PIN recovery is no help,
  because it lives behind the gesture. The single-point route therefore cannot
  be merely an alternative offered at setup; it has to keep working regardless
  of what was chosen, or there has to be some other door that does. This is the
  part to design first.
- **Configurable, with a floor.** Default 5 seconds. Long enough that it is
  never accidental; short enough that a caregiver does not think it failed. It
  should not be settable to zero.

#### How the lockout is answered: the one-finger door never closes

**Choosing the two-corner hold adds a second, faster door. It does not close
the first one.** The corner hold stays on every board, at every grid size,
whatever was chosen — but when the two-corner gesture is in use it is
deliberately slowed to **fifteen seconds**, and shows nothing at all for the
first quarter of that.

The alternative designs both fail:

- *Offer the corner hold only as an alternative at setup.* Then the caregiver
  who picks two corners has no way in with one hand, and no way to get one
  back, because changing the setting requires already being inside.
- *Keep both doors at the same speed.* Then choosing the two-corner gesture
  buys nothing. The whole complaint against the corner hold is that a two-second
  press on one spot is a thing a user finds by accident.

Fifteen seconds is the number because it separates the two cases the design
actually has to tell apart. A user exploring a grid, or resting a hand on the
device, does not hold one point unbroken for fifteen seconds; the ring stays
invisible for the first four, so there is nothing inviting them to try. A
caregiver who was told one sentence — *hold the top-left corner of the sentence
bar for fifteen seconds* — always gets in, with one finger, a stylus, or a head
pointer, on a device somebody else configured.

It is worse than the two-corner hold on purpose. That is the trade: the fast
door is the one you choose, the slow door is the one that cannot be taken away.

**What this does not solve.** Switch access reaches buttons, not held
locations, so neither door is usable by scanning alone. That is a real gap and
it stays open — the answer is a scan-reachable route into caregiver mode, which
is a separate piece of work and belongs with §4.6b rather than here.

#### What shipped

- `CaregiverGesture` and `CaregiverEntry` in
  `app/lib/features/auth/caregiver_gesture.dart`. Stored in `app_state` beside
  the PIN — two keys, the gesture and the hold in seconds — so it belongs to
  the device. An unreadable value falls back to the standard gesture rather
  than throwing: this sits on the path to the only door into settings, and a
  device that cannot open its own settings cannot be fixed from inside them.
- `CornerPairHold` in `app/lib/features/auth/corner_pair_hold.dart` takes two
  rectangles, not two buttons. The locations are the gesture; what occupies
  them differs by board and by page.
- `GridSurface` gained `pairHold` and `onPairHold`, and with them a state
  object, because it is what dispatches `onSelect` and therefore the only
  place that can swallow the two keys. The anchors are laid over the grid from
  the same `GridGeometry` the cells come from.
- The choice is asked once, at the bottom of first-run setup, and changed
  afterwards under **Getting in here** in caregiver settings, where the hold
  itself is a 1–20 second slider.
- Both holds now reveal their ring a quarter of the way in rather than at a
  fixed 500ms, so a fifteen-second target does not spend fourteen seconds
  advertising itself.

**The suppression is the fiddly part, and it is worth knowing why.** Both keys
act on *release*, and when the hold completes both fingers are still down — so
the releases that end the gesture would send the user home and onto a second
page on their way into settings. The flag that swallows them is therefore
cleared by the *next contact*, not by that release: a release is dispatched to
the anchor before it reaches the key underneath, so clearing it there would
clear it a moment too early. Getting that backwards leaves home dead for the
rest of the session on a board whose user cannot say so, which is why there is
a test for each direction.

Thirteen tests in `app/test/caregiver_two_corner_test.dart`, seven mutations
run against them: suppression removed, the clearing callback emptied, the right
anchor dropped, the one-handed fallback closed, the hold floor removed, the
talk screen never arming the gesture, and an unreadable stored value throwing
instead of falling back. Each was confirmed present in the file before the
re-run, and each was caught.

**Not built here:** the hold duration is not asked at first run, only the
gesture. Five questions is already what setup asks; a sixth about seconds, from
somebody who has not yet made the gesture once, is a number they cannot have an
opinion about. It is a slider in settings instead.

### 4.28 Time, and words for not being sure — the uncertainty half delivered

Two vocabulary additions. The uncertainty words shipped; the `time` category
is still to build.

**A `time` category.** Nothing on the board says when. Today, tomorrow,
yesterday, morning, afternoon, night, now, later, soon, before, after, and the
days of the week. It is a new category board, which costs a slot on the wheel —
and the wheel is append-only, so the slot goes on the end and every learned key
keeps what it opens.

**Words for not being sure** — `maybe`, `perhaps`, `unsure`, `possibly`,
`probably`. Worth naming separately from the rest of the fringe because of what
they do: without them, every answer a person gives is a commitment. A board
that can say `yes` and `no` and not `maybe` puts somebody in the position of
overstating what they mean, every time, and the people around them have no way
to tell that it is the board talking rather than the person.

Where they go was the open question. Settled by measurement, over the 29
distinct grids `GridChoice.derive` can actually produce across four icon sizes,
two orientations and ten plausible devices, plus 7×12 and 7×11 by hand, for all
four age presets, comparing every word's page, row and column before and after.
**No word is lost at any size.**

**`maybe` joins the `describing` band on the root board**, last in it, so it
lands beside `no` and `don't` at 7 rows and up. Level 1, because the level-1
board is where the problem bites hardest: single words, and every answer a
commitment. Not marked essential, so it cannot displace something more
load-bearing on the smallest grid.

Its measured cost across all 29 grids is **one word, at one size**: at 6×9,
`out` moves from root page 2 to page 3. Everywhere else it is free. At 5×8,
5×9 and 5×10 `maybe` itself lands on root page two, which is the band at its
floor shedding its own last item rather than anything else paying.

**`perhaps`, `possibly`, `probably` and `unsure` form a `not sure` row on the
`feelings` board**, `shedRank: 5` — between `more feelings` and `strong words`,
so at a level-3 tie this row goes first, because `maybe` already carries the
job at level 1 and page two costs a key press rather than an answer.

**⚠️ What that row costs, on the default grid.** At 7×12 — the grid this
project uses — the `not sure` row is paid for by **the `ours` reserve row on
the feelings board**, the row held open for a family's own words. Also at 7×13,
11×7 and 11×8. It is softened rather than erased: the new row leaves seven open
cells of its own on an eleven-wide board, so the space is still there. What is
lost is the *named* reserve — a caregiver word added into that tail now belongs
to `not sure` rather than to `ours`, which is a change of meaning and not only
of label.

**And the reason trimming the row would not help:** a band owns a whole row, so
`unsure` on its own would cost the identical row at every grid size. The other
three ride free. The question is therefore not "do four words earn a row" but
"does `unsure` earn a row" — and `unsure` is the only one of the four saying
something `maybe` cannot, because it is a state you report about yourself,
which is what a feelings board is for. `perhaps` is a pure synonym of `maybe`
and is present because it is free, not because it was argued for. **The only
lever that returns the `ours` reserve is dropping the band entirely.**

Elsewhere the row is paid for by level-2 and level-3 words moving one page
later — `jealous`, `confused` and `surprised` at 10×8; `mean` and `worse` at
5×8 — and at fourteen of the larger grids it costs nothing at all.

`maybe` was also removed from the adult preset's own band, where it had been a
workaround for its absence from the root board. Two locations for one word is
against that file's own rule, and a per-preset test now holds it to one.

**The level-1 density moved, deliberately.** `vocab_level_calibration_test.dart`
asserted the root board's level-1 content area was *exactly* 36, Project Core's
published whole-day figure. It is now 37, guarded separately from the category
boards, which still hold to 36 — see §4.11 for why that is a number worth
moving once and the copy that had to move with it.

### 4.26 A caregiver can name a row themselves — agreed, not built

The labels in §4.19 come from the shipped layout, which means a board a
caregiver made by hand has none, and a row whose contents they changed keeps
the name the seed gave it. Both are cases where the person who knows the user
should be able to say what a row is for.

**Chosen from a list, not typed.** Every band the app ships already has a name
written for a reader — `drinks`, `meals`, `fruit`, `doing`, `people you know`,
`places you go` — and that list is long enough to cover most of what a new row
would hold. Picking from it keeps the vocabulary of the board consistent
between the shipped rows and the added ones, which is the whole point of
labelling. **With free text as the last option**, because a caregiver building
a row for one child's swimming club is not served by a list.

Shape:

- **Reached from the board editor**, on the row rather than on a button: tap
  the row's label, get the list. A row with no label yet shows an empty slot
  when the setting is on, so there is somewhere to tap.
- **Stored per line, not per band.** A caregiver-made board has no bands at
  all, so the override has to key off the line index. New nullable column on
  `boards` — a JSON map of line index to name — kept separate from `band_map`
  so that what the seed decided and what a person chose never get confused.
- **An override wins over the band's own name**, and clearing it falls back.

Two costs to state plainly when it is built:

- **A rebuild (§4.20) or a grid change discards these.** Both re-lay the board,
  so line 3 afterwards is not the line 3 that was named. Carrying a name onto a
  different row would be worse than losing it. The confirmation for both has to
  say so, and it is a reason to keep the list short and quick to re-apply
  rather than to make naming feel expensive.
- **It can contradict the board.** Nothing stops a row of fruit being named
  `drinks`. That is the caregiver's call to make and their mistake to fix — the
  alternative is refusing a name because the software disagrees, on a board
  whose entire premise is that the people who know the user decide.

### 4.30 Deleting a word — delivered

Requested: a word can be deleted, confirmed by typing `DELETE`, because
mistakes happen and removing one has to be possible.

Today the editor can hide a word, move it, relabel it and change its picture.
It cannot remove one. A caregiver who adds `Nana` twice, or types a word wrong,
or adds one for a child who has since moved on, has no way to take it back —
only to hide it, which leaves the location occupied forever.

**Delete is not hide, and the difference is the location.** Hiding keeps the
cell occupied, which is the rule that makes "grow over time" and "never
relocate" both true (§2). Deleting has to release the cell, or it is hiding
with a harsher word. So the confirmation must say the thing that is actually at
stake: **the location becomes free, and the next word put there will be reached
by the movement this word had.** That is the cost, and it is not the same
sentence as "this word will be gone".

Shape:

- **Typed `DELETE`**, matching the `REBUILD` confirmations for a grid change
  and a seed rebuild (§4.20). Those are the two other operations that cost
  learned positions, and one vocabulary for all three is worth more than three
  shades of severity.
- **State the practice first, in the user's own numbers**, the way
  `RemapConfirmSheet` already does: how many taps this location has taken and
  over how long. `usage_events` is anchored to `cell_id` with a
  `label_snapshot`, so that history survives the word it was recorded for.
- **Soft, and undoable in one tap.** `buttons.deletedAt` exists and
  `edit_events` already carries `EditKind.delete`. Undo restores the word to
  its own cell — and must refuse rather than guess if something else has taken
  that cell since.
- **A system button is not deletable.** Home, back, the category keys and the
  paging keys are the frame; removing one is a board that cannot be navigated,
  not a word somebody no longer needs. §4.15's board deletion offers the
  control on every board and refuses with a reason, which reads better than a
  control that is simply absent — the same applies here.

### 4.31 Moving a word to another board picks the spot on the board — delivered

Requested: moving a word to another board should take you to that board to
choose the location visually, rather than picking it out of a menu.

Today "Move to another board" asks for the destination, then shows a
`SimpleDialog` of up to forty entries reading `Row 3, column 5`. Moving a word
*within* a board is already visual — you tap the word, then tap where it should
go — so the cross-board path is the odd one out, and it is the one where seeing
the board matters more, because the caregiver does not have that board's layout
in their head.

Reading coordinates off a list also asks somebody to translate a number into a
place on a grid whose whole argument is that position carries meaning. The list
is capped at forty, so on a large board some free locations cannot be chosen at
all.

Shape:

- **The destination board is still a list**, because boards are a list. Only
  the location becomes visual.
- **Then the destination board opens in the editor with the word in hand**, and
  a tap on any free location places it — the same gesture as a move within a
  board, so there is one thing to learn rather than two.
- **The confirmation stays.** Crossing boards is still a move, and it still
  costs whatever practice the old location had.
- **Afterwards the editor stays on the destination board**, because that is
  where the word now is and the caregiver's next question is how it looks
  there.

### 4.32 Search results name the pack they came from — delivered

Requested: attribution under a symbol while searching the packs, so it is clear
which pack a picture came from.

The picker draws a grid of pictures and nothing else. A search for one word
deliberately puts several packs' answers side by side — that is the point of
searching them all — and the caregiver choosing between them currently has no
way to tell a Mulberry drawing from an OpenMoji one except by recognising the
house style.

Two reasons it matters, and the second is the load-bearing one:

- **Consistency is the thing being chosen.** A board whose pictures all come
  from one set is easier to read than one assembled from four, and a caregiver
  cannot keep to a set they cannot identify.
- **Attribution is a licence condition, not a courtesy.** Every bundled pack is
  CC BY-SA or CC BY, and all of them require the credit to be reachable from
  inside the running app. `SymbolCredits` satisfies that today for the app as a
  whole, and naming the pack at the moment of choosing is where it is actually
  useful to a person.

`SymbolRef` already carries `packId` and `SymbolRegistry.packFor` returns the
pack, whose `name` is written for a reader. Nothing new has to be stored.

### 4.33 A key every board carries cannot be hidden — delivered

Requested: system icons must not be hideable. Changing their picture stays
allowed.

The editor's hide control is offered on every button including `home`, `back`,
the category keys and the paging keys. Hiding one of those does not remove a
word somebody might not need — it removes the way off a board. A board whose
`home` key is hidden is a board an AAC user cannot leave, and they have no way
to say so.

The picture is a different matter and stays editable. What a key *looks* like
is exactly the kind of personalisation that helps somebody find it, and it
costs nothing: the location, the action and the movement are all unchanged.

Consistent with §4.15 and §4.30: **the control stays visible and refuses with
a reason.** A control that is simply absent reads as a bug and explains
nothing, and the reason here is worth reading — it is the same sentence that
explains why the key exists at all.

Refused in `RemapService.setHidden` as well as in the sheet, because the sheet
is not the only caller and a rule enforced only in the UI is a rule until
somebody writes a second caller. **Only the direction that takes a key away**:
unhiding is allowed, so a board built before this rule has a way back.

#### Found while building this

The delete tile pushed the actions sheet 16 pixels past the bottom of the
screen, which hid whichever action ended up last. It is a scrolling sheet now —
how many actions it holds depends on the button and on whether pictures are
available at all, so its height was never fixed to begin with.

### 4.34 "Remove the picture" was missing on most buttons — delivered

Reported: the control is not always there, and it was not clear why.

It asked whether a picture had been **chosen** — `symbolId != null` — when the
caregiver's question is whether there is a picture **on the button**. Most of
the shipped board has no symbol of its own and draws whatever the packs hold
for its word, so the control was hidden on exactly the buttons somebody was
looking at a picture on. It appeared only for a photo or a symbol picked by
hand.

It now asks what the button is actually drawing, through the same
`resolveButton` the board draws with. Removal writes the same marker it always
did, which is what the marker is for: **"deliberately no picture" is a
different state from "nothing chosen yet"**, and only the first survives a pack
being switched on later.

**Offered while the lookup is still in flight**, not after. A control that
appears once a slow pack replies is one a caregiver has already decided is
missing and closed the sheet on. The cost of being early is a press that pins
"no picture" on a button that turned out to have none — which is a thing
somebody might want anyway.

Three mutations, and the third is the one that mattered: hiding the control
until the lookup returns passed every test until a hanging pack was added to
the file. A word with no picture anywhere is still not offered it.

### 4.35 The device's own emoji as symbols — delivered

Asked: are we allowed to use the emoji of the system the app runs on as icon
options?

**Yes, with one line that must not be crossed.** Drawing an emoji *character*
with whatever font the OS provides is displaying text — the same thing every
text field on the device does — and redistributes nothing. Apple Color Emoji
and Segoe UI Emoji are proprietary fonts: their glyph images may never be
extracted, bundled, or shipped, and this must not become a route to doing that
by accident. So the rule is **store the codepoint, never the picture**. Nothing
about the font travels with the board.

The trade, stated plainly: **the drawing is not the same on another device**,
or after an OS update. That matters less here than it sounds — the motor plan
is the location, not the picture — but a board exported to OBF renders
differently elsewhere, and a school with mixed devices sees different pictures
for the same word. It is a per-device convenience, not a portable symbol set.

#### Why it is worth more than it looks

Measured, because the answer was not what the pack list implies. Of the five
bundled packs only **`core` has any images at all** — 274 symbols, exactly the
shipped vocabulary. `mulberry`, `openmoji`, `twemoji` and `tawasol` are
declared, are credited on the symbol credits screen, and return **nothing, for
every query, always**: only `assets/symbols/core/` is in `pubspec.yaml`.

So today a caregiver adding their own word has no offline source of pictures.
The word gets whatever `GlobalSymbolsPack` fetches, or it gets none. Against
that, the system emoji font is thousands of symbols, offline, at zero bundle
cost — which is a much bigger gap than "another pack" suggests.

#### Shape

- **`SymbolImageKind.glyph`**, whose `uri` is the character. `SymbolPicture`
  gets one more case and draws it as scaled text. Everything else in the
  resolver is unchanged, including the label-only fallback.
- **A keyword index has to be bundled**, because the OS exposes no searchable
  list. Unicode's CLDR emoji annotations are the standard source and are
  permissively licensed; generated by a tool alongside `fetch_symbols.dart`,
  the same way the core pack is.
- **Not on by default for auto-attach.** §5's rule stands: a wrong symbol shown
  to somebody looking at it is a near miss they can reject, and a wrong symbol
  attached unattended is the board putting a word in somebody's mouth. Emoji
  keywords are broad, so this pack is for the picker only.

#### What shipped

1,505 emoji in a 211 KB index — names and search words from Unicode CLDR
48.2.0, under the Unicode License v3, with the notice carried in `NOTICE.md`,
in the index's own `attributions` field, and on the in-app symbol credits
screen, because the licence requires the credit to travel with the data.
Verified by reading the asset: it holds codepoints and words, and not one image
byte.

**The emoji set is pinned to 13.1 (2020), not the latest.** A codepoint the
device's font does not have renders as a missing-glyph box — precisely the
broken-image outcome §5 forbids — and the supported iOS and Android floors here
predate the newer sets. It costs about 58 emoji.

`SymbolImageKind.glyph` carries the character; `SymbolPicture` draws it scaled
to its cell. A `GlyphSymbolPack` marker interface is what `auto_symbol.dart`
excludes, rather than the `isBundled` flag — so flipping that flag later cannot
quietly open the door. Three tests hold it, and the third is a control proving
the other two fail for the right reason.

#### The bug it surfaced, which was already logged

§4.6b recorded that the board's pack list was written twice and would drift.
It was three by the time this landed, and they disagreed: the board falls back
to `['core']`, the editor kept its own copy of the same list, and the picker's
"what is this button drawing" preview asked *every* registered pack. With
thousands of emoji suddenly answering ordinary words, that preview started
showing pictures the board would never draw — and offering to remove them.

Now one `boardSymbolPackIds`, in the symbols layer, used by all three. The
keyword fallback stays curated on purpose: it runs with nobody looking, so a
broad match there is a wrong picture nobody chose on a screen whose user cannot
report it. Broad packs belong in the picker, where a person is deciding.

### 4.36 Four bundled packs return nothing — found, not fixed

`mulberry`, `openmoji`, `twemoji` and `tawasol` are constructed by
`bundledSymbolPacks()`, listed to the registry, and credited on the symbol
credits screen — and `pubspec.yaml` ships only `assets/symbols/core/`, so every
search against them fails to load a manifest and returns empty. Verified by
searching all five for five ordinary words: `core` answered, the other four
returned nothing.

Two separate problems, and they want different answers:

- **The search side** is a silent no-op. Four packs a caregiver can see and
  switch on that can never produce a picture.
- **The credits side** is the more delicate one. The attributions are not
  wrong — `core` really is assembled from those sets and its manifest carries
  per-symbol credits — but listing them as packs in their own right implies the
  app carries sets it does not.

Not fixed here because the right answer is a product decision: bundle the sets
for real (bundle size), or stop declaring the ones that are not bundled and let
`core` carry their credits alone. Whoever picks should read `NOTICE.md` first,
since the licences require the credit to be reachable from inside the app and
that must stay true either way.

### 4.37 Joining words take the root board's spare column — agreed, not built

The root board holds one empty column, labelled `THINGS`, reserved so a
particular person's most-used nouns can be promoted to the root board and cost
one movement instead of three. Beside it, `JOINING WORDS` — `a`, `the`, `and`,
`but`, `because`, `so` — is exactly full.

Decided: **joining words win the spare column.** They are the words that turn a
run of content words into a sentence, they apply to *any* sentence rather than
to one person's vocabulary, and on a starter board that generality is worth
more than a reserve nobody has filled yet. A caregiver who wants their own
nouns on the root board can still put them anywhere empty; what they lose is a
column held open for that purpose in advance.

**Nothing moves.** `articles` keeps the column it has and gains the one beside
it as its reserve; the `nouns` band goes away. Every word on the board stays
exactly where it is — this is a change to what a region *means* and to what its
label says, not to any location.

### 4.38 A band keeps its lines across every page of a group — agreed, not built

Reported: on an iPad mini at medium icons, the `DOING` columns are 4, 5 and 6
on `home` and columns 1 and 2 on `home 2`. Asked: what is the value of holding
a region in the same place across pages?

It is the same argument the whole board rests on, one level down. A region that
means "doing" teaches somebody where to look, and a region that moves when you
page is learned twice. It matters more for scanning: a row-column scan's first
press narrows to a region, and a region that relocates per page makes that
narrowing worth nothing. The visible symptom today is that the region labels
differ between page one and page two of the same board.

**Measured before deciding, and the result was the opposite of the expected
trade.** Holding lines steady needs *fewer* pages, never more, at every grid
size tried — 7×12: 12 pages today against 9; 7×11: 13 against 11; 5×8: 23
against 17; and equal at 10×8, 11×7 and 9×14. The reason is that today each
overflowing band claims a fresh whole line on page two, so five bands spilling
one word each cost five lines; refilling the lines a band already owns, which
are usually wider, packs better. So there is no consistency-versus-density
trade here to weigh. It is simply better.

#### The part that is not obvious

A band shed *entirely* off page one owns no lines there, so "keep the same
lines" is undefined for it. This is not an edge case: across every buildable
grid and all four age presets there are **1,414** band-and-grid combinations
where an overflowing band has no page-one line assignment, because `_shedALine`
takes whole lines and a band that gives up all of them gets no entry at all.

So the rule has two halves:

- **A band that owns lines on page one keeps them on every page.**
- **A band that owns none is given lines on the first page it appears on, from
  the lines whose page-one owner has nothing to spill there — and then keeps
  those on every later page.**

Consistency from the page a band first appears on, which is the strongest
promise available, rather than a rule that silently does nothing for half the
bands.

#### Free space beats a new page

Refined after the first draft: **a band only has to page when a neighbour is
competing for the space.** Where the lines beside it are not claimed by another
band on that page, it is welcome to grow into them instead.

So the anchor is the band's own lines, and the rule when it runs out of them
is, in order:

1. **Grow into adjacent lines nothing else needs on this page.** A line whose
   page-one owner has nothing to spill here is free, and using it costs nobody
   a position.
2. **Only then page**, and on the next page the band starts from its own lines
   again.

This keeps consistency where consistency is free and refuses to buy it with a
key press. A page is a movement every time the word is said; an empty column
beside a band is not. It also lowers the page counts above further, since the
measured figures assumed a band was confined to its own lines.

What it costs is that a band's *extent* can differ page to page — `doing` might
run 4–6 on page one and 1–6 on page two. Its **start** does not move, which is
what a person reaches for, and the alternative is an extra page to protect an
edge nobody navigates by.

Two consequences worth stating:

- **Pages get sparser and that is correct.** A band with nothing to spill
  leaves its lines empty on page two rather than letting another band borrow
  them. Half of every board already ships deliberately empty (§2); these are
  reserved locations, not missing ones, and they are where that band's own
  extra words go.
- **The band map becomes a property of the group, not of the board.** Region
  labels then read the same on every page, which is the same fix seen from the
  caregiver's side.

### 4.25 Letting clusters share a row — measured, and not worth building

The proposal was a setting: instead of every cluster starting its own row
(§4.24), let a cluster fill the tail the one before it left, saving the wasted
tails and the words they push to a second page.

**Measured, it saves nothing.** `layOutBands` budgets a whole line per band in
`totalWidth()` before it places anything, and does so whether or not the band
sets `startsLine: false`. Eight bands run through the engine both ways placed
44 and overflowed 10 either way — identical. Packing only slides the survivors
up into fewer rows and leaves the trailing rows empty.

**And it costs the labels outright.** A band with `startsLine: false` gets no
`bandLines` entry at all, so §4.19 has nothing to name it with — not a shared
label or a truncated one, no label, with `bandAt()` attributing its cells to
the band above. In that same measurement three of six clusters went unnamed.

So it is not a trade between tidiness and density. As the engine stands,
own-row is strictly better on both counts, and the setting would only let a
caregiver make the board worse in two ways at once.

**What would have to change first:** the line budget would have to stop
charging for a line a band does not use, and `bandLines` would have to be able
to describe a region that is part of a row. Both are `band_layout.dart` changes
of real size. Worth revisiting only if a board turns up where own-row pages off
something a person needs daily — §4.24 looked and found none.

### 4.23 Three bugs the macOS build surfaced — delivered

Running the same code on a desktop window found three things the iPad had been
hiding. Worth keeping the macOS target for that reason alone.

- **One word in two places.** `to`, `out` and `this` appeared on both pages of
  the home board. `topUpVocabulary` asked "is this word already here?" of a
  single board, and pages are separate boards — so a word §4.21 had moved from
  page two to page one looked missing and was placed again. It now asks the
  whole page group. **This is the failure the project exists to prevent**: one
  word, two locations, and no way for a user to know which one they learned.
- **"Build the board" did nothing.** `setState(() => _ready = Future.value(p))`
  — an arrow body returns the value it assigns, so the closure looked
  asynchronous, and Flutter refuses an async `setState` and discards it. The
  app stayed on the screen it was on. A block body fixes it. It was silent on
  iOS only because the first run there had already happened.
- **Setting a PIN failed on macOS** with `-34018`, *"a required entitlement
  isn't present"*. The salt lives in the keychain and a sandboxed macOS app
  cannot reach it without `keychain-access-groups`. Added to both the debug and
  release entitlements.

Also: the label switch now says when there is nothing to label, rather than
going on and changing nothing. A board built before §4.19 recorded its regions
has none to read, and a switch that appears to do nothing reads as broken
rather than as an older board.

### 4.29 Row labels were invisible, and why nothing caught it — delivered

The labels shipped working on the root board and invisible on every category
board. Two faults, and the second one matters more than the first.

**The strip was always drawn as a band across the top.** The root board bands
by column so that is right for it; a category board bands by row, so every
label was positioned at its row's offset inside a box 22 pixels tall and landed
outside it. It now runs down the side for a row-banded board. And on the side
the strip is only as wide as a label is tall, so the word has to run **along**
the row — rotated, reading bottom to top, the way a spine does.

**Every test passed while it was broken**, which is the part worth keeping.
`find.text` found each label, `getTopLeft` reported distinct offsets, and the
labels were genuinely in the tree — just drawn where nobody could see them.
A test that asks "is the widget there" cannot tell that apart from working.

So: **`test/board_render_test.dart` renders the real screen to a PNG.**
Home and food, each with labels on and off. Regenerate with
`flutter test --concurrency=1 --update-goldens test/board_render_test.dart`
after a deliberate layout change, and **look at the file** — a golden nobody
opens is only a checksum. Text renders as boxes without a font bundle, which
does not matter: what these catch is geometry, and geometry is what was wrong.

The narrower assertion now in `region_labels_test.dart` is the strip's own
shape — down the side it is `regionLabelExtent` wide and taller than four of
them. That is what bites when the axis is wrong; the label-finding assertions
never did.

### 4.24 A category row is one cluster — delivered

Reported against the food board: *"the columns and rows are not organized at
all, so it becomes a MESS."* Drinks ran into bread and toast, `breakfast` sat
at the end of a row next to `salad`, and `lunch dinner snack` opened the next
row beside `apple banana`. Meal names, fruit and staples were interleaved.

**The cause was one band holding all forty three nouns**, wrapping at the row
edge wherever it happened to reach it. The clusters were contiguous in reading
order and that is not the same as being on one row. §4.0 had traded tidy rows
for page-one density and the trade was wrong: a row that runs two groups
together is learned word by word, and a row that is only drinks is learned
once.

Now **one cluster to a band, one band to a row**, on every category board.

| board | rows now | page two, before → after |
|---|---|---|
| people | greeting, family, names, community, words for people, who you mean | 0 → 0 |
| food | eating, drinks, meals, everyday food, fruit, how it is | 0 → 10 |
| play | saying, doing, games, toys, films and music, again | 0 → 8 |
| feelings | saying, liking, feeling, more feelings, right and wrong, ours | 0 → 0 |
| places | everyday, travel, at home, places you go, where, ours | 0 → 0 |
| body | saying, toileting, head, arms and legs, body, care | 5 → 6 |
| doing | unchanged — six clusters already | 0 → 0 |

**Twenty four words on page two, up from five.** Nineteen of the twenty four
are level 3 and are drawn by nobody below the top level, so what a level-2
board actually loses from page one is five words: `cake`, `biscuit`, `sore`,
`sleepy`, `poorly`. Four of the seven boards pay nothing at all. Page two is
one press of a key that is in the same place on every board; a mixed row is
permanent.

The empty tails are not waste. A cluster of five on an eleven-wide grid leaves
six reserved cells, and those are where a caregiver's own words *for that
cluster* go — a child's brand of yoghurt lands beside the other treats instead
of wherever there happened to be room.

**Own row rather than shared row, and this is measured rather than assumed.**
Letting a cluster fill the tail of the one above it (`startsLine: false`) saves
nothing: `layOutBands` budgets a whole line per band before it places anything,
so a packed band is still charged a row and the same words shed either way —
44 placed and 10 overflowed with and without packing, on the same eight bands.
What packing does change is that a band which does not start a line gets no
entry in `bandLines`, so it has no region label at all. Three of six clusters
went unnamed in the measurement. Packing is worth having only if the budget
stops charging for a line it does not use.

**Costs, stated plainly.** The body board has seven clusters and six rows, so
the symptom adjectives — `itchy`, `sore`, `dizzy`, `thirsty`, `sleepy`,
`poorly` — read on page two. They lose to the medicine cupboard on level, not
on rank: `emergency` is level 1 and nothing in the symptoms is. It is still the
right one to move, because every word in it needs a body part to attach to and
the parts are three rows above it. The teenage preset's play board pays most:
its `screen` strip is a ninth band, so `games` joins `outdoor` on page two —
sixteen words against eight before.

Nothing was re-levelled. Level totals are unchanged at 99 / 249 / 372.

### 4.21 A narrow grid scattered related words — delivered

Reported at 7×11: `we`, `they` and `my` on page two while their pronoun column
had five empty cells; `to` and `out` on page two while their column had three.
Fifteen words left the board to free one column.

**The layout sheds by line and was choosing by word.** A band claims whole
lines, so a word taken from a band with room to spare costs that word its place
and buys the grid nothing — the grid is no narrower, and the word is on page
two. The loop took the globally least important word and repeated, which meant
it emptied the bands with the *most* slack first, because slack is where the
lowest-ranked words sit.

Now a line is given up at a time, all of it from one band. Every band is asked
what a line would cost it; the band whose most important sacrifice is the least
important overall pays, and only that band loses anything.

**Within the band, the words that go are the least important, not the last.**
A band holds its words in the order they read, so its final line is as likely
to be core vocabulary as anything else — taking a line off the end shed `good`
while keeping a word nobody had needed yet.

Measured at 7×11: **15 words lost became 6**, and the 6 are the articles band,
whose column genuinely disappeared. `we they my`, `to out` and `this` all stay.
7×12 is byte-identical. At 8×10 every grammar key now survives where none did;
at 6×12 and 5×14 the endings do.

One test was encoding the old behaviour and now asserts the better one: at the
smallest usable grid two words are shed rather than three, because the third
band was never asked and its word had a location nothing was competing for.

### 4.20 Rebuild a board set from the shipped vocabulary — delivered

A board set is materialised once, at profile creation, and nothing re-runs it.
That is the right rule for a person who has learned a layout, and the wrong one
while the layout is still being designed: a change to the seed reaches new
profiles and leaves the device it was tested on showing the old board. The
question mark was still sitting in the pinned column after being removed from
the seed, because that column had been written months of taps earlier.

So: **Rebuild from the shipped vocabulary**, in caregiver settings. It builds a
fresh board set at the profile's current grid and points the profile at it.

- **It discards, it does not merge.** Anything a caregiver added by hand is
  gone. That is the honest description and the confirmation says it in those
  words, with the count of hand-added words that would go.
- **Typed confirmation**, like the grid change, because it is the same class of
  act and reflex should not reach it.
- **The old vocabulary is left in place**, not deleted. Usage rows point at its
  cells, and the history is what the remap warning is built on.

Not a migration and deliberately not one: a migration would have to guess which
of two layouts a person had learned. This asks.

### 4.19 Labelled regions — delivered

A caregiver setting, **off by default**, that names each run of locations by
what it is for: `who`, `doing`, `where`, `word endings`, `asking`.

**The regions are recorded, not inferred.** `boards.band_map` (schema 6) stores
which lines each band took, written by the seed from the same `bandLines` the
layout engine produced. Guessing from the words that happen to sit in a column
would put a name on a grouping nobody chose, and would disagree with the board
the moment a caregiver moved a word.

- **Chrome, above the grid.** It takes height from the grid rather than a
  location — the reserved lines are exactly where a caregiver's own words go,
  and a label that consumed one would be teaching the layout by damaging it.
  Switching it off puts every button back; nothing is rebuilt and no cell
  moves.
- **Both axes.** The root board bands by column so the labels run across the
  top; a category board bands by row so they run down the side. The stored map
  carries the axis.
- **A label covers the lines its band owns, reserved ones included.** An empty
  reserved column is the most useful thing on the board to be able to name and
  the one with no word to give it away.
- **Partial lines are fine**, as agreed: a band's boundary is its lines, and a
  band that only half fills its last one still owns it.
- **Names are rewritten only where they need it.** `pronouns` reads `who`,
  `verbs` reads `doing`, `endings` reads `word endings`. Bands already named
  after what they hold — `family`, `eating`, `moving` — are left alone rather
  than given a second name to keep in step.

**A board built before schema 6 has no map and is simply not labelled.** A
board a caregiver made by hand has no bands and is not labelled either. Both
fill in on a rebuild (§4.20).

### 4.19-old The original brief

A setting that segments each board into its regions and names them: the
rightmost column as **questions**, the bottom row as the **system row**, the
verb columns on the home board as **verbs**, and so on for every band.

**Off by default.** It is scaffolding for the people teaching the board, not
for the person speaking on it — and a label costs pixels a button was using.

**The data already exists.** `BandLayout.bandLines` records the first and last
line each band owns, including the lines it holds open and never filled, and
`bandAt(row:, col:)` already answers "which band owns this location". Nothing
needs to be inferred or recomputed. `system_cell_map` names the frame.

Why it earns its place, given the thesis: the board's whole argument is that a
column *means* something — the root board encodes Fitzgerald sentence order, so
reading left to right builds a sentence, and category boards group by word
class. That structure is invisible to a caregiver, a TA or a classroom
assistant looking at the grid for the first time. They are the people who have
to model the board, and Johnson et al. (2006) puts failure to maintain the
system at the top of the abandonment list. A label that says *verbs* over that
band is the cheapest possible way to teach the pattern the layout is built on.

Open questions before it can be built:

- **Where the label goes.** It cannot take a cell — that would displace
  vocabulary, and the reserved lines are exactly where a caregiver's own words
  are meant to land. So it has to be chrome: a thin strip outside the grid, or
  drawn over the band's edge.
- **Both axes at once.** The root board bands by column and category boards by
  row, so the labels move edge with the axis. A board needs at most one strip;
  the frame (question column, system row) needs the other.
- **It must not move a single cell.** If the strip takes height or width from
  the grid, it is a displacing change and needs the treatment §4.9 gave the
  prediction strip — new profiles only, written down explicitly for existing
  ones. If it can be drawn in the existing inset, it is free and can simply be
  a toggle.
- **What a reserved line is called.** The band names are internal
  (`pronouns`, `endings`, `articles`); some are right for a caregiver and some
  are not. Each band needs a display name written for a human, and an empty
  reserved column needs one too — it is the most useful label on the board and
  the one with no band word for it.

### 4.18 The trail is a path, not a tap log — delivered

Pressing a category three times drew `home → body → body → body`. The trail
appended a crumb per press, so it recorded what was pressed rather than the way
to get back — which is the only thing it is for. A caregiver reading it is
being told how to repeat the route, and repeating three presses of `body` is
not the route.

Two rules, and they come from how the board is actually reachable:

- **A category key is one press from anywhere**, because it sits on the system
  row of every board. So arriving at a category board makes the path
  `home → that category`, whatever the user pressed to get there. Going
  `body → people` reads `home → people`, because that is what somebody
  repeating it would do.
- **A step onto somewhere the route has already been rewinds to it** rather
  than appending, which is what `back` already did.

**Paging stays a step**, because it is reached by a key on the board it pages
from.

**A turn of the wheel is not a step, and the first attempt got this wrong.** It
recorded a crumb per press of the cycle key, which is the same tap-log defect
one level down: cycling round the wheel and past your category records a route
nobody would walk again. Pressing "more categories" five times on a three-turn
wheel leaves you on turn two and read as five presses.

Which turn a category sits on is a fact about the category, so the route is
**rebuilt from the category** rather than accumulated on the way to it: from
home the wheel is on its first turn, so a category on turn two is two presses
of the cycle key and then the key showing its name, whatever was actually
pressed. The crumb also takes the **category's own name** rather than the label
of the key that was pressed — a caregiver's own shortcut button straight onto
the food board reads `home → food`, because that is what somebody repeating it
from home would press.

The mutation that made this land: counting turns from *the wheel's current
turn* instead of the category's passes every test that goes through the wheel,
because tapping a category key means you are already on its turn. The two only
part company when a category board is reached another way, and that case now
has a test.

### 4.17 Home turns the category wheel back — delivered

`home` reset the board, the navigation trail and the back target, and left the
category wheel wherever it stood. So home was a place the board only half
returned to: the category keys are a window onto one list and the cycle key
moves the window, so `food` is a different board on each turn, and the sequence
to a word depended on which turn somebody had stopped on.

That is the one thing the whole layout exists to prevent. Home is now a
complete reset, the wheel included.

Deliberately **not** applied to `back` or to auto-return. `back` is a step in a
route somebody is walking and rewinding the wheel underneath them would move a
key they are about to press; auto-return happens after every word, and turning
the wheel there would stop a user saying two words from the same second-turn
category without re-cycling between them.

### 4.15 Deleting a board created by mistake — built

A caregiver could create a board and could not remove one. "New board" is two
taps from the caregiver home, so a mistyped or duplicate board is easy to make
and was permanent once made.

Not a plain delete. A board holds cells, cells hold buttons, and buttons hold
the usage history that the remap warning is built on. What it does:

- **An empty board a caregiver just made is the easy case.** One tap on the
  bin beside it in the board list, no confirmation, a note afterwards. That is
  the case this exists for and it is the only path with no ceremony.
- **A board with words on it states what would go**, in the count of words and
  the recorded taps against those locations — "Maya has tapped those locations
  341 times across 12 days in the last 90 days" — over the same 90-day window
  a single word's move uses, so two numbers a caregiver reads in one sitting
  were measured the same way.
- **Deletion is a `deleted_at`**, like a profile. `boards.deleted_at` has
  existed since schema version 1, so nothing migrated. The board's buttons take
  a `deleted_at` and a `hidden` — `hidden` is what the grid and the prediction
  strip read, `deleted_at` is what stops a bulk unhide such as the
  strong-language switch, which matches on label and knows nothing about
  boards, bringing the words back. Every cell is left exactly as it was,
  occupied included: removing a board is not a way to make a location move.
- **No key is orphaned.** Any button whose `targetBoardId` names the board is
  hidden and set to `none` in the same transaction. It keeps its cell, because
  a location somebody has reached for must never be handed to something else,
  and a navigate key with a null target would strand the talk screen on a board
  that is not there.
- **Every recorded tap survives.** `usage_events` is untouched, and the whole
  thing is written to `edit_events` with the tap count it cost and the prior
  state of each key.

**Only a caregiver-made board can go, and the reason is shown rather than the
control being absent.** Refused: the home board; a board with a place on the
category wheel; a board opened by a key that holds the same coordinates on
every board, which is what the later pages of every seeded board are. That last
test is what separates seeded structure from a caregiver's own board without a
column to record it in — every seeded board-to-board link is placed
`isSystem`, and nothing a caregiver can create is.

The wheel is therefore never touched. `vocabularies.system_cell_map` is
append-only because the keys are a window onto it, and taking a name out is
that hazard in reverse: it would change which board every key after it opens
without a single button moving. Emptying such a board is the alternative
offered, and the refusal says so.

Not built: any way back. Soft deletion means a removed board is recoverable in
principle, and `edit_events` holds what would be needed, but there is no
restore screen.

### 4.16 Pinning a word to every board — agreed, not built

Requested: a caregiver should be able to pin a word.

The mechanism already exists and is not exposed. The question column is pinned
— `what where who when why how` hold the same coordinates on **every** board,
so they are reachable without going home first — and so is the system row. Both
are described by `vocabularies.system_cell_map`. Nothing lets a caregiver put
their own word in that class.

Why it is worth having: the whole board is built so a word costs the same
movements every time, and the one thing that breaks that promise is depth. A
word on a category board costs the trip in and the trip back. Pinning is the
existing answer to "this person says this constantly" — and today the only
answer offered is to move the word to the root board, which is a displacing
edit that competes for the scarcest space there.

Open questions before it can be built:

- **What it costs.** A pinned location is taken from every board at once, so
  pinning one word is not one cell but one cell times the number of boards.
  The confirmation has to say that in cells, not in words.
- **Where it comes from.** The pinned column is `rows - 1` long and full at
  7×12 (see §4.14). Pinning has to either extend the column, take from the
  content area, or be refused with a reason.
- **Unpinning must not strand the word.** It has to return somewhere, and the
  somewhere has to be decided before the pin is offered.

#### The three answers, settled

**A pin is a copy, not a move.** The word keeps the location it already has and
*gains* a second, shorter route to itself. That single decision closes the
stranding question outright: unpinning takes the pinned location back to
reserved and the original path is untouched, because it was never disturbed.
Nothing can be stranded because nothing moved.

It looks wasteful — one word, two locations — and it is the right waste. The
alternative is moving the word to the pinned column, which is a displacing edit
that costs its learned position on the board it came from, to buy a shorter
route to the same word. Pinning is supposed to make a frequent word cheaper,
not to trade one motor path for another. Two paths to one word is also already
how this board works: `where` is in the pinned column *and* reachable nowhere
else, and a category key reaches a board that `back` also reaches.

**What it costs is one cell on every board, and there is currently one to
spend.** The pinned column is `rows - 1` deep and the shipped frame puts six
questions in it, so at **7 rows it is exactly full and there are no spare
pinned cells**. At 8 rows or more there is at least one.

The one free location on the shipped 7×12 frame is the **gap at column 2 of the
system row** — the deliberate empty cell between the home/back pair and the
category keys, reserved on every board. Spending it on a pin costs the
mis-reach guard it exists for: home and back undo what the user just did, the
category keys go somewhere new, and shoulder to shoulder an imprecise reach for
one lands on the other. That is a real trade and it is the caregiver's to make,
stated in those words rather than as "one location is available".

So the rule is: **pin into an `empty_reserved` location in the pinned column or
on the system row, or refuse.** One pin at 7×12, more on a taller grid, none
once they are spent.

**What is not on offer:** widening the pinned column. Going from one pinned
column to two takes a content column from *every* board — six locations a board
at 7×12, across every board in the set — and re-lays everything left of it.
That is a grid change, not a pin, and it belongs behind the §4.20 rebuild path
with a full displaced-word report or nowhere.

**And not this either:** freeing a pinned cell by hiding the question in it.
Hiding never releases a location (§2), so a hidden `when` does not make its cell
available to something else. That rule is what makes "grow over time" and
"never relocate" both true, and pinning is not the thing to break it for.

### 4.6a Sentences the board still cannot build

Each of these is a real utterance a person would want, named rather than
quietly absent:

- **A plural subject behind a determiner, in the settling mode only.**
  "where are the people?" comes out *"where is the people"* under
  `CopulaMode.agree`: the copula settles against the word immediately after it,
  so a determiner in between blocks the agreement.

  ⚠️ **This was overstated. Under the default mode it is not a defect at all** —
  toggle does not settle anything, so pressing the key twice gives "are" and
  nothing overwrites it. It costs one extra press and is otherwise exactly the
  sentence wanted. This is only reachable by a profile that has chosen the
  other mode.

  Also worth recording: **`people` is not a word this board can say.** It is a
  category name and a band name, and `copulaFor` lists it among the plural
  subjects, but nothing places it as a speakable button — so the example
  sentence cannot be built at all, in either mode, for a different reason than
  the one this entry claimed.

  If it is fixed, the honest fix is plural detection rather than a smarter
  repair: deferring past determiners only helps for the handful of words known
  to be plural, and "where is my shoes" would stay wrong either way.
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
- **The bundled pack list was written twice — fixed**, and had become three by
  the time the emoji pack landed. One `boardSymbolPackIds` now; see §4.35.
- **Nothing writes `UsageSource.switchAccess`.** The reports count it
  correctly, but no scanning input path exists yet, so a switch user's
  selections are still recorded as touches. The reporting is correct ahead of
  the producer; the producer is Phase 8.
- **The paging key was drawn whether or not the next page had anything on it at
  the current level — fixed.** Measured before fixing, and it was wider than
  this entry claimed: at 7×12 a **level-1** profile pages forward from home,
  `food` and `body` onto boards that draw nothing at all, and `play` page two
  draws nothing at level 1 *or* 2. The entry named level 2 and home only, which
  the shedding rewrite in §4.21 had since moved.

  The key is now not drawn when its page has no content the current level
  draws — the same rule as `back` at the root board, and for the same reason:
  its location stays reserved, so the key reappears in exactly the same place
  the moment the page is worth going to. Hiding it is a rendering decision,
  never a move.

  Only the **content area** counts — the frame is on every board, so a page
  carrying nothing but the system row and the pinned question column shows the
  user the keys they just left. "Switched off by a caregiver" and "above the
  level" are different states and both count as nothing to see.

  A paging key is recognised off the system row rather than off its label: the
  row carries home and back, which are their own actions, the category slots,
  which the wheel owns, and the cycle key — so a system navigation key that is
  not a category slot is a paging key, whatever anybody renames it to.

  Five tests in `app/test/empty_page_test.dart`, four mutations, all caught.
  One of the five exists only to assert the *premise*: that the shipped board
  really does still produce a page above level 1. Without it a future seed
  change could make the other four pass by describing nothing.
- **`docs/starter-vocabulary.md` — delivered.** The distinction that mattered
  is §2.1 against §2.2 of it: the Universal Core 36 verified from its primary
  source and drawn at level 1, against Banajee (2003) and Marvin (1994) as real
  papers whose paywalled word lists were never obtained and on which nothing
  rests. It leaves two gaps open rather than closing them plausibly — the
  med.unc.edu half of the Universal Core licence discrepancy could not be
  reproduced, and the Fitzgerald Key's 1926 date, which the out-of-copyright
  claim in `core_vocabulary.dart` depends on, is unconfirmed.
- **Neither way into caregiver mode is reachable by scanning.** Both are held
  points — one corner, or two — and switch access reaches buttons, not held
  locations. A caregiver who drives the tablet by switch cannot open the
  settings on it at all. §4.27 makes the one-handed door impossible to close,
  which is as far as a gesture can go; the answer past that is a scan-reachable
  route, and it lands with the scanning work in Phase 8.
- **Setup offered a grid the seed then refused — fixed.** `GridChoice.derive`
  asked whether the *frame* fits, a size threshold; the layout engine asks
  whether the words a board must always reach have anywhere to go. Two rules
  for one question, agreeing at every grid the app can produce but one: an
  iPad mini 5 or 10.2" held in landscape with extra-large icons derives 4×6,
  which setup offered and "Build the board" then threw on. **That is Haley's
  own tablet**, not a hypothetical device — the grid is derived from the real
  screen, which is what made it reachable rather than theoretical.

  Setup now asks the layout engine itself, memoised because the setup page
  asks for every icon size on every rebuild. `rootBandsFor` is now one
  derivation shared by the seed and the check, rather than the seed's own copy
  — two derivations of one thing drift, and this drift *was* the bug.
  `test/grid_offer_test.dart` sweeps all nine devices × two orientations ×
  four icon sizes and asserts setup's answer and the seed's are the same.

  A fourth mutation went further than the fix: dropping the spilled questions
  from `rootBandsFor` broke nothing. A grid under seven rows cannot pin all six
  questions, and the ones that do not fit are supposed to become ordinary root
  board words — an extra movement to ask "why" is a cost, losing "why" is a
  different thing entirely. Nothing tested it. Now something does.
- **A region label longer than its band was truncated — fixed by wrapping.**
  On the shipped 7×12 root board `word endings` read `WORD ENDIN…`, `joining
  words` read `JOINING WO…`, and `yes, no and how it is` read `YES, NO AND…`.
  A label runs along its band, so what fits is the band's own width — one
  column for most of them — and the strip was a single 22px line with nowhere
  to wrap. A label nobody can read teaches nothing, which is the whole argument
  for §4.19.

  These names are two and three words, so the answer is a second line rather
  than shorter names: the precision is why they were chosen. The strip is 32px
  and holds two lines, and it is **fixed at two whether or not any label needs
  them**. Sizing it to the longest label would let a caregiver renaming a row
  change the height of the grid, and with it the size of every cell on it —
  which is the one thing this project does not do quietly.
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

- **There is no installed base, and until there is, changes need not protect
  one.** One device runs this, and it belongs to the person building it. A
  change to the shipped vocabulary or layout does not need a path that carries
  existing boards forward — it needs a way to rebuild them, which is §4.20.

  What this does **not** suspend: the motor-plan invariants. Positions stored
  and not computed, hiding never freeing a cell, `motor_plan_invariant_test`
  blocking CI. Those are what the product *is*, not backwards compatibility.
  Schema migrations are still written when the schema changes, because the
  database on that one device holds real practice.

  Several changes above were made more complicated than they needed to be by
  defending boards that do not exist. This reverses at App Store release.
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
