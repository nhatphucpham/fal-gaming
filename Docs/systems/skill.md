# Skill

## Purpose

Khí (the skill gauge), the active skill every class casts when its Khí is
full, the 3-star Hậu chiêu (a second step after the skill), passives that
fire on battle triggers, and the statuses they leave (taunted, guard, armor
break, stun). Skills, passives and their effects are data; the simulation
runs them through registries keyed by id. It does not draw anything: the
presentation is in [Battle playback](battle_playback.md).

## Layer and files

- Layer: simulation (plain C++17, no Godot headers, no floats) with a bridge.
- Simulation, in `Native/src/skill/`:
  - `skill_types.h`: `EffectDef`, `SkillStepDef`, `SkillDef`, `PassiveDef`,
    `StatusKind`, and the per-unit state (`UnitSkillState`: Khí, cast,
    charge, passive counters, statuses) and `ScheduledStep` (a Hậu chiêu).
  - `skill_selectors`, `skill_areas`, `skill_effects` (+
    `skill_effects_special.cpp`), `skill_passives` (triggers, conditions,
    `fire_passive`): the registries.
  - `skill_cast`: Khí gain, the cast action, scheduled Hậu chiêu.
  - `skill_charge`: the charge runner shared by the cavalry opening and its
    skill.
  - `skill_statuses`: apply, refresh, expire statuses.
  - `skill_validation`: resolves ids to handlers and checks ranges.
- `BattleSim` (`Native/src/battle/`) calls into these and owns the state;
  `battle_basic_types.h` holds the board and damage types both folders use.
- Bridge, in `Native/src/battle/`: `skill_effect_data`, `skill_data`,
  `passive_data` (resources), plus the `skill`/`passive` fields of
  `ClassData` and the overrides on `UnitData`.
- Content: `Data/Skills/`, `Data/Passives/`, listed in `Data/catalog.tres`.
- Depends on: [Battle](battle.md) (damage, moves, events, targeting).

## Data

Ids: `skill.<name>`, `passive.<name>`, and handler ids `select.*`,
`area.*`, `effect.*`, `trigger.*`, `condition.*`. A `ClassData` has
`skill: SkillData` and `passive: PassiveData` (either may be null); a
`UnitData` may set `skill_override` / `passive_override` to use another one.
`Catalog.validate()` checks ids, duplicates, name and description keys, and
that every skill and passive a class or unit uses is listed in the catalog.
`Battle.register_class()` / `add_unit()` resolve handler ids and ranges and
refuse bad data with an error naming the skill and field (`Battle: class.x
skill: skill.sweep has unknown selector 'select.nope'`).

`SkillData` (`Data/Skills/<name>.tres`):

| Field | Unit / range | Notes |
| --- | --- | --- |
| `id`, `name_key`, `description_key` | `skill.<name>`, translation keys | `SKILL_<NAME>`, `SKILL_<NAME>_DESC` (one line) |
| `qi_cost` | Khí, 1..1000 | the unit's full Khí |
| `selector`, `selector_range` | handler id; cells 0..8 | where the skill aims: the anchor |
| `area`, `area_size` | handler id; cells 0..8 | the cells around the anchor |
| `effects` | 1..3 `SkillEffectData` | applied in order |
| `star3_area`, `star3_area_size` | handler id or empty; -1 keeps the base size | area at 3 stars |
| `has_after_skill`, `after_delay_ticks` | bool; ticks 0..10000 | the Hậu chiêu, at 3 stars only |
| `after_selector`, `after_area`, `after_area_size` | empty selector: the main cells again | |
| `after_effects` | 0..3; empty repeats the main effects | |

