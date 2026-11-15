class_name RigClips
extends RefCounted
## The generic key-pose clips every class starts from (port of the sketch's
## `CLIPS`, `IDLE`, `STANCE` and `walkPose`): a clip is a list of keys, each
## easing from the previous pose to its own over its seconds. A key may
## stand for the class's rest pose (idle or stance), which RigKit fills in.
## Numbers are the sketch's, so the figures match its renders.
## [codeblock]
## var keys := RigClips.get_clip(&"attackUp")
## var pose := UnitPose.blend(from, keys[0].pose, RigClips.eased(keys[0].easing, 0.5))
## [/codeblock]

enum Easing { LINEAR, OUT, IN, IN_OUT }
enum Rest { NONE, IDLE, STANCE }


## One key of a clip: ease from the previous pose to `pose` over `seconds`.
class ClipKey:
	extends RefCounted
	var seconds: float
	var easing: Easing
	var pose: UnitPose
	## The class rest pose this key stands for, filled in per class.
	var rest: Rest

	func _init(key_seconds: float, key_easing: Easing, key_pose: UnitPose, key_rest: Rest = Rest.NONE) -> void:
		seconds = key_seconds
		easing = key_easing
		pose = key_pose
		rest = key_rest


static var _idle: UnitPose
static var _stance: UnitPose
static var _clips: Dictionary[StringName, Array] = {}


static func eased(easing: Easing, t: float) -> float:
	match easing:
		Easing.OUT:
			return 1.0 - (1.0 - t) * (1.0 - t)
		Easing.IN:
			return t * t
		Easing.IN_OUT:
			return t * t * (3.0 - 2.0 * t)
	return t


## The generic rest pose out of a fight: sword hanging by the leg.
static func get_idle() -> UnitPose:
	if _idle == null:
		_idle = UnitPose.make({"uaF": -9, "laF": -6, "blade": 56, "uaB": 12, "laB": -12})
	return _idle


## The generic rest pose in a fight: sword raised before the chest.
static func get_stance() -> UnitPose:
	if _stance == null:
		_stance = UnitPose.make({"torso": 3, "head": -2, "uaF": -30, "laF": -82, "blade": -66, "uaB": 20, "laB": -40, "hip": 26, "fF": 5.6, "fB": -5.6})
	return _stance


## The generic clip `name`: attackUp, attackDown, skillUp, skillDown, hit,
## die, fall (die without getting up) or cheer. Never change the result.
static func get_clip(name: StringName) -> Array[ClipKey]:
	if _clips.is_empty():
		_build()
	var keys: Array[ClipKey] = []
	keys.assign(_clips[name])
	return keys


## `rest` breathing (the sketch's idle bob) at `phase` radians of the
## breath, or held still for NAN (a calm figure), with `eyes` (0 open, 1 shut).
static func breathing(rest: UnitPose, phase: float, eyes: int) -> UnitPose:
	var bob := 0.0 if is_nan(phase) else sin(phase)
	var swing := 0.0 if is_nan(phase) else sin(phase - 0.6)
	var v := rest.values
	return rest.with_fields({
		"torso": v[UnitPose.TORSO] + 0.8 * bob, "head": v[UnitPose.HEAD] - 0.6 * bob, "hip": v[UnitPose.HIP] - 0.25 * (1.0 + bob),
		"uaF": v[UnitPose.UA_F] + 1.5 * bob, "uaB": v[UnitPose.UA_B] - 1.5 * bob, "blade": v[UnitPose.BLADE] + 1.5 * swing,
		"eyes": eyes,
	})


## The run cycle at `phase` (one stride per 1.0): legs swing front to back,
## never sideways; the trailing foot lifts its heel.
static func walk_pose(phase: float) -> UnitPose:
	var turn := phase * TAU
	var s := sin(turn)
	var c := cos(turn)
	var front := _leg(s, c)
	var back := _leg(-s, -c)
	return UnitPose.make({
		"torso": 2 + 3 * s, "head": -2 - 2 * s, "uaF": -22 + 16 * s, "laF": -64, "blade": -38 + 12 * s,
		"uaB": 10 - 8 * s, "laB": -38 - 12 * s, "kLB": 0.85 - 0.15 * s, "hip": 24.6 - 0.9 * absf(c), "jump": 1.4 * absf(s),
		"fF": 3.8, "fB": -3.8, "stF": front.x, "lF": front.y, "heF": front.z, "stB": back.x, "lB": back.y, "heB": back.z,
	})


