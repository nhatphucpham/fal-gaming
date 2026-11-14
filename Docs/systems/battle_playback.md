# Battle playback

## Purpose

Drives a started `Battle` tick by tick and turns the events it returns into
animations on a `BoardView`. It never changes simulation state and reads it
only through `Battle` getters (`get_unit_state` for max hp at the start).

## Layer and files

- Layer: presentation.
- Code: `Scenes/Battle/battle_playback.gd` (`BattlePlayback`, a Node) and
  `Scenes/Battle/battle_fx.gd` (`BattleFx`, short-lived effects) and
  `Scenes/Battle/impact_order.gd` (`ImpactOrder`).
- Depends on: `Battle` and `SimClock` (native), `BoardView` and `UnitView`
  ([Board](board.md)).

## Ticking and speed

`SimClock` keeps the tick maths: `Main` switches off the clock's own
`_process`, and `BattlePlayback.advance(delta)` (called from its
`_process`) calls `SimClock.advance(delta * speed)`. Each `ticked` signal
steps the battle once. The clock's `max_ticks_per_frame` (5) caps catch-up
after a stall and drops the backlog. The clock's `running = false` is not
used for this, because `advance()` ignores calls while not running.

`speed` is 1, 2 or 4 (the x1 / x2 / x4 button). It multiplies the tick rate
and the speed scale of every tween the playback, the effects and the unit
views create, so animations keep pace with the battle.

## Events to animations

Damage and deaths land when the projectile does: each attack records an
impact delay (melee 0.08 s, arrows and bolts by distance, 0.12 to 0.35 s),
and events caused by it wait that long, scaled by speed. So an arrow fired
before a sword swing can land after it. `ImpactOrder`
(`Scenes/Battle/impact_order.gd`) keeps the hp bar in simulation order: an
impact sets a unit's bar only when its event id is newer than the last one
applied to that unit, so the bar never jumps back up. An impact that lands on
a unit already playing its death shows nothing.

| Event | Animation |
| --- | --- |
| `battle_started` | none (the screen has already slid to the battle layout) |
| `unit_moved` `walk` | glide over `duration_ticks`, with a small step bob |
| `unit_moved` `charge` | faster gallop bob, stretched figure, dust puffs along the path |
| `unit_moved` `knockback` | quick skidding slide with a tilt and a dust puff, after the hit lands |
| `unit_attacked` `melee` | lunge toward the target and a slash arc on the target cell |
| `unit_attacked` `ranged` | recoil and an arrow flying in an arc to the target cell |
| `unit_attacked` `magic` | recoil and a bolt, then the three cells of the row flash |
| `damage_dealt` | target flashes white and flinches, a damage number pops and floats (bigger and gold when `is_counter`), the hp bar slides down with a pale trail; with `blocked_by`, a shield flash at the blocker |
| `unit_died` | the unit falls over and fades out |
| `charge_ended` | none (the charge's moves and hit already show it) |
| `battle_ended` | after 0.6 s the winners hop twice, then `battle_finished` fires and the screen shows the result banner |

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `begin(battle, board, views, clock)` | method | Starts playing a started battle; `views` maps unit index to `UnitView`; resets the clock |
| `advance(delta_sec)` | method | Feeds real time (scaled by speed) to the clock; tests call it directly |
| `stop()` | method | Stops ticking; delayed animations still finish |
| `abort()` | method | Stops, drops every delayed animation and forgets the views (the screen frees them next) |
| `get_view_count()` | method | Views still referred to; 0 after `abort()` |
| `speed` | property | 1, 2 or 4 |
| `tick_advanced(tick)` | signal | After each stepped tick (the screen updates the timer and side bars) |
| `battle_finished(winner, reason)` | signal | After the closing animation |

`BattleFx` factories: `arrow`, `bolt`, `cell_flash`, `slash`, `number`,
`shield_flash`, `dust`; add to `board.get_fx_layer()` and call `play(speed)`.
Each draws itself in `_draw` and frees itself at the end.

## Log events

None. Use `Battle.log_enabled` for the simulation's own log.

## How to extend

- **New event type:** add a handler to `_handlers` in `_ready()`.
- **New attack kind:** add a branch for it in `_on_unit_attacked()` and, if
  needed, a `BattleFx` factory.

## Tests

`Tests/sandbox_test.gd` plays a full battle through `advance()` at x4 and
checks that a result is produced, tests the `ImpactOrder` rule, and checks
that the playback forgets its views after "Xếp lại". Animations are checked by eye.

## Known limits

- Effects are freed and recreated rather than pooled; a battle makes a few
  hundred small nodes in total.
- No sound yet.
