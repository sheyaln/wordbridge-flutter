# ADR 0003: Position is identity

**Status:** Accepted
**Date:** August 24, 2026

## Context

"Buttons must not move" sounds like a UI constraint. It is actually a data
modeling constraint, and getting it wrong at the schema level makes it
unfixable in the UI.

The natural way to model a board is a list of buttons rendered in order into a
grid. It is also fatal. With a computed layout, *every* mutation is a potential
relocation: deleting button 12 shifts 13 through 84 up one cell, inserting
shifts them down, reordering shifts everything in between. The reshuffle is
invisible in the code, because no line says "move `eat`", and it is
catastrophic on the device, because a user who had automated `eat` now presses
the wrong word with a movement they no longer have to think about. They will
not notice they have said something else until it has been said.

The failure has to be impossible rather than merely avoided, because it is
silent on both sides: the code does not report it and the user cannot.

## Decision

**Separate position from content, and make position the primary identity.**

A grid location is a permanent, addressable database row that exists whether or
not anything sits on it. Content is a nullable attachment to a location.
Vocabulary growth means attaching content to already existing empty locations,
or revealing content already attached.

### Cells are created in advance

When a board is created, **all `rows × cols` cells are inserted immediately**,
empty, in one transaction. Cell ids are stable forever: never reused, never
deleted.

```
cells: id (uuidv7, permanent), board_id, row, col,
       span_rows, span_cols, state, created_at
       UNIQUE (board_id, row, col)
```

This costs a few hundred rows per vocabulary and buys three things:

1. **Blank positions become first class.** This matches real clinical practice,
   where empty cells are *deliberately reserved* for future vocabulary rather
   than treated as absence. Vocabulary grows *into* reserved blanks. It never
   reshuffles to make room.
2. **Usage can be anchored to a location.** `usage_events.cell_id` references a
   cell, so tap history survives content changes and remapping, which is what
   makes the impact warning in [ADR 0001](0001-project-thesis.md) possible at
   all.
3. **Cell merging is a property of the location**, not of the content. A wide
   "clear" bar is a cell with `span_cols > 1`.

### Three cell states

| State | Meaning |
|---|---|
| `empty_reserved` | Cell exists, holds nothing, deliberately reserved for growth |
| `occupied` + button `hidden = 1` | A word is assigned, not rendered, **and the cell is not available to anything else** |
| `occupied` + button `hidden = 0` | Rendered |

> **Hiding a word must never free its cell.**

This one rule is what makes "grow over time" and "never relocate"
simultaneously true. Independent SLP guidance converges on the same practice:
hide rather than delete, start at the final grid size, add into empty cells
rather than moving an existing word, and reserve blanked out cells at setup to
hold future vocabulary. The schema makes that practice the only thing the
software can do.

Vocabulary levels follow for free. A progression from a first level of roughly
84 words, through a transition level of roughly 200, to a full 2000 or more, is
not a different board set. It is the same materialized grid under a render
filter:

```sql
WHERE vocab_level <= :profile_level AND hidden = 0
```

Unhide a word six months later and it appears exactly where it always was.
Nothing moves.

### Grid geometry belongs to the vocabulary, not the board

Motor planning depends on *absolute physical finger position*. If board A were
6×8 and board B 4×6, the same conceptual slot would land under a different
finger and the plan is destroyed. Geometry therefore lives on `vocabularies`,
and uniform geometry across every board in a vocabulary is an enforced
invariant.

Grid size is chosen **once**, at setup, from vision and motor assessment. Start
at the size the user will eventually need and hide what they are not ready for.
Changing it afterward on a vocabulary with usage history is a destructive
migration that reports every displaced word and requires typed confirmation. It
is never a settings dropdown.

### Buttons attach to cells, nullably

```
buttons: id, cell_id (NULL = unplaced), vocabulary_id,
         label, message, speak_text, action, target_board_id,
         symbol_id, part_of_speech, colors,
         hidden, vocab_level, is_system, ...
         UNIQUE INDEX ON (cell_id) WHERE cell_id IS NOT NULL
```

`cell_id` is nullable for two reasons. It permits an atomic three step swap
under the partial unique index when a remap is genuinely wanted, and it gives
the editor an "unplaced words" tray. *Here are 24 words in this vocabulary with
no home yet, drag them into empty cells* is good caregiver UX and a natural
place for bulk imports to land.

## Consequences

- Rendering reads cells and left joins buttons, never the reverse. A cell with
  no button renders as reserved blank, and the layout is identical either way.
- The renderer computes exact pixel rects from the measured container size and
  absolutely positions cells keyed `row:col`. No flex wrap, because subpixel
  reflow shifts targets between renders. No viewport recycling list widgets,
  because recycling is a correctness hazard when cell identity is the whole
  point. On the order of 84 positioned widgets is trivial for the renderer.
- Deleting a board is a soft delete. Its cells persist so historical usage
  remains resolvable.
- `app/test/motor_plan_invariant_test.dart` is the enforcement mechanism and
  blocks CI.

## Related

- [ADR 0001](0001-project-thesis.md), the thesis
- [ADR 0002](0002-no-polysemous-symbols.md), one meaning per button, so a motor
  path is a sequence of locations
