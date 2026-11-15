class_name KitSpear
extends RefCounted
## Thương (class.spear): a long willow-leaf spear in both hands, the rear
## (sword) hand at the hip, the off hand a forearm further along the shaft.
## Ready toward the enemy: from behind the spear points up the board, from
## the front it points at the viewer (short shaft, big head). The thrust
## drives both hands along the board. Conical war hat, quilted coat.

const LUNGE := {"torso": 6, "hip": 24.4, "fF": 6.4, "fB": -6.4}
const CARRY := {"gw": 0, "uaF": -8, "laF": -28, "blade": -94}


static func build() -> RigKit:
	var stance_back := _hold(Vector2(7.4, -0.5), Vector2(8.8, -10.5), Vector2(11.5, -6.5), 0.9, {})
	var stance_front := _hold(Vector2(5.5, -6.5), Vector2(0.8, -0.8), Vector2(10.5, -9), 0.5, {})
	var pull_back := _hold(Vector2(7.4, 1.5), Vector2(8.6, -8.5), Vector2(11.8, -4), 0.9, LUNGE)
	var pull_front := _hold(Vector2(6.5, -8.5), Vector2(1.6, -2.5), Vector2(11, -11), 0.6, LUNGE)
	var thrust_back := _hold(Vector2(7, -9.5), Vector2(8, -19.5), Vector2(10.8, -14), 0.86,
		{"torso": -6, "head": -4, "wo": 5, "hip": 26.8, "fF": 5, "fB": -5, "dx": 6, "trail": 1})
	var thrust_front := _hold(Vector2(4.5, -2.5), Vector2(0, 2.6), Vector2(9.5, -5.5), 0.4,
		{"torso": -7, "head": 4, "wo": 2, "hip": 24, "fF": 6.4, "fB": -6.4, "dx": 6, "trail": 1})
	var kit := RigKit.new()
	var changes := {
		&"head": {"detail": Callable(RigHeads, &"dress_head").bind(Callable(RigHeads, &"war_hat"))},
		&"torso": {"detail": Callable(RigTorso, &"dress").bind({"armor": &"quilt"}), "depends": RigPiece.USES_VIEW},
	}
	kit.pieces = RigKit.remix(RigBody.base_pieces(), changes, [&"sword", &"pauldron", &"pauldronB"], [RigWeapons.spear_piece()])
	kit.fit = Callable(KitSpear, &"fit")
	kit.stance = {RigSolver.VIEW_BACK: stance_back, RigSolver.VIEW_FRONT: stance_front}
	var idle_fields := CARRY.duplicate()
	idle_fields.merge({"uaB": 12, "laB": -12})
	kit.idle = RigKit.both_views(UnitPose.make(idle_fields))
	kit.clips = {
		&"attackUp": _attack(stance_back, pull_back, thrust_back),
		&"attackDown": _attack(stance_front, pull_front, thrust_front),
		&"skillUp": _skill(stance_back, pull_back, thrust_back),
		&"skillDown": _skill(stance_front, pull_front, thrust_front),
		&"hit": {RigSolver.VIEW_BACK: _hit(stance_back), RigSolver.VIEW_FRONT: _hit(stance_front)},
	}
	kit.walk = Callable(KitSpear, &"walk")
	kit.tip = Vector2(44, 30)
	kit.is_tip_on_weapon = true
	kit.glow_x = 38.0
	kit.is_glow_on_weapon = true
	kit.skill_wind_keys = 1
	return kit


## Both hands stay on the shaft: no off-hand grip width from the clips.
static func fit(_pose: UnitPose) -> Dictionary:
	return {"gw": 0}


## The run with the spear carried at the slope, bobbing with the stride.
static func walk(phase: float, _view: StringName) -> UnitPose:
	var carry := CARRY.duplicate()
	carry["blade"] = -86 + 4 * sin(TAU * phase)
	return RigClips.walk_pose(phase).with_fields(carry)


# Both hands on the shaft: the rear (sword) hand, the front hand on the
# shaft, the sword elbow; the spear's length scale (foreshortening).
static func _hold(rear: Vector2, front: Vector2, elbow: Vector2, weapon_length: float, extra: Dictionary) -> UnitPose:
	var blade := rad_to_deg(atan2(front.y - rear.y, front.x - rear.x))
	var fields := {"hip": 26, "fF": 5.6, "fB": -5.6, "torso": 3, "head": -2, "blade": blade, "wl": weapon_length, "wo": 0, "gw": 1,
		"grip": rear.distance_to(front) / weapon_length}
	fields.merge(RigSolver.arm_to(true, elbow, rear, blade), true)
	fields.merge(extra, true)
	return UnitPose.make(fields)


static func _attack(stance: UnitPose, pull: UnitPose, thrust: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.16, RigClips.Easing.OUT, pull), RigClips.ClipKey.new(0.08, RigClips.Easing.IN, thrust), RigClips.ClipKey.new(0.14, RigClips.Easing.LINEAR, thrust.with_fields({"trail": 0})),
		RigClips.ClipKey.new(0.26, RigClips.Easing.IN_OUT, stance),
	]


static func _skill(stance: UnitPose, pull: UnitPose, thrust: UnitPose) -> Array[RigClips.ClipKey]:
	var slide := thrust.values[UnitPose.WO] + 3
	return [
		RigClips.ClipKey.new(0.32, RigClips.Easing.OUT, pull.with_fields({"glow": 1, "hip": 23.2})),
		RigClips.ClipKey.new(0.1, RigClips.Easing.IN, thrust.with_fields({"glow": 1, "dx": 9, "wo": slide, "jump": 3})),
		RigClips.ClipKey.new(0.2, RigClips.Easing.LINEAR, thrust.with_fields({"glow": 0.4, "dx": 9, "wo": slide, "trail": 0})),
		RigClips.ClipKey.new(0.32, RigClips.Easing.IN_OUT, stance),
	]


static func _hit(stance: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.07, RigClips.Easing.OUT, stance.with_fields({"torso": -9, "head": -8, "hip": 25.2, "dx": -3.5, "eyes": 1, "flash": 1})),
		RigClips.ClipKey.new(0.13, RigClips.Easing.LINEAR, stance.with_fields({"torso": -8, "head": -8, "hip": 25.2, "dx": -3.5, "eyes": 1})),
		RigClips.ClipKey.new(0.26, RigClips.Easing.IN_OUT, stance),
	]
