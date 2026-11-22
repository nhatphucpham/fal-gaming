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
  - `tactics_bonds.h/.cpp`: bonds (Duyên) between leaders of one side: the
    rules, the attack bonus while close and the phase tallies (see
    [Tactics world](tactics_world.md)); `tactics_battle_bonds.cpp` is
    their bridge.
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
| `leash_follow_cells` | 2 | a `follow` soldier steps out to strike only within this Manhattan distance of its leader, 0..64 |
| `leash_vanguard_cells` | 4 | the same for `vanguard`, 0..64 |
| `leash_flank_cells` | 4 | the same for `flank`, 0..64 |
| `retreat_hp_pct` | 35 | a soldier at or below this share of its max hp falls back, 0..100 |
| `shield_leader_hp_pct` | 50 | a leader at or below this share of its max hp that an enemy can reach gets a soldier in the way, 0..100 |
| `free_threat_limit` | 2 | a `free` soldier with no fight worth taking stops short of a cell this many enemies can reach (unless as many allies stand within 2 cells), 1..64 |
| `role_slot_weight` | 12 | how much a formation slot's depth counts against walking (one cell = 10) when matching soldiers to slots by role, 0..100 |
| `ai_strength_radius_cells` | 4 | the guard AI (below) sums hp within this many cells of a strike and of its target, 0..64 |
| `ai_attack_ratio_pct` | 100 | the guard strikes only where its hp near the strike is at least this % of the enemy's near the target (a blow that kills a leader always), 0..1000 |
| `ai_advance_ratio_pct` | 120 | the guard leaves its posts once its side's whole hp is at least this % of the enemy's, 0..1000 |
| `ai_hold_radius_cells` | 1 | a holding guard leader stays within this many cells of its post, 0..64 |

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
| `passive.trail_zone` | `zone`, `radius_cells`, `duration_rounds` | `wind_trail` (wind, radius 1, 1 round, where the leader stops; one a phase: a later move of the same phase takes the zone along, so hops never stack wards) |
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
`facing_a`/`_b` (initial heading), `guard_cells` (posts the side defending
the objective holds; on the map, checked on load). `TacticsScenarioData`
(`Data/Tactics/Scenarios/`): `rules`, `map`, `leaders_a`, `leaders_b`
placed on the spawn cells in order (side A with the scenario's
`supplied_troops` when it gives them), and the environment: fog of war,
weather and times of day (see [Tactics vision](tactics_vision.md)).
Scenarios: `scenario.river_crossing` (clear day, fog of war on; three enemy
leaders, Lang Vương the third) and `scenario.night_raid` (woods and a ford
to a lit camp; night from round 1, dusk from round 5, day from round 9; fog
turning to rain in round 5; three kite scouts among its supplied
soldiers).

## Rules

- Cells are (col, row); distances are Manhattan, except the area square.
- A round is side A's phase then side B's. `end_phase()` passes the turn.
- A leader's turn stays open until it waits (Chờ) or the phase ends. While
  open, in any order:
  - it may move any number of times, each move paid from one budget of
    its `move_points` per phase (`move_points_left` in its state). The
    budget is fixed when the phase starts (after expired buffs are gone),
    so walking onto terrain that a passive rewards with move points does
    not add points mid-phase;
  - it may attack once (`has_attacked`), before or after moving;
  - it may cast its skill once when charged (`has_cast`); the attack and
    the skill are independent, so a leader may do both;
  - it may change its order any number of times.
  `wait()` closes it: after that it can do nothing more in the phase, not
  even change its order. A leader is also *closed* (`is_leader_closed`,
  `is_closed()` on the bridge) when nothing is left for it: it cannot move
  (no points, or no reachable cell) and has no attack target and no skill
  cell. A human phase never ends on its own; the screen ends it when every
  leader of the side is closed, and "Kết lượt" (`end_phase()`) ends it
  early.
- Heading: a leader's heading and straight-move streak follow the net
  move of the phase (from where it stood at the phase start), so two short
  moves give the same heading and streak as one long one; with no net move
  it keeps the heading it started the phase with and the streak drops to
  0. The `charge` keyword's straight run goes on over a second move only
  when that move is straight and continues the last step.
