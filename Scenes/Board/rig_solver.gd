class_name RigSolver
extends RefCounted
## Turns a UnitPose into one transform per bone, in figure units with the
## feet on y = 0 (port of the sketch's `solve`). Seen from the front or the
## back a leg never bends sideways: a bent knee comes toward the viewer or
## goes away, so the thigh and shin get shorter on screen instead (a scale
## per bone). An off hand on a two-handed weapon reaches for it by IK.
## [codeblock]
## var frame := RigSolver.solve(pose, RigSolver.VIEW_FRONT)
## var hand := frame.bones[RigSolver.H_F] * Vector2(0, 1.5)
## [/codeblock]

## A player unit: seen three-quarters from behind, facing up the board.
const VIEW_BACK: StringName = &"back"
## An enemy unit: seen from the front, facing down the board.
const VIEW_FRONT: StringName = &"front"
const UPPER_ARM: float = 9.5
const FOREARM: float = 9.0
const LEG: float = 12.5
const ANKLE: float = 2.2
const SHOULDER: float = 5.6
const HIP_HALF: float = 2.6
# Bones, parents before children; F = the sword side, B = the other.
const ROOT: int = 0
const TORSO: int = 1
const HEAD: int = 2
const UA_B: int = 3
const LA_B: int = 4
const H_B: int = 5
const UA_F: int = 6
const LA_F: int = 7
const H_F: int = 8
const TH_B: int = 9
const SH_B: int = 10
const FT_B: int = 11
const TH_F: int = 12
const SH_F: int = 13
const FT_F: int = 14
const BONE_COUNT: int = 15
## A piece drawn in figure space instead of a bone's.
const WORLD: int = -1
const PARENTS: Array[int] = [-1, ROOT, TORSO, TORSO, UA_B, LA_B, TORSO, UA_F, LA_F, ROOT, TH_B, SH_B, ROOT, TH_F, SH_F]
const OFFSETS: Array[Vector2] = [
	Vector2.ZERO, Vector2.ZERO, Vector2(0, -18.2), Vector2(-SHOULDER, -14.6), Vector2(0, UPPER_ARM), Vector2(0, FOREARM),
	Vector2(SHOULDER, -14.6), Vector2(0, UPPER_ARM), Vector2(0, FOREARM), Vector2(-HIP_HALF, 0), Vector2(0, LEG),
	Vector2(0, LEG), Vector2(HIP_HALF, 0), Vector2(0, LEG), Vector2(0, LEG),
]
# The pose field holding each bone's angle (-1: none).
const ANGLE_FIELDS: Array[int] = [
	UnitPose.ROOT, UnitPose.TORSO, UnitPose.HEAD, UnitPose.UA_B, UnitPose.LA_B, -1, UnitPose.UA_F, UnitPose.LA_F, -1,
	UnitPose.TH_B, UnitPose.SH_B, UnitPose.FT_B, UnitPose.TH_F, UnitPose.SH_F, UnitPose.FT_F,
]
# Bone lengths of the bones that can be shortened on screen (0: fixed).
const LENGTHS: Array[float] = [0, 0, 0, UPPER_ARM, FOREARM, 0, UPPER_ARM, FOREARM, 0, LEG, LEG, 0, LEG, LEG, 0]
# Joint limits in degrees; elbows never fold past straight the wrong way.
const LIMITS: Dictionary[int, Vector2] = {LA_F: Vector2(-150, 20), LA_B: Vector2(-150, 150), HEAD: Vector2(-35, 35)}
# Points that may touch the ground: bone, point, radius.
const CONTACTS: Array[Array] = [
	[FT_F, Vector2(2.6, ANKLE), 0.0], [FT_F, Vector2(-2.6, ANKLE), 0.0], [FT_B, Vector2(2.6, ANKLE), 0.0],
	[FT_B, Vector2(-2.6, ANKLE), 0.0], [ROOT, Vector2.ZERO, 5.5], [TORSO, Vector2(0, -14), 7.0], [HEAD, Vector2(0, -8), 7.4],
	[SH_F, Vector2.ZERO, 3.0], [SH_B, Vector2.ZERO, 3.0], [H_F, Vector2(0, 1.5), 2.4], [H_B, Vector2(0, 1.5), 2.4],
]


