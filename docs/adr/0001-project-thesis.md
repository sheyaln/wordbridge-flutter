# ADR-0001: Project thesis — customization that defends the motor plan

**Status:** Accepted
**Date:** 2026-08-24

## Context

Motor planning works by never moving anything. A word occupies one location forever, and with enough repetition the user stops looking for it — the same way a touch-typist stops looking for `k`. The dominant implementation, LAMP Words for Life, protects that property by making layouts effectively unchangeable: default vocabulary files are locked, and editing requires forking a copy.

That protection has a cost, and the cost is measurable.

**Johnson, Inglebret, Jones & Ray (2006)**, *AAC* 22(2):85-99 — the canonical AAC abandonment study, built from six focus groups and a 106-question survey of 275 ASHA AAC-specialist members — ranked the drivers of inappropriate abandonment. The top-ranked construct was **"Not Maintaining/Adjusting the System."** Failure to customize is the field's number-one named cause of AAC failure.

**Yau, Choo, Tan, Monson & Bovell (2024)**, *Frontiers in Psychiatry* 15:1385947, found **73–100% of stakeholders** reporting "poor customization, sensory overwhelm, and physical incompatibility with user needs," and noted that parent-carers specifically "struggled navigating high-tech devices and vocabulary customization." The barrier is not that customization exists. It is that it is too hard.

Parents say the same thing in plainer language. From App Store reviews of LAMP:

> "the app's vocabulary is severely lacking… the words *blueberry* and *coyote* are not in the vocabulary… And even though you can program them into the App, there are often not appropriate pictures to go with the words."

> "As a busy family we often do not have the time to program the amount of words and pictures needed for our 12 year old into the device."

So there are two failure modes, not one. A layout that moves destroys automaticity. A layout that can't be adjusted gets abandoned. Existing systems pick a side.

## Decision

wordbridge treats the motor plan as an invariant the *software* enforces, rather than one the clinician's discipline protects.

> **Additive changes are safe. Displacing changes are not.**

A change is **displacing** if a word the user has already used moves, disappears, or acquires a different access sequence. Everything else is **additive**: filling an empty cell, revealing a hidden one, editing a label or symbol or spoken text, adding fringe vocabulary, changing a voice.

Additive edits are unceremonious — no fork-a-locked-file ritual, no mode. Displacing edits are possible, because sometimes they are genuinely correct, but they are surfaced with their real cost measured against real usage:

> *"Moving **eat** will change its motor pattern. Maya has tapped this location 341 times in the last 90 days. If she has learned this position, moving it may take weeks to relearn. Move anyway?"*

This is the entire product in one dialog. LAMP's answer to a risky edit is to make it hard to reach. AssistiveWare's is to forbid it. Ours is to tell you what it costs and let the person who knows the user decide.

## Consequences

Three architectural commitments follow, and each has its own ADR:

- **Position is identity.** Grid locations are permanent rows that exist independently of content ([ADR-0003](0003-motor-plan-model.md)). Positions are never computed from a list of buttons — computed positions are how grid apps silently reshuffle.
- **Hiding never frees a cell.** The mechanism that lets vocabulary grow without relocating anything ([ADR-0003](0003-motor-plan-model.md)).
- **Usage is logged against the location, not the word** ([ADR-0006](0006-usage-logging.md)). Without this the warning above is unwriteable, and remapping would retroactively rewrite history.

The claim is falsifiable and we test it. `test/motor_plan_invariant_test.dart` snapshots every word's motor path, simulates full vocabulary growth, and fails CI if any pre-existing path changes by a byte.

## What we are not claiming

The evidence for motor planning is thinner than the marketing around it. Direct experimental support is essentially **Thistle, Holmes, Horn & Reum (2018)**, *AJSLP* 27(3):1010-1017 — 24 typically developing four-year-olds, consistent versus variable symbol location over five sessions. Both groups began near 6.0s; the consistent group reached 3.3s while **the variable group did not improve at all**. That is a striking result and it is one study, on children without disabilities, measuring response time.

Against it, **Light et al. (2004)** found iconic encoding performed significantly *worse* than three other organizations for children of the same age — which is part of why we reject polysemous symbols ([ADR-0002](0002-no-polysemous-symbols.md)).

We build as if consistent location matters, because the mechanism is plausible and the cost of being wrong is low. We do not claim more, and our materials should say so. LAMP's evidence is thinner than its marketing implies; a project positioning itself as the honest alternative cannot inherit that habit.
