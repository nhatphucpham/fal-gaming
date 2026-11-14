# Battle

## Purpose

Runs one auto-battle between side A (the player) and side B, tick by tick,
with integer math only, so the same setup gives the same events and state
hash on every device. It does not draw anything, read input, or run the shop,
rounds or economy; presentation listens to its events.

## Layer and files

- Layer: simulation (plain C++17) with a bridge (Godot classes).
- Simulation, no Godot headers, no floating point, in `Native/src/battle/`:
  - `battle_types.h`: ids, enums, cells, `ClassDef`, `UnitState`, `BattleEvent`.
  - `battle_rules.h/.cpp`: the `Rules` struct, stat derivation, rule checks.
  - `battle_board.h/.cpp`: occupancy, coordinates, distance, path search.
  - `battle_targeting.h/.cpp`, `battle_shapes.h/.cpp`,
    `battle_openings.h/.cpp`: the handler registries.
  - `battle_damage.h/.cpp`: the damage pipeline.
  - `battle_sim.h`, `battle_sim.cpp` (setup, tick loop, end, hash) and
    `battle_sim_actions.cpp` (targeting, attacks, moves): `BattleSim`.
- Bridge: `class_data`, `unit_data`, `battle_rules_data` (resources),
  `battle` (the `Battle` node), `battle_event_dictionary` (events to
  dictionaries), `bridge_strings.h` (string helpers).
- Content: `Systems/Content/catalog.gd` (`Catalog`) and `Data/`.
- Depends on: nothing. The caller drives `step()`, usually from `SimClock`.

## Data

All files are listed in `Data/catalog.tres` (`Catalog`: `classes`, `units`,
`battle_rules`). Ids are `class.<name>`, `unit.<name>`, `race.<name>`,
`element.<name>`. `Catalog.validate()` reports empty entries, malformed and
duplicate ids, unknown `class_id`s and costs outside 1..5; handler ids are
checked by `Battle.register_class()`.

`ClassData` (`Data/Classes/<name>.tres`), base stats of a cost-1, one-star unit:

| Field | Unit / range | Notes |
| --- | --- | --- |
| `id`, `name_key` | `class.<name>`, translation key | e.g. `CLASS_SHIELD` |
| `max_hp`, `attack` | 1..100000, 0..10000 | scaled by cost and star |
| `attacks_per_100s` | attacks per 100 s, 1..10000 | 60 is 0.6 attacks/s |
| `range_cells` | cells, 1..8 | Chebyshev distance |
| `armor`, `magic_resist` | 0..10000 | mitigation `100 / (100 + value)` |
| `damage_kind` | `DAMAGE_PHYSICAL` (0), `DAMAGE_MAGIC` (1) | picks armor or magic resist |
| `targeting` | handler id | `target.nearest`, `target.column_first`, `target.densest_row3` |
| `opening` | handler id or empty | `opening.hold_line`, `opening.charge` |
| `attack_shape` | handler id | `shape.single`, `shape.row3` |
| `counters` | `Array[StringName]` of class ids | +`counter_bonus_pct` damage against them |
| `is_ranged` | bool | ranged single-target attacks can be blocked |
| `blocks_arrows` | bool | takes ranged shots aimed past it |
| `immune_to_knockback`, `stops_charge` | bool | either one prevents knockback |

`UnitData` (`Data/Units/<name>.tres`): `id`, `name_key` (`UNIT_<NAME>`),
`class_id`, `race_id` (`race.human`, `race.wolf`), `cost` 1..5, `element_id`
(empty, or `element.fire`/`ice`/`wind`/`lightning` for mages; unused yet).

`BattleRulesData` (`Data/Rules/battle_rules.tres`):

| Field | Default | Meaning |
| --- | --- | --- |
| `ticks_per_second` | 20 | simulation rate, 1..240 |
| `cost_multipliers_pct` | 100, 125, 155, 190, 230 | hp and attack by cost 1..5; each 1..1000 |
| `star_multiplier_pct` | 180 | hp and attack, once per star above 1; 1..300 |
| `counter_bonus_pct` | 30 | extra damage against a countered class; 0..100 |
| `move_ticks_per_cell`, `charge_ticks_per_cell` | 10, 7 | ticks per cell |
| `time_limit_ticks` | 900 | 45 s |
| `target_lost_ticks` | 40 | out of range this long drops the target |
| `repath_ticks` | 20 | ticks without a path before switching target |
| `hold_line_max_ticks`, `hold_line_grace_ticks` | 200, 20 | hold line limits |
| `max_units_per_side` | 10 | |

