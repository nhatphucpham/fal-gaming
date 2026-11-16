# Tactics

## Purpose

Runs the rules of the turn-based tactics mode: leaders with squads of
soldiers on a terrain grid, alternating side phases, movement with zones of
control, engagements with a counter, keywords, orders, passives, charged
leader skills, zones, an AI that declares its intent, and victory. Integer
math only, so the same commands give the same events and state hash on every
device. It does not draw, read input, or touch the auto-battle (`Battle`);
the [Tactics screen](tactics_screen.md) shows it and sends its commands.

## Layer and files

- Layer: simulation (plain C++17, namespace `tactics`) with a bridge.
- Simulation in `Native/src/tactics/`, no Godot headers:
  - `tactics_types.h` (cells, rules, definitions), `tactics_state.h`
    (unit, zone, buff, intent and event state).
  - `tactics_sim.h/.cpp` (setup, phases, victory), `tactics_sim_commands.cpp`
    (commands, forecast and preview), `tactics_sim_state.cpp` (damage,
    death, relocation, buffs, zones), `tactics_hash.cpp` (state hash):
    `TacticsSim`.
  - `tactics_paths` (Dijkstra, zone of control), `tactics_combat`
    (engagement, hit damage), `tactics_orders` (squad orders),
    `tactics_ai` (intent and AI phase), `tactics_validation` (range checks).
  - Registries: `tactics_keywords`, `tactics_zones`, `tactics_passives`,
    `tactics_skills` (charge mechanisms and targets), `tactics_skill_effects`.
- Bridge: the resources `tactics_terrain_data`, `tactics_rules_data`,
  `tactics_keyword_data`, `tactics_zone_data`, `tactics_passive_data`,
  `tactics_skill_data` (with `TacticsSkillEffectData`), `tactics_unit_data`
  (`TacticsUnitData`, `TacticsTroopData`, `TacticsLeaderData`),
  `tactics_map_data`, `tactics_scenario_data`, `tactics_catalog`; the
  `TacticsBattle` node (`tactics_battle.cpp`, `tactics_battle_queries.cpp`)
  and `tactics_event_dictionary` (events to dictionaries).
- Depends on: `battle::compute_damage` (`Native/src/battle/battle_damage.h`)
  for mitigation, and `ClassData` / `UnitData` for base stats. It does not
  use `ClassData.counters`.

## Data

Everything is listed in `Data/Tactics/tactics_catalog.tres`
(`TacticsCatalog`: `rules`, `terrains`, `keywords`, `zones`, `passives`,
`skills`, `troops`, `leaders`, `maps`, `scenarios`); nothing scans folders.
`TacticsCatalog.validate()` checks id prefixes, duplicates, name keys,
references to unlisted files (terrains, keywords, zones, passives,
skills, troops, leaders, maps), terrain ids named by keywords
(`terrain_ids`) and passives (`condition_terrain_id`), units (squad size against the capacity
with passives; no keyword or passive listed twice), maps (spawn cells on
the map, passable and not shared) and scenarios (each is loaded on a
scratch battle, so a spawn cell that an earlier leader's soldier takes is
reported). Ids:
`terrain.`, `keyword.`, `zone.`, `tactics_passive.`, `tactics_skill.`,
`troop.`, `leader.`, `map.`, `scenario.`. Name keys (`TERRAIN_PLAIN`,
`LEADER_LAC_HONG`, ...) have no Locale rows yet.

`TacticsRulesData` (`Data/Tactics/Rules/tactics_rules.tres`):

| Field | Default | Meaning |
| --- | --- | --- |
| `hits_per_engagement` | 4 | hits by each side per engagement, 1..10 |
| `anticipation_shift_cells` | 1 | forward shift of formation slots after 2 straight moves, 0..20 |
| `help_radius_cells` | 4 | `free` soldiers answer an attack on an allied soldier within this Manhattan distance |
| `max_leaders_per_side` | 5 | 1..8 |
| `max_rounds` | 30 | after this many rounds side B wins (`time_limit`), 1..1000 |

