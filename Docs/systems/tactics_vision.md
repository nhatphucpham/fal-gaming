# Tactics vision: fog of war, weather and time of day

## Purpose

What each side of a tactics battle sees, remembers and can do because of
it, and the environment of a scenario: its weather (which may turn once)
and its cycle of times of day. It does not draw anything; the screen side
is in [Tactics screen](tactics_screen.md), section Fog.

## Layer and files

- Layer: simulation (`Native/src/tactics/tactics_vision.*`,
  `tactics_sim_vision.cpp`), bridge (`tactics_environment_data.*`,
  `tactics_battle_vision.cpp`), presentation (`Scenes/Tactics/`).
- Depends on: the map and terrains, units and keywords (`keyword.scout`),
  the AI ([Tactics](tactics.md)) and incidents
  ([Tactics roster](tactics_roster.md)).

## Data

`TacticsScenarioData` (`Data/Tactics/Scenarios/`):

| Field | Meaning |
| --- | --- |
| `fog_of_war` | Off: everyone sees everything, as before milestone 4. |
| `weather` | A `TacticsWeatherData`; none is clear. |
| `weather_change_round`, `weather_after` | From that round on (0: never) the weather is `weather_after`; the screen warns a round ahead. |
| `daytimes` | The cycle of `TacticsDaytimeData`; none is day all battle. |
| `daytime_step_rounds` (1..99), `daytime_start_index` | Each time lasts that many rounds, starting at that index. |
| `supplied_sizes`, `supplied_troops` | The soldiers the scenario gives side A's leaders, in order (sizes per leader); empty keeps each leader's own squad. |

`TacticsWeatherData` (`Data/Tactics/Weathers/`, id `weather.<name>`):
`vision_delta` (cells), `ranged_range_delta` (cells, leaders and soldiers
with range > 1), `burn_pct` (fire zone damage, 100 = normal),
`cost_terrain_ids` + `cost_delta` (move cost added on those terrains),
`hides_intents`, `wind` (a direction) + `wind_range_delta` (ranged shots
along the wind reach that much further, against it that much less),
`waver_pct` (added to the odds of a soldier out of its leader's sight),
`name_key`, `description_key`, `icon`.

`TacticsDaytimeData` (`Data/Tactics/Daytimes/`, id `daytime.<name>`):
`vision_delta`, `uses_lights`, `hides_intents`, `waver_pct`,
`darkness_pct` (0..100, how dark the screen draws it), keys and `icon`.

Shipped values:

| Id | Values |
| --- | --- |
| `weather.clear` | nothing |
| `weather.rain` | vision -1, ranged range -1, burn 50 %, ford and river +1 cost |
| `weather.fog` | vision -1, hides intents, waver +10 |
| `weather.wind` | wind (1, 0), ±1 range |
| `daytime.day` | nothing |
| `daytime.dusk` | vision -1, lights, darkness 30 % |
| `daytime.night` | vision -2, lights, hides intents, waver +10, darkness 60 % |

Other numbers: `vision_cells` on units (troops 4, archer 5, kite scout 6,
every leader 5); terrains `vision_bonus` (hill 2), `sight_block` (hill 2,
forest 1), `hides_units` (forest), `light_cells` (village and fort 2);
rules `leader_light_cells` 1, `intent_read_cells` 3, `reveal_cells` 1,
`attack_reveal_phases` 2; incidents `unseen_waver_pct` (flee 20, betray
10); `keyword.scout` (amount 4) on the kite scout and Liễu Mi.

## Rules

- Sight: a unit sees a cell when the Manhattan distance plus the
  `sight_block` of the cells strictly between them on a Bresenham line is
  at most its radius: `vision_cells` + the `vision_bonus` of its cell + the
  weather's and the time's `vision_delta`, at least 1. A side sees the
  union of its fighting units' sight.
- Lights: when the time `uses_lights`, a lit cell (within `light_cells` of
  a village or fort, within `leader_light_cells` of any leader) is seen as
  far as by day. Lights are what the night tint leaves bright.
- Cells are never seen, seen before (dimmed, remembered) or visible now.
  Cells a walk passes in sight of are remembered too.
- Units: an enemy on a visible cell is seen, except on a `hides_units`
  terrain: there only a unit of the side within `reveal_cells`, or a scout
  that sees the cell, sees it. A unit that attacks or casts is seen by the
  other side for `attack_reveal_phases` phases.
- Last seen: each side remembers where it last saw each enemy (also one a
  walk passed); a remembered cell seen again without it is forgotten.
- Intents: under fog an enemy leader's intent is shown only when it is
  seen; in a weather or time that `hides_intents`, only within
  `intent_read_cells` of one of our units, or a scout's keyword amount.
- Planning: reachable cells, paths, strike targets and forecasts use only
  the enemies the side sees. A forecast is never stopped by a zone of
  control the side does not see.
- Ambush: a walk that meets an unseen enemy (its cell, or its zone of
  control on a cell before the last) stops on the last free cell before it,
  pays only for the cells walked and emits `ambushed`.
- Undo: a move that shows a new enemy (or is ambushed) cannot be taken
  back; one that only shows cells can.
- AI: plays by the same sight. It targets enemies it sees; seeing none it
  marches to the nearest last-seen cell, else the objective it must take,
  else never-seen cells; a guard that sees no enemy keeps its posts. It
  weighs strength with what it sees and remembers.
- Incidents: a soldier out of its leader's sight (fog on, its leader alive
  and not seeing its cell) may waver at `unseen_waver_pct` + the time's and
  the weather's `waver_pct` even when its own trigger does not hold; such a
  wavering soldier is calmed only when its leader sees it again. The
  one-phase warning stays.
