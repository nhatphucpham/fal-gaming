class_name PoseAnimator
extends Node
## Plays the pose animations of one figure: idle sway and blinks, walk and
## gallop, attack, skill wind-up and release, hit, death and cheer. It owns
## the UnitPose and asks the figure to redraw only when the pose changed:
## at most ACTION_REDRAWS_PER_SEC while an action runs, about
## IDLE_REDRAWS_PER_SEC (staggered per unit) while only idling, on blinks
## only while calm, never while frozen (stone) or after death.
## Every pose field has its own track (one tween), so an animation only ever
## restarts the fields it moves and each track ends at that field's rest;
## the strike settles to the current stance whenever its track ends.
## Tracks follow playback_speed (the battle speed), also while running.
## UnitView owns one.
## [codeblock]
## var animator := PoseAnimator.new(figure)
## animator.set_class(&"class.sword")
## figure.pose = animator.pose
## view.add_child(animator)
## animator.attack(PI / 2.0)
## [/codeblock]

enum Ease { OUT, IN, IN_OUT, BACK }

const IDLE_REDRAWS_PER_SEC: float = 10.0
## Redraws a second while an action runs (a 60 fps screen skips every other).
const ACTION_REDRAWS_PER_SEC: float = 30.0
const SWAY_SPEED: float = 1.7
const BLINK_SEC: float = 0.12
const BLINK_GAP_MIN_SEC: float = 2.0
const BLINK_GAP_RANGE_SEC: float = 3.0
const HURT_EYES_SEC: float = 0.3
const HAPPY_EYES_SEC: float = 1.2
## The weapon levelled while charging.
const CHARGE_STRIKE: float = -0.6
const GALLOP_SPEED: float = 9.0
const CHARGE_GALLOP_SPEED: float = 17.0
## A wind-up with no release after this long past its end releases anyway.
const RELEASE_GRACE_SEC: float = 0.1
## The skill pose fields a wind-up raises and its release or cancel lowers.
const WIND_UP_FIELDS: Array[StringName] = [&"crouch", &"raise", &"rear"]
## How each class moves; unknown classes use DEFAULT_MOTION. "attack" names
## the attack method, "stance" is the strike value held in a fight.
const CLASS_MOTION: Dictionary[StringName, Dictionary] = {
	&"class.archer": {"attack": &"_attack_shoot", "stance": -1.0, "step_speed": 11.0, "guards": false, "rears": false},
	&"class.mage": {"attack": &"_attack_cast", "stance": -0.45, "step_speed": 11.0, "guards": false, "rears": false},
	&"class.shield": {"attack": &"_attack_swing", "stance": -0.45, "step_speed": 11.0, "guards": true, "rears": false},
	&"class.cavalry": {"attack": &"_attack_swing", "stance": -0.45, "step_speed": 9.0, "guards": false, "rears": true},
}
const DEFAULT_MOTION: Dictionary = {"attack": &"_attack_swing", "stance": -0.45, "step_speed": 11.0, "guards": false, "rears": false}

var pose := UnitPose.new()
## Multiplies the speed of every pose track and of the walk cycle; running
## tracks change speed too.
var playback_speed: float = 1.0:
	set(value):
		playback_speed = value
		for property: StringName in _tracks:
			_set_speed(_tracks[property])
		_set_speed(_release_timer)
		_set_speed(_eyes_tween)
## In a fight the weapon stays half wound up (the bow drawn).
var is_in_combat: bool = false
var is_dead: bool = false
## Frozen (turned to stone): the pose holds exactly as it is.
var is_frozen: bool = false
## True between wind_up() and its release (or cancel).
var is_winding: bool = false
## False holds the idle sway still: only blinks redraw (bench, the dimmed
## waiting line-up).
var is_swaying: bool = true
## False for figures that ignore poses (bosses, the sage): they never redraw
## while idle. A flag, because Godot re-enables processing on ready, so
## set_process(false) before the node enters the tree does not stick.
var is_posed: bool = true

var _figure: CanvasItem
var _motion: Dictionary = DEFAULT_MOTION
var _time: float = 0.0
var _phase: float = 0.0
var _slot_offset: float = 0.0
var _idle_slot: int = -1
var _action_slot: int = -1
var _was_active: bool = false
var _blink_at: float = 0.0
var _blink_end: float = 0.0
var _is_charging: bool = false
# One tween per pose field: an animation restarts only the fields it moves.
var _tracks: Dictionary[StringName, Tween] = {}
var _release_timer: Tween
var _eyes_tween: Tween


