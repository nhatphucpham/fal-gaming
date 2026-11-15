class_name KitArcher
extends RefCounted
## Cung (class.archer): hood, quiver, a recurve bow in the off hand. The aim
## runs along the board: from the front the bow stands upright before the
## chest, the bow arm short (pointing at the viewer), the draw hand at the
## cheek, the arrow short with its head toward the viewer; from behind the
## bow is raised beyond the head, the draw elbow out on the sword side.
## Stance = half drawn; attack = full draw, hold, release. Idle and the run
## carry the bow low. Archers face the target with the bow hand.

const BOW_FRONT: Array[Vector2] = [Vector2(-3.8, -12.6), Vector2(-1.4, -9.6)]
const BOW_BACK: Array[Vector2] = [Vector2(-6, -24.5), Vector2(-6, -34)]


static func build() -> RigKit:
	var stance_front := _aim(BOW_FRONT, Vector2(11, -11), Vector2(5, -17), {"head": 4})
	var full_front := _aim(BOW_FRONT, Vector2(12.2, -14.6), Vector2(5.8, -19.6), {"head": 4, "hip": 25.4})
	var loosed_front := _aim(BOW_FRONT, Vector2(12, -18.5), Vector2(13, -26.5), {"head": 4, "hip": 25.4, "draw": 0, "nock": 0})
	var stance_back := _aim(BOW_BACK, Vector2(12, -13), Vector2(4.4, -19.4), {"head": -4})
	var full_back := _aim(BOW_BACK, Vector2(12.6, -15.6), Vector2(4.2, -21.6), {"head": -5, "hip": 25.4})
	var loosed_back := _aim(BOW_BACK, Vector2(13, -17), Vector2(13.4, -26), {"head": -5, "hip": 25.4, "draw": 0, "nock": 0})
	var kit := RigKit.new()
	var changes := {
		&"head": {"detail": Callable(RigHeads, &"dress_head").bind(Callable(RigHeads, &"hood"))},
		&"torso": {"detail": Callable(RigTorso, &"dress").bind({"armor": &"vest", "belt2": true}), "depends": RigPiece.USES_VIEW},
	}
	kit.pieces = RigKit.remix(RigBody.base_pieces(), changes, [&"sword", &"pauldron", &"pauldronB", &"scarf"], [RigBow.quiver_piece(), RigBow.bow_piece()])
	# Generic hit and death keep the arms in close; the cheer still raises them.
	kit.fit = Callable(KitArcher, &"fit")
	kit.stance = {RigSolver.VIEW_BACK: stance_back, RigSolver.VIEW_FRONT: stance_front}
	kit.idle = RigKit.both_views(UnitPose.make(_relaxed(0.0)))
	kit.clips = {
		&"attackUp": _attack(stance_back, full_back, loosed_back),
		&"attackDown": _attack(stance_front, full_front, loosed_front),
		&"skillUp": _skill(stance_back, full_back, loosed_back),
		&"skillDown": _skill(stance_front, full_front, loosed_front),
	}
	kit.walk = Callable(KitArcher, &"walk")
	kit.tip = Vector2.ZERO
	kit.glow_bone = RigSolver.H_B
	kit.glow_x = 0.0
	kit.aims_off_hand = true
	return kit


## The archer's fit: a raised off arm (cheer, a fall) lets the bow go
## slack; otherwise the relaxed hold.
static func fit(pose: UnitPose) -> Dictionary:
	if pose.values[UnitPose.UA_B] > 100.0:
		return {"nock": 0, "draw": 0, "bowUp": 0}
	return _relaxed(0.0)


## The run with the bow carried low and the free arm swinging.
static func walk(phase: float, _view: StringName) -> UnitPose:
	var swing := sin(TAU * phase)
	var arms := _low(0.6 * swing)
	arms.merge(_loose(1.6 * swing), true)
	return RigClips.walk_pose(phase).with_fields(arms)


static func _aim(bow: Array[Vector2], draw_elbow: Vector2, draw_fist: Vector2, extra: Dictionary) -> UnitPose:
	var fields := {"torso": 2, "hip": 26, "fF": 5.6, "fB": -5.6, "draw": 1, "nock": 1, "bowUp": 1}
	fields.merge(RigSolver.arm_to(false, bow[0], bow[1]), true)
	fields.merge(RigSolver.arm_to(true, draw_elbow, draw_fist), true)
	fields.merge(extra, true)
	return UnitPose.make(fields)


# The bow hanging upright by the off hip, the other hand loose by the sword hip.
static func _relaxed(swing: float) -> Dictionary:
	var fields := _low(swing)
	fields.merge(_loose(swing), true)
	return fields


static func _low(swing: float) -> Dictionary:
	var fields := RigSolver.arm_to(false, Vector2(-8.4, -6 - swing), Vector2(-7.6, 2.6 - swing * 1.6))
	fields.merge({"draw": 0, "nock": 0, "bowUp": 0}, true)
	return fields


static func _loose(swing: float) -> Dictionary:
	return RigSolver.arm_to(true, Vector2(8.6, -6.2 + swing), Vector2(6.8 - swing, 1.8 + swing * 1.6))


static func _attack(stance: UnitPose, full: UnitPose, loosed: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.22, RigClips.Easing.OUT, full), RigClips.ClipKey.new(0.1, RigClips.Easing.LINEAR, full), RigClips.ClipKey.new(0.06, RigClips.Easing.OUT, loosed),
		RigClips.ClipKey.new(0.22, RigClips.Easing.LINEAR, loosed), RigClips.ClipKey.new(0.3, RigClips.Easing.IN_OUT, stance),
	]


static func _skill(stance: UnitPose, full: UnitPose, loosed: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.3, RigClips.Easing.OUT, full.with_fields({"glow": 1, "hip": 24.4})),
		RigClips.ClipKey.new(0.3, RigClips.Easing.LINEAR, full.with_fields({"glow": 1, "hip": 24.2})),
		RigClips.ClipKey.new(0.06, RigClips.Easing.OUT, loosed.with_fields({"glow": 0.6})),
		RigClips.ClipKey.new(0.26, RigClips.Easing.LINEAR, loosed.with_fields({"glow": 0.2})),
		RigClips.ClipKey.new(0.32, RigClips.Easing.IN_OUT, stance),
	]
