# Run

## Purpose

A run is 12 stages against fixed enemy line-ups. Before each battle the
player buys units from a shop, keeps them on a bench, places them on the
board and merges copies into higher stars; after it they pick a reward.
`RunState` holds every rule of a run and its save, including the Kỳ Ngộ
meters and mutations ([epiphany.md](epiphany.md)). It does not draw anything
or run battles: the run screen plays each battle with `Battle` and
`BattlePlayback` and reports the result back. Stage 12 holds the boss Cự
Nham ([boss.md](boss.md)).

## Layer and files

- Layer: the rules are pure-data GDScript (`Systems/Run/`), like `Lineup`:
  no nodes, no clock, and one seeded `RandomNumberGenerator`, so a seed
  always gives the same shops and rewards. Battles stay in the native
  `Battle`. The screens are presentation (`Scenes/Run/`, `Scenes/Title/`).
- `Systems/Run/`: `run_state.gd` (`RunState`), `run_roster.gd`
  (`RunRoster`, pieces and placement rules, used only by `RunState`),
  `run_piece.gd` (`RunPiece`), `shop.gd` (`Shop`), `run_rules.gd`
  (`RunRules`), `stage_data.gd` (`StageData`), `run_save.gd` (`RunSave`),
  `save_reader.gd` (`SaveReader`, typed reads of save fields),
  `run_save_fields.gd` (`RunSaveFields`, reads and checks a save's
  top-level fields for `load_save_data()`),
  `run_settings.gd` (`RunSettings`), and the Kỳ Ngộ files
  `epiphany_tracker.gd`, `epiphany_battle.gd`, `epiphany_data.gd`,
  `epiphany_family.gd`.
- `Systems/Content/battle_factory.gd` (`BattleFactory`): makes a `Battle`
  from the catalog's rules and adds line-ups; shared with the sandbox.
- `Scenes/Run/`: `run_screen.gd` (`RunScreen`), `run_layout.gd`
  (`RunLayout`), `run_hud.gd` (`RunHud`), `prep_controller.gd`
  (`PrepController`), `piece_views.gd` (`PieceViews`), `reward_screen.gd`
  (`RewardScreen`), `end_screen.gd` (`EndScreen`), `synergy_hud.gd`
  (`SynergyHud`) and `lineup_synergy.gd` (`LineupSynergy`), see
  [Synergy](synergy.md); `boss_hud.gd` (`BossHud`, see [Boss](boss.md));
  `run_interludes.gd` (`RunInterludes`, the cutscenes, see
  [Cutscene](cutscene.md)).
- `Scenes/Title/title_screen.gd` (`TitleScreen`), `how_to_screen.gd`
  (`HowToScreen`, "Cách chơi").
- `UI/`: `shop_bar.gd`, `shop_card.gd`, `bench_bar.gd`, `sell_zone.gd`,
  `cost_button.gd`, `resource_chip.gd`, `icon_painter.gd`, `timer_badge.gd`,
  `prep_timer.gd`, `reward_card.gd`, `confetti_burst.gd`, `synergy_bar.gd`,
  `synergy_panel.gd`, `epiphany_seal.gd`, `mute_button.gd`, `boss_badge.gd`,
  `boss_card.gd`, `boss_bar.gd`.
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
| `enemy_counts` | 2, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 7 | Enemy units per stage, checked against `Data/Stages/` (stage 12: the boss and 6 guards) |
| `win_gold`, `win_supply` | 1, 2 | Paid for a won battle |
| `streak_gold_wins`, `streak_gold_bonus` | 2, 4; 1, 2 | Win streak: from the 2nd win in a row +1 gold more per win, from the 4th +2 (`get_streak_bonus()`); a loss starts over |
| `loot_gold` | 5 | Reward "Kho báu": gold now |
| `encounter_stages` | 2, 4, 6, 8, 10 | Stages whose reward is followed by a road encounter ([encounter.md](encounter.md)); sorted, each once, in 1..`stage_count` - 1, never `boss_stage` or the story stage before it |
| `loss_morale_base`, `loss_morale_per_enemy` | 6, 2 | A loss costs 6 + 2 per enemy still alive |
| `rest_morale`, `hunt_supply` | 15, 6 | Rewards "Nghỉ ngơi" and "Săn bắn" (morale never above the maximum) |
| `black_market_levels`, `black_market_free_refreshes` | 1, 1 | "Chợ đen": the next stage's shop rolls one level higher, with one free refresh |
| `rewards_after_win`, `rewards_after_loss` | 3, 2 | Rewards offered, drawn from rest, hunt, black market and loot with the run's RNG (rest never at the final stage) |
| `boss_stage`, `boss_reveal_stage` | 12, 6 | The stage with exactly one boss; from which stage the prep shows the boss badge |
| `ngo_*`, `epiphanies_per_run` | see [epiphany.md](epiphany.md) | Kỳ Ngộ numbers |

