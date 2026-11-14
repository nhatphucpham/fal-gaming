# Synergy

## Purpose

Turns a line-up into its automatic bonuses: Nghề (class milestones), Tộc
(race milestones), Trận đồ (formations, matched by [Formation](formation.md))
and the Hợp Lực meter that counts them, and translates everything active into
battle modifiers. The same evaluation runs on the preparation screen (every
line-up change, and the drag preview) and in the battle at `start()`, for
both sides. It holds no state between calls and never changes the run.

## Layer and files

- Simulation, `Native/src/rules/` (namespace `rules`, plain C++17):
  - `modifier_handlers.h/.cpp`: the modifier and rule registries
    (`find_modifier_handler`, `find_rule_handler`, `find_stat_id`).
  - `synergy_types.h`: `ModifierDef`, `TierDef`, `MilestoneDef`,
    `FormationDef`, `HopLucDef`, `SynergyConfig`, `SynergyResult`, `Grant`.
  - `synergy_validation.h/.cpp`: `resolve_config()` (ids to indexes,
    ranges, tier order, rules allowed only where they make sense).
  - `synergy_eval.h/.cpp`: `evaluate()` (milestones, formations, levels,
    Hợp Lực) and `collect_grants()` (modifiers per unit).
- Battle side: `Native/src/battle/battle_modifiers.h` (`ActiveModifier`,
  `SynergySource`), `battle_synergy.cpp` (install at start, events, volleys,
  broken formations, damage adjustments), `battle_attack_modifiers.cpp`
  (crits, every-Nth bonus, pierce, multi-cell knockback).
- Bridge, `Native/src/synergy/`: `ModifierData`, `SynergyTierData`,
  `MilestoneData`, `FormationData`, `HopLucData` (resources) and `Synergy`
  (RefCounted).
- Content: `Data/Synergies/` (milestones), `Data/Formations/`,
  `Data/Rules/hop_luc.tres`, all listed in `Data/catalog.tres`;
  `Catalog.get_synergy()` builds and caches the `Synergy`.
- Presentation: `Scenes/Run/synergy_hud.gd` (`SynergyHud`),
  `Scenes/Run/lineup_synergy.gd` (`LineupSynergy`), `UI/synergy_bar.gd`
  (`SynergyBar`), `UI/synergy_panel.gd` (`SynergyPanel`),
  `Scenes/Board/formation_outlines.gd`, `Scenes/Battle/synergy_playback.gd`
  (`SynergyPlayback`), the synergy badge on `UI/shop_card.gd` and the
  milestone list in `UI/unit_info_panel.gd`.
- Depends on: [Formation](formation.md). The battle depends on it (see
  [Battle](battle.md)).

## Rules

- **Class milestones** count the different unit ids of the class on the
  board (two archers of the same id count once).
- **Race milestones** count units; cost 4 and 5 count as 2
  (`double_from_cost`).
- Each tier reached is one active milestone: shield at 4 is 2 milestones.

| Milestone | At | Effect | Modifier |
| --- | --- | --- | --- |
| shield | 2 / 4 | armor +20 / the first damaging hit each shield takes is blocked ("Chặn") | `mod.stat_add` / `mod.block_first_hit` |
| sword | 2 / 3 / 4 | +15% damage / +5 Khí per basic attack / reflect 30% of melee damage taken | `mod.damage_dealt_pct` / `mod.qi_on_attack` / `mod.reflect_melee_pct` |
| spear | 2 / 4 | range +1 when in rank 1 at the start / basic attacks also hit the enemy behind the target | `mod.range_add_if_front` / `mod.pierce_behind` |
| cavalry | 2 / 3 | opening charge impact +30% / knockback 2 cells | `mod.charge_impact_pct` / `mod.knockback_cells` |
| archer | 2 / 3 / 4 | attack 20% faster / first basic attack crits / pierce behind | `mod.attack_speed_pct` / `mod.first_attack_crit` / `mod.pierce_behind` |
| mage | 2 / 4 | basic attack area row3 plus the cell behind / skills +30% | `mod.attack_shape` (`shape.row3_behind`) / `mod.skill_damage_pct` |
| human | 1 / 3 / 5 | formations with a human +1 level / +5% team damage per active formation / formations with 2 humans +2 levels | `rule.formation_level` / `mod.damage_dealt_pct` (`per_formation`) / `rule.formation_level` |
| wolf-folk | 1 / 3 / 5 | a 3-unit formation completes with 2 if a wolf-folk is in its middle / a wolf-folk kill gives every wolf-folk +10 Khí / 4-unit formations need 3 | `rule.formation_missing_middle` / `mod.qi_on_ally_kill` / `rule.formation_missing_any` |

