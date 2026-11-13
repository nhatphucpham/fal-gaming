# Falemag

Falemag is a lightweight 2D game built with Godot 4.7.2, focused on story and
tactics. It targets low-end PCs and mobile phones, and may later support
online play.

The project is at the starter stage: a C++ GDExtension with one sample node,
a main scene that uses it, a smoke test, a Windows export preset, and CI.
Gameplay, story, and controls are not yet implemented.

## Requirements

- [Godot 4.7.2 standard edition](https://godotengine.org/download/archive/4.7.2-stable/)
  and its matching export templates (**Editor > Manage Export Templates**).
- Git and Git LFS.
- Python 3, SCons and a C++ compiler (Visual Studio 2022 Build Tools on
  Windows) to build the GDExtension. See [Build and test](Docs/build.md).

## Clone, open and test (Windows cmd.exe)

Replace the path below with your Godot console executable:

```bat
git lfs install
git clone --recurse-submodules https://github.com/nhatphucpham/fal-gaming.git
cd fal-gaming
python -m pip install scons
scons target=template_debug
set "GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
"%GODOT%" --headless --editor --path "%CD%" --import
"%GODOT%" --editor --path "%CD%"
"%GODOT%" --headless --path "%CD%" --script res://Tests/smoke_test.gd
```

In the editor, press **F5** to run the project or **F6** to run the current
scene.

## Export

From the project directory, after installing export templates:

```bat
scons target=template_release
mkdir build\windows
"%GODOT%" --headless --path "%CD%" --export-release "Windows Desktop" "%CD%\build\windows\Falemag.exe"
```

Only the Windows preset exists so far; an Android preset will be added. The
`build` directory is ignored by Git.

## Documentation

- [Build and test](Docs/build.md)
- [Architecture](Docs/architecture.md)
- [Conventions](Docs/conventions.md)
- [Agent instructions](AGENTS.md)

Work on short-lived branches and open pull requests into `master`.
