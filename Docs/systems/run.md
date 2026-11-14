# Run

## Purpose

A run is 12 stages against fixed enemy line-ups. Before each battle the
player buys units from a shop, keeps them on a bench, places them on the
board and merges copies into higher stars; after it they pick a reward.
`RunState` holds every rule of a run and its save. It does not draw anything
or run battles: the run screen plays each battle with `Battle` and
`BattlePlayback` and reports the result back.

## Layer and files

- Layer: the rules are pure-data GDScript (`Systems/Run/`), like `Lineup`:
  no nodes, no clock, and one seeded `RandomNumberGenerator`, so a seed
  always gives the same shops and rewards. Battles stay in the native
  `Battle`. The screens are presentation (`Scenes/Run/`, `Scenes/Title/`).
- `Systems/Run/`: `run_state.gd` (`RunState`), `run_roster.gd`
  (`RunRoster`, pieces and placement rules, used only by `RunState`),
  `run_piece.gd` (`RunPiece`), `shop.gd` (`Shop`), `run_rules.gd`
  (`RunRules`), `stage_data.gd` (`StageData`), `run_save.gd` (`RunSave`),
  `run_settings.gd` (`RunSettings`).
- `Systems/Content/battle_factory.gd` (`BattleFactory`): makes a `Battle`
  from the catalog's rules and adds line-ups; shared with the sandbox.
- `Scenes/Run/`: `run_screen.gd` (`RunScreen`), `run_layout.gd`
  (`RunLayout`), `run_hud.gd` (`RunHud`), `prep_controller.gd`
  (`PrepController`), `piece_views.gd` (`PieceViews`), `reward_screen.gd`
  (`RewardScreen`), `end_screen.gd` (`EndScreen`).
- `Scenes/Title/title_screen.gd` (`TitleScreen`).
- `UI/`: `shop_bar.gd`, `shop_card.gd`, `bench_bar.gd`, `sell_zone.gd`,
  `cost_button.gd`, `resource_chip.gd`, `icon_painter.gd`, `timer_badge.gd`,
  `prep_timer.gd`, `reward_card.gd`, `confetti_burst.gd`.
- `Tools/run_bot.gd`: the balance bot (not exported).
- Depends on: `Catalog` (units, `run_rules`, `stages`), `Battle`,
  `BattlePlayback`, `BoardView`, `UnitView`, `LineupViews`, `PieceDrag`.

## Data

`Data/Rules/run_rules.tres` (`RunRules`) holds every number; tuning never
touches code. `Catalog.validate()` checks it with `RunRules.validate()`.

| Field | Value | Meaning |
| --- | --- | --- |
| `start_morale`, `max_morale` | 60, 60 | Morale is the run's life; 0 loses the run |
| `start_gold`, `start_supply`, `start_level` | 10, 0, 3 | At the start of stage 1, before its income |
| `max_level` | 9 | Board capacity is the level, at most `max_board_units` (8) |
| `bench_slots` | 6 | Bench size |
| `max_star`, `copies_to_merge` | 3, 3 | Three copies of one unit and star make one of the next star |
| `legend_cost`, `legend_copies_to_merge`, `legend_max_star`, `legend_board_limit` | 5, 2, 2, 2 | Cost-5 units merge from two copies, stop at 2 stars, and at most two stand on the board |
| `shop_slots`, `refresh_gold` | 5, 2 | Offers per roll and the refresh price |
| `supply_pack_gold`, `supply_pack_amount` | 4, 4 | "Mua lương": 4 gold for 4 supply |
| `supply_to_next` | 2, 4, 6, 10, 14, 20 | Supply to go from level 3 to 4, ... 8 to 9 |
| `shop_odds` | one row per level 3..9 | Percent of cost 1..5 per slot (level 3: 75/25/0/0/0; level 9: 10/18/30/32/10) |
| `stage_income` | 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 10 | Gold at the start of each stage's preparation |
| `stage_supply`, `winter_from_stage`, `winter_supply` | 2, 9, 1 | Supply per preparation; 1 from stage 9 |
| `enemy_counts` | 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8 | Enemy units per stage, checked against `Data/Stages/` |
| `win_gold`, `win_supply` | 1, 2 | Paid for a won battle |
| `loss_morale_base`, `loss_morale_per_enemy` | 6, 2 | A loss costs 6 + 2 per enemy still alive |
| `rest_morale`, `hunt_supply` | 15, 6 | Rewards "Nghỉ ngơi" and "Săn bắn" (morale never above the maximum) |
| `black_market_levels`, `black_market_free_refreshes` | 1, 1 | "Chợ đen": the next stage's shop rolls one level higher, with one free refresh |
| `rewards_after_loss` | 2 | Rewards offered after a loss (a win offers all three) |

