# Battle

## Purpose

Runs one auto-battle between side A (the player) and side B, tick by tick,
with integer math only, so the same setup gives the same events and state
hash on every device. It does not draw anything, read input, or run the shop,
rounds or economy; presentation listens to its events.

## Layer and files

- Layer: simulation (plain C++17) with a bridge (Godot classes).
- Simulation, no Godot headers, no floating point, in `Native/src/battle/`:
  - `battle_basic_types.h`: board size, sides, cells, damage kinds (shared
    with `Native/src/skill/`).
  - `battle_types.h`: ids, enums, `ClassDef`, `UnitState`, `BattleEvent`.
  - `battle_rules.h/.cpp`: the `Rules` struct, stat derivation, rule checks.
  - `battle_board.h/.cpp`: occupancy, coordinates, distance, path search.
  - `battle_targeting.h/.cpp`, `battle_shapes.h/.cpp`,
    `battle_openings.h/.cpp`: the handler registries.
  - `battle_damage.h/.cpp`: the damage pipeline.
  - `battle_sim.h`, `battle_sim.cpp` (setup, tick loop, end),
    `battle_hash.cpp` (state hash), `battle_sim_actions.cpp` (targeting,
    attacks, moves, skill damage), `battle_attack_modifiers.cpp` and
    `battle_synergy.cpp` (synergy modifiers, volleys, broken formations):
    `BattleSim`.
  - `battle_modifiers.h`: `ActiveModifier`, `SynergySource`.
- Synergies (milestones, formations, Hợp Lực): `Native/src/rules/` and
  `Native/src/formation/`, see [Synergy](synergy.md) and
  [Formation](formation.md).
- Skills, Khí, passives and statuses: `Native/src/skill/`, see [Skill](skill.md).
- Bridge: `class_data`, `unit_data`, `battle_rules_data`, `skill_data`,
  `skill_effect_data`, `passive_data` (resources),
  `battle` (the `Battle` node), `battle_event_dictionary` (events to
  dictionaries), `bridge_strings.h` (string helpers).
- Content: `Systems/Content/catalog.gd` (`Catalog`) and `Data/`.
- Depends on: the synergy rules when `set_synergy()` was called. The caller drives `step()`, usually from `SimClock`;
  on screen that is `BattlePlayback` (see [Battle playback](battle_playback.md)).

## Data

All files are listed in `Data/catalog.tres` (`Catalog`: `classes`, `units`,
`skills`, `passives`, `battle_rules`). Ids are `class.<name>`, `unit.<name>`, `race.<name>`,
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
| `skill`, `passive` | `SkillData`, `PassiveData` or null | see [Skill](skill.md) |

`UnitData` (`Data/Units/<name>.tres`): `id`, `name_key` (`UNIT_<NAME>`),
`class_id`, `race_id` (`race.human`, `race.wolf`), `cost` 1..5, `element_id`
(empty, or `element.fire`/`ice`/`wind`/`lightning` for mages; unused yet),
`skill_override`, `passive_override` (null: the class's).

`BattleRulesData` (`Data/Rules/battle_rules.tres`):

| Field | Default | Meaning |
| --- | --- | --- |
| `ticks_per_second` | 20 | simulation rate, 1..240 |
| `cost_multipliers_pct` | 100, 125, 155, 190, 230 | hp and attack by cost 1..5; each 1..1000 |
| `star_multiplier_pct` | 180 | hp and attack, once per star above 1; 1..300 |
| `counter_bonus_pct` | 30 | extra damage against a countered class; 0..100 |
| `move_ticks_per_cell`, `charge_ticks_per_cell` | 10, 7 | ticks per cell; 1..1000 |
| `time_limit_ticks` | 900 | 45 s; 1..100000 |
| `target_lost_ticks` | 40 | out of range this long drops the target; 0..10000 |
| `repath_ticks` | 20 | ticks without a path before switching target; 1..10000 |
| `hold_line_max_ticks`, `hold_line_grace_ticks` | 200, 20 | hold line limits; 0..10000 |
| `max_units_per_side` | 10 | 1..28 |
| `qi_per_attack`, `qi_per_hit_taken` | 10, 5 | Khí gains; 0..1000 |
| `cast_ticks` | 10 | skill cast length; 1..1000 |
| `star_skill_pct` | 100, 150, 250 | skill coefficient by star 1..3; each 1..400 |
| `crit_multiplier_pct` | 150 | critical hit damage; 100..300 |

`get_attack_charge_full()` is derived, not stored: `100 * ticks_per_second`.

Classes and rules outside these ranges are refused with a `Battle:` error,
and so is an unknown `damage_kind`. Every int setter of the three resources
(`damage_kind` included) and each element of `cost_multipliers_pct` (a
`PackedInt64Array`) saturate 64-bit GDScript ints to the `int` range instead
of wrapping, so huge values stay out of range and are refused too.
The ranges keep scaled stats and tick arithmetic inside `int` and the damage
numerator below `9e17` (int64 holds about `9.2e18`); `compute_damage` also
clamps its inputs.

Stats: `hp = base_hp * cost_mult / 100`, then `* 180 / 100` per star above 1,
truncating at each step; the same for attack. Other stats do not scale.
`add_unit` refuses a unit whose derived max_hp is below 1; an attack of 0 is
allowed.

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
  at full. A stunned unit does nothing more; a unit casting or starting a
  skill casts (see [Skill](skill.md)); a skill charge runs. Then an active
  opening decides the action. Otherwise the unit keeps or
  picks a target; if the target is in range it attacks when the charge is
  full (spending it), else it steps one cell along the path.
- **Targeting.** A taunted unit targets its taunter while both live and
  does not re-pick. Otherwise ties break by: same column as the attacker, lower hp,
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
  cell and the cells left and right of it; `shape.row3_behind` (mage 2) adds
  the cell behind the target. `mod.pierce_behind` (spear 4, archer 4) adds
  the enemy right behind the first unit hit.
- **Damage.** `attack * coefficient / 100`, counter `* 130 / 100`, crit
  `* crit_multiplier_pct / 100` (steady aim), bonus groups `* (100 +
  increase) / 100 * (100 - decrease) / 100` (increase: momentum; decrease:
  guard), mitigation `* 100 / (100 + armor or magic_resist)`, where armor
  is first lowered by armor break for physical damage; all multiplications
  first, one truncation, at least 1. Synergy modifiers join the same
  groups: the attacker's `mod.damage_dealt_pct` (and `mod.skill_damage_pct`
  for skills) add to the increase, the victim's `mod.damage_taken_pct` and,
  against ranged physical attacks, `mod.ranged_physical_taken_pct` add to
  the decrease (capped at 100). Then a synergy block makes it 0
  (`is_blocked_by_modifier`), a fish-scales split shares it, and a sword's
  reflection deals fixed damage back if the victim lives (see
  [Synergy](synergy.md)).