func _init(figure: CanvasItem) -> void:
	_figure = figure
	_phase = randf() * TAU
	_slot_offset = randf()
	_time = randf() * 10.0
	_blink_at = _time + 1.0 + randf() * 3.0


## Picks how the figure moves from its class id (CLASS_MOTION).
func set_class(class_id: StringName) -> void:
	_motion = CLASS_MOTION.get(class_id, DEFAULT_MOTION)


## The strike value a unit at rest holds: half wound up in a fight.
func get_stance() -> float:
	return _motion["stance"] if is_in_combat else 0.0


func _process(delta: float) -> void:
	var is_active := _is_animating()
	if is_dead:
		_redraw_while(is_active)
		if not is_active and not _was_active:
			set_process(false)
		return
	_time += delta
	if pose.stride > 0.01:
		pose.step += delta * playback_speed * _motion["step_speed"]
		pose.gallop += delta * playback_speed * (CHARGE_GALLOP_SPEED if _is_charging else GALLOP_SPEED)
		is_active = true
	if is_active or _was_active:
		_update_idle()
		_redraw_while(is_active)
		return
	if not is_posed:
		return
	var slot := floori(_time * IDLE_REDRAWS_PER_SEC + _slot_offset)
	if slot != _idle_slot:
		_idle_slot = slot
		if _update_idle():
			_figure.queue_redraw()


## Puts the pose back at rest, out of combat; keeps the walk phases.
func reset() -> void:
	_kill_all()
	var step := pose.step
	var gallop := pose.gallop
	pose.copy_from(UnitPose.get_rest())
	pose.step = step
	pose.gallop = gallop
	is_in_combat = false
	is_dead = false
	is_winding = false
	_is_charging = false
	set_frozen(false)
	set_process(true)
	_figure.queue_redraw()


## Walks (legs cycle) for `seconds`, dropping the combat stance; a charge
## gallops faster with the weapon levelled instead. A walk cancels a
## wind-up; a charge keeps it (glowing, weapon levelled) for the release.
func walk(seconds: float, is_charge: bool) -> void:
	if is_dead:
		return
	if is_winding and not is_charge:
		_cancel_wind_up()
	_is_charging = is_charge
	if not is_charge:
		is_in_combat = false
	if is_winding:
		for property: StringName in WIND_UP_FIELDS:
			_to(_track(property), property, 0.0, 0.15)
	_to(_track(&"strike"), &"strike", _rest_strike(), 0.15)
	var stride := _track(&"stride")
	_to(stride, &"stride", 1.0, 0.12)
	_to(stride, &"stride", 0.0, 0.18, seconds, Ease.IN_OUT)
	stride.tween_callback(_end_walk).set_delay(seconds)


## A basic attack toward `aim` (figure angle, 0 up). During a wind-up it is
## the skill's release instead.
func attack(aim: float) -> void:
	if is_dead:
		return
	pose.aim = aim
	is_in_combat = true
	if is_winding:
		release()
		return
	call(_motion["attack"])


## The skill pose over `seconds`: crouch, weapon raised and glowing, a horse
## rears. Holds until release() (the next attack), or releases by itself
## shortly after `seconds`.
func wind_up(seconds: float) -> void:
	if is_dead:
		return
	is_in_combat = true
	is_winding = true
	_to(_track(&"crouch"), &"crouch", 1.0, seconds * 0.5)
	_to(_track(&"raise"), &"raise", 1.0, seconds * 0.8, 0.0, Ease.BACK)
	_to(_track(&"glow"), &"glow", 1.0, seconds)
	if _motion["rears"]:
		_to(_track(&"rear"), &"rear", 1.0, seconds * 0.7, 0.0, Ease.BACK)
	_release_timer = _restart(_release_timer)
	_release_timer.tween_callback(release).set_delay(seconds + RELEASE_GRACE_SEC)