Selling gives back `cost x star` gold, plus `star` supply once the piece has
fought in a battle.

`Data/Stages/stage_01.tres` .. `stage_12.tres` (`StageData`): `id`
(`stage.01` ..), `name_key` (`STAGE_01` ..) and `slots`, the enemy line-up
as `LineupSlot`s of side B in local (col, rank). They are listed in stage
order in `Data/catalog.tres` (`stages`), so nothing scans folders.
`StageData.validate()` checks unknown units, cells off the half, doubled
cells and the unit count. Stage 12 is "Đại Trận Lạc Hồng", with the legend
Lạc Hồng at 2 stars.

## Stage flow

`start()` begins stage 1's preparation. Each preparation pays the stage's
gold and supply and rolls the shop (`stage_started`). `begin_battle()` ends
it; the screen plays the battle and calls `finish_battle(is_win,
enemies_alive)`. A win pays gold and supply; a loss costs morale. Morale at
0 ends the run (`LOST`), a win at stage 12 ends it (`WON`); otherwise the
run offers rewards (`REWARD`) and `choose_reward()` begins the next stage.
A loss at stage 12 repeats it, without gold or supply income, and the
rest reward is not offered there, so morale only falls and the repeats end. Pieces always stay
with the player between stages.

## Public API

`RunState` (RefCounted). Every command returns a `Result`: `OK`,
`NOT_ENOUGH_GOLD`, `NOT_ENOUGH_SUPPLY`, `BENCH_FULL`, `BOARD_FULL`,
`LEGEND_LIMIT`, `BAD_TARGET`, `NO_PIECE`, `EMPTY_SLOT`, `MAX_LEVEL`,
`WRONG_PHASE` or `NOT_OFFERED`. A refused command changes nothing. Board
cells are local (col, rank) of side A.

| Member | Kind | Description |
| --- | --- | --- |
| `RunState.new(catalog, seed)`, `start()` | methods | A new run; `start()` begins stage 1 |
| `phase`, `stage`, `morale`, `gold`, `supply`, `level`, `stages_cleared`, `run_seed` | fields | Read only for callers |
| `buy(shop_slot)` | command | Onto the first free bench slot; a full bench is fine if the purchase merges at once |
| `buy_to(shop_slot, bench_slot, cell)` | command | Onto a given bench slot or board cell (the other unset) |
| `refresh_shop()`, `buy_supply()`, `level_up()` | commands | The three economy buttons |
| `sell(piece_id)` | command | Removes the piece, pays `get_sell_value()` |
| `move_to_board(piece_id, cell)`, `move_to_bench(piece_id, slot)` | commands | Move, or swap with the piece there |
| `begin_battle()`, `finish_battle(is_win, enemies_alive)` | commands | Around a battle |
| `choose_reward(reward)` | command | `Reward.REST`, `HUNT` or `BLACK_MARKET`, if offered |
| `get_piece`, `get_pieces`, `get_bench_piece`, `get_board_piece`, `get_board_pieces`, `get_board_count`, `get_capacity` | queries | Pieces and places |
| `get_shop_offers`, `get_refresh_cost`, `get_level_up_cost`, `get_sell_value`, `would_merge` | queries | Shop and prices |
| `get_stage_data`, `get_board_slots`, `get_reward_options`, `is_black_market_active` | queries | Stage, battle slots, rewards |
| `to_save_data()`, `load_save_data(data) -> bool` | methods | See the save format below |
| `gold_changed(gold, delta)`, `supply_changed(supply, delta)`, `morale_changed(morale, delta)`, `level_changed(level)` | signals | Each change, with its size for the chips' animation |
| `shop_rolled()`, `piece_bought(piece_id, shop_slot)`, `piece_moved(piece_id)`, `piece_sold(piece_id, gold, supply)`, `pieces_merged(result_id, consumed_ids)` | signals | One per change; a purchase that merges sends `piece_bought` then `pieces_merged` |
| `phase_changed(phase)`, `stage_started(stage)`, `battle_resolved(is_win, gold_delta, supply_delta, morale_delta)` | signals | Stage flow |

