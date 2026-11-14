# Architecture

- `project.godot` defines the project. It uses the GL Compatibility renderer on
  desktop and mobile so the game runs on low-end hardware, with a 1280x720 base
  viewport and `canvas_items` stretch mode.
- `Scenes/main.tscn` is the main scene, currently an empty `Node2D` root.
- `Tests/smoke_test.gd` checks that the main scene loads and has a 2D root.
- `export_presets.cfg` holds export presets. Each preset excludes `Tests/`.

Gameplay systems will be written in C++ through GDExtension once the core
design is decided; scenes compose and tune them. No native extension or
third-party plugin is included yet.

## Layers and documentation

Code is organized in three layers (simulation, bridge, presentation) as
described in [Coding conventions](conventions.md). Each system gets a page in
`Docs/systems/`, written from `Docs/systems/_template.md` when the system is
added. A system page written elsewhere before this rule moves there the next
time it changes.
