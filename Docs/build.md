# Build and test

Gameplay code is C++ in a GDExtension, so the native library must be built
before Godot opens or imports the project. Without it Godot logs that
`res://falemag.gdextension` cannot be loaded and that the `SimClock` class is
missing, and the node loads as an unknown node.

## Requirements

- Godot 4.7.2 standard edition and its export templates.
- Python 3 and SCons 4.11 or later (`python -m pip install scons`); older
  versions do not find Visual Studio 2026.
- A C++17 compiler: Visual Studio 2022 or 2026 Build Tools (MSVC) on Windows, GCC or
  Clang on Linux. Android builds also need the Android NDK `28.1.13356709`
  installed through the Android SDK, with `ANDROID_HOME` set. Web builds need
  Emscripten 4.0.20 activated through emsdk.
- The `Native/godot-cpp` submodule (`git submodule update --init`).

## Build the extension

Run SCons from the repository root. If `scons` is not on your PATH (common
with the Microsoft Store Python), use `python -m SCons` instead. The first
build also compiles godot-cpp and takes a few minutes; later builds only
recompile changed files.

| Target | Command |
| --- | --- |
| Editor and debug builds on this machine | `scons target=template_debug` |
| Release export on this machine | `scons target=template_release` |
| Android arm64 | `scons platform=android arch=arm64 target=template_debug` (debug APK) or `target=template_release` |
| Android arm32 (older phones) | `scons platform=android arch=arm32 target=template_debug` or `target=template_release` |
| Web (no threads) | `scons platform=web threads=no target=template_debug` or `target=template_release` |

Libraries are written to `bin/` with names such as
`libfalemag.windows.template_debug.x86_64.dll`, matching the entries in
`falemag.gdextension`. The `bin/` folder is ignored by Git. Build the matching
library for each platform and export type (debug or release) before
exporting.

godot-cpp is pinned to `10.0.0-stable` and built against the Godot 4.7 API
(`api_version` in `SConstruct`). The extension needs Godot 4.7 or later.

## Validate

After building, run the editor import and `Tests/smoke_test.gd` as shown in
the README. The smoke test checks that the extension is loaded, that the main
scene contains a `SimClock`, and that it ticks as expected.

The first import of a fresh checkout loads the extension mid-scan, and Godot
4.7.2 then crashes on exit (exit code 134). Running the import again
succeeds. CI avoids it by writing
`res://falemag.gdextension` to `.godot/extension_list.cfg` before importing.

CI builds debug and release libraries for Linux x86_64, Windows x86_64,
Android arm64 and arm32, and the web (wasm32 without threads), and uploads
them as workflow artifacts. It then runs the import and smoke test with the
Linux library, and checks that the Android and Web exports contain theirs.
These checks do not replace testing an exported build on the target device.

CI runs once per commit: on pull requests, and on pushes to `master`. A
branch without a pull request is not built. A newer commit on a pull request
cancels the run for the older one. Builds on `master` are never cancelled;
when two pushes to `master` overlap, only one `pages` deploy runs and the
other is cancelled. A pull request with merge conflicts is not built until
they are resolved.

The Linux jobs run on the pinned `ubuntu-24.04` image, not `ubuntu-latest`,
so a runner image update cannot change the compiler, glibc or Android SDK
under the build without a commit. To move to a newer image, change
`runs-on` in `.github/workflows/` in its own pull request and check that
every job still passes.

On pull requests a separate `Docs` workflow checks that code changes also
update the documentation; see [Coding conventions](conventions.md), section 8.

## Adding C++ classes

Put sources in `Native/src/`, register each class in
`Native/src/register_types.cpp`, and rebuild. Use
`GDREGISTER_RUNTIME_CLASS` for nodes that should not run inside the editor.
`Native/` holds a `.gdignore` so Godot does not import it.

## Android

The `Android` preset builds an APK for arm64 phones (Android 7.0 and later)
without a custom Gradle build. Choices made to keep it light:

- Only `arm64-v8a` is exported. Dropping 32-bit ARM and x86 roughly halves
  the APK; every phone sold since about 2017 is arm64. Enable
  `architectures/armeabi-v7a` only if a target device needs it.
- The renderer is GL Compatibility (OpenGL ES 3.0), which runs on low-end
  GPUs. Textures import with ETC2/ASTC compression
  (`rendering/textures/vram_compression/import_etc2_astc`), which Android
  export requires and which keeps GPU memory low.
- The screen follows the sensor in landscape, uses immersive mode, and
  stretches with `aspect="expand"` so tall phone screens show more of the
  scene instead of black bars.
- The `INTERNET` permission is on for online play and the TTS service.

Before the GDExtension was added, a debug export was about 28 MB and a
release export about 26 MB; almost all of it is the engine library, and the
native library adds little. A custom engine build
with unused modules disabled can shrink it further when that matters.

### Export locally

1. Install the Android SDK (platform-tools, build-tools) and JDK 17, then set
   their paths in **Editor > Editor Settings > Export > Android**. The
   `ANDROID_HOME` and `JAVA_HOME` environment variables work too.
2. Install the 4.7.2 export templates.
3. Export from the editor (**Project > Export > Android**), or from a shell:

```sh
"$GODOT" --headless --path . --export-debug "Android" build/android/Falemag.apk
```

Godot signs debug builds with the debug keystore from Editor Settings, or the
one named by `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `_USER` and `_PASSWORD`. A
release build needs your own keystore through the matching
`GODOT_ANDROID_KEYSTORE_RELEASE_*` variables; never commit a keystore.

CI exports a debug APK on every run and uploads it as the
`falemag-android-debug` artifact, kept for seven days. It proves the preset
exports; it does not run the game. Install the APK on a real low-end phone
(`adb install -r Falemag.apk`) to check performance.

### Native libraries

`falemag.gdextension` lists `android.debug.arm64` and `android.release.arm64`
(plus arm32, which the preset does not export yet). Build the matching `.so`
with the Android NDK before exporting; the preset packages it into the APK
without a Gradle build. In CI the `android` job downloads the
`falemag-android-arm64` library from the `native` job.

## Web

The `Web` preset is the quickest way to try the game on a phone, including
iPhone, where APKs do not install. Choices:

- **No threads** (`variant/thread_support=false`). The page runs without the
  `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers, so it
  works on GitHub Pages and in Safari on iOS. Audio is slightly more prone to
  crackle under load than a threaded build.
- **GDExtension support** (`variant/extensions_support=true`). Needed for the
  C++ code. The engine is about 10.6 MB gzipped instead of 10.1 MB. The C++
  library is built with `platform=web threads=no` to match, and the CI `web`
  job downloads it from the `native` job before exporting.
- ETC2/ASTC and S3TC/BPTC textures are both exported, so phones and desktops
  each get a compressed format.
- It is a progressive web app: on iPhone, **Share > Add to Home Screen**
  opens it full screen in landscape.

CI exports a release build on every run and uploads it as the `falemag-web`
artifact. On pushes to `master` the `pages` job publishes it to
<https://nhatphucpham.github.io/fal-gaming/>. This needs **Settings > Pages >
Source: GitHub Actions** turned on once in the repository.

To try a build locally, export it and serve the folder over HTTP (opening
`index.html` from disk does not work):

```sh
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
python3 -m http.server --directory build/web 8000
```