`RunSave` (static): `save(run)`, `load_run(catalog) -> RunState` (null
without a usable save), `has_save()`, `delete()`. `RunSettings` (static):
`load_prep_seconds()`, `save_prep_seconds(seconds)`,
`next_prep_seconds(seconds)` over 60, 90 and 0 (unlimited).

`Main`: `show_title()`, `start_new_run(seed = -1) -> RunScreen`,
`continue_run() -> RunScreen`, `open_sandbox() -> SandboxScreen`.

`RunScreen` (Main sets `run`, `sim_clock` and `prep_seconds` before adding
it): `start_battle() -> bool` ("Ra trận", or the timer ran out),
`continue_after_battle()` (the banner's "Tiếp tục"), `cycle_speed()`,
`press_refresh()`, `press_buy_supply()`, `press_level_up()`, the fields
`controller`, `playback`, `reward_screen`, `layout`, `is_saving` and
`last_battle_won`, and the signal `run_finished(run)`.

`PrepController`: `tap_shop_card(slot)`, `tap_bench_slot(slot)`,
`tap_cell(cell)`, `tap_sell_zone()`, `drop_shop_card(slot, drop_point)`,
`drop_piece(piece_id, pointer, drop_point)`, `deselect()`, `is_dragging()`,
`is_enabled`; signals `info_requested(unit, star)` and
`action_refused(result)`. Gestures and tests call the same methods. Board
cells here are global.

## Input and screens

- Tap a shop card to select it (targets light up), then tap a bench slot or
  board cell; tap the selected card again to buy it onto the bench. Or drag
  the card there.
- Tap or drag a piece to move it between bench and board, or swap. While a
  piece is selected or dragged, the shop turns into the sell zone with its
  value.
- A refused command shakes the button or flashes the lacking resource; a
  full bench flashes red.
- Long press (or right click) shows a unit's stats, also during a battle.
- The preparation timer (60 s, 90 s or none, set on the title screen)
  starts the battle when it runs out. It pauses when the window loses focus,
  the app is paused, or the browser tab is hidden.
- Three cards (two after a loss) offer the reward; the end screen shows the
  result, stages cleared and the board's units.

## Save format

`user://run_save.json` (the browser's IndexedDB on the web), written with
`FileAccess` at the start of a run and after every reward, deleted when the
run ends. A broken file, a missing key, an unknown unit or an unknown
version is warned about once; "Chơi tiếp" then stays on the title, and
"Ván mới" overwrites the file.

```json
{
  "version": 1,
  "seed": "4242", "rng_state": "1234567890123",
  "stage": 2, "stages_cleared": 1, "morale": 60,
  "gold": 9, "supply": 4, "level": 3, "next_piece_id": 6,
  "pieces": [{"id": 1, "unit_id": "unit.archer", "star": 1, "has_fought": true,
              "bench": -1, "col": 3, "rank": 1}],
  "shop": ["unit.archer", "", "unit.spearman", "unit.shield_guard", "unit.wolf_blade"],
  "black_market": false, "free_refreshes": 0
}
```

`seed` and `rng_state` are strings because JSON numbers are doubles. A
piece has a `bench` slot (-1 when on the board) or a board `col` and
`rank`. A run is always saved in its preparation, so loading resumes there
with the same shop. Raising `version` makes older saves unusable: add a
migration in `RunSave.load_run()` when the format changes.

## Balance bot

`Tools/run_bot.gd` plays whole runs with a greedy player: it buys the
best-value units, merges, levels up when it can, keeps the strongest units
on the board, picks Rest at 40 morale or less, else Hunt while levels
remain, else the black market, and gives a run up after 60 battles. Run it after changing stages or rules:

```
godot --headless --path . --script res://Tools/run_bot.gd -- 300 1
```

Result of 300 runs from seed 1 with the current data. "First try" counts
each run's first battle at that stage; stage 12 is retried after a loss.

| Stage | First try win % | Avg morale after |
| --- | --- | --- |
| 1-4 | 99-100 | 60 |
| 5 | 96 | 59.5 |
| 6 | 82 | 57.6 |
| 7 | 73 | 54.9 |
| 8 | 72 | 52.8 |
| 9 | 54 | 49.5 |
| 10 | 55 | 46.4 |
| 11 | 49 | 43.6 |
| 12 | 31 (9 per attempt over 954 attempts) | 20.9 |

Run win rate 30.0% (90 of 300), 9.1 stages cleared on average. A person who reads the
enemy line-up and places units against it does better than the bot.

## Log events

None. Data problems are reported by `Catalog.validate()` with `push_error`
(`Run: ... shop_odds ...`, `Run: stage ... has 7 units, expected 8`); save
and settings problems with one `push_warning` each (`Run: could not write
...`).

## How to extend

- **Change a number:** edit `Data/Rules/run_rules.tres`, then run the tests
  and the bot.
- **Change a stage:** edit its `slots` in `Data/Stages/stage_NN.tres` (side
  B, local col 1-7, rank 1-4 with 1 the front); the unit count must match `enemy_counts`.
- **Add a stage:** add `Data/Stages/stage_13.tres` with `id = &"stage.13"`
  and `name_key = "STAGE_13"`, list it at the end of `stages` in
  `Data/catalog.tres`, raise `stage_count` and add one entry to
  `stage_income` and `enemy_counts` in the rules, and add `STAGE_13` to
  `Locale/strings.csv`. `Catalog.validate()` reports anything missing.
- **Add a reward:** add it to `RunState.Reward` and `REWARD_IDS`, apply it
  in `choose_reward()`, give it a look in `RewardScreen._looks()` and its
  `REWARD_*` strings.

## Tests

- `Tests/run_test.gd`: the rules without screens: the catalog's rules and
  stages, start values, a seed's shops, buying and selling, refresh, refused
  purchases, merges on the bench and board and chained, legends, levels,
  moves and swaps, income, battle results, rewards, the black market,
  stage 12 repeats, a lost run, the save round trip and broken saves.
- `Tests/run_flow_test.gd`: stage 1 through the real screens: Main starts a
  run, units are bought and placed with the controller's taps, the battle
  plays at x4, input is refused meanwhile, "Tiếp tục" opens the rewards and
  one starts stage 2, which is in the save. It deletes the save at the end.

```
godot --headless --path . --script res://Tests/run_test.gd
godot --headless --path . --script res://Tests/run_flow_test.gd
```

## Known limits

- Every shop roll is independent: there is no shared pool of copies.
- Board cells are about 80 px wide at the 720 base, below the 88 px target
  for touch, so that the 7 x 8 board, bench and shop fit a portrait phone.
- The first stages are easy for anyone who places their units: with
  cost 1-2 one-star enemies, the bot wins stages 1-4 almost always.
