class_name PoseAnimator
extends Node
## Plays the key-pose clips of one rigged figure (port of the sketch's
## actor: `play` and `update`): idle breathing and blinks, the run, attack,
## skill wind-up and release, hit, knockback, death and cheer, each easing
## from the pose it starts at. After a clip the figure settles to its rest
## pose: the class's stance in a fight, its idle pose otherwise. It owns the
## current UnitPose and the weapon trail, and asks the figure to redraw only
## when the pose changes: at most ACTION_REDRAWS_PER_SEC while a clip runs,
## about IDLE_REDRAWS_PER_SEC (staggered per unit) while idling, on blinks
## only while calm, never while frozen (stone) or after death.
## UnitView owns one; see the call table in Docs/systems/board.md.
## [codeblock]
## var animator := PoseAnimator.new(figure)
## animator.set_class(&"class.sword")
## animator.set_view(RigSolver.VIEW_BACK)
## view.add_child(animator)
## animator.attack(PI / 2.0)
## [/codeblock]

const IDLE_REDRAWS_PER_SEC: float = 10.0
## Redraws a second while a clip runs (a 60 fps screen skips every other).
const ACTION_REDRAWS_PER_SEC: float = 30.0
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
const BLINK_PERIOD_SEC: float = 3.4
const BLINK_SEC: float = 0.12
const TRAIL_SAMPLES: int = 14
const TRAIL_FADE_PER_SEC: float = 7.0
const TRAIL_MIN: float = 0.03
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
## The weapon trail in figure space: (tip, inner edge) per sample, oldest
## first, with a weight per sample.
var trail := PackedVector2Array()
var trail_weights := PackedFloat32Array()

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
var _slot_offset: float = 0.0
var _idle_slot: int = -1
var _action_slot: int = -1
var _was_active: bool = false
## The last wind-up key's pose: held until the release, also after a charge.
var _wind_pose: UnitPose
var _trail_slot: int = -1
var _eyes_shown: int = 0


func _init(figure: CanvasItem) -> void:
	_figure = figure
	_slot_offset = randf()
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
	return not _queue.is_empty() or _walk_left > 0.0 or not trail_weights.is_empty()


## True for classes that face the target with the off hand (archers).
func aims_off_hand() -> bool:
	return _kit != null and _kit.aims_off_hand


func _process(delta: float) -> void:
	if _kit == null:
		return
	var dt := delta * playback_speed
	var is_active := _advance(dt)
	_update_trail(dt)
	is_active = is_active or not trail_weights.is_empty()
	if is_dead:
		_redraw_while(is_active)
		if not is_active and not _was_active:
			set_process(false)
		return
	if is_active or _was_active:
		_redraw_while(is_active)
		return
	if _is_holding:
		# A held wind-up keeps its pose: no breathing over it.
		return
	if is_swaying:
		# Real time, not battle time: idle redraws stay about 10 a second at x4.
		var slot := floori(Time.get_ticks_msec() * 0.001 * IDLE_REDRAWS_PER_SEC + _slot_offset)
		if slot != _idle_slot:
			_idle_slot = slot
			_breathe()
			_figure.queue_redraw()
	elif _get_blink() != _eyes_shown:
		_breathe()
		_figure.queue_redraw()


## Runs for `seconds` (the run cycle), dropping the fight stance; a charge
## runs (gallops) faster and keeps a wind-up glowing for its release. A
## plain walk cancels a wind-up and any clip.
func walk(seconds: float, is_charge: bool) -> void:
	if is_dead or _kit == null:
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
	var keys := _skill_keys()
	var wind_seconds := 0.0
	for index: int in _kit.skill_wind_keys:
		wind_seconds += keys[index].seconds
	var stretch := seconds / wind_seconds if seconds > 0.0 else 1.0
	var wind: Array[RigClips.ClipKey] = []
	for index: int in _kit.skill_wind_keys:
		wind.append(RigClips.ClipKey.new(keys[index].seconds * stretch, keys[index].easing, keys[index].pose))
	_wind_pose = wind.back().pose
	_start(wind)
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
	var keys := _skill_keys()
	_start(keys.slice(_kit.skill_wind_keys))


## Flinches back with hurt eyes (a shield braces its shield). A wind-up or
## a charge holds; only the view's flash shows the hit.
func hit() -> void:
	if is_dead or is_frozen or _kit == null or is_winding or _walk_left > 0.0:
		return
	_play(&"hit")