Selling gives back `cost x star` gold, plus `star` supply once the piece has
fought in a battle.

`Data/Stages/stage_01.tres` .. `stage_12.tres` (`StageData`): `id`
(`stage.01` ..), `name_key` (`STAGE_01` ..) and `slots`, the enemy line-up
as `LineupSlot`s of side B in local (col, rank). They are listed in stage
order in `Data/catalog.tres` (`stages`), so nothing scans folders.
`StageData.validate()` checks an empty `name_key`, unknown units, cells off
the half, doubled cells and the unit count, and the boss count (one at `boss_stage`, none elsewhere).
Stages 1-4 are all 1-star; stages 5-8 have one 2-star enemy each and the
rest 1-star; stages 9-11 are mostly 2-star. Stage 12 is "Đại Trận Lạc Hồng": the boss Cự Nham with six 2-star guards
(three marksmen, the legend Lạc Hồng, an iron guard and a wolf shield).
The shop never offers a boss and a save holding one is refused. From stage 4 the enemies stand in formations and
reach milestones the player can read during the preparation (their outlines
are drawn on the enemy half): 4 Hộ Pháp and Thương Che Cung, 5 Hạc Dực
and Thương Che Cung, 6 Tường Khiên and Hộ Pháp, 7 Song Kiếm and Hộ Pháp
(wolf-folk 5), 8 Phương Trận and two Hộ Pháp, 9 and 10 Tường Khiên (with
a wolf-folk middle in 9) and Hộ Pháp, 11 Mũi Giáo and Mưa Tên, 12 Mưa Tên,
Tường Khiên and Hộ Pháp; Phương Trận, Ngư Lân and Tam Tài often come along.

## Stage flow

`start()` begins stage 1's preparation. Each preparation pays the stage's
gold and supply and rolls the shop (`stage_started`). `begin_battle()` ends
it; the screen plays the battle and calls `finish_battle(is_win,
enemies_alive, piece_damage)`. A win pays gold and supply; a loss costs
morale. Morale at 0 ends the run (`LOST`), a win at stage 12 ends it
(`WON`); otherwise the run offers rewards (`REWARD`), adds the battle's Ngộ
(which may fire a Kỳ Ngộ: `epiphany_offered`, and the reward waits for
`choose_epiphany()`), and `choose_reward()` begins the next stage, or,
after a road stage (`encounter_stages`), opens a road encounter (phase
`ENCOUNTER`, see [encounter.md](encounter.md)) whose `choose_encounter()`
begins it. Each win in a row past the first pays the streak bonus
(`streak_paid`); an open bet is settled by the next battle (`bet_settled`).
A loss at stage 12 repeats it, without gold or supply income, and the
rest reward is not offered there, so morale only falls and the repeats end. Pieces always stay
with the player between stages.

## Public API

