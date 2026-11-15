class_name KitCavalry
extends RefCounted
## Kỵ (class.cavalry): a rider on a horse with a couched lance. The generic
## clips are fitted to a seated rider (legs astride, no jumps: a jump
## rears the horse instead); the rider slumps over the horse to die.
## Helmet with two pheasant feathers, plate armour and scarf.

const SEAT := {"ik": 0, "ride": 1, "thF": -60, "shF": 60, "thB": 60, "shB": -60, "ftF": 0, "ftB": 0, "flat": 1, "stF": 0, "stB": 0}
const IDLE_ARMS := {"uaF": -8, "laF": -24, "blade": -92, "uaB": 22, "laB": -64}


static func build() -> RigKit:
	var stance_back := seated({"torso": 3, "uaF": -28, "laF": -54, "blade": -76, "uaB": 22, "laB": -64})
	var stance_front := seated({"torso": 3, "uaF": -20, "laF": -66, "blade": 30, "uaB": 22, "laB": -64})
	var pull_back := stance_back.with_fields({"torso": 6, "uaF": -6, "laF": -40, "blade": -70, "wo": -5, "hip": 30.4})
	var pull_front := stance_front.with_fields({"torso": 6, "uaF": -4, "laF": -56, "blade": 26, "wo": -5, "hip": 30.4})
	var thrust_back := stance_back.with_fields({"torso": -6, "head": -3, "uaF": -160, "laF": -12, "blade": -88, "wl": 0.9, "wo": 9, "dx": 7, "trail": 1})
	var thrust_front := stance_front.with_fields({"torso": -8, "head": 4, "uaF": -56, "laF": -22, "blade": 50, "wl": 0.72, "wo": 9, "dx": 7, "trail": 1})
	var kit := RigKit.new()
	kit.pieces = _pieces()
	kit.fit = Callable(KitCavalry, &"fit")
	kit.is_mounted = true
	kit.stance = {RigSolver.VIEW_BACK: stance_back, RigSolver.VIEW_FRONT: stance_front}
	kit.idle = RigKit.both_views(seated(IDLE_ARMS))
	var die := _die()
	kit.clips = {
		&"attackUp": _attack(stance_back, pull_back, thrust_back),
		&"attackDown": _attack(stance_front, pull_front, thrust_front),
		&"skillUp": _skill(stance_back, pull_back, thrust_back),
		&"skillDown": _skill(stance_front, pull_front, thrust_front),
		&"die": die,
		&"fall": die.slice(0, 4),
	}
	kit.walk = Callable(KitCavalry, &"walk")
	kit.tip = Vector2(50, 32)
	kit.is_tip_on_weapon = true
	kit.glow_x = 44.0
	kit.is_glow_on_weapon = true
	kit.skill_wind_keys = 1
	return kit


## The seat laid over a generic pose: higher hips, no jump (the horse
## lifts instead), a longer lunge when the body does not lean.
static func fit(pose: UnitPose) -> Dictionary:
	var p := pose.values
	var fields := SEAT.duplicate()
	fields.merge({"hip": 31 + (p[UnitPose.HIP] - 26) * 0.5, "jump": 0, "hl": p[UnitPose.JUMP] / 6.0,
		"dx": p[UnitPose.DX] if p[UnitPose.ROOT] != 0.0 else p[UnitPose.DX] * 1.2}, true)
	return fields


## The gallop: the horse's legs cycle, the rider rocks with the stride.
static func walk(phase: float, view: StringName) -> UnitPose:
	var swing := sin(TAU * phase)
	return seated({"torso": 6 + 2 * swing, "head": -2, "uaF": -24, "laF": -56, "blade": -78 if view == RigSolver.VIEW_BACK else 30,
		"uaB": 24, "laB": -70, "hip": 31 + 1.2 * sin(TAU * (phase + 0.25)), "hg": 1, "hph": phase})


## A pose seated on the horse (the sketch's `S`).
static func seated(fields: Dictionary) -> UnitPose:
	var all := SEAT.duplicate()
	all["hip"] = 31
	all.merge(fields, true)
	return UnitPose.make(all)


# The base body with the plumed helm, plate and scarf, the lance and the horse.
static func _pieces() -> Array[RigPiece]:
	var changes := {
		&"head": {"detail": Callable(RigHeads, &"dress_head").bind(Callable(RigHeads, &"helm").bind({"feathers": true})), "depends": RigPiece.USES_VIEW | RigPiece.USES_SWAY, "sway_period_sec": 0.38},
		&"torso": {"detail": Callable(RigTorso, &"dress").bind({"armor": &"plate", "scarf": true})},
	}
	var extra: Array[RigPiece] = RigWeapons.lance_pieces()
	extra.append_array(RigHorse.pieces())
	return RigKit.remix(RigBody.base_pieces(), changes, [&"sword"], extra)


# The rider slumps over the horse, lies there, fades, and sits up again
# unseen (the first 4 keys are the battle's fall).
static func _die() -> Array[RigClips.ClipKey]:
	var slump := seated({"torso": 16, "head": 18, "uaF": -14, "laF": -30, "blade": 20, "uaB": 10, "laB": -20, "hip": 29, "eyes": 1, "flash": 0.6})
	var down := seated({"torso": 30, "head": 24, "uaF": -6, "laF": -10, "blade": 40, "uaB": 6, "laB": -6, "hip": 22, "eyes": 1})
	return [
		RigClips.ClipKey.new(0.26, RigClips.Easing.OUT, slump), RigClips.ClipKey.new(0.4, RigClips.Easing.IN, down), RigClips.ClipKey.new(0.5, RigClips.Easing.LINEAR, down),
		RigClips.ClipKey.new(0.5, RigClips.Easing.LINEAR, down.with_fields({"alpha": 0})),
		RigClips.ClipKey.new(0.6, RigClips.Easing.LINEAR, down.with_fields({"alpha": 0, "hip": 31, "torso": 0, "head": 0})),
		RigClips.ClipKey.new(0.3, RigClips.Easing.LINEAR, seated(IDLE_ARMS)),
	]


static func _attack(stance: UnitPose, pull: UnitPose, thrust: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.16, RigClips.Easing.OUT, pull), RigClips.ClipKey.new(0.08, RigClips.Easing.IN, thrust), RigClips.ClipKey.new(0.14, RigClips.Easing.LINEAR, thrust.with_fields({"trail": 0})),
		RigClips.ClipKey.new(0.26, RigClips.Easing.IN_OUT, stance),
	]


static func _skill(stance: UnitPose, pull: UnitPose, thrust: UnitPose) -> Array[RigClips.ClipKey]:
	var slide := thrust.values[UnitPose.WO] + 4
	return [
		RigClips.ClipKey.new(0.32, RigClips.Easing.OUT, pull.with_fields({"glow": 1, "hl": 0.8})),
		RigClips.ClipKey.new(0.1, RigClips.Easing.IN, thrust.with_fields({"glow": 1, "dx": 11, "wo": slide})),
		RigClips.ClipKey.new(0.2, RigClips.Easing.LINEAR, thrust.with_fields({"glow": 0.4, "dx": 11, "wo": slide, "trail": 0})),
		RigClips.ClipKey.new(0.32, RigClips.Easing.IN_OUT, stance),
	]