## Leans back for `seconds` (pushed by a knockback).
func flinch_for(seconds: float) -> void:
	if is_dead or _kit == null or is_winding:
		return
	_walk_left = 0.0
	var lean := _kit.get_clip(&"hit", view)[0].pose.merged({"flash": 0})
	_start([
		RigClips.ClipKey.new(KNOCKBACK_LEAN_SEC, RigClips.Easing.OUT, lean),
		RigClips.ClipKey.new(seconds, RigClips.Easing.LINEAR, lean),
		RigClips.ClipKey.new(KNOCKBACK_SETTLE_SEC, RigClips.Easing.IN_OUT, get_stance()),
	])


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
	if is_dead or _kit == null:
		return
	if is_winding:
		_cancel_wind_up()
	is_in_combat = false
	_is_charging = false
	_walk_left = 0.0
	_play(&"cheer")


## Freezes the pose as it is (no clip, breathing or blink), or thaws it. A
## hit flash and the weapon trail do not turn to stone with it.
func set_frozen(frozen: bool) -> void:
	is_frozen = frozen
	if frozen and pose != null:
		pose = pose.merged({"flash": 0, "trail": 0})
		trail.clear()
		trail_weights.clear()
		if _figure != null:
			_figure.queue_redraw()
	# The node stops processing, so nothing moves.
	process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT


func _play(clip_name: StringName) -> void:
	_start(_kit.get_clip(clip_name, view))
	_is_holding = clip_name == &"fall"


func _start(keys: Array) -> void:
	trail.clear()
	trail_weights.clear()
	_queue.assign(keys)
	_from = pose
	_key_time = 0.0
	_is_holding = false


func _skill_keys() -> Array[RigClips.ClipKey]:
	return _kit.get_clip(&"skillUp" if view == RigSolver.VIEW_BACK else &"skillDown", view)


func _cancel_wind_up() -> void:
	is_winding = false
	_release_left = 0.0
	_is_holding = false
	_queue.clear()


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
			_is_charging = false
			# A wind-up carried through a charge settles back to its held pose.
			var settle := _wind_pose.merged({"glow": 1}) if is_winding else get_stance()
			_start([RigClips.ClipKey.new(WALK_SETTLE_SEC, RigClips.Easing.IN_OUT, settle)])
			_is_holding = is_winding
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
	var rest := get_stance()
	var bob := sin(_clock * BREATH_SPEED) if is_swaying else 0.0
	var swing := sin(_clock * BREATH_SPEED - 0.6) if is_swaying else 0.0
	_eyes_shown = _get_blink()
	var v := rest.values
	pose = rest.with_fields({
		"torso": v[UnitPose.TORSO] + 0.8 * bob, "head": v[UnitPose.HEAD] - 0.6 * bob, "hip": v[UnitPose.HIP] - 0.25 * (1.0 + bob),
		"uaF": v[UnitPose.UA_F] + 1.5 * bob, "uaB": v[UnitPose.UA_B] - 1.5 * bob, "blade": v[UnitPose.BLADE] + 1.5 * swing,
		"eyes": _eyes_shown,
	})


func _get_blink() -> int:
	return 1 if fmod(_clock, BLINK_PERIOD_SEC) < BLINK_SEC else 0


func _rest_now() -> void:
	if _kit == null:
		pose = UnitPose.new()
		_from = pose
		return
	pose = get_stance()
	_from = pose
	if _figure != null:
		_figure.queue_redraw()


# Samples the weapon tip while the pose swings (trail > 0), else fades.
func _update_trail(dt: float) -> void:
	if pose.values[UnitPose.TRAIL] > TRAIL_MIN:
		# One sample per redraw slot: solving the rig every frame is wasted.
		var slot := floori(Time.get_ticks_msec() * 0.001 * ACTION_REDRAWS_PER_SEC)
		if slot == _trail_slot:
			return
		_trail_slot = slot
		var still := pose.merged({"dx": 0}) if pose.values[UnitPose.DX] != 0.0 else pose
		trail.append_array(_kit.get_trail_points(RigSolver.solve(still, view), still))
		trail_weights.append(1.0)
	elif not trail_weights.is_empty():
		for index: int in trail_weights.size():
			trail_weights[index] -= dt * TRAIL_FADE_PER_SEC
	var first := 0
	while first < trail_weights.size() and trail_weights[first] <= 0.0:
		first += 1
	first = maxi(first, trail_weights.size() - TRAIL_SAMPLES)
	if first > 0:
		trail_weights = trail_weights.slice(first)
		trail = trail.slice(first * 2)


# Redraws at most ACTION_REDRAWS_PER_SEC while `is_active`, and once more
# when it stops, so the last pose is drawn.
func _redraw_while(is_active: bool) -> void:
	if is_active:
		var slot := floori(Time.get_ticks_msec() * 0.001 * ACTION_REDRAWS_PER_SEC)
		if slot != _action_slot or not _was_active:
			_action_slot = slot
			_figure.queue_redraw()
	elif _was_active:
		_figure.queue_redraw()
	_was_active = is_active
