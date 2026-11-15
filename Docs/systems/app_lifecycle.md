# App lifecycle

## Purpose

Knows whether the app is hidden and makes a hidden app cost nothing: the
SceneTree pauses and every sound is held, then both come back when it
shows again. It also owns the power-saving switch (low processor mode)
that a battle turns off while it plays. It does not save the run or stop
the game on a lost desktop focus.

## Layer and files

- Layer: presentation (an autoload service).
- Code: `Systems/App/app_lifecycle.gd` (`AppLifecycleService`, autoload
  `AppLifecycle`); the web half is in the Web export preset's
  `html/head_include` (`export_presets.cfg`).
- Depends on: `Audio` (`AudioService.set_suspended()`). Called by
  `BattlePlayback` (full frame rate while a battle plays).

## Data

None. `application/run/low_processor_mode` in `project.godot` says whether
idle screens save power; the service reads it at start into
`is_power_saving_wanted`.

## Behaviour

- **Hidden:** on the web, the page's `visibilitychange` (the callback is
  kept in a member so it is not collected); on Android and iOS,
  `NOTIFICATION_APPLICATION_PAUSED` and `RESUMED`. A desktop window that
  loses focus is not hidden: the game keeps running beside other windows.
- **While hidden:** the tree is paused and `Audio` is suspended (Master
  bus silent, players paused, nothing new starts; `Audio` always
  processes, so the pause alone would not stop it). On the web the
  `head_include` script also suspends every `AudioContext` and pauses the
  silent keep-alive `<audio>`, since a hidden tab's Web Audio would
  otherwise go on playing.
- **Shown again:** the sound comes back at once with the player's own mute
  (`Audio.is_muted()` is never changed); the tree unpauses
  `RESUME_DELAY_FRAMES` (1) frame later, so the first frame, whose delta
  holds the whole hidden time, reaches no timer, tween, preparation clock
  or battle clock. A tree that was paused before it was hidden stays
  paused.
- **Power saving:** with low processor mode Godot draws a frame only when
  something on screen changed, so idle screens (title, preparation) draw
  about 31 frames a second instead of 60: 30 for the shared idle steps
  and about one for labels such as the preparation timer (see
  [Performance](performance.md)). On desktop the mode also sleeps part of
  each frame, which the heaviest scene cannot spare, so `BattlePlayback`
  holds full frame rate from `begin()` until `battle_finished`, `abort()`
  or its exit from the tree. `_apply_power_mode()` is the only code that
  sets `OS.low_processor_usage_mode`.
- The autoload is not a tool script, so it does nothing in the editor; in
  tests it does nothing until a test calls `set_hidden()` or sends it
  `NOTIFICATION_APPLICATION_PAUSED`, which pauses the tree until
  `NOTIFICATION_APPLICATION_RESUMED` and one more frame.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `instance` | static var | The autoload, or null when none is |
| `hold_full_frame_rate(holder: Object, is_held: bool)` | static method | Asks for every frame while `holder` needs it, or gives it back; power saving returns when no holder is left. Does nothing without the autoload |
| `set_hidden(hidden: bool)` | method | Hides or shows the app; the platform calls it, tests call it to simulate |
| `is_hidden() -> bool` | method | True while hidden |
| `is_power_saving_wanted` | property | Whether idle screens save power (the project setting at start) |
| `is_power_saving() -> bool` | method | True while low processor mode is on |
| `set_full_frame_rate(holder, is_held)` | method | What the static call uses |
| `visibility_changed(is_hidden: bool)` | signal | The app was hidden or shown (before the tree unpauses) |

## Log events

None.

## How to extend

Something new that loops on its own (a sound, a timer that runs with
`process_always`, a JavaScript interval) must stop while the app is
hidden: listen to `visibility_changed`, or pause with the tree. Something
that needs every frame drawn while it runs (a new kind of battle) calls
`AppLifecycleService.hold_full_frame_rate(self, true)` and lets go when it
ends or leaves the tree.

## Tests

`Tests/app_lifecycle_test.gd` simulates hiding and showing: the tree pauses
and nothing processes while hidden, the sound is held and comes back, the
tree stays paused on the first frame after showing and then unpauses, the
player's mute and an earlier pause survive, a phone's pause notification
hides while a lost desktop focus does not, and power saving waits for every
holder of full frame rate. Run it with
`godot --headless --path . --script res://Tests/app_lifecycle_test.gd`.

## Known limits

- `SceneTreeTimer`s made with `process_always` (the default of
  `create_timer()`) keep counting while the tree is paused.
- The web half was checked in Chromium with an emulated iPhone; how Safari
  on a real iPhone resumes a suspended `AudioContext` without a tap still
  needs a device (the next tap resumes it in any case).
