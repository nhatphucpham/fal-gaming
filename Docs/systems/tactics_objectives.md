# Tactics objectives

## Purpose

What a tactics battle is won by, besides routing the enemy: five objective
kinds (take the pass, hold the city, escort, break the siege, bring down
the general), each with side goals that pay supplies, and how the enemy AI
plays for them. Sites are in [Tactics sites](tactics_sites.md).

## Layer and files

- Layer: simulation (rules, AI goals), bridge (data, queries),
  presentation (objective chip and card, marks, banners, muster, summary).
- Code: `Native/src/tactics/tactics_objectives.{h,cpp}` (the handlers and
  goals), `tactics_objective_data.{h,cpp}` (`TacticsObjectiveData`,
  `TacticsWaveData`, `TacticsGoalData`), `tactics_sim_sites.cpp`
  (convoy road, escapes, arrivals), `tactics_ai.cpp` (march goals,
  priority target, the general's post and flight),
  `tactics_battle_sites.cpp` (bridge); `Scenes/Tactics/tactics_screen.gd`
  (objective chip, card, waves), `muster_screen.gd` (objective in full),
  `tactics_summary_view.gd` (goals and supplies).
- Depends on: sites (strongholds), the tactics simulation and its AI.

## Data

`TacticsScenarioData.objective` (a `TacticsObjectiveData`; null keeps the
map's objective cell). Fields, by kind:

| Field | Kind | Meaning | Range |
| --- | --- | --- | --- |
| `kind` | all | `objective_kind.take_pass`, `.hold_city`, `.escort`, `.break_siege`, `.slay_general` | registered id |
| `site` | pass, city | the map's stronghold index | -1..31 |
| `rounds` | city, siege | rounds to hold; rounds to get out | 0..99 |
| `waves` | city | `TacticsWaveData`: `round`, `leaders`, `entry_cells` | |
| `road_cells`, `convoy` | escort | the cart's road (cell to next cell, ending on the edge) and its troop (non-combatant) | |
| `exit_cells` | siege, general | cells on the map's edge | |
| `count`, `required_leader` | siege | leaders that must get out, and which one (our leader order, -1 any) | 1..8, -1..7 |
| `general`, `flee_hp_pct`, `general_hold_cells` | general | enemy leader index, the hp % he flees at, how far from his post he fights | 0..7, 0..100, 0..16 |
| `goals` | all | `TacticsGoalData`: `kind` (`goal.villages_safe`, `.no_losses`, `.by_round`, `.camps_taken`), `value` (the round for by_round), `supplies` | 0..99, 0..100 |

`TacticsScenarioData.reserve_troop` and `reserve_cost` (1..100): the
soldier the muster hires for supplies.

## Rules

- Take the pass: a leader of ours takes the stronghold (see Tactics sites)
  and still stands on it with it ours at the end of the enemy's phase:
  win. The enemy guards it.
- Hold the city: we own the keep; we win at the end of round `rounds`.
  If the enemy takes it and still owns it at the end of a later round, we
  lose (`keep_lost`). Waves arrive at the start of the enemy's phase of
  their round, next to their entry cells; the enemy is not routed while a
  wave is still to come. The enemy marches on the keep.
- Escort: the cart starts on the first free cell of its road and, at the
  end of each of our phases, walks on it with its move points; it does
  not set out with an enemy next to it, does not step next to an enemy we
  see and does not pass a unit on the road. "Xe dừng" holds it for our
  phases until "Xe đi" (no step back after either). At the road's end
  it leaves the map: win. The cart dies: we lose. The enemy strikes the
  cart before anything else, and goes where it saw it last (else the
  road's end) when it does not see it.
- Break the siege: a leader of ours whose own move ends on an exit leaves
  with its squad. `count` leaders out, `required_leader` among them: win.
  The required leader falls, or too few are left: we lose
  (`leader_lost`). Past `rounds`: we lose. The enemy guards.
- Bring down the general: the general dies: win. At the start of a phase
  with his hp at or under `flee_hp_pct` he turns to flee (once, a banner
  for everyone) and runs for the nearest exit; if he gets out we lose.
  Until then he keeps within `general_hold_cells` of his post and strikes
  only from there.
- Every kind also ends with a rout and with `max_rounds` (enemy win).
- Side goals are judged when we win: each met goal emits `goal_met` and
  pays its supplies. The report lists `goals_met` and `supplies`; the
  campaign adds the supplies to the roster.

The numbers in use (Data/Tactics/Scenarios): river crossing, take the pass
(goals: no losses, win by round 10); night raid, bring down Hắc Hổ (flees
at 15%, exits on the west and east edges at row 6, hold 2; goals: every
camp, win by round 9); city defense, hold the keep 8 rounds, waves on
rounds 2, 5 and 7 (goals: no village burned, no losses); supply road,
escort the cart (260% hp, 3 moves) along 24 cells (goals: no village
burned, win by round 12); broken ring, 2 leaders out of a walled camp,
Lạc Hồng among them, within 10 rounds (goals: win by round 7, every
camp).

## Balance

`Tools/tactics_brain_probe.gd` plays each scenario with a scripted player
that plays for the objective (to the pass, around the keep, beside the
road ahead of the cart, out by the exits, after the general), keeps its
leaders together, casts skills and takes site offers. Over 200 seeds:
river crossing 58%, night raid 58.5%, city defense 63.5%, supply road
59.5%, broken ring 54%. The idle player (`--policy=idle`) loses every one.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `set_objective(objective) -> bool` | method | Before `start()`; `load_scenario` calls it |
| `get_objective_state() -> Dictionary` | method | `id, kind, site, cell` (stronghold, else the general's post), `rounds, count, required_leader, exit_cells, road_cells, convoy, convoy_holds, general, general_fleeing, flee_hp_pct, escaped, waves_sent, waves [{round, leaders, entry_cells}], goals [{kind, value, supplies, is_met}]` |
| `get_convoy_path() -> Array` | method | The cells the cart walks at the end of our phase |
| `set_convoy_hold(holds) -> Array` | method | Our phase only |
| `get_battle_report()` | method | Adds `supplies`, `goals_met` and each unit's `arrival` |

## Log events

| Level | Event | Fields |
| --- | --- | --- |
| info | `unit_escaped` | `unit`, `side`, `cell`, `kind` (exit, convoy, general), `seen_from` |
| info | `convoy_halted` | `unit`, `kind` (hold, go, holding, enemy, blocked) |
| info | `general_fleeing` | `unit` |
| info | `goal_met` | `side`, `goal`, `amount` |
| info | `battle_ended` | `reason`: objective, held, keep_lost, escorted, convoy_lost, broke_out, leader_lost, general_slain, general_fled, rout, time_limit |

## How to extend

A new objective kind is an `ObjectiveHandler` in `OBJECTIVE_HANDLERS`
(`tactics_objectives.cpp`): its guard side, battle start, phase start and
end, leader moved, unit died, rout and exit hooks, the AI's march goals
and priority target, and a validator; then `OBJECTIVE_KIND_*`,
`OBJECTIVE_DESC_*_FORMAT`, `OBJECTIVE_SHORT_*` and `TACTICS_END_*` texts
and the screen's progress line. A new goal is a `GoalHandler` in
`GOAL_HANDLERS` and a `GOAL_*` text.

## Tests

`Tests/tactics_objective_test.gd` (each kind won and lost, waves, the
convoy's walk, hold, halt and the enemy's aim, under fog too, exits, the
general's flight and post, goals, determinism); `Tests/tactics_fuzz_test.gd`
(objective kinds on many seeds); `Tests/tactics_roster_test.gd` and
`Tests/muster_test.gd` (supplies, recruits, the reserve and the objective
text); `Tests/tactics_screen_sync_test.gd` (chip, exits, convoy path).

## Known limits

- One objective per battle; side goals are judged only on a win.
- The general's escape is told to both sides (a banner), even out of
  sight.
