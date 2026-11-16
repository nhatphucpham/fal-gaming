class_name IdleTicks
extends RefCounted
## The shared clock of everything that animates while the player is idle
## (figures breathing, card glows, near-miss outlines), so their redraws
## fall on the same few frames and low processor mode can skip the others.
## Real time is cut into steps of 1/STEPS_PER_SEC s; an idle figure breathes
## once per tick of IDLE_PHASES steps, on the step of its phase, and pulses
## that need to look smooth redraw on every step. The clock is read once per
## process frame (engine_seconds), so every node sees the same step in a
## frame and one step costs one changed frame: the idle redraws need at
## most STEPS_PER_SEC changed frames a second, plus whatever else changes
## (a label, a timer). See Docs/systems/performance.md.
## [codeblock]
## var step := IdleTicks.current_step()
## if step != _last_step: _last_step = step; queue_redraw()
## [/codeblock]

## Idle redraws a second for one figure.
const PER_SEC: float = 10.0
## Phases one idle tick is split into: figures spread over them.
const IDLE_PHASES: int = 3
## Steps a second: the most distinct frames idle redraws use.
const STEPS_PER_SEC: float = PER_SEC * IDLE_PHASES


static var _cached_frame: int = -1
static var _cached_seconds: float = 0.0


## The engine's real time in seconds, the default clock. It is read once
## per process frame and the same value is returned for the rest of that
## frame, so a step boundary never falls between two nodes of one frame.
static func engine_seconds() -> float:
	var frame := Engine.get_process_frames()
	if frame != _cached_frame:
		_cached_frame = frame
		_cached_seconds = Time.get_ticks_msec() * 0.001
	return _cached_seconds


## The shared step of the current process frame.
static func current_step() -> int:
	return step_at(engine_seconds())


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
