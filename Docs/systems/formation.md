# Formation

## Purpose

Finds Trận đồ (formations) in one side's line-up: geometric shapes of units
on the 7 x 4 half board, matched in local coordinates. It reports each
active formation with its members, cells and level, and the formations one
unit short (near-misses) for the preparation screen. What a formation does
in a battle is a list of modifiers, applied by [Synergy](synergy.md) and the
battle; this system only matches shapes.

## Layer and files

- Layer: simulation (plain C++17, no Godot headers, no floats) with the
  `Synergy` bridge class and GDScript presentation.
- Simulation, `Native/src/formation/` (namespace `formation`):
  - `formation_types.h`: `Piece` (local col 1..7, rank 1..4, class index,
    race index, unit id, cost), `Slot`, `PatternDef`, `MissingRule`,
    `MatchOptions`, `Match`, `NearMiss`.
  - `formation_patterns.h/.cpp`: the pattern handler registry
    (`pattern.shape`) and board bounds.
  - `formation_match.h/.cpp`: `match_formations()`.
- Bridge: `Native/src/synergy/formation_data.h/.cpp` (`FormationData`) and
  `synergy.h/.cpp` (`Synergy.evaluate()`, shared with milestones).
- Presentation: `Scenes/Board/formation_outlines.gd` (`FormationOutlines`,
  the outlines on the board) and `outline_geometry.gd` (`OutlineGeometry`,
  loops around cells), driven by `Scenes/Run/synergy_hud.gd`.
- Depends on: nothing. [Synergy](synergy.md) calls it; the battle calls it
  through Synergy at `start()`.

## Data

`FormationData` resources in `Data/Formations/`, listed in
`Data/catalog.tres` (`formations`).

| Field | Unit / range | Notes |
| --- | --- | --- |
| `id`, `name_key`, `description_key` | `formation.<name>`, translation keys | e.g. `FORMATION_SHIELD_WALL`, `FORMATION_SHIELD_WALL_DESC` |
| `pattern` | handler id | `pattern.shape` (the only one so far) |
| `cells` | `Array[Vector2i]` of (dcol, drank) offsets, 1..6 slots | slot 0 is the anchor at (0, 0); drank grows toward the back |
| `slot_classes` | one class id per slot, or empty | empty matches any unit |
| `anchor_col`, `anchor_rank` | 0 (anywhere) or 1..7, 1..4 | pins slot 0 to a column or rank |
| `is_mirrored` | bool | also tries the shape mirrored left to right |
| `needs_distinct_classes` | bool | all members of different classes (Tam Tài) |
| `middle_slot` | -1..5 | the slot a wolf-folk must stand in for the 3-unit missing rule; -1 none |
| `color` | Color | outline and chip colour |
| `modifiers` | `Array[ModifierData]` | effects; see [Synergy](synergy.md) for handlers and scopes |

The twelve formations of GDD section 12:

| Formation | Shape (local) | Level-1 effect |
| --- | --- | --- |
| Tường Khiên `formation.shield_wall` | 3 shields side by side in a rank | allies right behind a member take 40% less ranged physical damage |
| Mưa Tên `formation.arrow_rain` | 3 archers side by side in rank 4 | every 80 ticks (4 s) the centre archer volleys 100% on the densest row of 3 |
| Hộ Pháp `formation.spell_guard` | a shield right in front of a mage | the mage deals +25% |
| Mũi Giáo `formation.spearhead` | cavalry in rank 1, spears at (c-1, 2) and (c+1, 2) | opening charge impact +50%, knockback +1 cell, the spears walk at charge speed until their first attack |
| Song Kiếm `formation.twin_blades` | 2 swords side by side | every third basic attack of each deals +100% |
| Thương Che Cung `formation.spear_cover` | a spear right in front of an archer | enemy charges into either stop with no impact damage and no knockback |
| Nhạn Hành `formation.wild_geese` | 5 units in a V pointing at the enemy | the wing tips attack 30% faster |
| Trường Xà `formation.long_serpent` | 5 units side by side in a rank | those five attack 15% faster |
| Phương Trận `formation.square` | 4 units in a 2 x 2 block | those four take 15% less damage |
| Hạc Dực `formation.crane_wings` | cavalry at (1, 1) and (7, 1) | opening charge impact +40% |
| Ngư Lân `formation.fish_scales` | a diagonal from rank 1, (c, 1), (c+1, 2), (c+2, 3), or mirrored | the first damaging hit on a member is split evenly among the living members, once per battle |
| Tam Tài `formation.three_powers` | 3 units of 3 classes in a column, ranks r..r+2 | all three start with +10 Khí |

