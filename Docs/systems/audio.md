# Audio

## Purpose

The game's sound: short effects by id and one music loop at a time, with a
mute switch saved in the settings. It only plays: presentation code calls it
on events; the simulation never does, and nothing ever waits for a sound.

## Layer and files

- Layer: presentation (an autoload service).
- Code: `Systems/Audio/audio.gd` (`AudioService`, autoload `Audio`),
  `sound.gd` (`Sound`, static calls), `sound_data.gd`, `sound_bank.gd`;
  `Tools/make_sfx.gd` (the generator).
- Data: `Data/Audio/sounds.tres` (`SoundBank`, in the catalog as
  `sounds`), `Assets/Sfx/*.wav`.
- Depends on: `RunSettings` (mute in `user://settings.json`).

## Data

`SoundData`: `id` (`coin`, `music_prep`), `stream`, `volume_db` (-40..6),
`is_music`. The bank has 24 effects (`ui_tap`, `coin`, `card_flip`, `buy`,
`sell`, `merge`, `level_up`, `timer_tick`, `battle_drum`, `hit_light`,
`hit_heavy`, `arrow`, `spell`, `skill_cast`, `block`, `charge`, `death`,
`formation_on`, `formation_break`, `petrify`, `win`, `lose`, `epiphany`,
`text_blip`) and 2 music loops (`music_prep`, `music_battle`).

All are 16-bit mono 22050 Hz WAVs made by `Tools/make_sfx.gd` from code
(tones, noise, envelopes; effects end with a 6 ms fade, everything is
normalised to -1.9 dBFS). The music loops are 4 s WAVs with a `smpl` loop
chunk, which Godot's importer turns into a forward loop. Sizes: effects
402 KB in all, music 2 × 177 KB. OGG would be smaller but Godot cannot
write it, so the loops are WAV. The files are tracked with Git LFS.

## Behaviour

- Buses `Music` (-10 dB) and `Sfx` (-3 dB) are created under Master if the
  project has none. Effects use a pool of 8 players; music has its own.
- The same id plays again only after 40 ms, and at most 4 voices of one id
  at once; a full pool reuses the oldest voice.
- Effects pitch up by 4% per battle speed step above 1, during the battle
  only: the run screen sets the speed when the battle starts (or the speed
  button is pressed in it) and back to 1 when it ends or the screen
  closes, so preparation and UI sounds keep their pitch.
- An unknown id warns once ("Audio: unknown sound id") and plays nothing.
- Web: nothing plays until `unlock()` (the title calls it on its first
  tap), then the requested music starts. The web export uses Sample
  playback (`audio/general/default_playback_type.web=1`).
- With no sound device (headless runs, CI) nothing is started.
- Mute mutes the Master bus, stops what plays and is saved; the title and
  the run's top bar have the switch.

## Hooks

| Where | Sounds |
| --- | --- |
| Title, buttons, cards | `ui_tap`, music `music_prep` |
| RunScreen (run signals) | `buy`, `sell`, `merge`, `level_up`, `card_flip`, `coin`, `timer_tick` (last 10 s), `battle_drum`, `win` / `lose`, music `music_prep` / `music_battle` |
| SynergyHud | `formation_on` (a new formation), `formation_break` |
| BattlePlayback / SkillPlayback | `hit_light`, `hit_heavy`, `block` (blocked or immune), `arrow`, `charge`, `death`, `skill_cast`, `spell`, `petrify` |
| Cutscene | `text_blip`, `epiphany` |

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `Sound.play(id)` | static | Plays an effect (nothing without the service). |
| `Sound.play_music(id)` | static | Starts a loop; `&""` stops it. |
| `Sound.set_battle_speed(speed)`, `Sound.toggle_muted() -> bool`, `Sound.is_muted()`, `Sound.unlock()`, `Sound.is_unlocked()` | static | |
| `AudioService.count_voices(id)`, `get_music_id()`, `set_bank(bank)`, `set_muted(muted)` | methods | For tests. |

Presentation code calls `Sound`, not `Audio`: scripts run with `--script`
(the tests) do not know autoload names when they compile.

## How to extend

Add a recipe to `EFFECTS` or `MUSIC` in `Tools/make_sfx.gd` and run it (see
[build.md](../build.md)); it rewrites the WAVs and the bank. A recorded WAV
can be dropped in `Assets/Sfx/` and listed in the bank instead.

## Tests

`Tests/audio_test.gd`: the bank (24 + 2, looping music), an unknown id
warning once, the cooldown and voice limit, the web lock, mute saved and
read back (to a test settings file). Nobody has listened to the sounds; the
generator's output was checked by header, length, peak and silence only.

## Known limits

- Synthesised placeholders, not recorded or composed audio.

## iPhone

Safari mutes Web Audio while the iPhone's ring/silent switch is on silent,
and only lets an audio context start from a `touchend` or `click`. The Web
export preset's `html/head_include` holds a small script that:

- sets `navigator.audioSession.type = 'playback'` (Safari 16.4 and later),
  so the game is heard like a video is;
- on older iPhones without that API, loops a silent `<audio>` element from
  the first tap, which moves the page to the playback category too;
- resumes every audio context that is not running on each `touchend`,
  `click` and `keydown` (also after an interruption such as a phone call).

The in-game speaker button is the mute. None of this has been checked on a
real iPhone from the build machine; it was checked that Chromium still
plays.