`get_attack_charge_full()` is derived, not stored: `100 * ticks_per_second`.

Classes and rules outside these ranges are refused with a `Battle:` error.
The ranges keep scaled stats inside `int` and the damage numerator below
`9e17` (int64 holds about `9.2e18`); `compute_damage` also clamps its inputs.

Stats: `hp = base_hp * cost_mult / 100`, then `* 180 / 100` per star above 1,
truncating at each step; the same for attack. Other stats do not scale.

## Rules

- **Board.** 7 columns x 8 rows; side A owns rows 0..3, B rows 4..7. Local
  coordinates are (col 1..7, rank 1..4), rank 1 being the front rank. A:
  `row = 4 - rank`, `col = local_col - 1`. B: `row = 3 + rank`,
  `col = 7 - local_col`. Forward is +row for A, -row for B.
- **Order.** Each tick, side A acts first on even ticks and B on odd ticks.
  Within a side: the unit nearest the enemy first, then by distance from
  column 3, then the unit's own left first (A: lower col, B: higher col).
  The order is computed at the start of the tick.
- **Action.** A dead unit skips. A move started on tick `t` with duration
  `d` lasts until tick `t + d`, when the unit can act again, whatever the
  action order: a walk takes exactly `move_ticks_per_cell` ticks per cell, a
  charge `charge_ticks_per_cell`, a knockback its event's `duration_ticks`.
  The unit occupies its destination from the start. The attack charge gains `attacks_per_100s`, capped
  at full. An active opening decides the action. Otherwise the unit keeps or
  picks a target; if the target is in range it attacks when the charge is
  full (spending it), else it steps one cell along the path.
- **Targeting.** Ties break by: same column as the attacker, lower hp,
  nearer column 3, further to the attacker's left, lower index. A target is
  kept until it dies or has been out of range for more than
  `target_lost_ticks` ticks after having been in range once. For every
  class, whenever the target is out of range and some enemy is in range, the
  unit picks again with its handler among the enemies in range only (a
  holding shield then fights the sword next to it, not a far archer).
  `target.densest_row3` also picks again among enemies in range before each
  attack.
- **Movement.** Breadth-first search over free cells to the nearest cell in
  range; steps in order forward, sideways toward the target's column (own
  left when in the same column), other sideways, backward. With no path for
  `repath_ticks` ticks the unit switches to the nearest reachable enemy.
- **Shapes.** `shape.single` hits the target; when a ranged attacker shoots
  along its column, the first enemy with `blocks_arrows` strictly between
  takes the hit (`blocked_by`). `shape.row3` hits every enemy in the target's
  cell and the cells left and right of it.
- **Damage.** `attack * coefficient / 100`, counter `* 130 / 100`, crit
  `* 150 / 100` (never yet), bonus groups `* (100 + increase) / 100 *
  (100 - decrease) / 100` (zero yet), mitigation `* 100 / (100 + armor or
  magic_resist)`; all multiplications first, one truncation, at least 1.
- **Openings.** `opening.hold_line`: no moving, attacks in range; ends at
  `hold_line_max_ticks`, or after `hold_line_grace_ticks` once no enemy
  targets the unit. `opening.charge`: runs forward at
  `charge_ticks_per_cell` until the next cell is taken or off the board; an
  enemy there takes one free basic attack and is pushed one cell further
  (if free and not prevented), taking `charge_ticks_per_cell` ticks. The
  tick of the impact is the charge's last action.
- **End.** A side with no living unit at the end of a tick loses (both: B
  wins). At `time_limit_ticks` the higher sum of `hp * 10000 / max_hp` wins,
  then more living units, then B.

## Public API

`Battle` (Node). It does not tick by itself: connect `SimClock.ticked` to a
function that calls `step()`, or call `step()` in a loop.