`RunState` (RefCounted). Every command returns a `Result`: `OK`,
`NOT_ENOUGH_GOLD`, `NOT_ENOUGH_SUPPLY`, `BENCH_FULL`, `BOARD_FULL`,
`LEGEND_LIMIT`, `BAD_TARGET`, `NO_PIECE`, `EMPTY_SLOT`, `MAX_LEVEL`,
`WRONG_PHASE`, `NOT_OFFERED`, `EPIPHANY_PENDING` or `NOT_ENOUGH_MORALE`
(an encounter cost). A refused command
changes nothing. Board
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
| `begin_battle()`, `finish_battle(is_win, enemies_alive, piece_damage = {})` | commands | Around a battle; `piece_damage` maps board piece ids to the damage they dealt (Kỳ Ngộ) |
| `choose_epiphany(option)` | command | Option 0 or 1 of the pending Kỳ Ngộ |
| `choose_reward(reward)` | command | `Reward.REST`, `HUNT`, `BLACK_MARKET` or `LOOT`, if offered; `EPIPHANY_PENDING` while a Kỳ Ngộ waits |
| `choose_encounter(option)`, `get_encounter_refusal(option)`, `encounters`, `has_free_bench_slot()` | command, queries | Road encounters, see [encounter.md](encounter.md) |
| `win_streak` | field | Battles won in a row |
| `encounter_offered(id)`, `encounter_chosen(id, option)`, `piece_gifted(piece_id)`, `streak_paid(streak, gold)`, `bet_settled(is_win, gold)` | signals | Encounter, free unit, streak bonus, bet |
| `epiphanies`, `get_synergy_overrides()`, `is_boss_stage()` | field, queries | The Kỳ Ngộ tracker, the player's mutations as Synergy overrides, the boss stage |
| `epiphany_offered(family)`, `epiphany_chosen(epiphany_id)` | signals | A Kỳ Ngộ fired; one was taken |
| `get_piece`, `get_pieces`, `get_bench_piece`, `get_board_piece`, `get_board_pieces`, `get_board_count`, `get_capacity` | queries | Pieces and places |
| `get_shop_offers`, `get_refresh_cost`, `get_level_up_cost`, `get_sell_value`, `would_merge` | queries | Shop and prices |
| `preview_board(piece_id, unit_id, cell, board) -> Result` | query | The board (copies, into `board`) as buying a card of `unit_id` onto `cell`, or with an empty `unit_id` moving `piece_id` there, would leave it, worked out on a copy of the roster with the same rules (a merging purchase ignores the cell, capacity, legend limit); the run is unchanged. The drag preview uses it |
| `get_stage_data`, `get_board_slots`, `get_reward_options`, `is_black_market_active` | queries | Stage, battle slots, rewards |
| `to_save_data()`, `load_save_data(data) -> bool`, `can_save()` | methods | See the save format below; `can_save()` is true in `PREP`, `REWARD` and `ENCOUNTER` |
| `gold_changed(gold, delta)`, `supply_changed(supply, delta)`, `morale_changed(morale, delta)`, `level_changed(level)` | signals | Each change, with its size for the chips' animation |
| `shop_rolled()`, `piece_bought(piece_id, shop_slot)`, `piece_moved(piece_id)`, `piece_sold(piece_id, gold, supply)`, `pieces_merged(result_id, consumed_ids)` | signals | One per change; a purchase that merges sends `piece_bought` then `pieces_merged` |
| `phase_changed(phase)`, `stage_started(stage)`, `battle_resolved(is_win, gold_delta, supply_delta, morale_delta)` | signals | Stage flow |
| `prep_changed()` | signal | After every successful preparation command (buy, sell, move, refresh, supply, level up); the run screen saves on it |

`RunSave` (static): `save(run)` (refused with `push_error` outside `PREP`
and `REWARD`), `load_run(catalog) -> RunState` (null
without a usable save), `has_save()`, `delete()`; each takes an optional
file path and otherwise uses the static `RunSave.path`
(`user://run_save.json`), which only tests change. `RunSettings` (static):
`load_prep_seconds()`, `save_prep_seconds(seconds)`,
`next_prep_seconds(seconds)` over 60, 90 and 0 (unlimited), `load_muted()`,
`save_muted(muted)`. Both settings share `user://settings.json` (a save
rewrites the file with the other setting kept); the static
`RunSettings.path` moves it, and the tests that open screens set it.

`Main`: `show_title()`, `start_new_run(seed = -1) -> RunScreen`,
`continue_run() -> RunScreen` (null, the save deleted and the title shown
again when the save cannot be used), `open_sandbox() -> SandboxScreen`.