- **Synergies.** With `set_synergy()`, `start()` evaluates both line-ups
  (formations are frozen then) and installs their modifiers; tick 1 emits
  one `synergy_activated` per milestone tier, formation and Hợp Lực, side A
  first, right after `battle_started`. Volleys (Mưa Tên) fire every `ticks`
  after the scheduled skill steps, skipped while the archer is stunned. A
  member's death emits `formation_broken` once and turns its formation's
  modifiers off.
- **Openings.** `opening.hold_line`: no moving, attacks in range; ends at
  `hold_line_max_ticks`, or after `hold_line_grace_ticks` once no enemy
  targets the unit. `opening.charge`: runs forward at
  `charge_ticks_per_cell` until the next cell is taken or off the board; an
  enemy there takes one free basic attack and is pushed one cell further
  (if free and not prevented), taking `charge_ticks_per_cell` ticks. Before
  the impact, enemies with a `charge_impact_incoming` passive (brace) may
  strike first. The tick of the impact is the charge's last action. The
  cavalry skill reuses this runner.
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
| `set_synergy(synergy: Synergy)`, `get_synergy()` | methods | Turns milestones, formations and Hợp Lực on for both sides (null turns them off); refused once units exist |
| `register_class(class_data: ClassData) -> bool` | method | Adds or replaces a class by id. Validates stats and handler ids; false and an error on bad data or when an added unit uses that id (call `clear()` first) |
| `add_unit(side, unit: UnitData, star, local_col, local_rank) -> int` | method | Unit index, or -1 with an error (no rules, bad side, unknown class, bad cell, cell taken, star not 1..3, derived max_hp below 1, side full, started) |
| `clear()` | method | Removes units, resets the tick; keeps classes and rules |
| `start()` | method | Freezes the setup; the first `step()` emits `battle_started` |
| `step() -> Array[Dictionary]` | method | Advances one tick, returns and emits its events; nothing after the end. While its signals run, `step`, `run_to_end`, `start`, `clear`, `add_unit`, `register_class` and `set_rules` are refused with an error |
| `run_to_end(max_ticks: int) -> String` | method | Starts if needed, steps until the end or `max_ticks` (>= 0), returns the hash; empty if a handler freed the node |
| `is_started()`, `is_finished()`, `get_winner()`, `get_tick()` | methods | Winner is -1 while running |
| `get_state_hash() -> String` | method | FNV-1a 64, 16 hex digits, over the tick, `finished`, `winner` and, per unit in index order: alive, hp, col, row, attack charge, move ticks left, target, has seen target in range, target out-of-range ticks, no-path ticks, opening active, Khí, cast (ticks left and cells), charge, passive counters, statuses, max hp, basic attacks made and range bonus; then the synergy sources (active, split used, level) and modifiers (unit, kind, value, uses); then the scheduled Hậu chiêu |
| `get_unit_count()`, `get_unit_state(index)`, `get_units()` | methods | `{index, side, unit_id, class_id, star, alive, hp, max_hp, attack, range_cells, col, row, target, move_ticks_left, qi, qi_max, casting, statuses}`; `range_cells` includes a synergy range bonus |
| `local_to_global(side, local_col, local_rank) -> Vector2i` | static | Global (col, row); (-1, -1) with an error for a bad side or cell |
| `global_to_local(side, col, row) -> Vector2i` | static | (local col, rank); rank leaves 1..4 in the enemy half; (-1, -1) with an error off the board |
| `log_enabled` | property | Prints the info log events below; default false |
| `event_emitted(event: Dictionary)` | signal | Every event, in order |
| `battle_ended(winner: int, reason: StringName)` | signal | Once, at the end |