Cavalry 2 is "+30% impact" rather than the GDD's "charges 1 s earlier":
charges already start on tick 1.

- **Hợp Lực** points = class milestones + race milestones + formation
  instances. Tiers are cumulative and frozen at the battle's start: 3 every
  unit starts with +10 Khí, 6 +8% damage, 9 +12% max hp (it replaces the
  GDD's chain tier until chains exist), 12 +10% attack speed, 15 +30 Khí
  more.
- **Grants.** A modifier reaches units by its scope; values of the same
  handler on a unit add up. Two instances of one formation never reach the
  same unit (a piece joins one instance per formation id, and formations
  may not use `scope.side`), so each instance's modifiers end with it.
- **Damage.** Increases (`mod.damage_dealt_pct`, the attacker's
  `mod.skill_damage_pct` for skills) join the damage request's increase;
  decreases (`mod.damage_taken_pct`, `mod.ranged_physical_taken_pct` against
  ranged physical attacks) join its decrease; the one-division formula of
  [Battle](battle.md) is unchanged. A block makes the hit 0 and it does
  not count as damage taken (no Khí for the victim, no on-hit passives;
  the attacker still gains its Khí per attack); a split gives
  the victim the rounding remainder and the others `amount / living`;
  reflection is fixed damage (no mitigation, never reflected again) and
  happens only if the victim survives.
- **Formations end** when a member dies (`formation_broken`): their
  modifiers stop applying (Hợp Lực stays frozen).

## Data

`ModifierData` (inside tiers and formations):

| Field | Meaning |
| --- | --- |
| `handler` | `mod.*` or `rule.*` id (registry above) |
| `scope` | `scope.counted` (the milestone's units), `scope.side` (the whole side), `scope.members` (a formation's members), `scope.slots` (members in `slots`), `scope.behind_members` (allies right behind a member at the start) |
| `slots` | slot indexes for `scope.slots` |
| `value` | 0..1000: percent, cells, Khí or armor, by handler |
| `count` | 0..100: every Nth attack, blocks per battle, levels (rules), slot count (missing rules) |
| `ticks` | 1..10000: the volley period |
| `param` | `mod.stat_add`: `armor` or `magic_resist`; `mod.attack_shape`: a shape id |
| `per_formation` | a side modifier of a milestone multiplied by the active formation count |

`MilestoneData`: `id` (`milestone.class_<x>` / `milestone.race_<x>`),
`name_key`, `counted_kind` (`class`/`race`), `counted_id`,
`counts_distinct_units`, `double_from_cost` (0 = never), `tiers`
(`SynergyTierData`: `at` strictly increasing, `description_key`,
`modifiers`). `HopLucData`: `tiers`, `formation_level_step_pct` (40),
`max_formation_level` (4).

Validation (`Synergy.setup()` and `Catalog.validate()`) rejects unknown
handlers, scopes or stats, misplaced scopes (formations may not use
`scope.counted` or `scope.side`), rules outside milestones,
`rule.formation_level` and `rule.formation_missing_middle` outside race
milestones (they count the milestone's race; `rule.formation_missing_any`
needs no race and may sit on a class milestone too), `per_formation`
outside a side modifier, start-of-battle stats (`mod.max_hp_pct`,
`mod.range_add_if_front`, `mod.attack_shape`: applied once, never reverted)
on a formation or a `per_formation` modifier, since a formation can break,
empty slot lists, two formation slots at one offset, tiers out of order,
and milestones counting an unknown class or race.

## Public API

`Synergy` (RefCounted):

| Member | Kind | Description |
| --- | --- | --- |
| `setup(formations, milestones, hop_luc) -> PackedStringArray` | method | Validates and builds; problems as messages, empty when ready |
| `is_ready() -> bool` | method | After a clean `setup()` |
| `evaluate(pieces: Array) -> Dictionary` | method | Pieces `{unit: UnitData, col, rank}` or `{unit_id, class_id, race_id, cost, col, rank}` (local cells). Returns `class_milestones` and `race_milestones` (`id`, `counted_id`, `count`, `thresholds`, `reached`), `formations` and `near_formations` (see [Formation](formation.md)), `hop_luc`, `hop_luc_tier` (the tier reached, 0 if none), `next_tier` (0 past the last) |

`Battle.set_synergy(synergy)` (refused once units exist) turns synergies on
for both sides; `BattleFactory.create()` does it with the catalog's.

Presentation:

- `SynergyHud` (RefCounted, built by `RunScreen`): `refresh(animate)`,
  `refresh_enemy()`, `preview(piece_id, shop_unit, local_cell)`,
  `end_preview()`, `roll_call()`, `end_battle()`,
  `on_formation_broken(side, id, cells)`, `open_panel()`, `get_counts(side)`;
  `result` and `enemy_result` hold the last evaluations.
- `LineupSynergy`: `run_pieces(run)`, `lineup_pieces(catalog, lineup)`,
  `preview_pieces(run, piece_id, shop_unit, to)`: the board as
  `RunState.preview_board()` says the drop would leave it (a card whose
  purchase merges shows the board after the merge, wherever it is dropped;
  the legend limit and a full board refuse), empty when RunState would
  refuse it.
- `SynergyBar` (the info row, one row with the unit counter): `setup`,
  `show_result`, `show_preview`, `end_preview`, `bounce`, `opened` signal;
  `get_chip_ids()` and `get_more_count()` for tests.
- `SynergyPanel` ("+N"): `open(result, catalog, title)`, `close()`,
  `get_lines()`.
- `PrepController.preview_requested(piece_id, shop_unit, local_cell)` and
  `preview_ended()` fire when a drag enters a new cell of the player's half
  or leaves it; the evaluation runs only then.

## Events

Emitted by the battle on tick 1, right after `battle_started`, for both
sides (A first): one `synergy_activated` per milestone tier reached
(`level` = tier number, `threshold` = its `at`), per formation instance
(`level` = formation level) and one for Hợp Lực (`level` = points). See the
event table in [Battle](battle.md).

## How to extend

- **Add a milestone tier or change a value:** edit the `.tres` in
  `Data/Synergies/` (or `Data/Rules/hop_luc.tres`) and its description in
  `Locale/strings.csv`.
- **Add a milestone** for a new class or race: a new `MilestoneData` with
  `counted_kind` and `counted_id`, listed in `Data/catalog.tres`.
- **Add a formation:** see [Formation](formation.md).
- **Add a modifier kind:** add an entry to the table in
  `modifier_handlers.cpp` (id, `ModifierKind`, whether it needs `param`)
  and read it where it acts in the battle (`sum_modifiers()` /
  `find_modifier()`); show a proc with `emit_modifier_triggered()` and a
  look in `SynergyPlayback`'s registry.

## Tests

`Tests/synergy_test.gd`: every milestone modifier with exact numbers in
tiny battles (armor, block, sword damage, Khí and reflection, spear range
and pierce, cavalry impact and knockback, archer speed, crit and pierce,
mage shape and skill damage, wolf-folk Khí on kills: exactly +10 for every
living wolf-folk and none for others), that a blocked hit gives the victim
no Khí and fires no on-hit passive while the attacker keeps its Khí, Hợp
Lực tier bonuses, and that a battle without synergy behaves as before.
`Tests/formation_test.gd` also covers milestone counting (duplicates once
for classes, cost 4-5 double for races), Hợp Lực totals and tiers, that
evaluate() changes nothing, and validation errors (including start stats
and `scope.side` on formations and repeated slot offsets);
`Tests/formation_battle_test.gd`: see [Formation](formation.md).
`Tests/synergy_ui_test.gd` (scene level): placing units updates the info
row and outlines, the "+N" panel opens, a drag previews without changing
the run and the outlines come back after it, the preview follows RunState
(a merging card on a free or taken cell, the legend limit), a broken
formation shatters its own instance's outline, the enemy's formations are
outlined, a battle with synergies plays
through. All run in CI.

## Known limits

- No Duyên bonds, Ngũ Hành, chains, other races or hidden formations.
- A long press on an enemy formation outline does not describe it yet (cut
  from milestone 5); the enemy unit's info panel lists its milestones.
- The shop badge assumes the bought unit lands on a free cell; it does not
  preview formations that only a specific cell would make.