static func _leg(sine: float, cosine: float) -> Vector3:
	return Vector3(5.0 * sine, 4.5 * maxf(0.0, cosine), clampf(maxf(0.0, -sine) * 0.9 + maxf(0.0, cosine) * 0.7, 0.0, 1.0))


static func _build() -> void:
	var back := ClipKey.new(0.26, Easing.IN_OUT, get_stance(), Rest.STANCE)
	var gather: Array[ClipKey] = [
		ClipKey.new(0.32, Easing.OUT, UnitPose.make({"head": 3, "uaF": -40, "laF": -124, "blade": -90, "uaB": -30, "laB": -112, "hip": 23.4, "fF": 6.6, "fB": -6.6, "glow": 1})),
		ClipKey.new(0.14, Easing.LINEAR, UnitPose.make({"head": 4, "uaF": -42, "laF": -126, "blade": -92, "uaB": -32, "laB": -114, "hip": 23.1, "fF": 6.6, "fB": -6.6, "glow": 1})),
	]
	# The enemy cuts down across its body, toward the bottom of the board.
	_clips[&"attackDown"] = [
		ClipKey.new(0.17, Easing.OUT, UnitPose.make({"torso": 5, "head": -2, "uaF": -150, "laF": -40, "blade": -72, "uaB": 18, "laB": -30, "hip": 26.8, "fF": 5, "fB": -5.5})),
		ClipKey.new(0.09, Easing.IN, UnitPose.make({"torso": -7, "head": 4, "uaF": 28, "laF": 20, "blade": -250, "uaB": 24, "laB": -20, "hip": 24, "fF": 6.4, "fB": -6.4, "dx": 4.5, "trail": 1})),
		ClipKey.new(0.12, Easing.LINEAR, UnitPose.make({"torso": -8, "head": 4, "uaF": 30, "laF": 20, "blade": -258, "uaB": 24, "laB": -20, "hip": 23.8, "fF": 6.4, "fB": -6.4, "dx": 4.5})),
		back,
	]
	# The player cuts upward from the hip to above the far shoulder.
	_clips[&"attackUp"] = [
		ClipKey.new(0.17, Easing.OUT, UnitPose.make({"torso": 6, "head": 3, "uaF": -16, "laF": -30, "blade": 64, "uaB": 20, "laB": -24, "hip": 24.4, "fF": 6.4, "fB": -6.4})),
		ClipKey.new(0.09, Easing.IN, UnitPose.make({"torso": -6, "head": -4, "uaF": -200, "laF": -20, "blade": -132, "uaB": 26, "laB": -26, "hip": 26.9, "fF": 5, "fB": -5, "dx": 4.5, "trail": 1})),
		ClipKey.new(0.12, Easing.LINEAR, UnitPose.make({"torso": -7, "head": -4, "uaF": -204, "laF": -18, "blade": -140, "uaB": 26, "laB": -26, "hip": 26.9, "fF": 5, "fB": -5, "dx": 4.5})),
		back,
	]
	var skill_down: Array[ClipKey] = gather.duplicate()
	skill_down.append_array([
		ClipKey.new(0.1, Easing.IN, UnitPose.make({"torso": -9, "head": 5, "uaF": 32, "laF": 20, "blade": -252, "uaB": 26, "laB": -20, "hip": 23, "fF": 7.2, "fB": -7.2, "dx": 8, "trail": 1, "glow": 1})),
		ClipKey.new(0.2, Easing.LINEAR, UnitPose.make({"torso": -10, "head": 5, "uaF": 34, "laF": 20, "blade": -262, "uaB": 26, "laB": -20, "hip": 22.8, "fF": 7.2, "fB": -7.2, "dx": 8, "glow": 0.4})),
		ClipKey.new(0.32, Easing.IN_OUT, get_stance(), Rest.STANCE),
	])
	_clips[&"skillDown"] = skill_down
	var skill_up: Array[ClipKey] = gather.duplicate()
	skill_up.append_array([
		ClipKey.new(0.1, Easing.IN, UnitPose.make({"torso": -7, "head": -5, "uaF": -204, "laF": -14, "blade": -130, "uaB": 28, "laB": -28, "hip": 27, "fF": 4.4, "fB": -4.4, "dx": 8, "jump": 4, "trail": 1, "glow": 1})),
		ClipKey.new(0.2, Easing.LINEAR, UnitPose.make({"torso": -8, "head": -5, "uaF": -208, "laF": -12, "blade": -140, "uaB": 28, "laB": -28, "hip": 26.6, "fF": 4.6, "fB": -4.6, "dx": 8, "glow": 0.4})),
		ClipKey.new(0.32, Easing.IN_OUT, get_stance(), Rest.STANCE),
	])
	_clips[&"skillUp"] = skill_up
	_clips[&"hit"] = [
		ClipKey.new(0.07, Easing.OUT, UnitPose.make({"torso": -9, "head": -9, "uaF": -30, "laF": -46, "blade": -34, "uaB": 22, "laB": -14, "hip": 25.2, "fF": 4, "fB": -6.6, "dx": -3.5, "eyes": 1, "flash": 1})),
		ClipKey.new(0.13, Easing.LINEAR, UnitPose.make({"torso": -8, "head": -8, "uaF": -28, "laF": -44, "blade": -32, "uaB": 20, "laB": -12, "hip": 25.2, "fF": 4, "fB": -6.6, "dx": -3.5, "eyes": 1})),
		back,
	]
	_build_die_and_cheer()


