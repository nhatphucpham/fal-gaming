class_name PoseAnimator
extends Node
## Plays the key-pose clips of one rigged figure (port of the sketch's
## actor: `play` and `update`): idle breathing and blinks, the run, attack,
## skill wind-up and release, hit, knockback, death and cheer, each easing
## from the pose it starts at. After a clip the figure settles to its rest
## pose: the class's stance in a fight, its idle pose otherwise. It owns the
## current UnitPose and the WeaponTrail, and asks the figure to redraw only
## when the pose changes, as PoseRedraws times it (by real time): at most 30
## times a second while a clip runs, 10 (on one of the shared IdleTicks
## phases) while idling, on blinks only while calm, never while frozen (stone) or after
## death. Each frame steps the clips by its time times the battle speed, at
## most MAX_BATTLE_STEP_SEC (as far as the battle itself steps in a frame).
## UnitView owns one; see the call table in Docs/systems/board.md.
## [codeblock]
## var animator := PoseAnimator.new(figure)
## animator.set_class(&"class.sword")
## animator.set_view(RigSolver.VIEW_BACK)
## view.add_child(animator)
## animator.attack(PI / 2.0)
## [/codeblock]

## The longest step of battle time in one frame. Mirrors the SimClock's
## catch-up limit (max_ticks_per_frame 5 at 20 ticks a second, a property
## of its instance, not a constant), so the poses keep up with the board.
const MAX_BATTLE_STEP_SEC: float = 0.25
## A wind-up with no release after this long past its end releases anyway.
const RELEASE_GRACE_SEC: float = 0.1
## Strides a second running and galloping; a charge goes faster.
const RUN_STRIDES_PER_SEC: float = 3.2
const RIDE_STRIDES_PER_SEC: float = 2.6
const CHARGE_STRIDE_FACTOR: float = 1.5
const WALK_BLEND_SEC: float = 0.18
const WALK_SETTLE_SEC: float = 0.22
const REST_SETTLE_SEC: float = 0.3
const BREATH_SPEED: float = 2.4
const KNOCKBACK_LEAN_SEC: float = 0.06
const KNOCKBACK_SETTLE_SEC: float = 0.26

## The pose drawn now. Replaced, never changed in place.
var pose: UnitPose
## Multiplies the speed of every clip and of the run; running clips change
## speed too.
var playback_speed: float = 1.0
## In a fight the figure rests in its class's stance.
var is_in_combat: bool = false
var is_dead: bool = false
## Frozen (turned to stone): the pose holds exactly as it is.
var is_frozen: bool = false
## True between wind_up() and its release (or cancel).
var is_winding: bool = false
## False holds the idle breathing still: only blinks redraw (bench, the
## dimmed waiting line-up).
var is_swaying: bool = true
## RigSolver.VIEW_BACK (player) or VIEW_FRONT (enemy): picks the clips.
var view: StringName = RigSolver.VIEW_BACK
## The weapon trail in figure space.
var trail := WeaponTrail.new()
## When the figure redraws and blinks; its `now` is the replaceable clock.
var redraws := PoseRedraws.new()

var _figure: CanvasItem
var _kit: RigKit
var _from: UnitPose
var _queue: Array[RigClips.ClipKey] = []
var _key_time: float = 0.0
var _walk_left: float = 0.0
var _walk_time: float = 0.0
var _walk_phase: float = 0.0
var _is_charging: bool = false
var _is_holding: bool = false
var _release_left: float = 0.0
var _clock: float = 0.0
var _eyes_shown: int = 0


func _init(figure: CanvasItem) -> void:
	_figure = figure
	_clock = randf() * 5.0


## Picks the class kit from its class id; figures outside the rig (the
## boss, the sage) get none and every action does nothing.
func set_class(class_id: StringName) -> void:
	_kit = RigKit.get_kit(class_id) if UnitPainter.is_posable(class_id) else null
	_rest_now()


## Seen from behind (the player's units) or from the front (the enemy's).
func set_view(rig_view: StringName) -> void:
	view = rig_view
	_rest_now()


## The rest pose the unit holds now: its stance in a fight, else idle.
func get_stance() -> UnitPose:
	if _kit == null:
		return null
	return _kit.stance[view] if is_in_combat else _kit.idle[view]


## Seconds of animation time, for the idle sway of cloth and plumes.
func get_clock() -> float:
	return _clock


## True while a clip, the run or a trail plays (not idle breathing).
func is_animating() -> bool:
	return not _queue.is_empty() or _walk_left > 0.0 or not trail.is_empty()


## Replaces the real-time clock (func() -> float, seconds) that times the
## redraws and blinks, for tests that step the animator by hand.
func set_clock(now: Callable) -> void:
	redraws.now = now


