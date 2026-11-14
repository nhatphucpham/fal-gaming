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
morale; after each stage pick a reward. The run is saved as you play (every
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
"%GODOT%" --headless --path "%CD%" --script res://Tests/battle_api_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/skill_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/passive_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/sandbox_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/run_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/run_flow_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/formation_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/synergy_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/formation_battle_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/synergy_ui_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/epiphany_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/boss_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/cutscene_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/audio_test.gd
"%GODOT%" --headless --path "%CD%" --script res://Tests/unit_pose_test.gd
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
- Systems: [SimClock](Docs/systems/sim_clock.md), [Battle](Docs/systems/battle.md),
  [Board](Docs/systems/board.md), [Battle playback](Docs/systems/battle_playback.md),
  [Run](Docs/systems/run.md), [Skill](Docs/systems/skill.md),
  [Synergy](Docs/systems/synergy.md), [Formation](Docs/systems/formation.md),
  [Kỳ Ngộ](Docs/systems/epiphany.md), [Cutscene](Docs/systems/cutscene.md),
  [Boss](Docs/systems/boss.md), [Audio](Docs/systems/audio.md)
- [Changelog](CHANGELOG.md)
- [Agent instructions](AGENTS.md)

Work on short-lived branches and open pull requests into `master`.