## A solved pose: a transform per bone (bone space to figure space), the
## on-screen length scale of each bone, and how far each heel is raised.
class Frame:
	extends RefCounted
	var bones: Array[Transform2D] = []
	var scales := PackedFloat32Array()
	var heel_front: float = 0.0
	var heel_back: float = 0.0


## The bone transforms of `pose` seen from `view` (VIEW_BACK or VIEW_FRONT).
static func solve(pose: UnitPose, view: StringName) -> Frame:
	var p := pose.values
	var angles := PackedFloat32Array()
	angles.resize(BONE_COUNT)
	for bone: int in BONE_COUNT:
		var field := ANGLE_FIELDS[bone]
		var degrees := p[field] if field >= 0 else 0.0
		if LIMITS.has(bone):
			degrees = clampf(degrees, LIMITS[bone].x, LIMITS[bone].y)
		angles[bone] = deg_to_rad(degrees)
	var scales := PackedFloat32Array()
	scales.resize(BONE_COUNT)
	scales.fill(1.0)
	scales[UA_F] = p[UnitPose.K_UF]
	scales[LA_F] = p[UnitPose.K_LF]
	scales[UA_B] = p[UnitPose.K_UB]
	scales[LA_B] = p[UnitPose.K_LB]
	if p[UnitPose.IK] > 0.001:
		_place_legs(p, angles, scales, view)
	var bones := _run(p, angles, scales, 0.0)
	if p[UnitPose.GW] > 0.001:
		_reach_off_hand(bones, angles, p)
		bones = _run(p, angles, scales, 0.0)
	var low := -1e9
	for contact: Array in CONTACTS:
		var bone_transform: Transform2D = bones[contact[0]]
		low = maxf(low, (bone_transform * (contact[1] as Vector2)).y + float(contact[2]))
	var ik := p[UnitPose.IK]
	var ground := lerpf(lerpf(-low, -p[UnitPose.HIP], ik), -p[UnitPose.HIP], p[UnitPose.RIDE]) - p[UnitPose.JUMP]
	var frame := Frame.new()
	frame.bones = _run(p, angles, scales, ground)
	frame.scales = scales
	frame.heel_front = p[UnitPose.HE_F] * ik
	frame.heel_back = p[UnitPose.HE_B] * ik
	return frame


## Arm angles and length scales that put the shoulder of side `side_f`
## (true: the sword side) toward `elbow` and the fist at `fist`, in torso
## space; with `blade` (degrees) the sword fist holds a weapon at that screen
## angle. Port of the sketch's `armTo`; returns pose fields.
static func arm_to(side_f: bool, elbow: Vector2, fist: Vector2, blade: float = NAN) -> Dictionary:
	var suffix := "F" if side_f else "B"
	var shoulder := Vector2(SHOULDER if side_f else -SHOULDER, -14.6)
	var upper := elbow - shoulder
	var upper_angle := atan2(-upper.x, upper.y)
	var has_blade := not is_nan(blade)
	var wrist := fist
	if has_blade:
		var blade_rad := deg_to_rad(blade)
		wrist = fist + Vector2(1.5 * sin(blade_rad), -1.5 * cos(blade_rad))
	var lower := wrist - elbow
	var lower_angle := atan2(-lower.x, lower.y)
	var lower_length := lower.length() - (0.0 if has_blade else 1.5)
	var fields := {
		"ua" + suffix: rad_to_deg(upper_angle),
		"la" + suffix: fmod(rad_to_deg(lower_angle - upper_angle) + 540.0, 360.0) - 180.0,
		"kU" + suffix: clampf(upper.length() / UPPER_ARM, 0.2, 1.1),
		"kL" + suffix: clampf(lower_length / FOREARM, 0.2, 1.1),
	}
	if side_f and not has_blade:
		fields["blade"] = rad_to_deg(lower_angle)
	return fields


