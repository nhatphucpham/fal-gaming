class_name PoseAnimator
extends Node
## Plays the pose animations of one figure: idle sway and blinks, walk and
## gallop, attack, skill wind-up and release, hit, death and cheer. It owns
## the UnitPose and asks the figure to redraw only when the pose changed:
## every frame while an action runs, about 15 times a second (staggered per
## unit) while only idling, never while frozen (stone) or after death.
## Action tweens follow playback_speed (the battle speed). UnitView owns one.
## [codeblock]
## var animator := PoseAnimator.new(figure)
## animator.set_class(&"class.sword")
## figure.pose = animator.pose
## view.add_child(animator)
## animator.attack(PI / 2.0)
## [/codeblock]

enum Ease { OUT, IN, IN_OUT, BACK }

const IDLE_REDRAWS_PER_SEC: float = 15.0
const SWAY_SPEED: float = 1.7
const BLINK_SEC: float = 0.12
const BLINK_GAP_MIN_SEC: float = 2.0
const BLINK_GAP_RANGE_SEC: float = 3.0
const HURT_EYES_SEC: float = 0.3
const HAPPY_EYES_SEC: float = 1.2
const CHARGE_STRIKE: float = -0.6
const GALLOP_SPEED: float = 9.0
const CHARGE_GALLOP_SPEED: float = 17.0
## A wind-up with no release after this long past its end releases anyway.
const RELEASE_GRACE_SEC: float = 0.1
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
## Multiplies the speed of every pose tween and of the walk cycle.
var playback_speed: float = 1.0
## In a fight the weapon stays half wound up (the bow drawn).
var is_in_combat: bool = false
var is_dead: bool = false
## Frozen (turned to stone): the pose holds exactly as it is.
var is_frozen: bool = false
## True between wind_up() and its release.
var is_winding: bool = false

var _figure: CanvasItem
var _motion: Dictionary = DEFAULT_MOTION
var _time: float = 0.0
var _phase: float = 0.0
var _slot_offset: float = 0.0
var _idle_slot: int = -1
var _blink_at: float = 0.0
var _blink_end: float = 0.0
var _is_charging: bool = false
# One tween per group of pose fields, so a hit does not cancel a swing.
var _action_tween: Tween
var _move_tween: Tween
var _hurt_tween: Tween
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
		if is_active:
			_figure.queue_redraw()
		else:
			set_process(false)
		return
	_time += delta
	if pose.stride > 0.01:
		pose.step += delta * playback_speed * _motion["step_speed"]
		pose.gallop += delta * playback_speed * (CHARGE_GALLOP_SPEED if _is_charging else GALLOP_SPEED)
		is_active = true
	var slot := floori(_time * IDLE_REDRAWS_PER_SEC + _slot_offset)
	if is_active or slot != _idle_slot:
		_idle_slot = slot
		_update_idle()
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
## gallops faster with the weapon levelled instead.
func walk(seconds: float, is_charge: bool) -> void:
	if is_dead:
		return
	_is_charging = is_charge
	if not is_charge:
		is_in_combat = false
	is_winding = false
	_action_tween = _restart(_action_tween)
	_tween(_action_tween, &"strike", CHARGE_STRIKE if is_charge else 0.0, 0.15)
	if is_charge:
		_tween(_action_tween, &"strike", get_stance(), 0.2, seconds, Ease.IN_OUT)
	_move_tween = _restart(_move_tween)
	_tween(_move_tween, &"stride", 1.0, 0.12)
	_tween(_move_tween, &"stride", 0.0, 0.18, seconds, Ease.IN_OUT)


## A basic attack toward `aim` (figure angle, 0 up). During a wind-up it is
## the skill's release instead.
func attack(aim: float) -> void:
	if is_dead:
		return
	pose.aim = aim
	if is_winding:
		release()
		return
	is_in_combat = true
	_action_tween = _restart(_action_tween)
	call(_motion["attack"])


## The skill pose over `seconds`: crouch, weapon raised and glowing, a horse
## rears. Holds until release() (the next attack), or releases by itself
## shortly after `seconds`.
func wind_up(seconds: float) -> void:
	if is_dead:
		return
	is_in_combat = true
	is_winding = true
	_action_tween = _restart(_action_tween)
	_tween(_action_tween, &"crouch", 1.0, seconds * 0.5)
	_tween(_action_tween, &"raise", 1.0, seconds * 0.8, 0.0, Ease.BACK)
	_tween(_action_tween, &"glow", 1.0, seconds)
	if _motion["rears"]:
		_tween(_action_tween, &"rear", 1.0, seconds * 0.7, 0.0, Ease.BACK)
	_action_tween.tween_callback(release).set_delay(seconds + RELEASE_GRACE_SEC)


## The skill's strike after a wind-up: the raised weapon comes down with a
## smear and the glow fades. Does nothing without a wind-up.
func release() -> void:
	if not is_winding or is_dead:
		return
	is_winding = false
	_action_tween = _restart(_action_tween)
	_tween(_action_tween, &"crouch", 0.0, 0.1)
	_tween(_action_tween, &"raise", 0.0, 0.1)
	_tween(_action_tween, &"rear", 0.0, 0.14)
	_tween(_action_tween, &"strike", 1.0, 0.08, 0.0, Ease.BACK)
	pose.trail = 1.0
	_tween(_action_tween, &"trail", 0.0, 0.3, 0.05)
	_tween(_action_tween, &"glow", 0.0, 0.5, 0.15)
	_tween(_action_tween, &"strike", get_stance(), 0.3, 0.3, Ease.IN_OUT)