| Member | Kind | Description |
| --- | --- | --- |
| `SIDE_A`, `SIDE_B` | constants | 0 and 1 |
| `set_rules(rules: BattleRulesData)` | method | Required before `add_unit`; refused once units exist |
| `register_class(class_data: ClassData) -> bool` | method | Adds or replaces a class by id. Validates stats and handler ids; false and an error on bad data or when an added unit uses that id (call `clear()` first) |
| `add_unit(side, unit: UnitData, star, local_col, local_rank) -> int` | method | Unit index, or -1 with an error (no rules, unknown class, bad cell, cell taken, star not 1..3, side full, started) |
| `clear()` | method | Removes units, resets the tick; keeps classes and rules |
| `start()` | method | Freezes the setup; the first `step()` emits `battle_started` |
| `step() -> Array[Dictionary]` | method | Advances one tick, returns and emits its events; nothing after the end. While its signals run, `step`, `run_to_end`, `start`, `clear`, `add_unit`, `register_class` and `set_rules` are refused with an error |
| `run_to_end(max_ticks: int) -> String` | method | Starts if needed, steps until the end or `max_ticks`, returns the hash |
| `is_started()`, `is_finished()`, `get_winner()`, `get_tick()` | methods | Winner is -1 while running |
| `get_state_hash() -> String` | method | FNV-1a 64 of tick and unit state, 16 hex digits |
| `get_unit_count()`, `get_unit_state(index)`, `get_units()` | methods | `{index, side, unit_id, class_id, star, alive, hp, max_hp, attack, col, row, target, move_ticks_left}` |
| `local_to_global(side, local_col, local_rank) -> Vector2i` | static | Global (col, row) |
| `global_to_local(side, col, row) -> Vector2i` | static | (local col, rank); rank leaves 1..4 in the enemy half |
| `log_enabled` | property | Prints the info log events below; default false |
| `event_emitted(event: Dictionary)` | signal | Every event, in order |
| `battle_ended(winner: int, reason: StringName)` | signal | Once, at the end |

`Catalog` (Resource script): `get_unit(id)`, `get_class_data(id)`, `validate()`.

## Events

Every event has `id` (from 1, increasing), `tick`, `type` (StringName) and
`cause` (the id of the event that caused it, 0 if none). Units are battle
indexes; cells are global.

| Type | Payload | Cause |
| --- | --- | --- |
| `battle_started` | | 0 |
| `unit_moved` | `unit`, `from_col`, `from_row`, `to_col`, `to_row`, `duration_ticks`, `kind`: `walk`/`charge`/`knockback` | knockback: the attack |
| `unit_attacked` | `unit`, `target`, `kind`: `melee`/`ranged`/`magic`, `to_col`, `to_row` | 0 |
| `damage_dealt` | `source`, `target`, `amount`, `hp_after`, `is_counter`, `is_crit`, `blocked_by` (-1 if none) | the attack |
| `unit_died` | `unit`, `killer` | the damage |
| `charge_ended` | `unit`, `hit` (-1 if none) | the impact attack, or 0 |
| `battle_ended` | `winner` (0 A, 1 B), `reason`: `elimination`/`time_limit` | 0 |

## Log events

Only when `log_enabled` is true:

| Level | Event | Fields |
| --- | --- | --- |
| info | `battle_started` | `units` |
| info | `unit_died` | `unit`, `unit_id`, `killer`, `cause` |
| info | `battle_ended` | `winner`, `reason` |

Example: `[info][Battle][t=412] unit_died unit=3 unit_id=unit.archer killer=7 cause=e41`.

## How to extend

- **Add a unit or class:** add a `.tres` under `Data/Units/` or
  `Data/Classes/` and list it in `Data/catalog.tres`. No code changes.
- **Add a targeting, shape or opening handler:** write the function in
  `battle_targeting.cpp`, `battle_shapes.cpp` or `battle_openings.cpp` and
  add it to that file's handler table; then use its id in a `ClassData`.
- **Tune:** edit `Data/Rules/battle_rules.tres`.

## Tests

`Tests/battle_test.gd` (run as in the README, also in CI) loads the catalog
and checks: validation and counts, stat derivation, determinism of a 5v5
(same hash twice, a different hash when one unit moves), sword and counter
damage, arrow blocking, charge with and without knockback, hold line,
switching to an enemy in range, mage row hits, walk, charge and knockback
durations, the time limit with both tie rules (more living units, then B),
a full 8v8 that ends by elimination (it prints its length), signals and
event ids, coordinate round trips, and refused commands (replacing a class
in use, re-entrant `step()`; these print two expected errors).

## Known limits

- No skills, mana, formations, synergies, elements or crits yet; the damage
  request has the fields for them.
- No random numbers yet, so there is no seed.
- Data is validated when a class or unit is registered or added, not when
  `Data/` changes; run the battle test after editing data.
