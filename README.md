# Falemag

Falemag is a single-player C++ Unreal Engine game project. Its genre and pitch
are not yet specified. Win64 is the initial target; other platforms have not
been configured or tested.

## Requirements

- Unreal Engine **5.5**, with C++ support.
- Windows 64-bit, Visual Studio 2022 with the Game development with C++
  workload (or Rider with the required MSVC toolchain and Windows SDK).
- Git and Git LFS. Configure `UE_ROOT` to the engine installation directory.
- For CI: a Windows self-hosted GitHub Actions runner labelled `unreal`,
  with the same engine, toolchain, Git LFS, and `UE_ROOT` available to the
  runner service. Use an isolated runner without unrelated credentials;
  fork pull requests run hygiene checks only and need a trusted build separately.

## Clone, build, open, and test (Windows cmd.exe)

Replace the engine path if necessary:

```bat
git lfs install
git clone https://github.com/nhatphucpham/fal-gaming.git
cd fal-gaming
set "UE_ROOT=C:\Program Files\Epic Games\UE_5.5"
call Scripts\build-editor.bat
"%UE_ROOT%\Engine\Binaries\Win64\UnrealEditor.exe" "%CD%\Falemag.uproject"
"%UE_ROOT%\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "%CD%\Falemag.uproject" -unattended -nop4 -nosplash -nullrhi -ExecCmds="Automation RunTests Falemag" -TestExit="Automation Test Queue Empty"
```

The test command exits after the queue finishes; inspect its log for failures.
CI also checks the exported automation report. See [build guide](Docs/build.md)
for game builds, cooking, packaging and Linux/macOS scripts.

## Required editor setup

The repository deliberately contains no generated assets or maps. After the
editor build:

1. Open the editor, create `Content/Falemag/Maps/L_Main`, and set it as both
   **Editor Startup Map** and **Game Default Map** in Project Settings > Maps
   & Modes. Add a floor, lighting and Player Start to make it playable.
2. Create `IA_Move` and `IA_Look` input actions with value type Axis2D and
   `IA_Jump` with value type Digital (bool). Create `IMC_Default`, map keyboard
   and mouse (or gamepad) inputs to these actions, and add appropriate axis
   modifiers for directional keys.
3. Create `BP_FalemagCharacter` derived from `FalemagCharacter` and assign
   the three input actions. Create `BP_FalemagPlayerController` derived from
   `FalemagPlayerController` and assign `IMC_Default` to Input Mapping Context.
4. Create `BP_FalemagGameMode` derived from `FalemagGameMode`, set its Default
   Pawn Class and Player Controller Class to those two Blueprints, and select
   it as the project's Default GameMode in Maps & Modes. Add a character mesh
   and any gameplay tuning as desired. Save assets and use Git LFS for them.

See [architecture](Docs/architecture.md), [conventions](Docs/conventions.md),
and [agent instructions](AGENTS.md). Use short-lived branches and pull requests
into `main`; no long-lived `develop` branch is required.