## The skill's strike after a wind-up: the raised weapon comes down with a
## smear and the glow fades. Does nothing without a wind-up.
func release() -> void:
	if not is_winding or is_dead:
		return
	_end_wind_up(0.1)
	var strike := _track(&"strike")
	_to(strike, &"strike", 1.0, 0.08, 0.0, Ease.BACK)
	# A charging rider levels the lance again quickly for the rest of the run.
	_to(strike, &"strike", _rest_strike(), 0.25 if _is_charging else 0.3, 0.15 if _is_charging else 0.3, Ease.IN_OUT)
	pose.trail = 1.0
	_to(_track(&"trail"), &"trail", 0.0, 0.3, 0.05)
	_to(_track(&"glow"), &"glow", 0.0, 0.5, 0.15)


## Flinches back with hurt eyes; a shield raises its shield instead.
func hit() -> void:
	if is_dead or is_frozen:
		return
	var guards: bool = _motion["guards"]
	pose.eyes = UnitPose.Eyes.HURT
	var flinch := _track(&"flinch")
	_to(flinch, &"flinch", 0.35 if guards else 1.0, 0.04)
	_to(flinch, &"flinch", 0.0, 0.26, 0.06, Ease.IN_OUT)
	if guards:
		var guard := _track(&"guard")
		_to(guard, &"guard", 1.0, 0.04)
		_to(guard, &"guard", 0.0, 0.25, 0.2, Ease.IN_OUT)
	_eyes_after(HURT_EYES_SEC, 1.5)


## Leans back for `seconds` (pushed by a knockback).
func flinch_for(seconds: float) -> void:
	if is_dead:
		return
	var flinch := _track(&"flinch")
	_to(flinch, &"flinch", 0.6, 0.06)
	_to(flinch, &"flinch", 0.0, 0.2, seconds, Ease.IN_OUT)


## Collapses limp with dead eyes; idle stops for good.
func die() -> void:
	_kill_all()
	set_frozen(false)
	is_dead = true
	is_winding = false
	_is_charging = false
	pose.eyes = UnitPose.Eyes.DEAD
	for property: StringName in [&"strike", &"raise", &"stride", &"glow", &"trail", &"guard", &"crouch", &"rear"]:
		pose.set(property, 0.0)
	var flinch := _track(&"flinch")
	_to(flinch, &"flinch", 0.8, 0.06)
	_to(flinch, &"flinch", 0.0, 0.2, 0.08)
	_to(_track(&"limp"), &"limp", 1.0, 0.34, 0.05, Ease.IN)
	_figure.queue_redraw()


## Weapon raised with happy eyes (a horse rears), for the winners. Ends a
## wind-up without its strike.
func cheer() -> void:
	if is_dead:
		return
	if is_winding:
		_cancel_wind_up()
	is_in_combat = false
	_is_charging = false
	pose.eyes = UnitPose.Eyes.HAPPY
	_to(_track(&"strike"), &"strike", 0.0, 0.1)
	var raise := _track(&"raise")
	_to(raise, &"raise", 1.0, 0.18, 0.0, Ease.BACK)
	_to(raise, &"raise", 0.0, 0.25, 0.9, Ease.IN_OUT)
	if _motion["rears"]:
		var rear := _track(&"rear")
		_to(rear, &"rear", 1.0, 0.25, 0.0, Ease.BACK)
		_to(rear, &"rear", 0.0, 0.2, 0.6)
	_eyes_after(HAPPY_EYES_SEC, 0.0)


## Freezes the pose exactly as it is (no tween, sway or blink), or thaws it.
func set_frozen(frozen: bool) -> void:
	is_frozen = frozen
	# Tweens made by this node pause with it.
	process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT


func _attack_swing() -> void:
	var strike := _track(&"strike")
	_to(strike, &"strike", 1.0, 0.08, 0.0, Ease.BACK)
	_to(strike, &"strike", _rest_strike(), 0.28, 0.2, Ease.IN_OUT)
	pose.trail = 1.0
	_to(_track(&"trail"), &"trail", 0.0, 0.22, 0.04)


# Loose the arrow, then nock a new one and draw again.
func _attack_shoot() -> void:
	pose.arrow = 0.0
	pose.strike = -1.0
	var strike := _track(&"strike")
	_to(strike, &"strike", 1.0, 0.06)
	_to(strike, &"strike", 0.0, 0.16, 0.12, Ease.IN_OUT)
	_to(strike, &"strike", _rest_strike(), 0.34, 0.36, Ease.IN_OUT)
	_to(_track(&"arrow"), &"arrow", 1.0, 0.01, 0.34)


