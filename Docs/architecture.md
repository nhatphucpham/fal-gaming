# Architecture

`project.godot` defines the Godot project and its main scene. `Scenes/main.tscn`
is an empty Node2D root, ready for the eventual game design. The existing
`Content/Falemag` directories can hold feature assets. `Tests/smoke_test.gd`
checks that the main scene loads and has a 2D root.

The old Unreal 3D starter classes and input setup were removed rather than
assuming a 2D control scheme. Add gameplay systems in C++ using Godot's
GDExtension interface when the gameplay design and native build setup are
decided; use scenes for composition and tuning. No native extension or
third-party plugin is included yet.

The Windows export preset excludes `Content/Falemag/_Dev` and `Tests` via its
exclude filter. Other export presets must apply the same exclusions independently.
