# Encounter

## Purpose

Road encounters ("Dọc đường"): after the reward of some stages the army
meets someone on the road and the player picks one of two cards (gold,
supply, morale, a free unit, free refreshes or a bet on the next battle).
They give the run more gold and small choices between battles. They are not
Kỳ Ngộ (`Docs/systems/epiphany.md`), which change how units fight.

## Layer and files

- Layer: game rules in GDScript (`Systems/Run/`, like the rest of the run);
  presentation in `Scenes/`.
- Code: `Systems/Run/encounter_data.gd` (`EncounterData`),
  `encounter_option.gd` (`EncounterOption`), `encounter_effect.gd`
  (`EncounterEffect`), `encounter_effects.gd` (`EncounterEffects`: the effect
  kinds, their text and what an option costs), `encounter_tracker.gd`
  (`EncounterTracker`: drawn, pending, the open bet, save data). `RunState`
  owns one tracker (`run.encounters`) and applies the effects.
- Presentation: `Scenes/Cutscene/encounter_cutscene.gd` (`EncounterCutscene`
  builds the `CutsceneData`), `Scenes/Run/run_interludes.gd`
  (`play_encounter()`), `Scenes/Run/run_screen.gd` (coin burst to the gold
  chip, the gifted unit's celebration), `UI/coin_burst.gd` (`CoinBurst`).
- Depends on: `Catalog` (`encounters`, units), `RunRules`
  (`encounter_stages`), the cutscene screen (`Docs/systems/cutscene.md`).

## Data

`Data/Encounters/<name>.tres`, one `EncounterData` each, listed in
`Data/catalog.tres` (`encounters`). The catalog needs at least as many
encounters as road stages, since a run never meets one twice.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | StringName | `encounter.<name>` |
| `name_key` | String | Its name, shown in the title "Dọc đường: <name>" |
| `speaker` | StringName | The figure met (a catalog unit id, or `ExtraFigures.SAGE_UNIT_ID`) |
| `line_keys`, `line_speakers` | Array | 2-3 lines; `SPEAKER_PLAYER` (0, the player's best piece, left) or `SPEAKER_STRANGER` (1, right) |
| `options` | `Array[EncounterOption]` | Exactly two; at least one always affordable |

`EncounterOption`: `title_key` (the card heading) and `effects`
(`Array[EncounterEffect]`, applied in order). `EncounterEffect`: `kind` and
`amount`:

| Kind | Amount | Effect |
| --- | --- | --- |
| `gain.gold` | -20..20, not 0 | Gold now (a cost when negative) |
| `gain.supply` | -20..20, not 0 | Supply now |
| `gain.morale` | -20..20, not 0 | Morale now (never above the maximum; a cost must leave at least 1) |
| `gain.free_unit` | 1..4 | A random non-boss unit of that cost on the bench (merges like a buy); needs a free bench slot |
| `gain.free_refreshes` | 1..5 | Free shop refreshes in the next preparation |
| `gain.bet` | 1..30 | Paid only if the next battle is won |

An option is refused (`get_encounter_refusal()`: `NOT_ENOUGH_GOLD`,
`NOT_ENOUGH_SUPPLY`, `NOT_ENOUGH_MORALE` or `BENCH_FULL`) when its costs,
summed per resource, are more than the run has, or a free unit has no bench
room. The card shows greyed out with "Không đủ để chọn"; touching it shakes
it (sound `block`) and changes nothing.

The eight encounters:

| Id | A | B |
| --- | --- | --- |
| `encounter.merchants` | +6 gold | +5 supply |
| `encounter.wager` | +4 gold | -3 gold, bet 10 |
| `encounter.deserters` | -3 gold, a cost-3 unit | +3 gold |
| `encounter.villagers` | +8 morale | +5 gold |
| `encounter.stranger` | 2 free refreshes, +2 gold | a cost-2 unit |
| `encounter.surplus` | -4 supply, +7 gold | +2 supply |
| `encounter.teacher` | +4 supply | +3 gold, +5 morale |
| `encounter.storehouse` | +8 gold, -6 morale | +3 gold |

## Flow

`RunRules.encounter_stages` (2, 4, 6, 8, 10) lists the road stages. After
the reward of one of them (won or lost), `choose_reward()` draws an
encounter the run has not met from the run's seeded RNG, the phase becomes
`ENCOUNTER` and `encounter_offered(id)` fires. The run screen saves, then
plays the encounter cutscene (road backdrop, title "Dọc đường: <name>").
`choose_encounter(option)` applies the effects, fires
`encounter_chosen(id, option)` and begins the next stage. Back in the
preparation the gold won flies as coins from the middle of the screen to
the gold chip (sound `coin` at launch and landing) and a gifted unit grows
in with stars and confetti (sound `merge`).

A bet (`gain.bet`) stays open through the next battle: `finish_battle()`
pays it on a win and drops it on a loss (`bet_settled(is_win, gold)`); the
banner shows a won bet as its own chip.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `RunState.encounters` | property | The `EncounterTracker`; read only |
| `RunState.choose_encounter(option) -> Result` | command | Takes option 0 or 1 of the pending encounter; refused like `get_encounter_refusal()` |
| `RunState.get_encounter_refusal(option) -> Result` | query | `OK`, `WRONG_PHASE`, `NOT_OFFERED` or what the run lacks |
| `RunState.has_free_bench_slot() -> bool` | query | Room for a free unit |
| `encounter_offered(id)`, `encounter_chosen(id, option)` | signals | Drawn; taken |
| `piece_gifted(piece_id)` | signal | A free unit landed on the bench |
| `bet_settled(is_win, gold)` | signal | The open bet was paid (or lost) |
| `EncounterTracker.get_pending()`, `get_drawn_ids()`, `get_bet_gold()` | queries | The pending encounter, those met, the open bet |
| `EncounterEffects.describe_option(option) -> String` | static | The card text, one line per effect |
| `EncounterCutscene.build(run) -> CutsceneData` | static | The cutscene of the pending encounter, with disabled cards marked |
| `RunInterludes.play_encounter(chosen, then) -> bool` | method | Plays it; `chosen` runs when a card is taken, `then` after the wipe |

## Save

The run save (version 4, `Docs/systems/run.md`) holds `"encounter":
{"drawn": [...ids], "pending": "<id or empty>", "bet_gold": n}` and the phase
`"encounter"`. A run closed during the cutscene resumes on the same
encounter. A save is refused when an id is unknown or repeated, the number
drawn does not match the road stages before the stage (plus the stage
itself in the `encounter` phase), a pending encounter is not the last one
drawn or appears outside the `encounter` phase (which must be at a road
stage, never the final one), or a bet is open outside the preparation right
after a road stage or is not one of the last encounter's bets.

## How to extend

- **Add an encounter:** add `Data/Encounters/<name>.tres` with two options
  (one always affordable), add it to `encounters` in `Data/catalog.tres`,
  add its name, card titles and lines to `Locale/strings.csv` (vi and en).
  `Catalog.validate()` checks it.
- **Add an effect kind:** add it to `EncounterEffects.KINDS` (text key,
  sign, range), give it a handler in `RunState._get_effect_handlers()` and,
  if it can be refused, a check in `EncounterEffects.get_option_refusal()`;
  give it an icon in `EncounterCutscene.ICONS`.
- **Change the road stages:** `encounter_stages` in
  `Data/Rules/run_rules.tres`.

## Tests

`Tests/encounter_test.gd` (headless, in CI): the data, seeded draws without
repeats, every effect kind, refused options (gold, supply, morale, full
bench) and their greyed cards, the bet paid only after a won battle, saves
with a pending encounter and with an open bet, tampered saves refused, the
win-streak bonus and the loot reward. `Tests/run_flow_test.gd` plays the
scene: a reward at stage 2 opens the saved encounter cutscene, a real
screen touch (through `Input.parse_input_event`) takes a card and "Ra trận"
of stage 3 takes the next press; a run closed at an encounter resumes on
it, and a touch on a greyed card is refused.

## Known limits

- Encounters are drawn uniformly; there is no weighting by stage yet.
- The bot always takes the option with the most gold now (a bet counts
  half), so balance numbers assume a gold-minded player.