`SkillEffectData` (sub-resource): `id` (`effect.*`), `target` (`AREA` 0:
living enemies in the cells; `SELF` 1; `SOURCE` 2: the other unit of a
passive's trigger), `value` 0..250 (so that with the highest star multiplier it stays
within the damage pipeline's 1000% cap), `duration_ticks` 0..10000, `count`
0..20, `star3_count` (-1 keeps `count`), `damage_kind` (physical 0, magic 1).

`PassiveData` (`Data/Passives/<name>.tres`): `id`, `name_key`,
`description_key`, `trigger` (`trigger.*`), `condition` (`condition.*` or
empty), `condition_radius` 0..8, `every_nth` 1..100 (fires on every Nth
matching trigger), `limit_per_battle` 0..100 (0 unlimited),
`once_per_source` (at most once per other unit), `effect`
(`SkillEffectData`).

`BattleRulesData` adds: `qi_per_attack` 10, `qi_per_hit_taken` 5,
`cast_ticks` 10 (1..1000), `star_skill_pct` [100, 150, 250] (skill
coefficient by star, each 1..400) and `crit_multiplier_pct` 150 (100..300).

### Registries

| Kind | Ids |
| --- | --- |
| Selector | `select.self` (the caster's cell), `select.column_most_enemies` (the column with most enemies, anchored on its frontmost enemy), `select.densest_area` (the enemy cell within `selector_range`, 0 any, whose area holds most enemies) |
| Area | `area.single`, `area.square` (size = radius), `area.front3`, `area.column_ahead` (size cells ahead, 0 to the end), `area.column`, `area.plus` |
| Effect | `effect.damage` (value % of attack), `effect.taunt`, `effect.guard` (value % less damage), `effect.armor_break` (value % less armor), `effect.stun` (cancels a cast), `effect.knockback` (one cell away from the caster), `effect.add_qi`, `effect.crit` and `effect.impact_bonus_per_cell` (passive modifiers), `effect.charge_column`, `effect.arrow_volley` |
| Trigger | `trigger.basic_attack_landed`, `trigger.damaged`, `trigger.arrow_blocked`, `trigger.melee_hit_taken`, `trigger.charge_impact_incoming`, `trigger.charge_impact`, `trigger.element_reaction` |
| Condition | `condition.within_radius`, `condition.victim_or_in_range` |

### The content

| Class | Skill (Khí) | Hậu chiêu (3 stars) | Passive |
| --- | --- | --- | --- |
| Shield | `skill.hold_ground` (80): taunts enemies within 2 cells and guards 40% for 60 ticks | when the taunt ends, pushes adjacent enemies back | `passive.bedrock`: +10 Khí when it blocks an arrow |
| Sword | `skill.sweep`: 180% on the 3 cells in front | the same sweep 5 ticks later | `passive.riposte`: every 3rd melee hit taken strikes back for 100% |
| Spear | `skill.heart_pierce`: 200% on 3 cells ahead, armor break 30% for 80 ticks | reaches the end of the column | `passive.brace`: strikes a charging enemy first for 100%, once per charger |
| Cavalry | `skill.breakthrough`: moves to the most crowded column and charges it, impact 150% | charges a second column | `passive.momentum`: +15% impact damage per cell run |
| Archer | `skill.arrow_rain`: 5 arrows of 70% into the most crowded column | 8 arrows | `passive.steady_aim`: every 4th attack is a critical hit |
| Mage | `skill.arcane_circle` (120): 220% magic in a plus on the densest spot | a 3x3 square | `passive.spirit_draw`: +15 Khí on an element reaction within 2 cells |

## Rules

- **Khí.** +`qi_per_attack` once per basic attack landed (a blocked arrow
  counts), +`qi_per_hit_taken` per damage event from an enemy; capped at
  `qi_cost`; no gain while casting. Units without a skill have no Khí.
- **Cast.** On its action, a unit with full Khí that is not moving starts a
  cast if its selector finds cells with at least one enemy; else it acts
  normally and keeps its Khí. The cast lasts `cast_ticks` ticks during which
  the unit does nothing else (its attack charge still fills); on the last
  tick the cells are re-checked for living enemies, the effects resolve and
  Khí goes to 0. A unit that dies or is stunned while casting does not
  resolve.
- **Power.** Skill coefficients are scaled by `star_skill_pct` (100/150/250%);
  passive damage is not. Skill damage goes through the normal pipeline
  (counter bonus included, never blocked by a shield) and carries the
  skill or passive id.
- **Hậu chiêu.** At 3 stars, a skill with `has_after_skill` schedules a
  second step `after_delay_ticks` after the main one; it runs at the start
  of that tick, before units act, if the caster is alive.
- **Statuses.** Active while the tick is below `end_tick`; reapplying keeps
  the later end and the bigger amount. Taunted units target the taunter and
  do not re-pick; guard lowers damage taken; armor break lowers armor for
  physical damage; stun skips actions. A dead taunter frees its victims.
- **Passives.** A trigger fires the owner's passive if the condition holds,
  the per-source and per-battle limits allow it, and the trigger count
  reaches `every_nth`. `basic_attack_landed` fires before the hit so a
  modifier (`effect.crit`) applies to it.
- **Order.** Each tick: statuses expire, due Hậu chiêu run, then units act
  in the battle order. Everything is integer and ordered; all of it is in
  the state hash.

### Dedicated handlers

Most skills are generic blocks (selector + area + effects). Two are not:
`effect.charge_column` has to run over many ticks (move to the column, run,
hit, knock back, maybe the next column) through the charge runner that the
cavalry opening uses, and `effect.arrow_volley` re-aims each arrow at the
column's new front after the previous one kills. Neither fits a one-shot
effect on fixed cells, so each has its own handler in
`skill_effects_special.cpp`.

## Public API

No new node. `Battle.get_unit_state()` adds `qi`, `qi_max`, `casting` and
`statuses` (an array of `{status, end_tick, amount, source}`). `Catalog`
adds `get_skill(id)`, `get_passive(id)`, `get_unit_skill(unit)` and
`get_unit_passive(unit)`.

## Events

| Type | Payload | Cause |
| --- | --- | --- |
| `qi_changed` | `unit`, `qi`, `qi_max` | the attack, damage, cast or passive |
| `skill_cast_started` | `unit`, `skill`, `cells` (Array of Vector2i), `end_tick` (the resolve tick) | 0 |
| `skill_resolved` | `unit`, `skill`, `cells`, `is_after_skill` | the cast start |
| `passive_triggered` | `unit`, `passive` | the trigger event |
| `status_applied` | `unit`, `status` (`status.taunted`/`guard`/`armor_break`/`stun`), `source`, `end_tick`, `amount` | the effect's resolve |
| `status_ended` | `unit`, `status` | 0 (expiry, or the taunter died); a dying unit's own statuses end silently |

`damage_dealt` adds `skill` (the skill or passive id, empty for a basic
attack). Effects caused by a resolve have the `skill_resolved` id as cause.
With `log_enabled`, `skill_cast_started` is logged at info level:
`[info][Battle][t=103] skill_cast_started unit=2 skill=skill.hold_ground cells=25`.

## How to extend

- **New skill from existing blocks:** add `Data/Skills/<name>.tres`
  (`SkillData` with `SkillEffectData` sub-resources), list it in
  `Data/catalog.tres` under `skills`, set it on a class (`skill`) or a unit
  (`skill_override`), add `SKILL_<NAME>` and `SKILL_<NAME>_DESC` to
  `Locale/strings.csv`. No code changes.
- **New passive:** the same with `Data/Passives/` and `PassiveData`.
- **New selector, area, effect, trigger or condition:** write the function
  and add it to the table in the matching `skill_*.cpp`, then use its id in
  data. A new status needs a `StatusKind`, its id in `skill_statuses.cpp` and
  its use where it acts.
- **Its look:** a skill without an entry in `SkillPlayback`'s registry shows
  a glyph on each cell; add an entry for a distinct effect.

## Tests

`Tests/skill_test.gd`: cast timing (10 ticks, Khí 0 after, no cast without
a target), each skill's damage at 1 and 3 stars, the Hậu chiêu (second
sweep, column end, push when the taunt ends, second column, 8 arrows, 3x3),
taunt redirection, guard and expiry, armor break, the reposition move.
`Tests/passive_test.gd`: Khí gain and cap, each passive (riposte every 3rd
melee hit, brace once before the impact, momentum, steady aim's 4th attack,
bedrock), refused data, unit overrides, determinism with skills, and an
8v8 that prints its length and casts per unit. Run both as in the README;
CI runs them. `Tests/skill_test_kit.gd` holds their shared set-up.

## Known limits

- `passive.spirit_draw` can never fire yet: element reactions do not exist,
  so nothing raises `trigger.element_reaction`. It is kept as data so the
  mage has its passive when elements arrive.
- `trigger.melee_hit_taken` counts basic melee attacks and the opening
  charge impact (which is a basic attack), not skills or skill charges.
- No skill uses `effect.stun` yet.
- `PassiveCounters.used_sources` is a 64-bit mask, so `once_per_source`
  tracks at most 64 units per battle (sides hold at most 28 each).