## Rules

- **Placements.** `pattern.shape` lists the anchor cells in a fixed order:
  rank 1..4, col 1..7, the plain shape before the mirrored one. A placement
  whose cells leave the board is skipped.
- **Matching.** For each formation in catalog order, three passes:
  complete matches; then matches with one member missing that a rule allows
  (wolf-folk 1: a 3-slot formation with a wolf-folk in its `middle_slot`;
  wolf-folk 5: a 4-slot formation, any one slot); then near-misses. A piece
  is used once per formation id: one id can match several times on disjoint
  pieces, and a unit can belong to several different formations.
- **Missing member.** A missing slot may be empty or hold a unit that does
  not fit it; with wolf-folk 1 it may not be the middle slot.
- **Near-misses.** A placement with exactly one slot unfilled, at least two
  members present, the missing cell empty, and members not already used by
  an active instance of the same formation. `needed_class` names the class
  the missing slot needs (empty for any unit; Tam Tài, whose slots take any
  class but must differ, reports none). One near-miss per formation and
  missing cell.
- **Level.** 1, plus human milestones (+1 when a member is human, +2 with
  human 5 and two humans), at most `max_formation_level` (4). Each level
  above 1 scales every modifier value: `value * (100 + 40 * (level - 1)) /
  100`, integers.
- **In battle.** Formations are matched once, at `start()`, on both sides.
  A formation stays active while its members move; the first death of a
  member turns it off (`formation_broken`).

## Public API

Through `Synergy.evaluate(pieces)` (see [Synergy](synergy.md)); the
formation part of its result:

| Key | Entry fields |
| --- | --- |
| `formations` | `id`, `level`, `cells` (members' local cells), `slot_cells` (all slots, including a missing one), `pieces` (indexes into the input), `missing_cell` ((-1, -1) when complete) |
| `near_formations` | `id`, `cells`, `pieces`, `missing_cell`, `needed_class` |

`FormationOutlines` (Node2D, under the board's pieces via
`BoardView.get_outline_layer()`):

| Member | Kind | Description |
| --- | --- | --- |
| `setup(catalog)` | method | Names and colours come from the catalog |
| `show_side(side, result, animate)` | method | Outlines a side's result; with `animate`, a formation that was not active before runs a light along its outline and stamps its name |
| `show_preview(result)`, `end_preview()`, `is_previewing()` | methods | The player's outlines as a drag would leave them, and back |
| `roll_call()` | method | Battle start: all outlines flash, names stamp one after another within 0.8 s |
| `shatter(side, id)` | method | Breaks and fades a formation's outline |
| `is_battle` | property | Hides near-misses and fades outlines while units walk away |
| `get_formation_ids(side)`, `get_near_ids()` | methods | What is drawn, for tests |

Active outlines are a glowing line in the formation's colour around the
members' cells; the enemy's are tinted red and dimmer; a near-miss is a
dashed line over the members and the missing cell, with a ghost "+" marker
in the needed class's colour on the missing cell.

## Log events

None; the battle logs its own events.

## How to extend

- **Add a formation:** add a `FormationData` `.tres` under
  `Data/Formations/` (cells, slot classes, anchors, middle slot, colour,
  modifiers), list it in `Data/catalog.tres`, and add its name and
  description to `Locale/strings.csv`. No code changes.
- **Add a pattern kind** (something `pattern.shape` cannot express): write
  a placement function in `formation_patterns.cpp` and add it to the
  registry table; use its id in `pattern`.

## Tests

`Tests/formation_test.gd`: every formation positive and negative, mirrored,
at the board edges, overlapping and repeated instances, Tam Tài's distinct
classes, wolf-folk 1 and 5 missing members, human levels and the level
cap, near-misses (two members, free cell, needed class). `Tests/
formation_battle_test.gd`: each formation's effect with exact numbers in a
tiny battle, a formation broken by a death, determinism, and that
`Synergy.evaluate()` equals what the battle applies.
`Tests/synergy_ui_test.gd` checks the outlines on the run screen.

## Known limits

- Formations are frozen at battle start; moving units never form new ones.
- No overlapping-formation bonus, hidden formations or level sources other
  than race (out of scope for milestone 5).
- During a battle the outlines stay on the starting cells (faded); they do
  not follow the units.
