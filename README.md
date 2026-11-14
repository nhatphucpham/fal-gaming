# Falemag

Falemag is a lightweight 2D game built with Godot 4.7.2, focused on story and
tactics. It targets low-end PCs and mobile phones, and may later support
online play.

The project is at an early stage: a C++ GDExtension with a fixed-step clock
and a deterministic battle core (classes, units and rules as data under
`Data/`), and a first playable run made for a phone held upright. From the
title screen, a run is 12 stages: in each preparation buy units from a shop
of five, keep them on a bench, place them on your half of the 7 x 8 board
and merge three copies into a stronger star, then press **Ra trận** and
watch the battle at x1, x2 or x4. Wins give gold and supply, losses cost
morale, and wins in a row pay a streak bonus; after each stage pick a
reward, and after stages 2, 4, 6, 8 and 10 a road encounter offers two
choices (gold, supply, morale, a free unit, free refreshes or a bet). The run is saved as you play (every
change in the preparation, each battle result and reward) and can be
continued. Class and race milestones, formations and Hợp Lực make the
line-up's shape matter; Kỳ Ngộ, shown in a cutscene, lets a milestone
family be lowered or mutated during the run, and stage 12 is the boss Cự
Nham, which turns to stone when skills come too fast. There are sound
effects, two music loops and a mute button, and "Cách chơi" gives four
tips. The sandbox, with the full roster and no economy, is still on the
title screen. Text is in Vietnamese. There are headless tests, a balance
bot, Windows, Android and Web export presets, and CI. The story is a short
scene before the boss; the rest is not yet written.

## Requirements

- [Godot 4.7.2 standard edition](https://godotengine.org/download/archive/4.7.2-stable/)
  and its matching export templates (**Editor > Manage Export Templates**).
- Git and Git LFS.
- Python 3, SCons and a C++ compiler (Visual Studio 2022 or 2026 Build Tools on
  Windows) to build the GDExtension. See [Build and test](Docs/build.md).

## Set up, build and test on Windows (PowerShell)

Every command below is for **PowerShell** (Windows Terminal or the
PowerShell window, not cmd and not MSYS2/Git Bash).

### 1. Install the tools (once)

```powershell
winget install --id Git.Git -e
winget install --id Python.Python.3.13 -e
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

Git for Windows includes Git LFS. The Build Tools line installs the MSVC C++
compiler and takes a while. Close PowerShell and open a new window so the new
programs are on `PATH`.

Then install Godot 4.7.2 into `C:\Godot`:

```powershell
New-Item -ItemType Directory -Force C:\Godot | Out-Null
curl.exe -L -o "$env:TEMP\godot.zip" https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip
Expand-Archive "$env:TEMP\godot.zip" -DestinationPath C:\Godot -Force
& C:\Godot\Godot_v4.7.2-stable_win64_console.exe --version
```

The last line should print `4.7.2.stable...`. Use `Godot_v4.7.2-stable_win64.exe`
to open the editor by hand; the `_console` one shows output in the terminal.
Exporting also needs the export templates (**Editor > Manage Export
Templates** in the editor).

### 2. Clone the repository

Pick a folder that is not already inside a clone, then:

```powershell
git lfs install
git clone --recurse-submodules https://github.com/nhatphucpham/fal-gaming.git
cd fal-gaming
```

If the clone was interrupted, or was made without `--recurse-submodules` or
before `git lfs install`, finish it from the `fal-gaming` folder:

```powershell
git lfs install
git restore --source=HEAD :/
git lfs pull
git submodule update --init --recursive
git status
```

`git restore` brings back files a failed checkout left out ("Clone succeeded,
but checkout failed"); it also undoes local edits, so commit or copy those
first. `git status` should then show no deleted or modified files.

### 3. Build and test in one command

```powershell
.\Tools\build_and_test.bat editor
```

The script checks Godot, Git LFS, the submodule, Python and SCons, builds the
C++ extension, imports the project, runs every test in `Tests/` and then
opens the editor (leave out `editor` to skip that). When a setup step fails it
stops and says how to fix it; failed tests are listed at the end. It finds
Godot in `C:\Godot`, on `PATH`, or in `Program Files\Godot`, Downloads or
Desktop; to use another
copy, set `$env:GODOT = "D:\path\to\Godot_v4.7.2-stable_win64_console.exe"`
first. It also works from cmd and by double-click, and
`Tools/build_and_test.sh` does the same in Git Bash, MSYS2 or Linux.

### Or step by step

From the `fal-gaming` folder:

```powershell
$GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
py -3 -m pip install --upgrade "scons>=4.11"
py -3 -m SCons target=template_debug
# Avoids a Godot 4.7.2 crash on the first import (see Docs/build.md)
New-Item -ItemType Directory -Force .godot | Out-Null
Set-Content -Path .godot\extension_list.cfg -Value "res://falemag.gdextension" -Encoding ascii
& $GODOT --headless --editor --path "$PWD" --import
Get-ChildItem Tests\*_test.gd | ForEach-Object {
    & $GODOT --headless --path "$PWD" --script "res://Tests/$($_.Name)"
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED: $($_.Name)" -ForegroundColor Red }
}
& $GODOT --editor --path "$PWD"
```

The build must succeed and write
`bin\libfalemag.windows.template_debug.x86_64.dll` before the import;
without it the tests report that `SimClock` is missing. Use `Set-Content`
rather than `echo ... >`, which writes UTF-16 in Windows PowerShell. The last
line opens the editor and waits until you close it.

In the editor, press **F5** to run the project or **F6** to run the current
scene.

## Export

From the project directory in PowerShell, after installing export templates:

```powershell
$GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
py -3 -m SCons target=template_release
New-Item -ItemType Directory -Force build\windows | Out-Null
& $GODOT --headless --path "$PWD" --export-release "Windows Desktop" "$PWD\build\windows\Falemag.exe"
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
- Systems: [SimClock](Docs/systems/sim_clock.md), [Battle](Docs/systems/battle.md),
  [Board](Docs/systems/board.md), [Battle playback](Docs/systems/battle_playback.md),
  [Run](Docs/systems/run.md), [Skill](Docs/systems/skill.md),
  [Synergy](Docs/systems/synergy.md), [Formation](Docs/systems/formation.md),
  [Kỳ Ngộ](Docs/systems/epiphany.md), [Cutscene](Docs/systems/cutscene.md),
  [Boss](Docs/systems/boss.md), [Audio](Docs/systems/audio.md),
  [Voice](Docs/systems/voice.md)
- [Changelog](CHANGELOG.md)
- [Agent instructions](AGENTS.md)

Work on short-lived branches and open pull requests into `master`.
