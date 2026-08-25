# ADR-0003: Position is identity — the motor-plan data model

**Status:** Accepted
**Date:** 2026-08-24

## Context

"Buttons must not move" sounds like a UI constraint. It is actually a data-modelling constraint, and getting it wrong at the schema level makes it unfixable in the UI.

The natural way to model a board is a list of buttons, rendered in order into a grid. It is also fatal. With a computed layout, *every* mutation is a potential relocation: deleting button 12 shifts 13 through 84 up one cell; inserting shifts them down; reordering shifts everything between. The reshuffle is invisible in the code — there is no line that says "move `eat`" — and catastrophic on the device, because a user who had automated `eat` now presses the wrong word with a movement they no longer have to think about.

This is not hypothetical. Parents report exactly this failure from commercial apps:

> "Latest update reset everything on my sons ipad. Now we have to redo months of work setting specific words for him!"

> "Not all, but a lot of buttons are moved around in different places. Why? I thought I understood the concept of motor planning, but after going from a Vantage Lite to LAMP WFL… I'm confused. I went in and moved the buttons back to the Vantage Lite spots."

The second is a parent migrating *within one company's product family* and finding the motor plan had moved.

## Decision

**Separate position from content, and make position the primary identity.**

A grid location is a permanent, addressable database row that exists whether or not anything sits on it. Content is a nullable attachment to a location. Vocabulary growth means attaching content to already-existing empty locations, or revealing content already attached.

### Cells are pre-materialized

When a board is created, **all `rows × cols` cells are inserted immediately**, empty, in one transaction. Cell ids are stable forever: never reused, never deleted.

```
cells: id (uuidv7, permanent), board_id, row, col,
       span_rows, span_cols, state, created_at
       UNIQUE (board_id, row, col)
```

This costs a few hundred rows per vocabulary and buys three things:

1. **Blank positions become first-class.** This matches real clinical practice, where empty cells are *deliberately reserved* for future vocabulary rather than treated as absence. Vocabulary grows *into* reserved blanks; it never reshuffles to make room.
2. **Usage can be anchored to a location.** `usage_events.cell_id` references a cell, so tap history survives content changes and remapping — which is what makes the impact warning in [ADR-0001](0001-project-thesis.md) possible at all.
3. **Cell merging is a property of the location**, not of the content. A wide "clear" bar is a cell with `span_cols > 1`.

### Three cell states

| State | Meaning |
|---|---|
| `empty_reserved` | Cell exists, holds nothing, deliberately reserved for growth |
| `occupied` + button `hidden = 1` | A word is assigned, not rendered, **and the cell is not available to anything else** |
| `occupied` + button `hidden = 0` | Rendered |

> **Hiding a word must never free its cell.**

This one rule is what makes "grow over time" and "never relocate" simultaneously true, and it is what home-grown board editors get wrong. It is also convergent practice: LAMP's Vocabulary Builder and AssistiveWare's Progressive Language both work this way, and independent SLP guidance is consistent — *hide, don't delete*; *start at the final grid size*; *add into empty cells, never move an existing word*; *reserve blacked-out cells at setup to hold future words*.

Vocabulary levels follow for free. A 1-hit (~84 words) → transition (~200) → full (2000+) progression is not a different board set; it is the same materialized grid under a render filter:

```sql
WHERE vocab_level <= :profile_level AND hidden = 0
```

Unhide a word six months later and it appears exactly where it always was. Nothing moves.

### Grid geometry belongs to the vocabulary, not the board

Motor planning depends on *absolute physical finger position*. If board A were 6×8 and board B 4×6, the same conceptual slot would land under a different finger and the plan is destroyed. Geometry therefore lives on `vocabularies`, and uniform geometry across every board in a vocabulary is an enforced invariant.

Grid size is chosen **once**, at setup, from vision and motor assessment — start at the size the user will eventually need and hide what they aren't ready for. Changing it afterwards on a vocabulary with usage history is a destructive migration that reports every displaced word and requires typed confirmation. It is never a settings dropdown.

### Buttons attach to cells, nullably

```
buttons: id, cell_id (NULL = unplaced), vocabulary_id,
         label, message, speak_text, action, target_board_id,
         symbol_id, part_of_speech, colors,
         hidden, vocab_level, is_system, ...
         UNIQUE INDEX ON (cell_id) WHERE cell_id IS NOT NULL
```

`cell_id` is nullable for two reasons: it permits an atomic three-step swap under the partial unique index when a remap is genuinely wanted, and it gives the editor an "unplaced words" tray — *here are 24 words in this vocabulary with no home yet, drag them into empty cells* — which is good caregiver UX and a natural place for bulk imports to land.

## Consequences

- Rendering reads cells and left-joins buttons, never the reverse. A cell with no button renders as reserved-blank; the layout is identical either way.
- The renderer computes exact pixel rects from measured container size and absolutely positions cells keyed `row:col`. No flex-wrap (sub-pixel reflow shifts targets between renders), no viewport-recycling list widgets (recycling is a correctness hazard when cell identity is the whole point). Order-of-84 positioned widgets is trivial for the renderer.
- Deleting a board is a soft delete; its cells persist so historical usage remains resolvable.
- `test/motor_plan_invariant_test.dart` is the enforcement mechanism and is CI-blocking.

## Related

- [ADR-0001](0001-project-thesis.md) — thesis
- [ADR-0002](0002-no-polysemous-symbols.md) — one meaning per button, so a motor path is a sequence of locations
- [ADR-0006](0006-usage-logging.md) — logging against `cell_id`
