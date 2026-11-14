# Architecture

- `project.godot` defines the project. It uses the GL Compatibility renderer on
  desktop and mobile so the game runs on low-end hardware. The base viewport
  is 720 x 1280 portrait with `canvas_items` stretch and `expand` aspect: a
  taller phone gets more spacing, and a landscape window keeps a 720-wide
  game column centred with the background filling the sides. Phones are held
  in portrait. Touch reaches the game as emulated mouse events
  (`emulate_mouse_from_touch`, on by default), so input has one code path.
- `Scenes/main.tscn` is the main scene: a `Node2D` root `Main`
  (`Scenes/main.gd`) with the `SimClock` and a `CanvasLayer` `UI` holding the
  current screen. `Main` sets the locale, switches off the clock's own
  ticking and hands the clock to the screen.
- `Tests/` holds headless test scripts run in CI: `smoke_test.gd` (the
  extension, the main scene and its `SimClock`), `battle_test.gd` and `battle_api_test.gd` (the
  battle core and its node API) and `sandbox_test.gd` (the sandbox screen and one full battle).
- `Data/` holds game content as typed `.tres` resources: `Data/Classes/`,
  `Data/Units/`, `Data/Rules/`, `Data/Sandbox/sandbox.tres` (the sandbox's
  enemy line-ups) and `Data/catalog.tres`, which lists every unit and class
  file explicitly so nothing scans directories at runtime (that breaks in
  exported and web builds).
- `Systems/` holds GDScript bridge services and data scripts, one folder per
  system. `Systems/Content/` has `Catalog` (lookup and validation),
  `SandboxData` and `UnitStats` (player-facing stats, derived through
  `Battle`). `Systems/Lineup/` has `Lineup`, the single owner of a side's
  formation (pure data with signals), and its data types `LineupSlot` and
  `LineupPreset`.
- `Scenes/Board/` holds the reusable battlefield: `BoardView`, `UnitView`,
  `UnitPainter` and `LineupViews`. `Scenes/Battle/` holds `BattlePlayback`
  and `BattleFx`, which play a `Battle` on a board. `Scenes/Sandbox/` holds
  the sandbox screen and its setup interaction; it is the only part that
  knows about the sandbox. See [Board](systems/board.md) and
  [Battle playback](systems/battle_playback.md).
- `UI/` holds the palette, the theme (built in code), and reusable widgets:
  buttons, unit cards, the roster strip, the info panel, the result banner,
  the battle status bars, the drag ghost and the pointer gesture helper.
- `Locale/strings.csv` holds every player-facing text (columns `keys,vi,en`),
  imported into `strings.vi.translation` and `strings.en.translation` and
  registered in `project.godot`. The fallback locale is `vi`, and `Main`
  sets `vi` at start since Vietnamese is the only player language for now.
  Keys follow the data (`UNIT_*`, `CLASS_*`, `RACE_*`) or the screen
  (`BUTTON_*`, `RESULT_*`, `INFO_*`).
- `export_presets.cfg` holds export presets. Each preset excludes `Tests/`.

## Screen flow

There is one screen so far, the sandbox. Setup (placing units) and battle
share it: starting a battle slides the roster and buttons away and slides in
the side health bars, the title gives way to the timer, and the battle plays
on the same board. The result banner slides in at the end; "Xếp lại" slides
everything back. Milestone 3 will add a shop and a run of stages around the
same board, unit views and playback.

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
