# ADR 0001: Customization that defends the motor plan

**Status:** Accepted
**Date:** August 24, 2026

## Context

Motor planning works by never moving anything. A word occupies one location
forever, and with enough repetition the user stops looking for it, the same way
a touch typist stops looking for `k`. What the user ends up with is a movement
rather than a search, and a movement is fast enough to hold a conversation
with.

The obvious way to protect that property is to make layouts unchangeable. It
works, and it costs something measurable.

**Johnson, Inglebret, Jones & Ray (2006)**, *Augmentative and Alternative
Communication* 22(2), built from six focus groups and a 106 question survey of
275 ASHA AAC specialist members, ranked the drivers of inappropriate
abandonment. The construct ranked first was **"Not Maintaining/Adjusting the
System."** Failure to customize is the most commonly named cause of AAC
failure in that data.

**Yau, Choo, Tan, Monson & Bovell (2024)**, *Frontiers in Psychiatry* 15:1385947,
found **73 to 100% of stakeholders** reporting "poor customization, sensory
overwhelm, and physical incompatibility with user needs," and reported that
parents and caregivers in particular struggled both to navigate the devices and
to adjust vocabulary. The barrier is not that customization exists. It is that
it is too hard.

The words a person actually needs arrive from their life rather than from a
shipped list: a sibling's name, a food from their culture, a special interest,
a second language. The people who know which words those are are parents,
teaching assistants and therapists.

So there are two failure modes, not one. A layout that moves destroys
automaticity. A layout that cannot be adjusted gets put in a drawer. Both have
to be false at once, and the tension between them is the design problem this
project exists to solve.

## Decision

wordbridge treats the motor plan as an invariant the *software* enforces,
rather than one a clinician's discipline has to protect.

> **Additive changes are safe. Displacing changes are not.**

A change is **displacing** if a word the user has already used moves,
disappears, or acquires a different access sequence. Everything else is
**additive**: filling an empty cell, revealing a hidden one, editing a label or
symbol or spoken text, adding fringe vocabulary, changing a voice.

Additive edits are unceremonious. No ritual, no mode, no copy to fork.
Displacing edits are possible, because sometimes they are genuinely correct,
but they are surfaced with their real cost measured against real usage:

> *"Moving **eat** will change its motor pattern. Maya has tapped this location
> 341 times in the last 90 days. If she has learned this position, moving it
> may take weeks to relearn. Move anyway?"*

That dialog is the entire product in one screen. The software holds the
invariant. The person who knows the user decides what it is worth.

## Consequences

Three architectural commitments follow:

- **Position is identity.** Grid locations are permanent rows that exist
  independently of content ([ADR 0003](0003-motor-plan-model.md)). Positions
  are never computed from a list of buttons, because computed positions are how
  grid apps reshuffle in silence.
- **Hiding never frees a cell.** This is the mechanism that lets vocabulary
  grow without relocating anything ([ADR 0003](0003-motor-plan-model.md)).
- **Usage is logged against the location, not the word.** Without this the
  warning above cannot be written, and a remap would retroactively rewrite the
  history it reports.

The claim is falsifiable and we test it. `app/test/motor_plan_invariant_test.dart`
snapshots every word's motor path, simulates full vocabulary growth, and fails
CI if any pre existing path changes by a byte.

## What we are not claiming

The evidence for motor planning is thin. Direct experimental support is
essentially **Thistle, Holmes, Horn & Reum (2018)**, *AJSLP* 27(3): 24
typically developing children aged four, consistent versus variable symbol
location over five sessions. Both groups began near 6.0 seconds; the consistent
group reached 3.3 seconds while **the variable group did not improve at all**.
That is a striking result and it is one study, on children without
disabilities, measuring response time.

Against it, **Light et al. (2004)** found iconic encoding performed
significantly *worse* than three other organizations for children of the same
age, which is part of why we reject polysemous symbols
([ADR 0002](0002-no-polysemous-symbols.md)).

We build as if consistent location matters, because the mechanism is plausible
and the cost of being wrong is low. We do not claim more, and our materials
should not either.