## True for classes that face the target with the off hand (archers).
func aims_off_hand() -> bool:
	return _kit != null and _kit.aims_off_hand


func _process(delta: float) -> void:
	if _kit == null:
		return
	var dt := minf(delta * playback_speed, MAX_BATTLE_STEP_SEC)
	var is_active := _advance(dt)
	trail.update(pose, _kit, view, dt)
	is_active = is_active or not trail.is_empty()
	if is_active or redraws.was_active():
		if redraws.is_action_due(is_active):
			_figure.queue_redraw()
		if is_dead and not is_active:
			set_process(false)
		return
	if is_dead:
		set_process(false)
		return
	if _is_holding:
		# A held wind-up keeps its pose: no breathing over it.
		return
	if is_swaying:
		if redraws.is_idle_due():
			_breathe()
			_figure.queue_redraw()
	elif redraws.is_idle_due() and redraws.get_blink() != _eyes_shown:
		# Blinks are seen on the figure's idle ticks, like the breathing,
		# so a calm figure redraws on the shared frames too.
		_breathe()
		_figure.queue_redraw()


## Runs for `seconds` (the run cycle), dropping the fight stance; a charge
## runs (gallops) faster and keeps a wind-up glowing for its release. A
## plain walk cancels a wind-up and any clip.
func walk(seconds: float, is_charge: bool) -> void:
	if is_dead or is_frozen or _kit == null:
		return
	if is_winding and not is_charge:
		_cancel_wind_up()
	_is_charging = is_charge
	if not is_charge:
		is_in_combat = false
		_queue.clear()
		_is_holding = false
	if _queue.is_empty():
		_from = pose
		_walk_time = 0.0
	_walk_left = seconds


## A basic attack toward the enemy: the class's Up clip seen from behind,
## its Down clip from the front (the flip turns it to the target, so the
## aim angle is not needed). During a wind-up it is the skill's release.
func attack(_aim: float) -> void:
	if is_dead or _kit == null:
		return
	is_in_combat = true
	if is_winding:
		release()
		return
	if not _is_charging:
		_walk_left = 0.0
	_play(&"attackUp" if view == RigSolver.VIEW_BACK else &"attackDown")


## The skill clip's wind-up keys, stretched over `seconds` (the cast), then
## held until release() (the next attack), or released by itself shortly
## after `seconds`.
func wind_up(seconds: float) -> void:
	if is_dead or _kit == null:
		return
	is_in_combat = true
	is_winding = true
	_start(_kit.get_wind_up(view, seconds))
	_is_holding = true
	_release_left = seconds + RELEASE_GRACE_SEC
	if not _is_charging:
		_walk_left = 0.0


## The skill's strike after a wind-up: the rest of the skill clip. Does
## nothing without a wind-up.
func release() -> void:
	if not is_winding or is_dead:
		return
	is_winding = false
	_release_left = 0.0
	_is_holding = false
	_start(_kit.get_skill_clip(view).slice(_kit.skill_wind_keys))


## Drops a wind-up without its strike (the cast was cancelled: stun,
## stone) and settles from where it shows to the rest pose; a run goes on.
func cancel_wind_up() -> void:
	if is_winding:
		_cancel_wind_up()


## Flinches back with hurt eyes (a shield braces its shield). A wind-up or
## a charge holds; only the view's flash shows the hit.
func hit() -> void:
	if is_dead or is_frozen or _kit == null or is_winding or _walk_left > 0.0:
		return
	_play(&"hit")


## Leans back for `seconds` (pushed by a knockback).
func flinch_for(seconds: float) -> void:
	if is_dead or is_frozen or _kit == null or is_winding:
		return
	_walk_left = 0.0
	_is_charging = false
	_start(_kit.get_flinch(view, seconds, KNOCKBACK_LEAN_SEC, KNOCKBACK_SETTLE_SEC, get_stance()))


## Falls and stays down with shut eyes; idle stops for good.
func die() -> void:
	set_frozen(false)
	is_dead = true
	is_winding = false
	_is_charging = false
	_walk_left = 0.0
	_release_left = 0.0
	if _kit == null:
		return
	_play(&"fall")
	set_process(true)


## Weapon raised with happy eyes and two hops, for the winners. Ends a
## wind-up without its strike.
func cheer() -> void:
	if is_dead or is_frozen or _kit == null:
		return
	if is_winding:
		_cancel_wind_up()
	is_in_combat = false
	_is_charging = false
	_walk_left = 0.0
	_play(&"cheer")


