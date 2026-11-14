# Kỳ Ngộ (epiphany)

## Purpose

Kỳ Ngộ turns a run's fighting style into lasting change: each milestone
family (the six classes and two races) fills a hidden Ngộ meter by fighting;
when a meter passes its threshold the player picks one of two mutations of
that family, shown in a cutscene ([cutscene.md](cutscene.md)). It is a run
rule: it never runs inside a battle and never touches the enemy's line-up.

## Layer and files

- Layer: rules (GDScript, pure data), with the mutation applied by the
  synergy bridge (C++).
- Code: `Systems/Run/epiphany_tracker.gd` (meters, thresholds, firing,
  save), `epiphany_battle.gd` (what a battle gives), `epiphany_data.gd`,
  `epiphany_family.gd`; `Native/src/synergy/synergy_overrides.*` (an
  override list applied to a copy of the synergy config).
- Depends on: [run](run.md) (RunState owns the tracker and calls it from
  `finish_battle`), [synergy](synergy.md) (`Synergy.evaluate(pieces,
  overrides)`, `Battle.set_synergy_overrides`).

## Data

- `Data/Epiphanies/<family>.tres`, an `EpiphanyFamily` per milestone family,
  listed in `Data/catalog.tres` (`epiphanies`):

  | Field | Meaning |
  | --- | --- |
  | `family` | The milestone id (`milestone.class_shield`). |
  | `line_keys` | The cutscene lines: the first is the family's unit's, the rest the sage's. |
  | `epiphanies` | At least 3 `EpiphanyData`, of both kinds. |

- `EpiphanyData`:

  | Field | Meaning |
  | --- | --- |
  | `id` | `epiphany.<family>_<name>`, unique. |
  | `family` | Its milestone id. |
  | `kind` | `lower` (Hạ Mốc) or `variant` (Biến Dị). |
  | `name_key`, `description_key` | Card heading and one line ("Khiên 4 chỉ cần 3 Khiên"). |
  | `tier` | Index of the tier it changes (0 = first threshold). |
  | `modifiers` | `variant` only: the tier's new modifiers, using existing handlers. |

  A `lower` takes the tier's threshold down by 1 and must stay above the
  previous tier's threshold; a `variant` replaces the tier's modifier list.
- Numbers in `Data/Rules/run_rules.tres` (group "Kỳ Ngộ"):

  | Field | Value | Meaning |
  | --- | --- | --- |
  | `ngo_threshold_min`, `ngo_threshold_max` | 4, 7 | Each family's threshold is rolled in this range. |
  | `ngo_per_active` | 1 | Per battle, for each family with a tier reached. |
  | `ngo_loss_bonus` | 1 | More for each active family after a loss. |
  | `ngo_top_damage_bonus` | 2 | For the active, unmutated family whose units dealt the most damage (more than 0). |
  | `ngo_meter_max` | 99 | Meter cap (save validation). |
  | `epiphanies_per_run` | 4 | Most Kỳ Ngộ in one run. |

## Rules

- After every battle that does not end the run, `RunState.finish_battle`
  reads the board as it fought: the families with a tier reached (evaluated
  *with* the run's mutations) and each family's damage (the sum of
  `damage_dealt` of the board pieces it counts; a piece counts for its class
  family and its race family). Mutated families gain nothing more.
- Thresholds come from a generator seeded with `run_seed ^ 0x4E676F`, so
  they are fixed for the seed and the run's own generator (shops, offers) is
  untouched. The generator draws one threshold per family in catalog order.
- A Kỳ Ngộ fires when some unmutated meter is at or over its threshold, with
  at most one per stage (a replay of stage 12 after a loss is the same
  stage), at most four per run and each family once. The family with the
  highest overflow (meter minus threshold) fires; ties go to catalog order.
  Two of its options are drawn with the run's generator.
- While a choice is pending the reward waits (`choose_reward` returns
  `EPIPHANY_PENDING`). The choice lasts the rest of the run.
- Mutations apply to the player only: `RunState.get_synergy_overrides()` is
  passed to `Synergy.evaluate` for the player's board (bar, panel, outlines,
  previews, shop hints) and to `Battle.set_synergy_overrides(SIDE_A, ...)`
  before the player's units are added. The enemy side keeps the catalog's
  config.
