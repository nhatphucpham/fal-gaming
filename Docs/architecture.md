# Architecture

- `project.godot` defines the project. It uses the GL Compatibility renderer on
  desktop and mobile so the game runs on low-end hardware. The base viewport
  is 720 x 1280 portrait with `canvas_items` stretch and `expand` aspect: a
  taller phone gets more spacing, and a landscape window keeps a 720-wide
  game column centred with the background filling the sides. Phones are held
  in portrait. Touch reaches the game as emulated mouse events
  (`emulate_mouse_from_touch`, on by default), so input has one code path.
- `Scenes/main.tscn` is the main scene: a `Node2D` root `Main`
  (`Scenes/main.gd`) with the `SimClock` and a `CanvasLayer` `UI` holding the
  current screen. `Main` sets the locale, switches off the clock's own
  ticking, hands the clock to the screen and slides between screens (see
  Screen flow below). Screens are built in code, except the sandbox scene.
- `Tests/` holds headless test scripts run in CI: `smoke_test.gd` (the
  extension, the main scene and its `SimClock`), `battle_test.gd` and
  `battle_api_test.gd` (the battle core and its node API), `skill_test.gd`
  and `passive_test.gd` (skills, Khí, passives and statuses, sharing
  `skill_test_kit.gd`), `sandbox_test.gd`
  (the sandbox screen and one full battle), `run_test.gd` (the run's rules)
  and `run_flow_test.gd` (stage 1 through the real screens), the formation
  and synergy tests, `epiphany_test.gd` (Kỳ Ngộ), `boss_test.gd` (Cự Nham
  and Hóa Đá), `cutscene_test.gd` (the cutscene screen) and
  `audio_test.gd` (the Audio autoload). `voice_test.gd` tests the Voice
  autoload against a fake server on localhost.
- `Tools/` holds developer scripts that are not tests and not exported:
  `run_bot.gd`, the balance bot that plays whole runs (see
  [Run](systems/run.md)), and `make_sfx.gd`, which writes the sound files
  under `Assets/Sfx/` (see [Audio](systems/audio.md)).
- `Assets/Sfx/` holds the 24 sound effects and 2 music loops as 16-bit
  mono WAV files, stored with Git LFS. `Assets/Voice/` is for voice lines
  baked into the build, named by `Voice.cache_key()` (none yet; see
  [Voice](systems/voice.md)).
- `Data/` holds game content as typed `.tres` resources: `Data/Classes/`,
  `Data/Units/`, `Data/Skills/` and `Data/Passives/` (each class's skill and
  passive), `Data/Rules/` (battle rules and `run_rules.tres`),
  `Data/Stages/` (the run's 12 enemy line-ups), `Data/Sandbox/sandbox.tres`
  (the sandbox's enemy line-ups), `Data/Epiphanies/` (the Kỳ Ngộ options of
  each milestone family), `Data/Bosses/` (the boss Cự Nham, a `UnitData`
  kept apart from the shop's units), `Data/Cutscenes/` (written cutscenes),
  `Data/Audio/sounds.tres` (the sound bank) and `Data/catalog.tres`, which lists every
  unit, class, skill, passive and stage file explicitly so nothing scans directories at runtime (that breaks in
  exported and web builds).
- `Systems/` holds GDScript bridge services and data scripts, one folder per
  system. `Systems/Content/` has `Catalog` (lookup and validation),
  `SandboxData`, `UnitStats` (player-facing stats, derived through
  `Battle`) and `BattleFactory` (a `Battle` with the catalog's rules and
  line-ups added). `Systems/Run/` has the run's rules as pure-data
  GDScript: `RunState` and its parts (`RunRoster`, `Shop`, `RunPiece`),
  the data types `RunRules` and `StageData`, Kỳ Ngộ (`EpiphanyTracker`,
  `EpiphanyFamily`, `EpiphanyData`, `EpiphanyBattle`), and `RunSave` (with
  `RunSaveFields` and `SaveReader` to check a save) and
  `RunSettings` for `user://`. `Systems/Lineup/` has `Lineup`, the single owner of a side's
  formation (pure data with signals), and its data types `LineupSlot` and
  `LineupPreset`. `Systems/Audio/` has the `Audio` autoload
  (`AudioService`), the static facade `Sound` that presentation code calls,
  and the data types `SoundBank` and `SoundData`. `Systems/Voice/` has the
  `Voice` autoload (`VoiceService`) and `VoiceLine`, the optional spoken
  dialogue from the TTS service (see [Voice](systems/voice.md));
  `Scenes/Dev/voice_demo.tscn` tries it by hand. `Scenes/Dev/` holds
  developer pages only and is not exported.
- `Scenes/Board/` holds the reusable battlefield: `BoardView`, `UnitView`,
  `UnitPainter` and `LineupViews`. `Scenes/Battle/` holds `BattlePlayback`
  and `BattleFx`, which play a `Battle` on a board, and `SkillPlayback`,
  `SkillFx` and `SkillOverlay` for skill events. `Scenes/Sandbox/` holds
  the sandbox screen and its setup interaction; it is the only part that
  knows about the sandbox. `Scenes/Run/` holds the run screen and its
  parts (layout, HUD, preparation controller, piece views, rewards, end
  screen, boss HUD, Kỳ Ngộ and story interludes) and `Scenes/Title/` the
  title screen and the "Cách chơi" screen. `Scenes/Cutscene/` holds the
  cutscene screen, its backdrop, ink wipe and choice cards, and
  `EpiphanyCutscene`, which builds a Kỳ Ngộ scene from a run. See
  [Board](systems/board.md), [Battle playback](systems/battle_playback.md)
  and [Run](systems/run.md).
- `UI/` holds the palette, the theme (built in code), and reusable widgets:
  buttons, unit cards, the roster strip, the info panel, the result banner,
  the battle status bars, the drag ghost and the pointer gesture helper, and
  for the run the shop, bench, sell zone, cost buttons, resource chips,
  icons drawn in code, the timer, reward cards and confetti, the Kỳ Ngộ
  seal, the boss badge, bar and card, and the mute button.
- `Locale/strings.csv` holds every player-facing text (columns `keys,vi,en`),
  imported into `strings.vi.translation` and `strings.en.translation` and
  registered in `project.godot`. The fallback locale is `vi`, and `Main`
  sets `vi` at start since Vietnamese is the only player language for now.
  Keys follow the data (`UNIT_*`, `CLASS_*`, `RACE_*`) or the screen
  (`BUTTON_*`, `RESULT_*`, `INFO_*`, `STAGE_*`, `REWARD_*`, `END_*`,
  `FORMATION_*`, `MILESTONE_*`, `HOP_LUC*`, `SYNERGY_*`, `EPIPHANY_*`,
  `CUTSCENE_*`, `STORY_*`, `BOSS_*`, `HOWTO_*`, `SOUND_*`).
- `export_presets.cfg` holds export presets. Each preset excludes `Tests/`,
  `Tools/` and `Scenes/Dev/`.

## Screen flow

`Main` starts on the title screen: "Ván mới" (new run), "Chơi tiếp" (only
with a save), "Bàn thử" (the sandbox, which has a "Về" button back) and the
preparation time setting. A run screen plays one stage after another on the
same board: the preparation (shop, bench, board, timer), then "Ra trận"
slides the shop and buttons away for the side health bars and the battle
plays on the board; the result banner shows what was won or lost, "Tiếp tục"
opens the reward cards, and a reward starts the next preparation. When the
run is won or lost the end screen shows the result and returns to the title.
Every switch between screens is a slide.

When a Kỳ Ngộ fires after a battle, its cutscene plays before the reward
cards, and the choice is made there. After the reward of stage 11, the
story scene with Liễu Mi and Ba Khắc plays before stage 12, the boss
stage. "Cách chơi" on the title screen opens four tips.

## Autoloads

There are two autoloads. An autoload's name is not known when a script
runs with `--script` (the tests), while its node exists at runtime.

- `Audio` (`Systems/Audio/audio.gd`, class `AudioService`) owns the sound
  players, the mute setting and the web audio unlock. Scripts reach it
  through the static class `Sound` because of the `--script` limit. Only
  presentation code plays sounds; the run's rules and the battle never do.
  See [Audio](systems/audio.md).
- `Voice` (`Systems/Voice/voice_service.gd`, class `VoiceService`) is a
  global service because one request queue, one line cache and one
  online/offline state must serve every scene that speaks. Scenes call
  `Voice` directly; `--script` runs cannot use the `Voice` name, so the
  test creates its own `VoiceService`. See [Voice](systems/voice.md).

The run's rules are GDScript, not C++: they decide only what to buy, place
and pay between battles, never how a battle goes, so they need no fixed
point and no lockstep. They still use a seeded generator only, so a seed
replays the same shops. Battles remain in the native `Battle`. See
[Run](systems/run.md).

## Native code

Gameplay systems are written in C++ through GDExtension; scenes compose and
tune them.

- `Native/godot-cpp/` is the godot-cpp submodule (pinned to `10.0.0-stable`,
  Godot 4.7 API).
- `Native/src/` holds the extension sources. `register_types.cpp` registers
  classes with Godot.
- `SConstruct` builds the sources into `bin/`, and `falemag.gdextension` tells
  Godot which library to load on each platform.

`SimClock` is the first native node. It converts frame time into fixed integer
ticks (20 per second by default) and emits `ticked(tick)` for each one. Time is
counted in whole microseconds so every device produces the same tick sequence,
which turn-based combat, auto-battles and lockstep networking can build on.
After a long stall it fires at most `max_ticks_per_frame` ticks and drops the
rest, so a slow phone does not fall further behind.

The class is documented in [SimClock](systems/sim_clock.md). No third-party
plugin is included.

`Native/src/battle/` is the battle system: an auto-battle between two sides
on a 7 x 8 board. Its simulation (`battle_*.h/.cpp`, class `BattleSim`) is
plain C++17 with no Godot headers and no floating point, so a battle gives
the same events and state hash on every device. Bridge classes expose it:
the `ClassData`, `UnitData` and `BattleRulesData` resources and the `Battle`
node, which turns simulation events into dictionaries and signals. `Battle`
does not tick by itself; the caller steps it, for example from
`SimClock.ticked`. See [Battle](systems/battle.md).

`Native/src/skill/` is the skill system inside the battle simulation: Khí,
casts, the 3-star Hậu chiêu, passives and statuses, as plain C++ with
registries of selectors, areas, effects, triggers and conditions keyed by
the ids used in `Data/Skills/` and `Data/Passives/`. `BattleSim` owns the
state and calls into it; its resources (`SkillData`, `SkillEffectData`,
`PassiveData`) live with the other bridge classes in `Native/src/battle/`.
See [Skill](systems/skill.md).

`Native/src/formation/` matches formations (shapes of units on one side's
half, in local coordinates) and `Native/src/rules/` counts class and race
milestones and Hợp Lực and turns everything active into battle modifiers,
both plain C++ with registries of patterns, modifiers and rules keyed by the
ids in `Data/Formations/`, `Data/Synergies/` and `Data/Rules/hop_luc.tres`.
The `Synergy` bridge class (`Native/src/synergy/`) evaluates a line-up
without a battle, for the preparation screen's info row, outlines and drag
preview; `Battle.set_synergy()` applies the same evaluation to both sides at
`start()`. See [Synergy](systems/synergy.md) and
[Formation](systems/formation.md).

## Layers and documentation

Code is organized in three layers (simulation, bridge, presentation) as
described in [Coding conventions](conventions.md). Each system gets a page in
`Docs/systems/`, written from `Docs/systems/_template.md` when the system is
added. A system page written elsewhere before this rule moves there the next
time it changes.