static func _build_die_and_cheer() -> void:
	var lie := {"stF": 0, "root": -88, "torso": -4, "head": -8, "uaF": -62, "laF": -22, "blade": 4, "uaB": 40, "laB": 30, "thF": -12, "shF": 22, "thB": 6, "shB": 14, "ftF": -70, "ftB": -60, "ik": 0, "flat": 0, "dx": -6, "eyes": 1}
	var lie_gone := lie.duplicate()
	lie_gone["alpha"] = 0
	var die: Array[ClipKey] = [
		ClipKey.new(0.26, Easing.OUT, UnitPose.make({"torso": 12, "head": 14, "uaF": -24, "laF": -40, "blade": 14, "uaB": 20, "laB": 10, "hip": 19, "fF": 5.4, "fB": -5.4, "eyes": 1, "flash": 0.6})),
		ClipKey.new(0.34, Easing.IN, UnitPose.make(lie)),
		ClipKey.new(0.5, Easing.LINEAR, UnitPose.make(lie)),
		ClipKey.new(0.5, Easing.LINEAR, UnitPose.make(lie_gone)),
		ClipKey.new(0.6, Easing.LINEAR, get_idle().with_fields({"alpha": 0})),
		ClipKey.new(0.3, Easing.LINEAR, get_idle(), Rest.IDLE),
	]
	_clips[&"die"] = die
	_clips[&"fall"] = die.slice(0, 4)
	var up := {"head": -2, "uaF": -166, "laF": -8, "blade": -88, "uaB": 158, "laB": 14, "eyes": 2}
	var low := up.duplicate()
	low["hip"] = 23.5
	var high := up.duplicate()
	high["jump"] = 6
	var land := up.duplicate()
	land["hip"] = 25
	var low_pose := UnitPose.make(low)
	var high_pose := UnitPose.make(high)
	var land_pose := UnitPose.make(land)
	_clips[&"cheer"] = [
		ClipKey.new(0.16, Easing.OUT, low_pose), ClipKey.new(0.16, Easing.OUT, high_pose), ClipKey.new(0.15, Easing.IN, land_pose),
		ClipKey.new(0.16, Easing.OUT, high_pose), ClipKey.new(0.15, Easing.IN, land_pose), ClipKey.new(0.35, Easing.LINEAR, UnitPose.make(up)),
		ClipKey.new(0.3, Easing.IN_OUT, get_idle(), Rest.IDLE),
	]