func _attack_cast() -> void:
	var strike := _track(&"strike")
	_to(strike, &"strike", 1.0, 0.09, 0.0, Ease.BACK)
	_to(strike, &"strike", _rest_strike(), 0.3, 0.2, Ease.IN_OUT)
	pose.glow = 1.0
	_to(_track(&"glow"), &"glow", 0.0, 0.35, 0.08)


# Lowers the wind-up fields over `seconds`; the caller adds the strike.
func _end_wind_up(seconds: float) -> void:
	is_winding = false
	_kill(_release_timer)
	for property: StringName in WIND_UP_FIELDS:
		_to(_track(property), property, 0.0, seconds * (1.4 if property == &"rear" else 1.0))


# A wind-up that ends without its strike (moved away, the battle ended).
func _cancel_wind_up() -> void:
	_end_wind_up(0.15)
	_to(_track(&"glow"), &"glow", 0.0, 0.25)


# The strike value to come back to: levelled while charging, else the stance.
func _rest_strike() -> float:
	return CHARGE_STRIKE if _is_charging else get_stance()


func _end_walk() -> void:
	_is_charging = false
	var strike: Tween = _tracks.get(&"strike")
	if strike == null or not strike.is_valid() or not strike.is_running():
		_settle_strike()


# When the strike track ends, it eases to the stance that holds now (the
# fight may have started or a charge ended while it ran).
func _settle_strike() -> void:
	if is_dead or absf(pose.strike - _rest_strike()) < 0.005:
		return
	_to(_track(&"strike"), &"strike", _rest_strike(), 0.2, 0.0, Ease.IN_OUT)


# Sway, plume and orb follow the idle clock; the eyes blink now and then.
# Returns true when the pose changed.
func _update_idle() -> bool:
	var changed := false
	if is_swaying:
		pose.sway = sin(_time * SWAY_SPEED + _phase)
		changed = true
	if pose.eyes == UnitPose.Eyes.OPEN and _time > _blink_at:
		pose.eyes = UnitPose.Eyes.BLINK
		_blink_end = _time + BLINK_SEC
		changed = true
	elif pose.eyes == UnitPose.Eyes.BLINK and _time > _blink_end:
		pose.eyes = UnitPose.Eyes.OPEN
		_blink_at = _time + BLINK_GAP_MIN_SEC + randf() * BLINK_GAP_RANGE_SEC
		changed = true
	return changed


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


# Opens the eyes again after `seconds` of battle time, then waits
# `blink_delay_sec` before the next blink.
func _eyes_after(seconds: float, blink_delay_sec: float) -> void:
	_eyes_tween = _restart(_eyes_tween)
	_eyes_tween.tween_callback(func() -> void:
		if not is_dead:
			pose.eyes = UnitPose.Eyes.OPEN
			_blink_at = _time + blink_delay_sec
			_figure.queue_redraw()).set_delay(seconds)


func _is_animating() -> bool:
	for property: StringName in _tracks:
		var tween := _tracks[property]
		if tween.is_valid() and tween.is_running():
			return true
	return false


# Kills the track of `property` and returns a fresh one at the playback speed.
func _track(property: StringName) -> Tween:
	var tween := _restart(_tracks.get(property))
	_tracks[property] = tween
	if property == &"strike":
		tween.finished.connect(_settle_strike)
	return tween


func _to(tween: Tween, property: StringName, to: float, seconds: float, delay_sec: float = 0.0, curve: Ease = Ease.OUT) -> void:
	var tweener := tween.tween_property(pose, NodePath(property), to, maxf(seconds, 0.0001)).set_delay(delay_sec)
	match curve:
		Ease.OUT:
			tweener.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		Ease.IN:
			tweener.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		Ease.IN_OUT:
			tweener.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		Ease.BACK:
			tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Kills `tween` and returns a fresh parallel one at the playback speed.
func _restart(tween: Tween) -> Tween:
	_kill(tween)
	var fresh := create_tween().set_parallel(true)
	fresh.set_speed_scale(playback_speed)
	return fresh


func _set_speed(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.set_speed_scale(playback_speed)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


func _kill_all() -> void:
	for property: StringName in _tracks:
		_kill(_tracks[property])
	_tracks.clear()
	_kill(_release_timer)
	_kill(_eyes_tween)
