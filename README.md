# Falemag

Falemag is a single-player 2D game project using Godot 4.4.1. Win64 is the
first target. The genre and gameplay are not yet specified; this is an empty
2D starter scene, not a playable game. Unreal gameplay has not been ported,
since 2D movement and controls depend on the game's design.

## Requirements

- [Godot 4.4.1 standard edition](https://godotengine.org/download/archive/4.4.1-stable/).
- Windows 64-bit for the initial target; Git and Git LFS.
- Godot 4.4.1 export templates to export a Windows build. Install them through
  **Editor > Manage Export Templates**.

## Clone, open and test (Windows cmd.exe)

Replace the path below with your downloaded Godot console executable:

```bat
git lfs install
git clone https://github.com/nhatphucpham/fal-gaming.git
cd fal-gaming
set "GODOT=C:\Godot\Godot_v4.4.1-stable_win64_console.exe"
"%GODOT%" --headless --editor --path "%CD%" --import
"%GODOT%" --editor --path "%CD%"
"%GODOT%" --headless --path "%CD%" --script res://Tests/smoke_test.gd
```

In the editor, press **F6** to run the current scene or **F5** to run the
project. The main scene is intentionally empty.

## Export for Windows

After installing export templates, from the project directory:

```bat
mkdir build\windows
"%GODOT%" --headless --path "%CD%" --export-release "Windows Desktop" "%CD%\build\windows\Falemag.exe"
```

The export is unsigned. The `build` directory is ignored by Git. See
[build guide](Docs/build.md), [architecture](Docs/architecture.md),
[conventions](Docs/conventions.md), and [agent instructions](AGENTS.md).
Use short-lived branches and pull requests into `main`.
