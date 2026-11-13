# Architecture

- `project.godot` defines the project. It uses the GL Compatibility renderer on
  desktop and mobile so the game runs on low-end hardware, with a 1280x720 base
  viewport and `canvas_items` stretch mode.
- `Scenes/main.tscn` is the main scene, currently an empty `Node2D` root.
- `Tests/smoke_test.gd` checks that the main scene loads and has a 2D root.
- `Systems/Voice/` is the spoken-dialogue module, registered as the `Voice`
  autoload. See [Voice](voice.md). `Tests/voice_test.gd` tests it against a
  fake server, and `Scenes/Dev/voice_demo.tscn` tries it by hand.
- `export_presets.cfg` holds export presets. Each preset excludes `Tests/`.

Gameplay systems will be written in C++ through GDExtension once the core
design is decided; scenes compose and tune them. No native extension or
third-party plugin is included yet.
