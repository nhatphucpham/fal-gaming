# Architecture

- `project.godot` defines the project. It uses the GL Compatibility renderer on
  desktop and mobile so the game runs on low-end hardware, with a 1280x720 base
  viewport and `canvas_items` stretch mode.
- `Scenes/main.tscn` is the main scene: a `Node2D` root with a `SimClock`.
- `Tests/smoke_test.gd` checks that the extension loads and that the main
  scene and its `SimClock` behave as expected. `Tests/battle_test.gd` tests
  the battle system headless.
- `Data/` holds game content as typed `.tres` resources: `Data/Classes/`,
  `Data/Units/`, `Data/Rules/` and `Data/catalog.tres`, which lists every
  file explicitly so nothing scans directories at runtime (that breaks in
  exported and web builds).
- `Systems/` holds GDScript bridge services, one folder per system.
  `Systems/Content/catalog.gd` defines `Catalog`, the resource behind
  `Data/catalog.tres`: lookup by id and data validation.
- `export_presets.cfg` holds export presets. Each preset excludes `Tests/`.

## Native code

Gameplay systems are written in C++ through GDExtension; scenes compose and
tune them.

- `Native/godot-cpp/` is the godot-cpp submodule (pinned to `10.0.0-stable`,
  Godot 4.7 API).
- `Native/src/` holds the extension sources. `register_types.cpp` registers
  classes with Godot.
- `SConstruct` builds the sources into `bin/`, and `falemag.gdextension` tells
  Godot which library to load on each platform.

`SimClock` is the first native node. It converts frame time into fixed integer
ticks (20 per second by default) and emits `ticked(tick)` for each one. Time is
counted in whole microseconds so every device produces the same tick sequence,
which turn-based combat, auto-battles and lockstep networking can build on.
After a long stall it fires at most `max_ticks_per_frame` ticks and drops the
rest, so a slow phone does not fall further behind.

The class is documented in [SimClock](systems/sim_clock.md). No third-party
plugin is included.

`Native/src/battle/` is the battle system: an auto-battle between two sides
on a 7 x 8 board. Its simulation (`battle_*.h/.cpp`, class `BattleSim`) is
plain C++17 with no Godot headers and no floating point, so a battle gives
the same events and state hash on every device. Bridge classes expose it:
the `ClassData`, `UnitData` and `BattleRulesData` resources and the `Battle`
node, which turns simulation events into dictionaries and signals. `Battle`
does not tick by itself; the caller steps it, for example from
`SimClock.ticked`. See [Battle](systems/battle.md).

## Layers and documentation

Code is organized in three layers (simulation, bridge, presentation) as
described in [Coding conventions](conventions.md). Each system gets a page in
`Docs/systems/`, written from `Docs/systems/_template.md` when the system is
added. A system page written elsewhere before this rule moves there the next
time it changes.