## Flinches back with hurt eyes; a shield raises its shield instead.
func hit() -> void:
	if is_dead or is_frozen:
		return
	var guards: bool = _motion["guards"]
	pose.eyes = UnitPose.Eyes.HURT
	_hurt_tween = _restart(_hurt_tween)
	_tween(_hurt_tween, &"flinch", 0.35 if guards else 1.0, 0.04)
	_tween(_hurt_tween, &"flinch", 0.0, 0.26, 0.06, Ease.IN_OUT)
	if guards:
		_tween(_hurt_tween, &"guard", 1.0, 0.04)
		_tween(_hurt_tween, &"guard", 0.0, 0.25, 0.2, Ease.IN_OUT)
	_eyes_after(HURT_EYES_SEC, 1.5)


## Leans back for `seconds` (pushed by a knockback).
func flinch_for(seconds: float) -> void:
	if is_dead:
		return
	_hurt_tween = _restart(_hurt_tween)
	_tween(_hurt_tween, &"flinch", 0.6, 0.06)
	_tween(_hurt_tween, &"flinch", 0.0, 0.2, seconds, Ease.IN_OUT)


## Collapses limp with dead eyes; idle stops for good.
func die() -> void:
	_kill_all()
	set_frozen(false)
	is_dead = true
	is_winding = false
	pose.eyes = UnitPose.Eyes.DEAD
	for property: StringName in [&"strike", &"raise", &"stride", &"glow", &"trail", &"guard", &"crouch", &"rear"]:
		pose.set(property, 0.0)
	_action_tween = _restart(_action_tween)
	_tween(_action_tween, &"flinch", 0.8, 0.06)
	_tween(_action_tween, &"flinch", 0.0, 0.2, 0.08)
	_tween(_action_tween, &"limp", 1.0, 0.34, 0.05, Ease.IN)
	_figure.queue_redraw()


## Weapon raised with happy eyes (a horse rears), for the winners.
func cheer() -> void:
	if is_dead:
		return
	is_in_combat = false
	is_winding = false
	pose.eyes = UnitPose.Eyes.HAPPY
	_action_tween = _restart(_action_tween)
	_tween(_action_tween, &"strike", 0.0, 0.1)
	_tween(_action_tween, &"raise", 1.0, 0.18, 0.0, Ease.BACK)
	if _motion["rears"]:
		_tween(_action_tween, &"rear", 1.0, 0.25, 0.0, Ease.BACK)
		_tween(_action_tween, &"rear", 0.0, 0.2, 0.6)
	_tween(_action_tween, &"raise", 0.0, 0.25, 0.9, Ease.IN_OUT)
	_eyes_after(HAPPY_EYES_SEC, 0.0)


## Freezes the pose exactly as it is (no tween, sway or blink), or thaws it.
func set_frozen(frozen: bool) -> void:
	is_frozen = frozen
	# Tweens made by this node pause with it.
	process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT


func _attack_swing() -> void:
	_tween(_action_tween, &"strike", 1.0, 0.08, 0.0, Ease.BACK)
	pose.trail = 1.0
	_tween(_action_tween, &"trail", 0.0, 0.22, 0.04)
	_tween(_action_tween, &"strike", get_stance(), 0.28, 0.2, Ease.IN_OUT)


# Loose the arrow, then nock a new one and draw again.
func _attack_shoot() -> void:
	pose.arrow = 0.0
	pose.strike = -1.0
	_tween(_action_tween, &"strike", 1.0, 0.06)
	_tween(_action_tween, &"strike", 0.0, 0.16, 0.12, Ease.IN_OUT)
	_tween(_action_tween, &"arrow", 1.0, 0.01, 0.34)
	_tween(_action_tween, &"strike", get_stance(), 0.34, 0.36, Ease.IN_OUT)


func _attack_cast() -> void:
	_tween(_action_tween, &"strike", 1.0, 0.09, 0.0, Ease.BACK)
	pose.glow = 1.0
	_tween(_action_tween, &"glow", 0.0, 0.35, 0.08)
	_tween(_action_tween, &"strike", get_stance(), 0.3, 0.2, Ease.IN_OUT)


# Sway, plume and orb follow the idle clock; the eyes blink now and then.
func _update_idle() -> void:
	pose.sway = sin(_time * SWAY_SPEED + _phase)
	if pose.eyes == UnitPose.Eyes.OPEN and _time > _blink_at:
		pose.eyes = UnitPose.Eyes.BLINK
		_blink_end = _time + BLINK_SEC
	elif pose.eyes == UnitPose.Eyes.BLINK and _time > _blink_end:
		pose.eyes = UnitPose.Eyes.OPEN
		_blink_at = _time + BLINK_GAP_MIN_SEC + randf() * BLINK_GAP_RANGE_SEC


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
	for tween: Tween in [_action_tween, _move_tween, _hurt_tween]:
		if tween != null and tween.is_valid() and tween.is_running():
			return true
	return false


func _tween(tween: Tween, property: StringName, to: float, seconds: float, delay_sec: float = 0.0, curve: Ease = Ease.OUT) -> void:
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
	if tween != null and tween.is_valid():
		tween.kill()
	var fresh := create_tween().set_parallel(true)
	fresh.set_speed_scale(playback_speed)
	return fresh


func _kill_all() -> void:
	for tween: Tween in [_action_tween, _move_tween, _hurt_tween, _eyes_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
