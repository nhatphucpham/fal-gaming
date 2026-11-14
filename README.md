# Falemag

Falemag is a lightweight 2D game built with Godot 4.7.2, focused on story and
tactics. It targets low-end PCs and mobile phones, and may later support
online play.

The project is at an early stage: a C++ GDExtension with a fixed-step clock
and a headless, deterministic battle core (classes, units and rules as data
under `Data/`), a main scene, smoke and battle tests, Windows, Android and Web
export presets, and CI. The battle has no screen yet; story and controls are
not yet implemented.

## Requirements

- [Godot 4.7.2 standard edition](https://godotengine.org/download/archive/4.7.2-stable/)
  and its matching export templates (**Editor > Manage Export Templates**).
- Git and Git LFS.
- Python 3, SCons and a C++ compiler (Visual Studio 2022 or 2026 Build Tools on
  Windows) to build the GDExtension. See [Build and test](Docs/build.md).

## Clone, open and test (Windows cmd.exe)

Replace the path below with your Godot console executable:

```bat
git lfs install
git clone --recurse-submodules https://github.com/nhatphucpham/fal-gaming.git
cd fal-gaming
python -m pip install scons
python -m SCons target=template_debug
set "GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
rem Avoids a Godot 4.7.2 crash on the first import (see Docs/build.md)
mkdir .godot
echo res://falemag.gdextension> .godot\extension_list.cfg
"%GODOT%" --headless --editor --path "%CD%" --import
"%GODOT%" --editor --path "%CD%"
"%GODOT%" --headless --path "%CD%" --script res://Tests/smoke_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/battle_test.gd
```

In the editor, press **F5** to run the project or **F6** to run the current
scene.

## Export

From the project directory, after installing export templates:

```bat
python -m SCons target=template_release
mkdir build\windows
"%GODOT%" --headless --path "%CD%" --export-release "Windows Desktop" "%CD%\build\windows\Falemag.exe"
```

The `Web` preset builds the version to try on any phone, including iPhone:
CI publishes it from `master` to <https://nhatphucpham.github.io/fal-gaming/>.
The `Android` preset exports an arm64 APK. It needs the Android SDK and
JDK 17 set in **Editor > Editor Settings > Export > Android**; see
[Build and test](Docs/build.md). The `build` directory is ignored by
Git.

## Documentation

- [Build and test](Docs/build.md)
- [Architecture](Docs/architecture.md)
- [Coding conventions](Docs/conventions.md): rules for every change
- [System doc template](Docs/systems/_template.md)
- Systems: [SimClock](Docs/systems/sim_clock.md), [Battle](Docs/systems/battle.md)
- [Changelog](CHANGELOG.md)
- [Agent instructions](AGENTS.md)

Work on short-lived branches and open pull requests into `master`.