- Movement: Dijkstra over move costs; enemies block; allies can be
  passed but not stopped on; a cell next to an enemy (zone of control)
  ends movement unless the unit starts there. A unit whose move ended in a
  zone of control is *held*: it cannot move again in the phase while an
  enemy stays next to it (flying units are never held). Killing that enemy
  frees it with the points it has left.
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
  `anticipation_shift_cells`. Soldiers step after each of their leader's
  moves, and step once more and attack when the leader attacks, waits, or
  at the end of the phase, whichever comes first; how they choose is under
  Soldiers below. `order.hold` stays put (it still attacks).
  A squad whose leader died acts as `free`. `preview_squad()` shows where
  soldiers would go if the leader moved to a cell: it runs the same step
  on a copy, so it is exact.
- Buffs and zones made in round r for d rounds end at the start of their
  side's phase in round r + d (`end_round`), so both sides get the same
  length: a 1-round zone made by side B still works in side A's next phase.
  d = 0 ends at the start of the next phase.
- AI: each leader aims, among the enemies it can strike this phase (after
  a move) without dying to the counter for nothing, at a leader before a
  soldier, a kill before a hit, then the lowest hp, then the lower index,
  and walks to the safest cell to strike it from (as `get_strike_cell()`);
  with no such strike it goes for the nearest enemy by path and moves to
  the reachable cell closest to a cell it could attack it from. Then, when its
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
  The AI keeps to one move and one action per leader (it does not use the
  open turn), so a declared intent stays what it does.
- Guard AI: the side that defends the map's objective (the other side
  holds `objective_side`) plays the guard. It strikes only with a local
  edge: its hp within `ai_strength_radius_cells` of the strike cell (the
  leader's own counted) must be at least `ai_attack_ratio_pct` % of the
  enemy's hp within that radius of the target, unless the blow kills a
  leader; among those strikes it prefers, after a leader and a kill, the
  target with the least enemy hp around it. With no such strike it holds
  while its side's whole hp is under `ai_advance_ratio_pct` % of the
  enemy's: each leader takes a post (the map's `guard_cells`, shared out in
  unit order, nearest first; the objective when none is left) and goes to
  the reachable cell within `ai_hold_radius_cells` of it (else as near as it
  gets) that the fewest enemies can reach next phase, then the best
  terrain; it declares a wait there (or its skill, when the nearest enemy
  is in cast range). Stronger than that, it advances as above. An enemy
  that walked within range of a guard leader is struck in its phase only
  when the fight is favourable. On `river_crossing` the posts are the two
  cells in front of the fort, so the enemy holds the fort and its
  approaches and waits for a leader that comes alone.
