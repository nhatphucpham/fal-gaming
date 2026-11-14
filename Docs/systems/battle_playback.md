# Battle playback

## Purpose

Drives a started `Battle` tick by tick and turns the events it returns into
animations on a `BoardView`. It never changes simulation state and reads it
only through `Battle` getters (`get_unit_state` for max hp at the start).

## Layer and files

- Layer: presentation.
- Code: `Scenes/Battle/battle_playback.gd` (`BattlePlayback`, a Node),
  `Scenes/Battle/battle_fx.gd` (`BattleFx`, short-lived effects),
  `Scenes/Battle/impact_order.gd` (`ImpactOrder`), and for skills
  `Scenes/Battle/skill_playback.gd` (`SkillPlayback`, the skill event
  handlers), `Scenes/Battle/skill_fx.gd` (`SkillFx`, skill effects) and
  `Scenes/Battle/skill_overlay.gd` (`SkillOverlay`, the marks on a unit),
  and for synergies `Scenes/Battle/synergy_playback.gd` (`SynergyPlayback`).
- Depends on: `Battle` and `SimClock` (native), `BoardView` and `UnitView`
  ([Board](board.md)), `Catalog` (skill names), [Skill](skill.md) events.

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
| `damage_dealt` | target flashes white and flinches, a damage number pops and floats (bigger and gold when `is_counter`; gold with "!" when `is_crit`), the hp bar slides down with a pale trail; with `blocked_by`, a shield flash at the blocker. Skill damage may add its own look (below) |
| `unit_died` | the unit falls over and fades out; a boss instead cracks all over and crumbles (`UnitView.crumble()`, see [Boss](boss.md)) |
| `charge_ended` | none (the charge's moves and hit already show it) |
| `battle_ended` | after 0.6 s the winners hop twice, then `battle_finished` fires and the screen shows the result banner |
| `qi_changed` | the thin blue Khí bar under the hp bar fills; when full its frame glows and pulses |
| `skill_cast_started` | 0.2 s wind-up (crouch and rise), a glow at the caster's feet in its class colour until it resolves, the skill's cells lit in that colour with one outline around the area for the cast, and the skill name rising over the caster for 0.6 s |
| `skill_resolved` | a 2.5 px shake of the pieces and effects for 0.15 s and the skill's effect (table below) |
| `passive_triggered` | the passive icon (a diamond left of the hp bar) blinks once; no text |
| `status_applied`, `status_ended` | a small icon right of the hp bar while it lasts: red "!" taunted, indigo shield guard, cracked ochre shield armor break, gold star stun; a taunt also bounces a "!" over the taunted unit |
| `synergy_activated` | none here: the screen's roll call (outlines flash, names stamp, the Hợp Lực ring bounces) plays when the battle starts, see [Synergy](synergy.md) |
| `formation_broken` | the `formation_broken(side, id, cells)` signal; the screen shatters the outline of that instance (matched by its cells) |
| `modifier_triggered` | by handler, with the hit it belongs to: block "Chặn", reflection "Phản", charge immunity "Mất đà", double hit a gold cell flash and "Gấp đôi", split thin lines from the unit hit to the other members and "Chia đòn", volley the archer recoils and the formation name shows (its arrows fall like Tiễn Vũ's) |
| `damage_dealt` with `is_blocked_by_modifier` | no number (the "Chặn" says it) |
| `damage_dealt` with `is_immune` | no number and no flash: the hit bounces off a petrified unit |
| `status_applied` / `status_ended` of `status.petrified` | the unit stops its cast glow, turns grey with a steel sheen and cracks (`UnitView.set_petrified()`, drawn by `StoneLayer`), "Hóa Đá" pops above it, a steel icon shows by its hp bar, and `unit_petrified(index, true)` fires; the end reverses it and fires `unit_petrified(index, false)` |

Skill effects, from `SkillPlayback`'s registry by skill id:

| Skill | Effect |
| --- | --- |
| `skill.hold_ground` | a ring spreading over the ground around the shield |
| `skill.sweep` | a wide arc over the three cells in front |
| `skill.heart_pierce` | a long thrust line down the column |
| `skill.breakthrough` | dust at the start, a star burst on each impact |
| `skill.arrow_rain`, `formation.arrow_rain` (volley) | one arrow falls per hit, 0.07 s apart; each hit lands with its arrow |
| `skill.arcane_circle` and any skill not in the registry | a spinning glyph on each cell |

Big effects are capped at 3 at a time (a resolve over the cap shows only the
shake and the damage) and name popups at 3; popups of casters side by side
stack instead of overlapping and stay on the board. Everything uses the
battle speed.

Sounds go through `Sound.play()` (see [Audio](audio.md)): `skill_cast` on
a cast start, `spell` on a resolve, `arrow` and `charge` on those moves,
`hit_light` per hit, `hit_heavy` for a crit or a hit of 120 or more,
`block` for a blocked or immune hit, `death`, and `petrify`. The audio
service drops repeats inside 40 ms and keeps at most four voices of one
sound, so a volley stays readable. The run screen sets the pitch from the
battle speed with `Sound.set_battle_speed()`.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `begin(battle, board, views, clock, catalog = null)` | method | Starts playing a started battle; `views` maps unit index to `UnitView`; resets the clock; sets each view's Khí; `catalog` names skills in popups (none without it) |
| `get_view(index)`, `spawn_fx(fx)`, `run_after(seconds, action)`, `cell_center(cell)`, `get_ticks_per_second()`, `get_shake_layers()` | methods | Helpers `SkillPlayback` uses; `run_after` waits battle time at the current speed and is dropped by `abort()` |
| `advance(delta_sec)` | method | Feeds real time (scaled by speed) to the clock; tests call it directly |
| `stop()` | method | Stops ticking; delayed animations still finish |
| `abort()` | method | Stops, drops every delayed animation and forgets the views (the screen frees them next) |
| `get_view_count()` | method | Views still referred to; 0 after `abort()` |
| `speed` | property | 1, 2 or 4 |
| `tick_advanced(tick)` | signal | After each stepped tick (the screen updates the timer and side bars) |
| `battle_finished(winner, reason)` | signal | After the closing animation |
| `formation_broken(side, formation_id, cells)` | signal | A formation instance lost a member; `cells` are its members' global cells |
| `unit_petrified(index, is_petrified)` | signal | A unit turned to stone or back (the run screen's boss bar shows it) |
| `get_impact_delay(event_id)`, `show_source_name(view, source_id, color)` | methods | Helpers `SynergyPlayback` uses |

`BattleFx` factories: `arrow`, `bolt`, `cell_flash`, `slash`, `number`,
`shield_flash`, `dust`; `SkillFx` (a `BattleFx`) adds `area_glow`,
`name_popup`, `ground_ring`, `taunt_mark`, `wide_slash`, `thrust`, `burst`,
`falling_arrow`, `glyph`. Add to `board.get_fx_layer()` (or use
`spawn_fx`) and call `play(speed)`. Each draws itself in `_draw` and frees
itself at the end. `UnitView` adds `set_qi(qi, qi_max)`, `wind_up(seconds)`
and `skill_overlay` (`set_casting`, `add_status`, `remove_status`,
`blink_passive`).

## Log events

None. Use `Battle.log_enabled` for the simulation's own log.

## How to extend

- **New event type:** add a handler to `_handlers` in `_ready()` (skill
  events: `SkillPlayback.get_handlers()`, synergy events:
  `SynergyPlayback.get_handlers()`).
- **A modifier proc's look:** add its handler id to `_looks` in
  `SynergyPlayback._init()`.
- **A skill's look:** add its id to `_resolvers` (on resolve) or
  `_damage_looks` (per damage event, may delay the hit) in
  `SkillPlayback._init()`, with a `SkillFx` factory if needed. A status icon
  goes in `SkillOverlay`'s `_painters`.
- **New attack kind:** add a branch for it in `_on_unit_attacked()` and, if
  needed, a `BattleFx` factory.

## Tests

`Tests/sandbox_test.gd` plays a full battle through `advance()` at x4 and
checks that a result is produced, tests the `ImpactOrder` rule, and checks
that the playback forgets its views after "Xếp lại"; skills fire in that
battle, so their handlers run headless. Animations are checked by eye.

## Known limits

- Effects are freed and recreated rather than pooled; a battle makes a few
  hundred small nodes in total.
- Sounds are generated (see [Audio](audio.md)); nobody has listened to
  them on a device yet.