`Catalog` (Resource script): `get_unit(id)`, `get_class_data(id)`,
`get_skill(id)`, `get_passive(id)`, `get_unit_skill(unit)`,
`get_unit_passive(unit)`, `validate()`.

## Events

Events are read-only dictionaries (`step()`'s array too); copy one to
change it. A handler that removes the battle should use `queue_free()`:
`Battle` stops touching itself when freed mid-step, but Godot's own
`emit_signal` still reads the freed object and warns about it. Every event has `id` (from 1, increasing), `tick`, `type` (StringName) and
`cause` (the id of the event that caused it, 0 if none); that is why the
synergy events name their milestone or formation `source_id`. Units are battle
indexes; cells are global.

| Type | Payload | Cause |
| --- | --- | --- |
| `battle_started` | | 0 |
| `unit_moved` | `unit`, `from_col`, `from_row`, `to_col`, `to_row`, `duration_ticks`, `kind`: `walk`/`charge`/`knockback` | knockback: the attack |
| `unit_attacked` | `unit`, `target`, `kind`: `melee`/`ranged`/`magic`, `to_col`, `to_row` | 0 |
| `damage_dealt` | `source`, `target`, `amount`, `hp_after`, `is_counter`, `is_crit`, `blocked_by` (-1 if none), `skill` (skill or passive id, a formation id for a volley or split share, empty for a basic attack), `is_blocked_by_modifier` | the attack, or the skill's resolve, volley or split |
| `unit_died` | `unit`, `killer` | the damage |
| `charge_ended` | `unit`, `hit` (-1 if none) | the impact attack, or 0 |
| `battle_ended` | `winner` (0 A, 1 B), `reason`: `elimination`/`time_limit` | 0 |
| `synergy_activated` | `side`, `kind`: `class`/`race`/`formation`/`hop_luc`, `source_id` (milestone or formation id, or `hop_luc`), `cells`, `units`, `level` (tier number, formation level or Hợp Lực points), `threshold` (the tier's count, 0 otherwise) | 0 |
| `formation_broken` | `side`, `kind`, `source_id`, `cells`, `units` | the death |
| `modifier_triggered` | `unit`, `modifier` (handler id), `source_id`, `cells` (a split's formation cells) | the attack, hit or tick that set it off |
| `qi_changed`, `skill_cast_started`, `skill_resolved`, `passive_triggered`, `status_applied`, `status_ended` | see [Skill](skill.md) | |

## Log events

Only when `log_enabled` is true:

| Level | Event | Fields |
| --- | --- | --- |
| info | `battle_started` | `units` |
| info | `unit_died` | `unit`, `unit_id`, `killer`, `cause` |
| info | `skill_cast_started` | `unit`, `skill`, `cells` |
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
damage, arrow blocking, charge with knockback and without it (shield,
spear), hold line, switching to an enemy in range, mage row hits, walk,
charge and knockback durations, the time limit (the higher score wins with
fewer units, then both tie rules: more living units, then B), a full 8v8
that ends by elimination (it prints its length), and coordinate round trips.

Skills, Khí, passives and statuses have their own tests
(`Tests/skill_test.gd`, `Tests/passive_test.gd`; see [Skill](skill.md)), and
so do synergies (`Tests/synergy_test.gd`, `Tests/formation_battle_test.gd`;
see [Synergy](synergy.md)).

`Tests/battle_api_test.gd` checks the node's API: signals and event ids,
read-only events, a handler that frees the node mid-step, refused commands
(replacing a class in use, re-entrant `step()`) and rejected input (rules
out of range, a cost multiplier above 32 bits, unknown and 64-bit
`damage_kind`, a derived max_hp of 0, bad side, star or cell, bad index and
coordinates). It prints the errors it provokes and announces each group.

## Known limits

- No elements yet; the damage request has the fields for them.
- No random numbers yet, so there is no seed.
- Data is validated when a class or unit is registered or added, not when
  `Data/` changes; run the battle test after editing data.
