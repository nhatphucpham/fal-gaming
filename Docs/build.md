# Build and test

Gameplay code is C++ in a GDExtension, so the native library must be built
before Godot opens or imports the project. Without it Godot logs that
`res://falemag.gdextension` cannot be loaded and that the `SimClock` class is
missing, and the node loads as an unknown node.

## Requirements

- Godot 4.7.2 standard edition and its export templates.
- Python 3 and SCons (`python -m pip install scons`): 4.11 or later on
  Windows, since older versions do not find Visual Studio 2026; 4.0 or later
  elsewhere.
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

For a first-time setup on Windows (Git, Python, Visual Studio Build Tools
and Godot, with PowerShell commands) see the README, section "Set up, build
and test on Windows".

On Windows, `Tools/build_and_test.bat` does the build, the import and every
test in `Tests/`, and stops with a hint at the first setup step that fails
(Godot missing or not 4.7, assets left as Git LFS pointers, no Python 3,
`Native/godot-cpp` empty, a failed build or import). It updates the submodule
and installs or upgrades SCons to 4.11 or later itself, and warns when SCons
fell back to MinGW instead of MSVC. The smoke test runs first and stops the
run if it fails; the other tests then all run in name order and the failed
ones are listed at the end. Last, like CI, it starts the main scene
headless for two frames (`--quit-after 2`). It finds the Godot
console executable through the `GODOT` variable or its `DEFAULT_GODOT` line,
runs from the repository root wherever it is started, and waits for a key at
the end so a double-clicked window stays open (`nopause` skips that, `editor`
opens the editor after the tests pass). It runs every `Tests/*_test.gd`, so a
new test file is picked up without editing it; keep helper scripts in
`Tests/` named otherwise, such as `*_kit.gd`.

When `GODOT` is not set, the `.bat` looks for a Godot 4.7 console
executable at `DEFAULT_GODOT` (`C:\Godot\...`), then on `PATH`, then under
`C:\Godot`, `Program Files\Godot`, Downloads and Desktop, subfolders
included. The `.sh` takes `godot` from `PATH` when it reports 4.7, and
otherwise searches those folders up to four levels deep.

Both scripts stop early when `Assets/Sfx/arrow.wav` is missing (a clone or
checkout that did not finish) or is still a Git LFS pointer.