## Freezes the pose as it is (no clip, breathing or blink), or thaws it. A
## hit flash, the weapon trail and a wind-up's glow do not turn to stone
## with it. The running clip and run end there and a wind-up is cancelled
## (the cast is): after the thaw the figure settles from the stone pose to
## its rest pose without a strike. A statue takes no new run, knockback or
## cheer.
func set_frozen(frozen: bool) -> void:
	is_frozen = frozen
	if frozen and pose != null and _kit != null:
		cancel_wind_up()
		_queue.clear()
		_key_time = 0.0
		pose = pose.merged({"flash": 0, "trail": 0, "glow": 0})
		_from = pose
		_walk_left = 0.0
		_is_charging = false
		trail.clear()
		if _figure != null:
			_figure.queue_redraw()
	# The node stops processing, so nothing moves.
	process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT


func _play(clip_name: StringName) -> void:
	_start(_kit.get_clip(clip_name, view))
	_is_holding = clip_name == &"fall"


func _start(keys: Array) -> void:
	trail.clear()
	_queue.assign(keys)
	_from = pose
	_key_time = 0.0
	_is_holding = false


func _cancel_wind_up() -> void:
	is_winding = false
	_release_left = 0.0
	_is_holding = false
	_queue.clear()
	# The settle (or the run) starts from what shows.
	_from = pose
	_walk_time = 0.0


# One step of the sketch's update(); true while a clip, the run or a
# settle plays.
func _advance(dt: float) -> bool:
	_clock += dt
	if _release_left > 0.0:
		_release_left -= dt
		if _release_left <= 0.0 and is_winding:
			release()
	if not _queue.is_empty():
		var gallop := pose.values[UnitPose.HG]
		_run_on(dt)
		_play_key(dt)
		if _kit.is_mounted:
			_gallop_under_clip(dt, gallop)
		return true
	if _walk_left > 0.0:
		_walk_time += dt
		_run_on(dt)
		var target := _kit.get_walk_pose(_walk_phase, view)
		if is_winding:
			target = target.merged({"glow": 1})
		pose = UnitPose.blend(_from, target, RigClips.eased(RigClips.Easing.IN_OUT, minf(1.0, _walk_time / WALK_BLEND_SEC)))
		if _walk_left <= 0.0:
			_start([RigClips.ClipKey.new(WALK_SETTLE_SEC, RigClips.Easing.IN_OUT, get_stance())])
		return true
	if _is_holding:
		return false
	if _from != get_stance():
		_start([RigClips.ClipKey.new(REST_SETTLE_SEC, RigClips.Easing.IN_OUT, get_stance())])
		return true
	return false


# The horse keeps galloping under a strike made on the run: from the
# amount `shown` before this frame its gallop rises over WALK_BLEND_SEC
# while the run goes on and slows over WALK_SETTLE_SEC once it ends, never
# below the clip's own amount.
func _gallop_under_clip(dt: float, shown: float) -> void:
	var own := pose.values[UnitPose.HG]
	var gallop := own
	if _walk_left > 0.0:
		gallop = clampf(shown + dt / WALK_BLEND_SEC, own, 1.0)
	elif shown > own:
		gallop = maxf(own, shown - dt / WALK_SETTLE_SEC)
	if gallop != own:
		pose = pose.merged({"hg": gallop, "hph": _walk_phase})
	if _queue.is_empty():
		# The clip just ended: the run or the settle goes on from what shows.
		_from = pose


func _run_on(dt: float) -> void:
	if _walk_left <= 0.0:
		return
	_walk_left -= dt
	if _walk_left <= 0.0:
		_is_charging = false
	var strides := RIDE_STRIDES_PER_SEC if _kit.is_mounted else RUN_STRIDES_PER_SEC
	_walk_phase += dt * strides * (CHARGE_STRIDE_FACTOR if _is_charging else 1.0)


func _play_key(dt: float) -> void:
	var key := _queue[0]
	_key_time += dt
	pose = UnitPose.blend(_from, key.pose, RigClips.eased(key.easing, minf(1.0, _key_time / key.seconds)))
	if _key_time < key.seconds:
		return
	_from = key.pose
	pose = key.pose
	_key_time -= key.seconds
	_queue.pop_front()
	if _queue.is_empty() and _walk_left > 0.0:
		_from = pose
		_walk_time = 0.0


# The rest pose breathing (the sketch's idle bob), with a blink now and then.
func _breathe() -> void:
	_eyes_shown = redraws.get_blink()
	var rest := get_stance()
	pose = RigClips.breathing(rest, _clock * BREATH_SPEED, _eyes_shown) if is_swaying else RigClips.held_breath(rest, _eyes_shown)


func _rest_now() -> void:
	if _kit == null:
		pose = UnitPose.new()
		_from = pose
		return
	pose = get_stance()
	_from = pose
	if _figure != null:
		_figure.queue_redraw()