- Victory: all enemy leaders dead (`rout`); a leader of `objective_side`
  ending its own move (`move_leader`, or the AI's move) on the objective
  (`objective`; `get_strike_cell()` and `get_strike_targets()` never use a
  strike cell on the objective, since that move alone wins); side B after `max_rounds` (`time_limit`). Being pulled or
  otherwise moved onto the objective does not win, and neither does
  starting the battle or a phase on it: such a leader must move off and
  back on. `battle_ended` is the last event: an engagement or skill that
  ends the battle stops at the death (no `engagement_ended`,
  `skill_resolved`, later effect or charge change follows), and nothing
  changes afterwards.

## Soldiers

Soldiers judge each fight with `predict_engagement()` (the forecast's own
arithmetic, guards included, on the battle as it stands) and a strike from
another cell on one scratch copy with the soldier placed there. A fight is
*favourable* when it kills, or when the soldier lives and deals more than
it takes. The enemy *reach* of a cell is how many living enemies could
attack a unit standing there in their next phase (a move with zones of
control, then their range). Everything is a pure function of the state in
squad order, so the squad preview and the real step agree, and both sides
use the same rules. All numbers are in `TacticsRulesData` (above).

- Budget: each soldier has its own `move_points` per phase. Every squad
  step walks within what is left of it, so a leader that moves in six
  short hops leads its squad no farther than one long move would. A
  soldier held by a zone of control stays held as a leader does.
- One strike: the squad strikes once per phase, when its leader attacks or
  closes (waits, or the phase ends), whichever comes first
  (`has_squad_struck`). Steps after that strike only take slots or fall
  back: no soldier steps out to strike again. A soldier attacked between
  two of the squad's steps still counts as attacked for `free` allies
  until its squad strikes.

- Slots: the order's slots for the living soldiers (`get_formation_slots`
  gives one per living soldier). Soldiers are matched to slots for the
  lowest total of 10 per cell walked minus `role_slot_weight` x role x
  slot depth (cells ahead of the leader; behind is negative), an exact
  assignment over at most eight slots. Role: ranged (`is_ranged` or range
  over 1) is -2 (to the rear), sturdy (a cover or first-strike keyword, or
  more armor than the squad's average) is 1 (to the front), others 0. A
  soldier walks to its slot, or to the reachable free cell nearest it; on a
  tie the better terrain (`get_terrain_fit`: +3 range bonus for ranged, +2
  or +1 less ranged damage, +2 armor, -3 more damage taken) wins.
- Ranged keep clear: a ranged soldier never steps onto a cell next to a
  living enemy (it cannot shoot an enemy there and is struck for free),
  unless the strike from that cell kills the only enemy beside it. Its
  slot, a step-out strike and a free soldier's approach all skip such
  cells; with no other cell it stays where it is.
- Stepping out (follow, vanguard, flank): a soldier may stop on any
  reachable cell within its order's leash of the leader (2, 4, 4 cells)
  to make a favourable strike. It prefers its slot cell, then a kill, then
  an enemy that can strike the leader now, then one that can reach it next
  phase, then the best trade (taken minus dealt), the lowest reach, the
  nearest to its slot, the shortest walk. Otherwise it takes its slot.
- Falling back: a soldier at or below `retreat_hp_pct` of its max hp goes
  to the reachable cell (within the leash, or no farther from the leader
  than its slot) the fewest enemies can reach, then (ranged) one it can
  still shoot from, then the farthest from the nearest enemy. A ranged one
  that ends in range still shoots.
- Shielding: when the leader is at or below `shield_leader_hp_pct` and an
  enemy can reach it next phase, the squad's nearest sturdy soldier (else
  the nearest melee one that is not hurt) stands on the cell next to the
  leader closest to the nearest such enemy.
- Free: a hurt soldier falls back with no leash. Otherwise it takes the
  favourable strike that kills, then answers the enemy that attacked an
  ally within `help_radius_cells`, then joins an enemy an ally already
  strikes, then the best trade, the lowest reach, the shortest walk. With
  none it closes in on that enemy (else the nearest by path) but not onto
  a cell that `free_threat_limit` or more enemies can reach unless as many
  allies stand within 2 cells: it holds just outside.
- Focus fire (after the step, in squad order): each soldier attacks the
  enemy in range it kills, then one it and the squadmates still to strike
  can finish together, then one that can strike the leader now, then one
  that can reach it next phase, then the best trade, the lowest hp, the
  lower index. It never takes a fight that kills it without killing,
  except under `vanguard`, which risks its soldiers.

Since fog of war (milestone 4) the probe plays by sight and takes
`--scenario=`; see [Tactics vision](tactics_vision.md), Balance, for the
current numbers. The numbers below are from before it.

