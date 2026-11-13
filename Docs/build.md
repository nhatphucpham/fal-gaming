# Build and test

Gameplay code is C++ in a GDExtension, so the native library must be built
before Godot opens or imports the project. Without it the editor reports that
`res://falemag.gdextension` cannot be loaded and `SimClock` nodes appear as
placeholders.

## Requirements

- Godot 4.7.2 standard edition and its export templates.
- Python 3 and SCons (`python -m pip install scons`).
- A C++17 compiler: Visual Studio 2022 Build Tools (MSVC) on Windows, GCC or
  Clang on Linux. Android builds also need the Android NDK `28.1.13356709`
  installed through the Android SDK, with `ANDROID_HOME` set. Web builds need
  Emscripten 4.0.20 activated through emsdk.
- The `Native/godot-cpp` submodule (`git submodule update --init`).

## Build the extension

Run SCons from the repository root. The first build also compiles godot-cpp
and takes a few minutes; later builds only recompile changed files.

| Target | Command |
| --- | --- |
| Editor and debug builds on this machine | `scons target=template_debug` |
| Release export on this machine | `scons target=template_release` |
| Android arm64 | `scons platform=android arch=arm64 target=template_release` |
| Android arm32 (older phones) | `scons platform=android arch=arm32 target=template_release` |
| Web (no threads) | `scons platform=web threads=no target=template_release` |

Libraries are written to `bin/` with names such as
`libfalemag.windows.template_debug.x86_64.dll`, matching the entries in
`falemag.gdextension`. The `bin/` folder is ignored by Git. Build the matching
release library for each platform before exporting it.

godot-cpp is pinned to `10.0.0-stable` and built against the Godot 4.7 API
(`api_version` in `SConstruct`). The extension needs Godot 4.7 or later.

## Validate

After building, run the editor import and `Tests/smoke_test.gd` as shown in
the README. The smoke test checks that the extension is loaded, that the main
scene contains a `SimClock`, and that it ticks as expected.

CI builds debug and release libraries for Linux x86_64, Windows x86_64,
Android arm64 and arm32, and the web (wasm32 without threads), uploads them as workflow artifacts, then runs the
import and smoke test with the Linux library. These checks do not replace
testing an exported build on the target device.

## Adding C++ classes

Put sources in `Native/src/`, register each class in
`Native/src/register_types.cpp`, and rebuild. Use
`GDREGISTER_RUNTIME_CLASS` for nodes that should not run inside the editor.
`Native/` holds a `.gdignore` so Godot does not import it.