- Overrides are data: `{"milestone", "tier", "at"?, "modifiers"?}`, applied
  to a copy of the config, then resolved and shape-checked again; a bad one
  is an error and changes nothing.

## Save

The run save (version 3) holds `"epiphany"`: `meters` (family to int, every
family exactly once, 0..`ngo_meter_max`), `chosen` (ids in order),
`pending_family`, `pending_options` (two ids of that family) and
`last_stage`. A save is refused when an id is unknown or doubled, two
mutations share a family, the count (with the pending one) passes the
per-run limit or `last_stage` (one fires per stage at most, so no more can
have fired than the stage of the last one), or a pending choice is outside
the REWARD phase or of another stage. Thresholds are not saved: they come
from the seed.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `RunState.epiphanies` | property | The run's `EpiphanyTracker` (read it; change it only through RunState). |
| `RunState.choose_epiphany(option: int) -> Result` | method | Takes option 0 or 1 of the pending Kỳ Ngộ. |
| `RunState.get_synergy_overrides() -> Array` | method | The mutations as overrides (player side). |
| `RunState.epiphany_offered(family)` | signal | A Kỳ Ngộ fired after the battle (phase REWARD). |
| `RunState.epiphany_chosen(epiphany_id)` | signal | A choice was taken. |
| `EpiphanyTracker.get_meter / get_threshold / is_near / is_mutated / get_mutation` | methods | For the prep panel: "near" is one short of the threshold or at it, while the family can still fire (not mutated or pending, and fewer than `epiphanies_per_run` chosen). |
| `EpiphanyTracker.has_pending / get_pending_family / get_pending_options` | methods | The pending choice. |
| `Synergy.evaluate(pieces, overrides = [])` | method | Milestone entries now carry `thresholds` and `tier_modifiers` after the overrides. |
| `Battle.set_synergy_overrides(side, overrides)` | method | Before units are added; the side's config is rebuilt from the catalog's. |

## Prep UI

The "+N" panel (`UI/synergy_panel.gd`) marks a mutated milestone with a
gold seal and shows the mutation's text, in dark gold with its own seal, on
the mutated tier; the thresholds shown are the mutated ones. A family that
is near its threshold has its heading wobble.

## How to extend

Add an `EpiphanyData` sub-resource to the family's file: a `lower` names a
tier whose threshold can drop by one; a `variant` lists modifiers with
handlers that already exist (see [synergy.md](synergy.md)). Add its
`description_key` to `Locale/strings.csv`. The catalog validation checks it:
ids, kind, tier, a lowered threshold above the previous tier, and each
mutation run through `Synergy.evaluate([], [override])`, so a variant whose
modifiers the native rules refuse on a milestone (an unknown handler, a
formation-only scope) fails at load, naming the family file.

## Tests

`Tests/epiphany_test.gd`: families and kinds, the gain rules, thresholds
from the seed, one per stage (highest overflow first), four per run with
each family once, a `lower` and a `variant` changing `Synergy.evaluate` and
a battle (and not the enemy side), the RunState commands, and save/load
with mutations and a pending choice, including refused saves (more
mutations than stages played), "near" ending once the run's Kỳ Ngộ are used
up, and a variant with a milestone-illegal scope failing catalog
validation.

## Known limits

- The GDD's thresholds are 8..14; the game uses 4..7 so that a run of 12
  stages sees its four Kỳ Ngộ (the bot takes 3.9 per run). A loss with the
  top-damage family can fire a Kỳ Ngộ as early as stage 1.
- Line keys live on the family, not on each mutation.