The probe `Tools/tactics_brain_probe.gd` plays seeded river crossings
(side A scripted with random squads and orders: each leader walks to the
nearest enemy leader and strikes the weakest enemy in reach; incidents
on; side B the AI) and prints soldiers and leaders lost, the share of
soldier attacks that killed or traded well, skills cast, how often an
enemy leader's move and action came out as it declared them, wins and
how battles ended; `--policy=idle` plays a side A that only ends its
phases:
`godot --headless --path . --script res://Tools/tactics_brain_probe.gd -- --battles=200 [--policy=idle]`.
With the guard AI and the open leader turn (200 seeds): the scripted
side wins 139 (rout 114, objective 25; the enemy wins 56 by the time
limit and 5 by rout), the idle side loses all 200 by the time limit, and
86% of enemy intents come true move and action alike (91% the move; the
player's own moves block the rest). With one move and one action per
leader it was 137 (rout 104, objective 33, 55 and 8) and 85%; before the
guard AI the scripted side won 200 and the idle one 101, with 57% of
intents kept. The scripted side still makes one move and one action, so
these numbers show the soldier budgets and squad strikes, not a player
who uses move, attack, move.

## Incidents

Biến cố: a few soldiers carry a hidden seed of one incident. The seed
never shows until its situation comes; then the soldier wavers (a mark
over it) for one phase, and at the end of that phase the incident fires
unless the situation faded or, for some incidents, its leader came close.
The [roster](tactics_roster.md) supplies karma and marks and reads the
report; the simulation alone decides what fires.

Files: `tactics_incidents.h/.cpp` (handler registry, seeds, karma, the
phase checks), `tactics_sim_incidents.cpp` (state helpers on `TacticsSim`),
`tactics_incident_data.h/.cpp` (`TacticsIncidentData`,
`TacticsIncidentRulesData`, `TacticsTraitData`),
`tactics_battle_incidents.cpp` (the bridge). Data in
`Data/Tactics/Incidents/` (one file per incident plus
`incident_rules.tres`) and `Data/Tactics/Traits/`; leaders list `traits`,
incidents their `mark_passive` (`Data/Tactics/Passives/mark_*.tres`).

`TacticsIncidentRulesData` (simulation fields; the roster fields are in
the roster doc):

| Field | Default | Meaning |
| --- | --- | --- |
| `min_seeds`, `max_seeds` | 1, 3 | Seeds planted on side A (the player) |
| `ai_min_seeds`, `ai_max_seeds` | 0, 2 | Seeds on side B, only incidents with `seeds_ai_side` |
| `marked_soldier_weight` | 3 | Soldier pick weight = 1 + marks x this |
| `mark_polarity_weight` | 10 | Incident weight + this per mark of the same polarity (good or bad) |
| `karma_weight_per_point`, `karma_weight_cap` | 5, 60 | Incident weight + min(karma x per point, cap): bait raises bad incidents, rescue good ones |
| `bait_distance_cells` | 4 | A soldier hit while its living leader is this far or farther counts as bait |
| `rescue_hp_pct` | 50 | A rescue: the leader's move ends next to its soldier at or under this % hp with an enemy next to it |
| `incidents` | the seven | `TacticsIncidentData` entries |

`TacticsIncidentData`: `id` (the handler), `name_key`, `description_key`,
`base_weight`, `seeds_ai_side`, `threshold_pct`, `threshold_count`,
`radius_cells`, `calm_radius_cells` (0: the leader cannot calm it),
`amount`, `secondary_amount`, `duration_rounds`, `mark_passive`. Fields a
handler does not read stay 0. `TacticsTraitData`: `id`, `name_key`,
`description_key`, `incident_ids` with the matching `weight_pcts`
(-100..1000); the weight of each listed incident in that leader's soldiers
is multiplied by (100 + pct) / 100. `trait.kind` (Lạc Hồng, Bá Khắc):
rescue +80%, betray -30%. `trait.strict` (Nguyệt Thương, Thiết Nha): flee
-60%, discontent -30%.

| Incident | Good | Base | Wavers when | Calm | Effect |
| --- | --- | --- | --- | --- | --- |
| `incident.rescue` | yes | 30 | its leader is at or under 40% hp and within 6 cells | - | dashes next to the leader and takes every hit aimed at it through the coming enemy phase |
| `incident.stand` | yes | 30 | 2+ enemies next to it and no ally next to it | - | armor +30 and cannot be moved for 1 round |
| `incident.surge` | yes | 30 | an ally died next to it since the start of its previous own phase | - | attack +60%, armor +15 for the rest of the battle |
| `incident.discontent` | no | 25 | it was bait in 2 phases | leader within 2 | ignores its order and acts `free` for its next own phase |
| `incident.riot` | no | 20 | its leader is dead or its squad lost 50% of its soldiers | leader within 2 | allied soldiers within 1 cell are shoved one cell away and take 40 damage |
| `incident.flee` | no (AI side too) | 25 | its leader is dead or 5+ cells away, and an enemy is within 2 | - | runs to the escape edge and leaves the battle |
| `incident.betray` | no (AI side too) | 15 | its leader is dead or at or under 35% hp, and an enemy leader with 60%+ hp is within 3 | leader within 2 | joins that leader's squad; with no room there it flees instead |

Rules:

- `set_incident_rules(rules, seed)` before `start()` turns incidents on;
  without it nothing is seeded and no incident event is ever sent. The
  seed drives a xorshift64* generator; the same seed, karma, records and
  commands give the same seeds, events and hash.
- Planting (at `start()`): forced seeds (`set_incident_seed`) when any were
  set, else per side a count in its range; each seed picks a soldier
  without a seed by soldier weight, then an incident by incident weight =
  (base + karma part + polarity part) x trait factor. Side B uses its
  carried karma too, and only `seeds_ai_side` incidents.
- Start of a side's phase: each dormant seed of that side whose trigger
  holds starts wavering (`soldier_wavered`). A wavering soldier hesitates:
  it skips its squad step and attack in that phase.
- End of that phase (after the squad steps): a wavering soldier whose
  trigger no longer holds calms (`incident_calmed`, `reason` `faded`); one
  whose living leader stands within `calm_radius_cells` calms (`leader`);
  otherwise the incident fires (`incident_fired`, then its effect, then
  `mark_earned`). A calmed seed goes back to dormant and can waver again;
  a fired seed is spent.
- Escape edge (flee, betray without room): the nearest edge cell the
  soldier reaches before any enemy (its distance is smaller than the
  nearest enemy's to that cell); the nearest edge cell when there is none.
  The soldier leaves the battle (`unit_fled`); it no longer counts as
  alive and its squad has room again.
- Karma: bait (a soldier hit or killed while its living leader is at
  least `bait_distance_cells` away; once per soldier and phase) and rescue
  (above) each add 1 to the side's battle karma (`karma_changed`). It
  weighs only the next battle's seeds, through the roster. A leader earns
  at most one rescue per phase (its first move that qualifies), so moving
  back and forth beside a hurt soldier farms nothing; that move cannot be
  undone.
- Every mark records the incident, the leader's id, the terrain and cell
  under the soldier and the round. Marks given by `set_unit_record`
  (good, bad) only weigh the seeds.

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
| `undo_move(unit) -> bool`, `can_undo_move(unit)` | method | Takes back the leader's moves in a human phase one at a time, newest first: each undo returns the battle to the exact state (and hash) before that move, points left included, and sends no event. The moves of one leader stack; a move by another leader starts a new stack (undoing that move brings the first leader's stack back). Undo is blocked (the stack is cleared) by: a move whose events are anything but `unit_moved`, `skill_charge_changed` or `vision_changed`, or after which its side knows more of the enemy ([Tactics vision](tactics_vision.md), Undo) (a squad or passive strike, a zone, a rescue, an incident, the objective or the end); an attack, a skill, a wait, an order change, or `end_phase()`. A refused command changes nothing. The screen animates the pieces back itself |
| `get_strike_targets(unit)` | method | Enemies the leader could attack this phase from a cell it can still reach with its points left (its own cell when it cannot move); empty once it attacked or closed |
| `get_strike_cell(unit, target) -> Vector2i` | method | Where the leader should strike `target` from: its own cell when it cannot move, else the cell in range it can reach with its points left that does not get it killed, then the fewest enemies able to reach the cell, the least counter damage, the better terrain, the shortest walk, the lower cell index; (-1, -1) when none |
| `forecast_move_attack(unit, cell, target) -> Dictionary` | method | `forecast_engagement` after the leader moved to `cell` (its own cell: no move) and its squad stepped, on a copy: the same keys plus `cell`, `squad` (`[{unit, cell}]`) and `target_gone` (the squad's step already killed it); `is_valid` false without an error when the move would be refused or the leader already attacked. The squad strikes after the leader, so the result is the leader's own engagement |
| `is_started`, `is_finished`, `get_winner`, `get_end_reason`, `get_round`, `get_turn`, `get_active_side` | method | Battle state |
| `get_unit_count`, `get_unit_state(unit)`, `get_units()`, `get_zones()` | method | Unit and zone dictionaries; a unit also has `start_side`, `record_id`, `has_fled`, `wavering` (the incident id while it wavers, else empty: a dormant seed stays hidden), `is_wavering_good`, `marks` (this battle), `is_guarding`, `holds_ground`, `acts_free` |
| `get_map_width`, `get_map_height`, `get_terrain_id(cell)` | method | Map |
| `get_reachable_cells(unit)`, `get_path_to(unit, cell)` | method | Cells the unit can end a move on from where it stands (without its own) with the points it has left (its full points outside its own side's phase, for threat ranges), and the path to one, both ends included (`[cell]` for its own cell); empty for a dead unit or a cell it cannot stop on. They do not check whether the leader waited, which `move_leader()` also needs |
| `get_formation_slots(leader)` | method | The slot cells of the leader's order (empty for `hold`, `free` or a dead leader) |
| `preview_squad(leader, cell)` | method | `[{unit, cell}]`: where the soldiers would stand after the leader moved there; `[]` and an error when that move would be refused |
| `forecast_engagement(attacker, defender) -> Dictionary` | method | Hits, damage per hit and hp after, without changing state; any two units (an enemy's attack too, whoever's phase it is); `is_valid` false when either is dead, they are on the same side, the defender is out of range or the battle ended. `attacker_modifiers` and `defender_modifiers` (the counter; empty without one) list the ids that change that side's hits, each once: the first-strike keyword, keywords, terrain and zones of the hit, then passives, buffs and terrain behind attack and armor |
| `get_skill_charge(leader)` | method | `{skill, charge, value, threshold, is_ready, area_bonus}` |
| `can_act(unit)` | method | The leader's turn is open: alive, on the active side, battle running, not waited; it may still wait and change orders. False for soldiers |
| `can_move(unit)`, `get_move_points_left(unit)` | method | The leader can act, has points left, is not held by a zone of control and has a cell to go to; the points it has left this phase |
| `can_attack(unit)`, `has_attacked(unit)` | method | The leader can act and has not attacked this phase (it may have no target in reach); whether it attacked |
| `can_cast(unit)` | method | The leader can act, has not cast this phase and its skill is ready |
| `is_closed(unit)` | method | Nothing is left for the leader this phase: it waited, or it cannot move and has no attack target and no skill cell. True for soldiers and the other side's leaders |
| `get_attack_targets(unit)` | method | Unit indexes `attack(unit, target)` would accept now |
| `get_skill_cells(unit)` | method | Cells `use_skill(unit, cell)` would accept now (row-major; empty when the skill is not ready, already cast this phase, or the leader waited) |
| `preview_skill(unit, cell) -> Dictionary` | method | `use_skill` run on a copy: `is_valid` (false, without an error, when it would be refused), `cells`, `targets`, `results` (`[{unit, amount, hp_after, is_dead}]`, the skill's hits summed per target), `buffed` (units), `zone_cells` |
| `get_enemy_intents()` | method | `[{unit, to, action, target, target_cell}]` (`action` `wait`, `attack` or `skill`); `target` is the enemy aimed at (-1 and `target_cell` (-1, -1) when none), or the leader itself for a skill cast on its own cell; a leader that died loses its intent |
| `get_state_hash() -> String` | method | FNV-1a 64 of the whole state (rules, map terrain, round, turn, units, zones, buffs, intents, the next event id), 16 hex digits; units, terrains and zones are identified by ids |
| `set_incident_rules(rules, seed) -> bool` | method | Turns incidents on (before `start()`); false for an invalid rules resource |
| `set_karma(side, bait, rescue)` | method | Karma carried from earlier battles (before `start()`) |
| `set_unit_record(unit, record_id, good_marks, bad_marks) -> bool` | method | Ties a unit to a roster person and gives its earlier marks (before `start()`) |
| `set_incident_seed(unit, incident) -> bool` | method | Forces a seed (tests, stills); when any is forced, nothing else is planted |
| `get_incident_seeds()` | method | Tests and tools only: `[{unit, incident, stage}]` (`dormant`, `wavering`, `fired`); the screen never reads it |
| `get_karma(side)` | method | `{bait, rescue, carried_bait, carried_rescue}` |
| `get_battle_report()` | method | `{is_finished, winner, reason, round, map, karma, units}`; each unit `{unit, record_id, id, role, start_side, side, status (alive, dead, fled), has_defected, leader_id, marks: [{incident, leader_id, terrain, cell, round}]}`; `bond_tallies: [{a, b, phases}]` (only with bonds set: per pair of one side's leaders, the phases of that side they ended within the bond radius) |
| `set_bonds(bonds, rules) -> bool` | method | Bonds (Duyên) between leaders of one side, before `start()`: `bonds` `[{a, b, level}]` (unit indices), `rules` `{radius_cells (0..8, default 2), attack_pct_per_level (0..100, 5), max_level (1..5, 3)}`; false (with an error) for a unit that is not a leader, two sides, a level outside 1..max_level, rules out of range or a started battle. Each of the two gets level x attack_pct_per_level % attack while the other is within radius_cells (Manhattan), in `get_stats_at` (forecasts list the source `bond`); it is hashed. Turns the phase tallies on |
| `get_bonds()` | method | `[{a, b, level, is_active, attack_pct}]` |
| `set_log_enabled(enabled)` | method | Prints the log events below |
| `event_emitted(event)` | signal | Each event, in order |
| `battle_ended(winner, reason)` | signal | Once; `reason` is `rout`, `objective` or `time_limit` |

Every event has `id`, `turn`, `round`, `type` and `cause` (the id of the
event that caused it, 0 if none; ids start at 1). A command's own first
event has cause 0; what follows from it points back: a squad's step to the
leader's `unit_moved`, `engagement_started` or `leader_waited` (a skill
does not move the squad), a trail zone to the move, a pull to the
engagement.
Expiries, burns and intents at the start of a phase point to its
`phase_started`; a squad that strikes at the end of the phase (its leader
neither attacked nor waited) and the charge gained then have cause 0. Types: `battle_started`, `phase_started`,
`phase_ended`, `unit_moved` (`kind` `move`, `squad`, `pull`),
`order_changed`, `leader_waited`, `intent_declared`, `engagement_started`,
`damage_dealt`, `engagement_ended`, `unit_died`, `skill_used`,
`skill_resolved`, `skill_charge_changed`, `skill_grew`, `buff_applied`,
`buff_ended`, `zone_created`, `zone_expired`, `passive_triggered`,
`soldier_wavered`, `incident_calmed`, `incident_fired`, `mark_earned`,
`unit_fled`, `unit_defected`, `karma_changed`, `battle_ended`. An
incident's effect events and its `mark_earned` point to its
`incident_fired`.

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
| `soldier_wavered` | `unit`, `incident`, `is_good` |
| `incident_calmed` | `unit`, `incident`, `reason` (`faded`, `leader`) |
| `incident_fired` | `unit`, `incident`, `is_good`, `leader` (its leader at that moment), `side`, `cell` |
| `mark_earned` | `unit`, `incident`, `leader_id`, `terrain`, `cell`, `count` (its marks in this battle) |
| `unit_fled` | `unit`, `from`, `to` (the escape edge cell) |
| `unit_defected` | `unit`, `side` (new), `from_side`, `leader` (its new leader) |
| `karma_changed` | `side`, `kind` (`bait`, `rescue`), `value` (the side's battle total) |
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
- New incident: add a handler (`is_triggered`, `fire`, `is_good`) to the
  registry in `tactics_incidents.cpp`, a `.tres` in
  `Data/Tactics/Incidents/` listed in `incident_rules.tres`, its mark
  passive, and the Locale rows `INCIDENT_<X>`, `_DESC`, `_HINT`,
  `TACTICS_PASSIVE_MARK_<X>` and `BIO_MARK_<X>_FORMAT`.
- New trait: a `.tres` in `Data/Tactics/Traits/`, listed by leaders.

## Tests

`Tests/tactics_world_test.gd` covers bonds (refusals, the bonus only
while close and in forecasts, tallies, the same hash on the same seed).
`Tests/tactics_test.gd` (catalog checks, scenario loading and failed
loads and setups, movement, paths and zones of control, engagement and forecast,
keywords, terrain, AI intent, victory, defeat and time limit, objective
only by the leader's own move, `battle_ended` as the last event, a replay
that must give the same state hash, what the hash covers (rules and
terrain too), the open leader turn (moves within the points, one attack,
skill and attack apart, nothing after a wait), data range
checks, side bounds, map legends, dead units in queries and intents) and
`Tests/tactics_brain_test.gd` (soldiers step out and come back, the
leash, ranged soldiers in the rear, focus on a kill, no deadly strike
except under vanguard, falling back, shielding the leader, a free soldier
not walking into a wall of enemies, `forecast_move_attack()` against the
real move and attack, three moves undone one at a time back to the exact
units and hash, what blocks undo (a zone, an order, an attack, another
leader's move and undoing it), soldiers gaining no distance from many
short moves, the squad striking once, the same events for the same
commands) and
`Tests/tactics_squad_test.gd` (orders, anticipation, slots of a dead
leader, the five charge mechanisms, skills and zones, the AI casting a
skill on an enemy and on its own side and a focus skill without moving,
the five passive kinds, one trail zone a phase however often the leader moves, the side a zone affects, side B durations and
event causes) and `Tests/tactics_fuzz_test.gd` (random maps, leaders
and commands, legal and not, on 24 seeds: queries and refused commands
leave the hash unchanged, a command is accepted exactly when its query
said so (`can_move`, `can_act`, `get_attack_targets`, `get_skill_cells`),
moves follow `get_path_to()` and `preview_squad()`, attacks land the
forecast, skills what `preview_skill()` said, the events account for every cell, hp, charge and zone
change, one unit per cell, `battle_ended` last, and a replay gives the
same hashes; strikes from `get_strike_cell()` land what
`forecast_move_attack()` said; leaders often move again, each turn's
walks stay within its points and each unit strikes once per phase,
`can_attack` / `can_cast` / `is_closed` / points left agree with the
state and nothing is accepted after a wait; undo follows a modelled stack
(at least three deep in the run) and gives back the hash and every
query's answer from before each move; a second replay that leaves the
undone moves out must give the same events and hashes afterwards) and
`Tests/tactics_query_test.gd` (a scenario loaded with
other squads and refused ones, `can_move` / `can_act` over an open turn
(two moves within the points, not past them, attack then move, move,
attack, move, an order after moving, nothing after a wait, a moved leader
with no target still open), the zone-of-control hold, attack targets, skill
cells, `preview_skill()` against the real cast for damage and support, the
forecast's modifier lists) and `Tests/tactics_incident_test.gd` (each
incident's trigger, its calm and its effect, hesitation, the escape edge,
bait and rescue karma, the karma odds over many seeds, traits, the report
and the same events and hash for the same seed), sharing
`Tests/tactics_test_kit.gd`. On even seeds the fuzz test also turns
incidents on, forces seeds in most soldiers and checks sides, flight and
defection against the events. Run:
`godot --headless --path . --script res://Tests/tactics_test.gd` (and the
squad, fuzz, query, incident and brain tests). All six are in CI.

## Known limits

- The AI is greedy (one leader at a time: the best strike it can make this
  phase, else the nearest enemy, or its post for the guard), does not use
  orders, does not go for the objective, and casts a skill for its own
  side as soon as it is ready, even with no soldier left to help. Its
  strength is hp only (not attack, range or terrain).
- Soldiers judge one fight at a time from the state at their step; they
  do not plan for the enemy's reply beyond the reach count, and a squad's
  later soldiers see what the earlier ones did.
- Undo covers only plain moves of the latest leader to move (and, after
  those are undone, the leader before it); any action clears it.
- The AI and the probe's scripted player make one move and one action per
  leader; neither uses move, attack, move, so the balance numbers do not
  measure it.
- Damage has no randomness; ties are broken by unit index and cell order.
  Incidents are the only random part, from the battle's seed.
- Incidents only touch soldiers; leaders never waver. The AI does not
  read wavering soldiers or try to calm them.
