class_name PoseRedraws
extends RefCounted
## When a PoseAnimator's figure redraws and blinks, by its own clock of
## real seconds (`now`, the engine's ticks unless a test replaces it):
## about IDLE_PER_SEC while idle, at a phase per figure so units do not
## redraw on the same frame; at most ACTION_PER_SEC while a clip, the run
## or a trail plays, and once more when it stops; blinks of BLINK_SEC every
## BLINK_PERIOD_SEC. Real time keeps all of them the same at any battle
## speed.

const IDLE_PER_SEC: float = 10.0
## A 60 fps screen skips every other frame.
const ACTION_PER_SEC: float = 30.0
const BLINK_PERIOD_SEC: float = 3.4
const BLINK_SEC: float = 0.12

## func() -> float: seconds of real time.
var now: Callable = Callable(PoseRedraws, &"engine_seconds")

var _idle_offset: float = randf()
var _blink_offset: float = randf() * BLINK_PERIOD_SEC
var _idle_slot: int = -1
var _action_slot: int = -1
var _was_active: bool = false


## The engine's real time in seconds, the default clock.
static func engine_seconds() -> float:
	return Time.get_ticks_msec() * 0.001


## True on the frame an idle figure should breathe again.
func is_idle_due() -> bool:
	var slot := floori(now.call() * IDLE_PER_SEC + _idle_offset)
	if slot == _idle_slot:
		return false
	_idle_slot = slot
	return true


## Whether a figure whose clip is `is_active` (or just stopped) redraws on
## this frame; once it has stopped, false and `was_active()` turns false.
func is_action_due(is_active: bool) -> bool:
	var due := false
	if is_active:
		var slot := floori(now.call() * ACTION_PER_SEC)
		due = slot != _action_slot or not _was_active
		if due:
			_action_slot = slot
	else:
		due = _was_active
	_was_active = is_active
	return due


## True while the last frame still had something playing.
func was_active() -> bool:
	return _was_active


## 1 (shut) during a blink, else 0 (open).
func get_blink() -> int:
	return 1 if fmod(now.call() + _blink_offset, BLINK_PERIOD_SEC) < BLINK_SEC else 0