`Tools/build_and_test.sh` does the same steps in bash: Git Bash or MSYS2 on
Windows (it passes Windows paths to Godot and turns off MSYS path rewriting,
and prefers the python.org `py` launcher so SCons uses MSVC rather than
MSYS2's MinGW), and Linux, where it builds the `.so` and looks for
`Godot_v4.7*_linux.x86_64` in `~/Godot`, `~/Downloads`, `~/Desktop` and
`/opt/godot`. On Linux it accepts SCons 4.0 or later, and when pip cannot
install it (a system Python that blocks pip) it suggests the package manager
or a virtual environment.

After building, run the editor import, `Tests/smoke_test.gd`,
`Tests/battle_test.gd`, `Tests/battle_api_test.gd`, `Tests/skill_test.gd`,
`Tests/passive_test.gd`, `Tests/sandbox_test.gd`, `Tests/run_test.gd`,
`Tests/run_flow_test.gd`, `Tests/formation_test.gd`, `Tests/synergy_test.gd`,
`Tests/formation_battle_test.gd`, `Tests/synergy_ui_test.gd`,
`Tests/epiphany_test.gd`, `Tests/boss_test.gd`, `Tests/cutscene_test.gd`,
`Tests/audio_test.gd`, `Tests/unit_pose_test.gd`,
`Tests/pose_animator_test.gd`, `Tests/pose_cast_test.gd`,
`Tests/pose_stone_test.gd`, `Tests/voice_test.gd`,
`Tests/perf_budget_test.gd`, `Tests/idle_frames_test.gd`,
`Tests/app_lifecycle_test.gd`, the tactics tests
(`Tests/tactics_test.gd`, `Tests/tactics_squad_test.gd`,
`Tests/tactics_fuzz_test.gd`, `Tests/tactics_query_test.gd`,
`Tests/tactics_incident_test.gd`, `Tests/tactics_roster_test.gd`,
`Tests/tactics_screen_test.gd`, `Tests/tactics_screen_sync_test.gd`,
`Tests/tactics_screen_input_test.gd`, `Tests/tactics_brain_test.gd`,
`Tests/tactics_feel_test.gd`) and `Tests/muster_test.gd` as shown in the
README. Tests that touch the
settings file point `RunSettings.path` at `user://settings_test.json`, so
the player's mute and preparation time are left alone.
The run test checks the rules of a run (`RunState`, the shop, merges, the
save) without any screen; the run flow test plays stage 1 through the real
screens, from Main's new run to stage 2's preparation (see
[Run](systems/run.md)). The run flow test points `RunSave.path` at
`user://run_save_test.json` and deletes that file at the end, so a run
saved on the same machine is left alone.
The sandbox test drives the sandbox screen headless through the functions its
gestures call and plays one battle to the end (see
[Board](systems/board.md)). The smoke test checks that the
extension is loaded, that the main scene contains a `SimClock`, and that it
ticks as expected. The battle tests load `Data/catalog.tres` and run short
battles headless (see [Battle](systems/battle.md)); the first prints the
length of a sample 8v8 battle, the second prints the errors it provokes on
purpose.

The first import of a fresh checkout loads the extension mid-scan, and Godot
4.7.2 then crashes on exit (exit code 134). Running the import again
succeeds. CI avoids it by writing
`res://falemag.gdextension` to `.godot/extension_list.cfg` before importing.

CI builds debug and release libraries for Linux x86_64, Windows x86_64,
Android arm64 and arm32, and the web (wasm32 without threads), and uploads
them as workflow artifacts. It then runs the import, the smoke, battle,
sandbox, run and run flow tests with the Linux library, and checks that the Android and Web
exports contain theirs.
After the tests it runs the performance probe twice, headless and under a
virtual display (`xvfb-run`, Mesa's software OpenGL), each time with
`--budget=Docs/perf_budget.json`, and writes the per-scene table to the job
summary; a scene over its budget fails the job.
These checks do not replace testing an exported build on the target device.

## Performance probe

`Tools/perf_probe.gd` plays the title, a full stage-11 preparation and that
battle at x1 and x4, and prints per scene the CPU time per frame, redraws,
draw calls, frames drawn, nodes and memory. It is a separate command, not
part of `Tools/build_and_test.sh` or `.bat`; run it before and after a change
and put both numbers in the pull request:

```bash
godot --headless --path . --script res://Tools/perf_probe.gd -- --budget=Docs/perf_budget.json
xvfb-run -a -s "-screen 0 400x700x24" godot --rendering-driver opengl3 --audio-driver Dummy --resolution 360x640 --path . --script res://Tools/perf_probe.gd -- --budget=Docs/perf_budget.json
```

What each number means, the budget and its rules are in
[Performance](systems/performance.md).

## Soldier probe

`Tools/tactics_brain_probe.gd` plays seeded river crossings (side A
scripted with random squads and orders, incidents on, side B the AI) and
prints, per side, the soldiers lost per battle and the share of soldier
attacks that killed or dealt more than they took
(see [Tactics](systems/tactics.md), Soldiers). Run it before and after a
change to the soldiers' rules or `Data/Tactics/Rules/tactics_rules.tres`:

```
godot --headless --path . --script res://Tools/tactics_brain_probe.gd -- --battles=200
```

## Balance bot

`Tools/run_bot.gd` plays whole runs with a simple greedy player and prints
the win rate of each stage and of the run, to check the stage table after a
change to `Data/Stages/` or `Data/Rules/run_rules.tres`:

```
godot --headless --path . --script res://Tools/run_bot.gd -- 300 1
```

The arguments are the number of runs, the first seed and, optionally,
`verbose`. `Tools/`, `Tests/` and `Scenes/Dev/` (developer pages such as
the voice demo) are left out of every export preset.

CI runs once per commit: on pull requests, and on pushes to `master`. A
branch without a pull request is not built. A newer commit on a pull request
cancels the run for the older one. Builds on `master` are never cancelled;
if a `pages` deploy is still running or waiting when another one starts, the
earlier one is cancelled. A pull request with merge conflicts is not built
until they are resolved.

The Linux jobs run on the pinned `ubuntu-24.04` image, not `ubuntu-latest`,
so a runner image update cannot change the compiler, glibc or Android SDK
under the build without a commit. To move to a newer image, replace
`ubuntu-24.04` everywhere in `.github/workflows/` (the `runs-on` keys and
the `os:` entries of the native matrix) in its own pull request, and check
that every job still passes.

On pull requests a separate `Docs` workflow checks that code changes also
update the documentation; see [Coding conventions](conventions.md), section 8.

## Sound files

`Tools/make_sfx.gd` writes every sound under `Assets/Sfx/` from code (a
seeded synthesizer, so the same script gives the same bytes). Run it after
changing a sound, then import so Godot picks up the files:

```
godot --headless --path . --script res://Tools/make_sfx.gd
godot --headless --editor --path . --import
```

It prints each file's size and peak and fails if the effects pass 600 KB
or the music 400 KB in total. The files are WAV because Godot cannot write
OGG Vorbis; see [Audio](systems/audio.md).

## Adding C++ classes

Put shared engine glue in `Native/src/` and each system in its own folder,
`Native/src/<system>/` (SConstruct compiles `Native/src/*.cpp` and
`Native/src/*/*.cpp`). Register each class in
`Native/src/register_types.cpp`, and rebuild. Keep simulation files free of
Godot headers so they build and replay without the engine. Use
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
- The screen is held in portrait (`display/window/handheld/orientation`),
  uses immersive mode, and stretches with `aspect="expand"` so tall phone
  screens get more spacing instead of black bars.
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
  opens it full screen in portrait (`progressive_web_app/orientation`).

CI exports a release build on every run and uploads it as the `falemag-web`
artifact. On pushes to `master` the `pages` job publishes it to
<https://nhatphucpham.github.io/fal-gaming/>. This needs **Settings > Pages >
Source: GitHub Actions** turned on once in the repository.

Before uploading, CI runs `Tools/web_cache_bust.py build/web "$GITHUB_SHA"`
so that a reload fetches the new build instead of a cached one: the page
loads `index.js?v=<sha>`, the engine fetches the wasm and pck files with
`?v=<sha>` while online, the page compares itself with `version.txt` and
clears the service worker and its caches once if they differ, and no-cache
meta tags ask the browser to revalidate `index.html`. The tool and the CI
step after it fail the job if Godot's exported page no longer looks as
expected, rather than publishing a build that would stay cached.

To try a build locally, export it and serve the folder over HTTP (opening
`index.html` from disk does not work):

```sh
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
python3 Tools/web_cache_bust.py build/web "$(git rev-parse --short HEAD)"
python3 -m http.server --directory build/web 8000
```
