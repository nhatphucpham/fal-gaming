# Architecture

- `project.godot` defines the project. It uses the GL Compatibility renderer on
  desktop and mobile so the game runs on low-end hardware, with a 1280x720 base
  viewport and `canvas_items` stretch mode.
- `Scenes/main.tscn` is the main scene: a `Node2D` root with a `SimClock`.
- `Tests/smoke_test.gd` checks that the extension loads and that the main
  scene and its `SimClock` behave as expected.
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

No third-party plugin is included.
