# Falemag

Falemag is a lightweight 2D game built with Godot 4.7.2, focused on story and
tactics. It targets low-end PCs and mobile phones, and may later support
online play.

The project is at the starter stage: an empty main scene, a smoke test,
Windows, Android and Web export presets, and CI. Gameplay, story, and controls are not yet
implemented.

## Requirements

- [Godot 4.7.2 standard edition](https://godotengine.org/download/archive/4.7.2-stable/)
  and its matching export templates (**Editor > Manage Export Templates**).
- Git and Git LFS.

## Clone, open and test (Windows cmd.exe)

Replace the path below with your Godot console executable:

```bat
git lfs install
git clone https://github.com/nhatphucpham/fal-gaming.git
cd fal-gaming
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
- [Changelog](CHANGELOG.md)
- [Agent instructions](AGENTS.md)

Work on short-lived branches and open pull requests into `master`.