`TacticsTerrainData` (`Data/Tactics/Terrains/`): `move_cost` 1..20,
`is_impassable`, `armor_bonus`, `damage_taken_pct` and
`ranged_damage_taken_pct` (-100..100, signed: negative takes less),
`ranged_range_bonus` 0..12 (cells added to a ranged unit's max range).

| Terrain | Cost | Effect |
| --- | --- | --- |
| `terrain.plain`, `.bridge`, `.village` | 1 | none |
| `terrain.forest` | 2 | ranged damage taken -30% |
| `terrain.hill` | 2 | armor +5, ranged range +1 |
| `terrain.river` | - | impassable |
| `terrain.ford` | 3 | damage taken +25% |
| `terrain.fort` | 1 | armor +20 |

`TacticsUnitData` (troops `Data/Tactics/Troops/`, leaders
`Data/Tactics/Leaders/`): `base_unit` (`UnitData`) and `base_class`
(`ClassData`, must match `base_unit.class_id`); `hp_pct` and `attack_pct`
scale the class's `max_hp` and `attack`; armor, magic resist, damage kind
and `is_ranged` come from the class. `min_range_cells`..`max_range_cells`
(Manhattan, 1..12), `move_points` 0..20, `keywords`.
`TacticsLeaderData` adds `lead_capacity` 0..8, `passives` (1..3 in the
catalog), `skill`, `default_order` (`order.follow`, `order.vanguard`,
`order.flank`, `order.hold`, `order.free`) and `squad` (troops).

`TacticsKeywordData`: `id` is the handler, with `amount`, `min_cells`,
`terrain_ids`.

| Keyword | Effect |
| --- | --- |
| `keyword.long_weapon` | strikes first when attacked in melee |
| `keyword.charge` | +`amount`% (30) when it attacks after a straight run of `min_cells` (3) this phase; not on counters |
| `keyword.armor_pierce` | ignores `amount`% (50) of armor |
| `keyword.cover` | allies orthogonally next to it take `amount`% (30) less ranged damage (the best cover applies) |
| `keyword.flying` | ignores move cost, impassable terrain and zones of control |
| `keyword.heavy` | +`amount` (1) move cost on `terrain_ids` (forest, ford) |

`TacticsZoneData` (`Data/Tactics/Zones/`): `effect` is the handler,
`zone_effect.ranged_ward` (allies of the side that made the zone take
`amount`% less ranged damage inside it) or `zone_effect.burn` (`amount`
damage, 0..100000, not mitigated, to that side's enemies inside at the
start of their phase); each handler states which side it affects. Samples: `zone.wind`
(ward 50), `zone.fire` (burn 60).

`TacticsPassiveData` (`Data/Tactics/Passives/`), `handler` is one of:

| Handler | Fields | Sample |
| --- | --- | --- |
| `passive.stat_bonus` | `stat`, `amount`, `condition_terrain_id`, `condition_adjacent_allies` (both must hold when both are set) | `iron_will` (armor +15 on a fort), `pack_fury` (+20% attack with 2 adjacent allies), `forest_ambush` (+20% attack in a forest) |
| `passive.squad_bonus` | `stat`, `amount`, `keyword`, `extra_capacity` | `drilled_ranks` (soldiers +10% attack, cover, capacity +1) |
| `passive.trail_zone` | `zone`, `radius_cells`, `duration_rounds` | `wind_trail` (wind, radius 1, 1 round, where the leader stops) |
| `passive.pull_strike` | `amount` | `hook_spear` (pulls the target 1 cell after the leader's own attack, not after counters) |
| `passive.skill_growth` | `amount` | `warlord_growth` (skill area +1 per enemy leader killed) |

Stats: `stat.attack_pct`, `stat.armor`, `stat.magic_resist`,
`stat.move_points`, `stat.max_range`. `passive.stat_bonus` needs a `stat`.
A squad passive's stat and keyword reach the soldiers only while their
leader lives.
Ranges: `amount` -1000..1000 (0..1000 for `pull_strike` and
`skill_growth`, which count cells), `condition_adjacent_allies` 0..4,
`extra_capacity` 0..8 (a leader still leads at most 8 soldiers),
`radius_cells` 0..64, `duration_rounds` 0..100.
Keyword `amount` is 0..1000 and `min_cells` 0..20.

`TacticsSkillData` (`Data/Tactics/Skills/`): `charge` (a charge id) and
`charge_threshold` 1..100000, `target`, `cast_range_cells` 0..64,
`area_radius_cells` 0..32, `chain_count` 1..16, `chain_jump_cells` 1..64,
`chain_falloff_pct` 0..100, `effects` (at least one
`TacticsSkillEffectData`: `handler`, `coefficient_pct` 0..1000,
`damage_kind`, `amount_pct` 0..1000, `duration_rounds` 0..100, `zone`).

- Charge: `charge.turns` (+1 at the end of each own phase),
  `charge.engagements` (+1 per engagement of the leader), `charge.focus`
  (+1 per own phase without moving, reset when moved or pushed),
  `charge.damage_taken` (+hp lost), `charge.soldiers_lost` (+1 per soldier
  lost). The value is capped at the threshold and reset by a cast.
- Target: `skill_target.single` (an enemy within cast range),
  `skill_target.area` (a square of radius `area_radius_cells` plus growth,
  centred within cast range), `skill_target.chain` (first enemy within cast
  range, then the nearest unhit enemy within `chain_jump_cells`, each jump
  `chain_falloff_pct` weaker).
- Effect: `skill_effect.damage` (`coefficient_pct` of the caster's attack),
  `skill_effect.squad_attack_buff` (the caster's soldiers +`amount_pct`%
  attack for `duration_rounds`), `skill_effect.create_zone` (`zone` on the
  selected cells for `duration_rounds`).

`TacticsMapData` (`Data/Tactics/Maps/`): `width` x `height` (1..32),
`rows` (one string of symbols per row, row 0 at the top), `legend_symbols`
(each symbol once) with the matching `legend_terrains`, `spawn_cells_a`/`_b`,
`objective_cell` ((-1, -1) for none) held by `objective_side` to win,
`facing_a`/`_b` (initial heading). `TacticsScenarioData`
(`Data/Tactics/Scenarios/`): `rules`, `map`, `leaders_a`, `leaders_b`
placed on the spawn cells in order. Sample: `scenario.river_crossing`.

## Rules

- Cells are (col, row); distances are Manhattan, except the area square.
- A round is side A's phase then side B's. In its phase each leader of the
  active side may move once and then act once (attack, skill or wait);
  acting ends its turn. `end_phase()` passes the turn.
- Movement: Dijkstra over move costs; enemies block; allies can be
  passed but not stopped on; a cell next to an enemy (zone of control)
  ends movement unless the unit starts there.
- Engagement: attacker and defender trade `hits_per_engagement` hits
  each, attacker first (defender first with `long_weapon` against melee);
  the defender only counters if the attacker is in its range. Per-hit
  damage is fixed at the start. `forecast_engagement()` runs the same code
  on a copy. Damage goes through `battle::compute_damage`, which caps the
  summed increases (keywords, terrain, zones) at +200% and the decreases
  at -100%, and every hit deals at least 1.
- Squads start on the `order.follow` slots whatever the leader's order
  (each soldier on the free cell nearest its slot; with none free it is
  left out, dead, at (-1, -1)), then follow their order: formation slots are relative to the leader's
  heading; after two straight moves the slots shift forward by
  `anticipation_shift_cells`. Soldiers step after their leader moves (or
  acts, or at the end of the phase), then attack: first an enemy that
  threatens their leader, then the lowest hp. `order.hold` stays put;
  `order.free` goes for the living enemy that attacked the nearest other
  allied soldier within `help_radius_cells` since that soldier's last
  squad step, else for the nearest enemy by path.
  A squad whose leader died acts as `free`. `preview_squad()` shows where
  soldiers would go if the leader moved to a cell.
- Buffs and zones made in round r for d rounds end at the start of their
  side's phase in round r + d (`end_round`), so both sides get the same
  length: a 1-round zone made by side B still works in side A's next phase.
  d = 0 ends at the start of the next phase.
- AI: each leader goes for the nearest enemy by path and moves to the
  reachable cell closest to a cell it could attack it from. Then, when its
  skill is ready: a skill for its own side (no effect works against
  enemies, such as `rally_banner`) is cast on the leader's own cell when
  the target handler accepts that cell; any other skill is cast on the
  enemy when it is in cast range. A skill counts as ready only if it is
  still ready after that move: when moving would lose the charge
  (`charge.focus`) and the skill can be cast from where the leader stands,
  it stays and casts it there. Otherwise it attacks that enemy, else
  the enemy in range with the lowest hp, else waits. When the other side
  is human, the AI's intents are declared at the start of the human phase
  (`get_enemy_intents()`) and followed as closely as the board allows; a
  declared skill that is no longer possible becomes an attack or a wait.
- Victory: all enemy leaders dead (`rout`); a leader of `objective_side`
  ending its own move (`move_leader`, or the AI's move) on the objective
  (`objective`); side B after `max_rounds` (`time_limit`). Being pulled or
  otherwise moved onto the objective does not win, and neither does
  starting the battle or a phase on it: such a leader must move off and
  back on. `battle_ended` is the last event: an engagement or skill that
  ends the battle stops at the death (no `engagement_ended`,
  `skill_resolved`, later effect or charge change follows), and nothing
  changes afterwards.

## Public API

`TacticsBattle` (Node). Commands return the events they caused as an Array
of read-only Dictionaries; a refused command returns `[]` and logs an
error.

| Member | Kind | Description |
| --- | --- | --- |
| `setup(rules, map) -> bool` | method | Starts a new battle setup; false when the data is invalid (then nothing stays set up) or the battle already started |
| `load_scenario(scenario) -> bool` | method | `setup` plus the scenario's leaders on the spawn cells; on failure nothing stays set up |
| `load_scenario_with_squads(scenario, side, squads) -> bool` | method | The same, but `squads` (one Array of `TacticsTroopData` per leader of `side`, in order) replaces that side's squads; refused (nothing set up) when the count differs or a squad is over its leader's capacity. The muster screen uses it |
| `set_side_ai(side, is_ai)`, `is_side_ai(side)` | method | AI phases run on their own after the human's `end_phase()` |
| `add_leader(side, leader, cell) -> int` | method | Adds the leader and its `squad`; returns the unit index or -1 |
| `add_leader_with_squad(side, leader, cell, squad) -> int` | method | Same with another squad (up to capacity) |
| `start() -> Array` | method | Starts round 1, side A |
| `move_leader(unit, cell)`, `attack(unit, target)`, `use_skill(unit, cell)`, `wait(unit)`, `set_order(unit, order)`, `end_phase()` | method | Commands for the active side; return events |
| `is_started`, `is_finished`, `get_winner`, `get_end_reason`, `get_round`, `get_turn`, `get_active_side` | method | Battle state |
| `get_unit_count`, `get_unit_state(unit)`, `get_units()`, `get_zones()` | method | Unit and zone dictionaries |
| `get_map_width`, `get_map_height`, `get_terrain_id(cell)` | method | Map |
| `get_reachable_cells(unit)`, `get_path_to(unit, cell)` | method | Cells the unit can end a move on from where it stands (without its own), and the path to one, both ends included (`[cell]` for its own cell); empty for a dead unit or a cell it cannot stop on. They do not check whose phase it is or whether the leader already moved or acted, which `move_leader()` also needs |
| `get_formation_slots(leader)` | method | The slot cells of the leader's order (empty for `hold`, `free` or a dead leader) |
| `preview_squad(leader, cell)` | method | `[{unit, cell}]`: where the soldiers would stand after the leader moved there; `[]` and an error when that move would be refused |
| `forecast_engagement(attacker, defender) -> Dictionary` | method | Hits, damage per hit and hp after, without changing state; any two units (an enemy's attack too, whoever's phase it is); `is_valid` false when either is dead, they are on the same side, the defender is out of range or the battle ended. `attacker_modifiers` and `defender_modifiers` (the counter; empty without one) list the ids that change that side's hits, each once: the first-strike keyword, keywords, terrain and zones of the hit, then passives, buffs and terrain behind attack and armor |
| `get_skill_charge(leader)` | method | `{skill, charge, value, threshold, is_ready, area_bonus}` |
| `can_move(unit)`, `can_act(unit)` | method | The leader may still move (neither moved nor acted) or act in this phase: alive, on the active side, battle running; false for soldiers |
| `get_attack_targets(unit)` | method | Unit indexes `attack(unit, target)` would accept now |
| `get_skill_cells(unit)` | method | Cells `use_skill(unit, cell)` would accept now (row-major; empty when the skill is not ready or the leader is done) |
| `preview_skill(unit, cell) -> Dictionary` | method | `use_skill` run on a copy: `is_valid` (false, without an error, when it would be refused), `cells`, `targets`, `results` (`[{unit, amount, hp_after, is_dead}]`, the skill's hits summed per target), `buffed` (units), `zone_cells` |
| `get_enemy_intents()` | method | `[{unit, to, action, target, target_cell}]` (`action` `wait`, `attack` or `skill`); `target` is the enemy aimed at (-1 and `target_cell` (-1, -1) when none), or the leader itself for a skill cast on its own cell; a leader that died loses its intent |
| `get_state_hash() -> String` | method | FNV-1a 64 of the whole state (rules, map terrain, round, turn, units, zones, buffs, intents, the next event id), 16 hex digits; units, terrains and zones are identified by ids |
| `set_log_enabled(enabled)` | method | Prints the log events below |
| `event_emitted(event)` | signal | Each event, in order |
| `battle_ended(winner, reason)` | signal | Once; `reason` is `rout`, `objective` or `time_limit` |

Every event has `id`, `turn`, `round`, `type` and `cause` (the id of the
event that caused it, 0 if none; ids start at 1). A command's own first
event has cause 0; what follows from it points back: a squad's step to the
leader's `unit_moved`, `engagement_started`, `skill_used` or
`leader_waited`, a trail zone to the move, a pull to the engagement.
Expiries, burns and intents at the start of a phase point to its
`phase_started`; a squad that steps at the end of the phase (its leader
neither moved nor acted) and the charge gained then have cause 0. Types: `battle_started`, `phase_started`,
`phase_ended`, `unit_moved` (`kind` `move`, `squad`, `pull`),
`order_changed`, `leader_waited`, `intent_declared`, `engagement_started`,
`damage_dealt`, `engagement_ended`, `unit_died`, `skill_used`,
`skill_resolved`, `skill_charge_changed`, `skill_grew`, `buff_applied`,
`buff_ended`, `zone_created`, `zone_expired`, `passive_triggered`,
`battle_ended`.

| Type | Payload |
| --- | --- |
| `battle_started` | `units` (count) |
| `phase_started`, `phase_ended` | `side` |
| `unit_moved` | `unit`, `from`, `to`, `path` (both ends included), `kind` |
| `order_changed` | `unit`, `order` |
| `leader_waited` | `unit` |
| `intent_declared` | `unit`, `to`, `action`, `target`, `target_cell` (as `get_enemy_intents()`) |
| `engagement_started` | `unit` (attacker), `target`, `kind` (`melee`, `ranged`), `is_first_strike` |
| `damage_dealt` | `source`, `target`, `amount` (the hit, before hp runs out), `hp_after`, `is_counter`, `source_id` (skill or zone id, empty for a basic hit) |
| `engagement_ended` | `unit`, `target`, `amount` (attacker's hits x damage), `counter_amount` |
| `unit_died` | `unit`, `killer`, `cell` |
| `skill_used` | `unit`, `skill`, `cell`, `cells`, `targets` |
| `skill_resolved` | `unit`, `skill`, `results` (`[{unit, amount, hp_after, is_dead}]`, damage only) |
| `skill_charge_changed` | `unit`, `charge`, `value`, `threshold` |
| `skill_grew` | `unit`, `skill`, `area_bonus` |
| `buff_applied` | `unit`, `stat`, `amount`, `end_round`, `source_id` |
| `buff_ended` | `unit`, `source_id` |
| `zone_created` | `unit` (source), `side`, `zone`, `cells`, `end_round` |
| `zone_expired` | `unit` (source), `zone`, `cells` |
| `passive_triggered` | `unit`, `passive` |
| `battle_ended` | `winner`, `reason` |

## Log events

Format `[info][Tactics][t=<turn>] <event> key=value`, when logging is on.

| Level | Event | Fields |
| --- | --- | --- |
| info | `battle_started` | `units` |
| info | `phase_started` | `side`, `round` |
| info | `unit_died` | `unit`, `unit_id`, `killer`, `cause` |
| info | `skill_used` | `unit`, `skill`, `targets` |
| info | `battle_ended` | `winner`, `reason` |

## How to extend

- New terrain, troop, leader, map or scenario: add a `.tres` under
  `Data/Tactics/` and list it in `tactics_catalog.tres`.
- New keyword, zone effect, passive kind, charge mechanism, skill target or
  skill effect: write the handler and add it to the registry array in
  `tactics_keywords.cpp`, `tactics_zones.cpp`, `tactics_passives.cpp`,
  `tactics_skills.cpp` or `tactics_skill_effects.cpp`; mark `needs_zone`
  when it reads a zone (and, for a passive, `needs_stat` when it reads
  `stat`) so validation checks it; a zone handler also says whether it
  affects the allies or the enemies of the side that made the zone, and a
  skill effect handler whether it works against enemies
  (`affects_enemies`; the AI casts a skill without such an effect on its
  own cell). A target handler's `select` gets the cell the caster casts
  from, so the AI can test a cast before it moves. Then add data that
  uses it.

## Tests

`Tests/tactics_test.gd` (catalog checks, scenario loading and failed
loads and setups, movement, paths and zones of control, engagement and forecast,
keywords, terrain, AI intent, victory, defeat and time limit, objective
only by the leader's own move, `battle_ended` as the last event, a replay
that must give the same state hash, what the hash covers (rules and
terrain too), one move and one action per leader and phase, data range
checks, side bounds, map legends, dead units in queries and intents) and
`Tests/tactics_squad_test.gd` (orders, anticipation, slots of a dead
leader, the five charge mechanisms, skills and zones, the AI casting a
skill on an enemy and on its own side and a focus skill without moving,
the five passive kinds, the side a zone affects, side B durations and
event causes) and `Tests/tactics_fuzz_test.gd` (random maps, leaders
and commands, legal and not, on 24 seeds: queries and refused commands
leave the hash unchanged, a command is accepted exactly when its query
said so (`can_move`, `can_act`, `get_attack_targets`, `get_skill_cells`),
moves follow `get_path_to()` and `preview_squad()`, attacks land the
forecast, skills what `preview_skill()` said, the events account for every cell, hp, charge and zone
change, one unit per cell, `battle_ended` last, and a replay gives the
same hashes) and `Tests/tactics_query_test.gd` (a scenario loaded with
other squads and refused ones, `can_move` / `can_act`, attack targets, skill
cells, `preview_skill()` against the real cast for damage and support, the
forecast's modifier lists), sharing `Tests/tactics_test_kit.gd`. Run:
`godot --headless --path . --script res://Tests/tactics_test.gd` (and the
squad, fuzz and query tests). All four are in CI.

## Known limits

- The AI is greedy (nearest enemy, one leader at a time), does not use
  orders, does not go for the objective, and casts a skill for its own
  side as soon as it is ready, even with no soldier left to help.
- Damage has no randomness; ties are broken by unit index and cell order.