- Weather and time events: `weather_changed` and `daytime_changed` at the
  start of side A's phase when they change.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `set_environment(scenario) -> bool` | method | Before `start()`; `load_scenario()` calls it |
| `has_fog_of_war() -> bool` | method | |
| `get_fog_cells(side) -> PackedByteArray` | method | Per cell 0 never seen, 1 seen, 2 visible |
| `is_cell_visible(side, cell)`, `is_unit_seen(side, unit)` | method | |
| `get_last_seen(side) -> Array` | method | `[{unit, cell}]` of enemies not seen now |
| `get_lit_cells() -> PackedByteArray` | method | 1 on lit cells |
| `is_intent_known(side, leader) -> bool` | method | |
| `get_weather_id(round)`, `get_daytime_id(round)`, `get_weather_change_round()` | method | |
| `vision_changed` | event | `side`, `cells`, `lost_cells` (cells now only remembered), `units`, `lost_units` with `lost_at` (where each is remembered, (-1, -1) for nowhere); only for a side played by hand |
| `ambushed` | event | `unit`, `by`, `cell`, `blocked` |
| `weather_changed`, `daytime_changed` | event | `now`, `before` |
| `unit_moved` | event | adds `seen_from`, `seen_to`: the other side saw it there |

Unit state adds `vision`, `is_scout` and `is_out_of_leader_sight`.

## How to extend

- A weather or time of day: a new `.tres` in `Data/Tactics/Weathers/` or
  `Daytimes/` with an icon in `Assets/Tactics/Icons/` and its two strings,
  listed in the catalog's `weathers` or `daytimes`; scenarios name it.
- A scout: add `keyword.scout` to a troop or leader.

## Tests

`Tests/tactics_vision_test.gd`: line of sight, hills, the union, fog
states, forest hiding, the attacker shown, the ambush stop, undo after a
reveal, the vision event, walk sight told, forecasts keeping a hidden zone
secret, the AI blind to what it does not see, last seen, each weather,
night and lights, the daytime cycle, the weather change, intents at night,
unseen wavering, its odds and calming, no environment, determinism. The
fuzz test plays every third seed under fog with weathers and times; the
screen tests play the river crossing with fog on (the sync test checks fog,
ghosts and hidden pieces after every playback; the feel test checks that
the fog texture is written only on a change and that an idle map draws
nothing).

## Balance

`Tools/tactics_brain_probe.gd -- --battles=200 [--scenario=night_raid]
[--policy=idle] [--no-fog]`: its scripted player goes for the enemy
leaders it sees, else where one was last seen, else the objective, walking
by terrain cost. At this milestone (200 seeds): river crossing 123 wins
(rout 107, objective 16; 77 lost by rout), night raid 115 (rout 104,
objective 11; 85 lost by rout); the idle player loses all 200 on both by the
time limit.

## Known limits

- The descriptions in `Locale/strings.csv` state the sight numbers in
  words; a change to the data needs the text changed too.
- The scripted probe player does not use scouts on purpose; it only walks
  with them.