# Legs by IK: aim each thigh at its foot and shorten thigh and shin by how
# far the knee comes toward the viewer (more seen from behind).
static func _place_legs(p: PackedFloat32Array, angles: PackedFloat32Array, scales: PackedFloat32Array, view: StringName) -> void:
	var facing := -1.0 if view == VIEW_BACK else 1.0
	var ik := p[UnitPose.IK]
	var root_transform := Transform2D(angles[ROOT], Vector2(p[UnitPose.DX], -p[UnitPose.HIP]))
	var share := 0.7 if facing < 0.0 else 0.35
	for leg: Array in [[true, UnitPose.F_F, UnitPose.L_F, UnitPose.ST_F, TH_F, SH_F], [false, UnitPose.F_B, UnitPose.L_B, UnitPose.ST_B, TH_B, SH_B]]:
		var hip := root_transform * Vector2(HIP_HALF if leg[0] else -HIP_HALF, 0)
		var to_foot := Vector2(p[leg[1]] - hip.x, -ANKLE - p[leg[2]] + facing * p[leg[3]] * 0.5 - hip.y)
		var reach := minf(to_foot.length(), 2.0 * LEG)
		var shortfall := 2.0 * LEG - reach
		var shin_scale := clampf(1.0 - shortfall * share / LEG, 0.3, 1.0)
		var thigh_scale := clampf(reach / LEG - shin_scale, 0.3, 1.0)
		angles[leg[4]] = lerpf(angles[leg[4]], atan2(-to_foot.x, to_foot.y) - angles[ROOT], ik)
		angles[leg[5]] = lerpf(angles[leg[5]], 0.0, ik)
		scales[leg[4]] = lerpf(1.0, thigh_scale, ik)
		scales[leg[5]] = lerpf(1.0, shin_scale, ik)


# Composes the bones from the root at height `ground`.
static func _run(p: PackedFloat32Array, angles: PackedFloat32Array, scales: PackedFloat32Array, ground: float) -> Array[Transform2D]:
	var bones: Array[Transform2D] = []
	bones.resize(BONE_COUNT)
	var world := PackedFloat32Array()
	world.resize(BONE_COUNT)
	for bone: int in BONE_COUNT:
		var parent := PARENTS[bone]
		var angle := angles[bone]
		var offset := OFFSETS[bone]
		if parent >= 0 and LENGTHS[parent] > 0.0:
			offset.y = LENGTHS[parent] * scales[parent]
		if bone == FT_F or bone == FT_B:
			angle = lerpf(angle, -world[parent], p[UnitPose.FLAT])
		elif bone == H_F:
			angle = deg_to_rad(p[UnitPose.BLADE]) - world[parent]
		elif bone == H_B:
			angle = 0.0
		if parent < 0:
			bones[bone] = Transform2D(angle, Vector2(p[UnitPose.DX], ground))
			world[bone] = angle
		else:
			bones[bone] = bones[parent] * Transform2D(angle, offset)
			world[bone] = world[parent] + angle
	return bones


# Two-bone IK for the off arm toward the point `grip` along the weapon, the
# elbow kept low; blends the arm angles by the grip weight.
static func _reach_off_hand(bones: Array[Transform2D], angles: PackedFloat32Array, p: PackedFloat32Array) -> void:
	var upper := UPPER_ARM * p[UnitPose.K_UB]
	var lower := FOREARM * p[UnitPose.K_LB] + 1.5
	var shoulder := bones[UA_B].origin
	var target := bones[H_F] * Vector2(p[UnitPose.GRIP] * p[UnitPose.WL] + p[UnitPose.WO], 1.5)
	var delta := target - shoulder
	var distance := clampf(delta.length(), 1.0, upper + lower - 0.01)
	var base := atan2(-delta.x, delta.y)
	var spread := acos(clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0))
	var best_upper := 0.0
	var best_lower := 0.0
	var best_y := -INF
	for sign_of: float in [1.0, -1.0]:
		var upper_angle := base + sign_of * spread
		var elbow := shoulder + Vector2(-sin(upper_angle) * upper, cos(upper_angle) * upper)
		if elbow.y > best_y:
			best_y = elbow.y
			best_upper = upper_angle
			best_lower = atan2(-(target.x - elbow.x), target.y - elbow.y)
	var trunk := angles[ROOT] + angles[TORSO]
	var weight := p[UnitPose.GW]
	angles[UA_B] = lerpf(angles[UA_B], _nearest_turn(best_upper - trunk, angles[UA_B]), weight)
	angles[LA_B] = lerpf(angles[LA_B], _nearest_turn(best_lower - best_upper, angles[LA_B]), weight)


# `angle` plus whole turns, as close as possible to `reference`.
static func _nearest_turn(angle: float, reference: float) -> float:
	return angle + TAU * floorf((reference - angle) / TAU + 0.5)