`RunScreen` (Main sets `run`, `sim_clock` and `prep_seconds` before adding
it; a run in `REWARD` opens on its pending Kỳ Ngộ cutscene, if any, then the
reward cards): `start_battle() -> bool` ("Ra trận", or the timer ran out),
`continue_after_battle()` (the banner's "Tiếp tục"), `cycle_speed()`,
`press_refresh()`, `press_buy_supply()`, `press_level_up()`, the fields
`controller`, `playback`, `reward_screen`, `layout`, `synergy_hud`,
`boss_hud`, `interludes`, `is_saving` and `last_battle_won`, and the signal
`run_finished(run)`. It builds each battle with
`Battle.set_synergy_overrides(SIDE_A, run.get_synergy_overrides())` before
adding units, and reads each piece's `damage_dealt` at the end.

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
  value. A drag that starts in the gap between bench slots picks up
  nothing. The sell zone and the reward cards use `PointerGesture` with
  long press turned off (`is_long_press_enabled = false`): any release
  that ends on them acts, whether a quick tap, a press held any time, or a
  finger that slid before lifting; a release off them or a cancelled touch
  does nothing.
- A refused command shakes the button or flashes the lacking resource; a
  full bench flashes red.
- Long press (or right click) shows a unit's stats, also during a battle,
  with the class and race milestones it counts toward ("Cung 3/4": units
  counted on its side and the next threshold).
- The info row under the board, one row: the Hợp Lực ring (points, a thin
  gold arc toward the next tier), up to two chips naming active formations
  in their colours, a "+N" pill (more formations and milestones reached;
  dots when there is nothing more), and the units-on-board counter. A tap on
  the row opens the synergy panel (formations with level and effect,
  formations one unit short, class and race milestones, Hợp Lực tiers).
- Formations are outlined on the board (see [Formation](formation.md));
  a new one runs a light around its outline and stamps its name.
- While a card or piece is dragged over the player's half, the outlines,
  chips and ring show what the drop would make ("9 → 10", green when more,
  red when less), evaluated only when the cell under the drag changes.
- A shop card whose purchase would reach a new milestone tier or is the
  class a formation one unit short needs shows a jade link badge.
- "Ra trận" starts with a 0.8 s roll call: each formation's outline flashes
  and its name stamps in, the ring bounces. A formation that loses a member
  shatters its outline.
- The preparation timer (60 s, 90 s or none, set on the title screen)
  starts the battle when it runs out. It pauses when the window loses focus,
  the app is paused, or the browser tab is hidden. Its badge has a gold
  ring that turns red and pulses in the last 10 seconds.
- During a battle the same badge counts down the battle's time limit in a
  different look, so it is not mistaken for the preparation timer: a steel
  ring on a darker face, steel digits, a small crossed-swords mark at its
  lower right, and no red pulse (`TimerBadge.show_battle_seconds()`).
- Three cards (two after a loss) offer the reward, after the Kỳ Ngộ
  cutscene when one fired. After stages 2, 4, 6, 8 and 10 the road
  encounter cutscene follows (see [encounter.md](encounter.md)). The result
  banner shows the streak bonus and a won bet as chips under the result
  ("+N chuỗi thắng", "+N cược thắng"), each popping in with a coin sound;
  gold from an encounter, the streak or the loot reward flies as coins to
  the gold chip in the next preparation. The chip holds that gold back
  from the moment it arrives (`RunHud.hold_gold()`) and counts up to it
  when the coins land (`release_gold()`), so it never shows the new total
  early and drops back. The end screen shows the result, stages cleared
  and the board's units.
- The top bar has the sound switch (`MuteButton`) and, from stage 6, the
  boss badge; in the boss battle the boss bar takes the title's place.
- Every control keeps at least 24 px (`RunLayout.SAFE_EDGE_PX`) from the top
  and bottom edges of the 720 x 1280 base: the top bar's buttons start at
  y 28 and "Ra trận" ends 33 px above the bottom. The sandbox's top bar and
  the title follow the same rule.
- The title screen's "Cách chơi" shows four tips; its first tap unlocks
  audio on the web.

## Save format

`user://run_save.json` (the browser's IndexedDB on the web), written with
`FileAccess` at the start of a run, after every successful preparation
command (`prep_changed`), when a battle ends in the reward choice, the
moment a Kỳ Ngộ card is taken, when a road encounter opens, and after
every reward or encounter card (the reward that
leads to stage 12 only once the story scene has ended; see
[cutscene.md](cutscene.md)). It is deleted as soon as the run is won or lost (when
the result banner appears). So closing the game at any point after a
battle cannot replay it: a non-final battle resumes on its reward cards,
with its result (morale, gold, supply) already applied; and a refresh or
purchase cannot be undone by reloading. A save that cannot be used is
warned about once (`Run: ... ignored`) and deleted when "Chơi tiếp" fails,
so the title then offers only "Ván mới". The whole save is refused, never
repaired, when:

- it is not JSON, any key the game writes is missing (all are required),
  or a field has the wrong JSON type (numbers must be whole, `seed` and
  `rng_state` decimal strings that fit 64 bits, `black_market`,
  `black_market_next` and `has_fought` booleans, `phase`, ids and reward ids strings);
- `version` is not 4; `phase` is not `"prep"`, `"reward"` or
  `"encounter"` (never at the final stage); `stage` is
  outside 1..`stage_count`, `level` outside `start_level`..`max_level`,
  `morale` outside 1..`max_morale`, `gold` or `supply` negative,
  `stages_cleared` negative or past the stages fought (below `stage` in
  `prep` and at the final stage; at most `stage` in `reward`, where the
  stage just won already counts; the same in `encounter`); `win_streak`
  is negative or above `stages_cleared`; `black_market_next` (a black
  market taken at a road stage, waiting for the next preparation) is true
  outside `encounter`;
- `rewards` is not empty in `prep` or `encounter`; in `reward` it does
  not hold `rewards_after_win` rewards (after a win) or
  `rewards_after_loss` of them (after a loss; at
  the final stage at most the two left without the rest),
  holds an unknown or doubled id, or offers the rest at the final stage;
- the shop has more offers than slots, or an unknown unit;
- a piece misses a key, has an unknown unit, an id below 1 or used twice,
  a star outside 1..`max_star` (`legend_max_star` for cost 5), a `bench`
  other than -1 or a slot, or (with `bench` -1) a cell off the half; two
  pieces share a cell or a slot; the board holds more than the level's
  capacity or more than `legend_board_limit` legends; or a group of copies
  could still merge. The game merges right after every purchase, so such a
  group means the file was not written by it; refusing is simpler and safer
  than merging on load;
- a piece or offer is a boss unit;
- `epiphany` is missing or impossible (see [epiphany.md](epiphany.md#save));
- `encounter` is missing or impossible (see [encounter.md](encounter.md#save)).

A bench piece's `col` and `rank` must be present as whole numbers, but
their values are ignored (it has no cell), and `free_refreshes` is clamped
to what the rules give (`black_market_free_refreshes` on a black-market
stage, plus the free refreshes of the option taken at the encounter just
before, else 0). Fields are read through `SaveReader`, so a hostile file
never raises a script error.

```json
{
  "version": 4,
  "seed": "4242", "rng_state": "1234567890123", "phase": "reward",
  "stage": 2, "stages_cleared": 1, "morale": 48,
  "gold": 9, "supply": 4, "level": 3, "next_piece_id": 6,
  "pieces": [{"id": 1, "unit_id": "unit.archer", "star": 1, "has_fought": true,
              "bench": -1, "col": 3, "rank": 1}],
  "shop": ["unit.archer", "", "unit.spearman", "unit.shield_guard", "unit.wolf_blade"],
  "black_market": false, "black_market_next": false, "free_refreshes": 0,
  "rewards": ["reward.hunt", "reward.black_market"], "win_streak": 0,
  "epiphany": {"meters": {"milestone.class_shield": 3, "...": 0},
               "chosen": ["epiphany.archer_lower_2"],
               "pending_family": "", "pending_options": [], "last_stage": 1},
  "encounter": {"drawn": [], "pending": "", "taken": -1, "bet_gold": 0}
}
```

`seed` and `rng_state` are strings because JSON numbers are doubles. A
piece has a `bench` slot, or `bench` -1 and a board `col` and `rank`.
`phase` `"prep"` resumes the preparation with the same shop; `"reward"`
opens on the same reward cards (`rewards`, `REWARD_IDS` ids), and the
choice then rolls the same next shop as without the reload, since
`rng_state` is saved after the rewards (and any Kỳ Ngộ options) were
drawn; `"encounter"` replays the same road encounter, and a black market
taken in the reward just before it (`black_market_next`) still opens in the
next preparation. Versions 1, 2 and 3
(before the phase and rewards, before Kỳ Ngộ, before road encounters) are
refused like any unknown version, without a migration: such saves only
existed during development. Raising `version`
makes older saves unusable: add a migration in `RunSave.load_run()` when
the format changes and players have saves.

## Balance bot

`Tools/run_bot.gd` plays whole runs with a greedy player: it buys the
best-value units, merges, levels up when it can, keeps the strongest units
on the board, picks Rest at 40 morale or less, else Hunt while levels
remain (loot next), else loot and the black market, always takes the first
Kỳ Ngộ card, takes the road-encounter card with the most gold now (a bet
counts at half its payout), fights with its mutations on (like the run
screen) and gives a run up after 60 battles. It has two formation habits:
a mage or archer goes right behind a front-rank shield (Hộ Pháp) or spear
(Thương Che Cung), and three archers stand together in rank 4 (Mưa Tên).

`--weak` stands in for a new player: it levels up whenever supply allows,
buys the first offer it can pay until nothing fits (so its bench fills and
gold piles up), never refreshes, sells or buys supply, and places pieces
from the left of the front rank (stars first). It takes the same rewards
and encounter cards. Run both after changing stages or rules:

```
godot --headless --path . --script res://Tools/run_bot.gd -- 300 1
godot --headless --path . --script res://Tools/run_bot.gd -- 300 1 --weak
```

Results of 300 runs from seed 1 with the current data. "First try" counts
each run's first battle at that stage; stage 12 is retried after a loss.

| Stage | Normal: first try win % | Avg morale after | Weak: first try win % | Avg morale after |
| --- | --- | --- | --- | --- |
| 1 | 100 | 60.0 | 100 | 60.0 |
| 2 | 100 | 60.0 | 100 | 60.0 |
| 3 | 100 | 59.1 | 100 | 59.3 |
| 4 | 100 | 59.1 | 99 | 59.2 |
| 5 | 100 | 58.4 | 88 | 57.3 |
| 6 | 100 | 58.4 | 78 | 54.6 |
| 7 | 100 | 57.8 | 50 | 47.9 |
| 8 | 100 | 57.8 | 48 | 42.6 |
| 9 | 100 | 57.4 | 0 (of 297 reaching it) | 26.9 |
| 10 | 94 | 56.6 | 0 | 16.2 |
| 11 | 75 | 53.4 | 0 | 8.1 |
| 12 | 56 (23 per attempt over 740 attempts) | 27.1 | 0 | 3.0 |

Normal: run win rate 56.7% (170 of 300), 11.3 stages cleared on average,
5 road encounters and 18.4 streak gold per run. Weak: no run won, 6.6
stages cleared on average; 99% of runs win stage 4 and 48% stage 8 at the
first try.

Milestone 7 (road encounters, streak bonus, loot, lane-target cavalry, and
stages 5-8 eased), all 300 runs from seed 1:

| Data | Normal win % | Weak: clears stage 4 | Weak: clears stage 8 |
| --- | --- | --- | --- |
| Before (milestone 6 data, new cavalry) | 34.0 | 99% | 0% |
| Encounters, streak and loot | 56.7 | 97% | 0% |
| ... and stages 5-8 eased | 56.3 | 97% | 50% |
| ... and stage 1 with two enemies (current) | 56.7 | 99% | 48% |

Stage 1 had three enemies, a mirror of what 10 gold buys, and the weak
bot won it only 52% of the time: a first battle that a careless line-up
loses. It now has two (the wolf archer is gone).

The weak player hit a wall at stage 5 (four 1-star enemies at stage 4,
five mostly 2-star at stage 5). Stages 5-8 now keep one 2-star each
(stage 5 the wolf shield, 6 the iron guard, 7 the wolf shield, 8 one iron
guard) and the rest 1-star, with the same units and cells; stages 9-11 and
the boss are unchanged. Every stage-5 to 8 enemy at 1 star gave the weak
bot 73% at stage 8 (100 runs); 2-star blood wolves at 7 and 8 gave 20%.
The normal bot barely notices: its win rate is decided by stages 10-12.

History before milestone 7: 36.3% at milestone 6 (32.7% before it, with
stage 12 eight units and no boss; 22.7% with the boss at 2600 hp and 70
attack, 32.7% at 2100 hp and 60 attack, 36.3% when casts during stone no
longer counted). 37.7% with skills (milestone 4). Synergies on for both
sides with the old stages and bot gave 48.0%; the formation stages with the
old bot (no habits) 8.3%; with the habits 63.7%. A person who reads the
enemy line-up and places units against it, and spaces their skills against
the boss, does better than the bot.

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
  `Locale/strings.csv`. `Catalog.validate()` reports a stage count that
  does not match `stage_count`, a bad or doubled `id`, an empty `name_key`,
  a wrong unit count and missing `stage_income` or `enemy_counts` entries;
  it does not check that the `STAGE_13` translation exists, so look at the
  stage name in the top bar.
- **Add a reward:** add it to `RunState.Reward` and `REWARD_IDS`, apply it
  in `choose_reward()`, give it a look in `RewardScreen._looks()` and its
  `REWARD_*` strings.

## Tests

- `Tests/run_test.gd`: the rules without screens: the catalog's rules and
  stages, start values, a seed's shops, buying and selling, refresh, refused
  purchases, merges on the bench and board and chained, legends, levels,
  moves and swaps, income, battle results, rewards, the black market,
  stage 12 repeats, a lost run, bench queries off the bench, the save
  round trip in the preparation and in the reward choice (after a win and a
  loss: same options, same next shop), `prep_changed` after every
  successful preparation command, and broken saves (every key left out,
  wrong types, out-of-range values, bad phases and rewards, doubled cells
  and slots, unknown units, over capacity, unmerged copies), which must be
  refused without script errors.
- `Tests/encounter_test.gd`: road encounters, the win-streak bonus and the
  loot reward (see [encounter.md](encounter.md#tests)).
- `Tests/run_flow_test.gd`: stage 1 through the real screens: Main starts a
  run, units are bought and placed with the controller's taps, the battle
  plays at x4, input is refused meanwhile, "Tiếp tục" opens the rewards
  (already in the save at the reduced morale); "Chơi tiếp" then lands on
  the same cards, a cancelled release on a card does nothing and a 0.5 s
  press chooses it, starting stage 2, which is in the save; a refresh is
  saved at once. With real input events it checks that a drag from a bench
  gap picks nothing up, that the sell zone ignores a cancelled or slid-off
  release and sells on a 0.5 s hold and on a slide that ends on it; then a
  lost run deletes its save at the banner, and a version-1 save is deleted
  when "Chơi tiếp" fails, leaving a title without it. A Kỳ Ngộ that fires
  after the first battle is passed through its cutscene (first card). A
  saved stage-2 reward leads to the road encounter, whose card is taken
  with a real screen touch (`Input.parse_input_event`), then stage 3's
  "Ra trận" takes a press; a run saved at an encounter resumes on it, a
  touch on its greyed card is refused, and its free card pays exactly its
  gold plus stage 3's income. During that card's coins, and the loot
  reward's, the gold chip's number never goes down and ends at the run's
  gold. Both tests set `RunSave.path` to a test file
  (`user://run_save_test.json`, `user://run_test_save.json`) and delete it,
  so the player's save is never touched.

- `Tests/synergy_ui_test.gd`: the synergy views on the real run screen
  (see [Synergy](synergy.md)); its save goes to
  `user://synergy_ui_test.json`.

```
godot --headless --path . --script res://Tests/run_test.gd
godot --headless --path . --script res://Tests/run_flow_test.gd
godot --headless --path . --script res://Tests/encounter_test.gd
godot --headless --path . --script res://Tests/synergy_ui_test.gd
```

## Known limits

- A game closed during a battle resumes in that stage's preparation with
  the board as it was (the last save before "Ra trận"), so that battle is
  fought again; the run is never saved mid-battle.
- Every shop roll is independent: there is no shared pool of copies.
- Board cells are about 80 px wide at the 720 base, below the 88 px target
  for touch, so that the 7 x 8 board, bench and shop fit a portrait phone.
- The first stages are easy for anyone who places their units: with
  cost 1-2 one-star enemies, the bot wins stages 1-4 almost always.
- The weak bot wins nothing from stage 9 on: stages 9-11 keep their 2-star
  line-ups, so a player who never merges is meant to stop around there.
