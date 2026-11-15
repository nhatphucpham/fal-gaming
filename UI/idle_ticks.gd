class_name IdleTicks
extends RefCounted
## The shared clock of everything that animates while the player is idle
## (figures breathing, card glows, near-miss outlines), so their redraws
## fall on the same few frames and low processor mode can skip the others.
## Real time is cut into steps of 1/STEPS_PER_SEC s; an idle figure breathes
## once per tick of IDLE_PHASES steps, on the step of its phase, so idle
## figures redraw on at most STEPS_PER_SEC distinct frames a second. Pulses
## that need to look smooth redraw on every step. See
## Docs/systems/performance.md.
## [codeblock]
## var step := IdleTicks.step_at(IdleTicks.engine_seconds())
## if step != _last_step: _last_step = step; queue_redraw()
## [/codeblock]

## Idle redraws a second for one figure.
const PER_SEC: float = 10.0
## Phases one idle tick is split into: figures spread over them.
const IDLE_PHASES: int = 3
## Steps a second: the most distinct frames idle redraws use.
const STEPS_PER_SEC: float = PER_SEC * IDLE_PHASES


## The engine's real time in seconds, the default clock.
static func engine_seconds() -> float:
	return Time.get_ticks_msec() * 0.001


## The shared step at `seconds` of real time.
static func step_at(seconds: float) -> int:
	return floori(seconds * STEPS_PER_SEC)


## The idle tick of `phase` (0..IDLE_PHASES-1) at `seconds`: it changes
## PER_SEC times a second, always on a step boundary.
static func idle_tick_at(seconds: float, phase: int) -> int:
	return floori(float(step_at(seconds) + phase) / IDLE_PHASES)


## A phase for a new figure.
static func random_phase() -> int:
	return randi() % IDLE_PHASES
