class_name KitShield
extends RefCounted
## Khiên (class.shield): the shield stays between the unit and the enemy:
## low in front of the off side seen from the front, beyond the body with
## its rim showing at the off side from behind. The attack shoves along the
## board with the shield a little nearer the enemy, then makes a short cut;
## a hit braces the shield. Iron helmet with cheek guards, lamellar armour.


static func build() -> RigKit:
	var hold_front := _shield_arm(Vector2(-9, -6.5), Vector2(-3, 0), {})
	var hold_back := _shield_arm(Vector2(-9.5, -9), Vector2(-3.5, -5), {})
	var stance_front := UnitPose.make(_joined({"torso": 3, "head": -2, "uaF": -26, "laF": -76, "blade": -62, "hip": 26, "fF": 5.6, "fB": -5.6}, hold_front))
	var stance_back := stance_front.with_fields(hold_back)
	var shove_up := UnitPose.make(_joined({"torso": -6, "head": -3, "uaF": -14, "laF": -40, "blade": 50, "hip": 26.6, "fF": 5, "fB": -5, "dx": 5},
		_shield_arm(Vector2(-9.5, -11), Vector2(-3.5, -8.5), {"wl": 0.9})))
	var shove_down := UnitPose.make(_joined({"torso": -6, "head": 3, "uaF": -14, "laF": -40, "blade": 50, "hip": 24.4, "fF": 6.4, "fB": -6.4, "dx": 5},
		_shield_arm(Vector2(-9, -5), Vector2(-3, 2.6), {"wl": 1.12})))
	var cut_up := shove_up.with_fields({"head": -4, "uaF": -176, "laF": -24, "blade": -118, "hip": 26.8, "dx": 5.5, "trail": 1, "wl": 0.94})
	var cut_down := shove_down.with_fields({"torso": -7, "head": 4, "uaF": 20, "laF": 16, "blade": -240, "hip": 24, "dx": 5.5, "trail": 1, "wl": 1.08})
	var brace_front := _brace(Vector2(-9, -6.5), Vector2(-3, 0), 1.06)
	var brace_back := _brace(Vector2(-9.5, -9), Vector2(-3.5, -5), 0.96)
	var kit := RigKit.new()
	var changes := {
		&"head": {"detail": Callable(RigHeads, &"dress_head").bind(Callable(RigHeads, &"helm").bind({"iron": true, "cheeks": true}))},
		&"torso": {"detail": Callable(RigTorso, &"dress").bind({"armor": &"lamellar", "strap": true}), "depends": RigPiece.USES_VIEW},
		&"pauldron": {"color": RigPalette.IRON},
		&"pauldronB": {"color": RigPalette.IRON},
	}
	kit.pieces = RigKit.remix(RigBody.base_pieces(), changes, [&"scarf"], [RigWeapons.shield_piece()])
	kit.stance = {RigSolver.VIEW_BACK: stance_back, RigSolver.VIEW_FRONT: stance_front}
	var arms := {"uaF": -9, "laF": -6, "blade": 56}
	kit.idle = {RigSolver.VIEW_BACK: UnitPose.make(_joined(arms, hold_back)), RigSolver.VIEW_FRONT: UnitPose.make(_joined(arms, hold_front))}
	kit.clips = {
		&"attackUp": _attack(stance_back, shove_up, cut_up),
		&"attackDown": _attack(stance_front, shove_down, cut_down),
		&"skillUp": _skill(stance_back, shove_up, cut_up),
		&"skillDown": _skill(stance_front, shove_down, cut_down),
		&"hit": {RigSolver.VIEW_BACK: _hit(stance_back, brace_back), RigSolver.VIEW_FRONT: _hit(stance_front, brace_front)},
	}
	kit.walk = Callable(KitShield, &"walk").bind(hold_back, hold_front)
	kit.skill_wind_keys = 1
	return kit


## The run with the shield held as in the stance of `view`.
static func walk(phase: float, view: StringName, hold_back: Dictionary, hold_front: Dictionary) -> UnitPose:
	return RigClips.walk_pose(phase).with_fields(hold_back if view == RigSolver.VIEW_BACK else hold_front)


# The off arm holding the shield: elbow and fist in torso space.
static func _shield_arm(elbow: Vector2, fist: Vector2, extra: Dictionary) -> Dictionary:
	var fields := RigSolver.arm_to(false, elbow, fist)
	fields["tilt"] = 0
	fields.merge(extra, true)
	return fields


static func _brace(elbow: Vector2, fist: Vector2, weapon_length: float) -> UnitPose:
	return UnitPose.make(_joined({"torso": -8, "head": 6, "uaF": -24, "laF": -50, "blade": -40, "hip": 24.6, "fF": 4, "fB": -6.6, "dx": -3, "eyes": 1, "flash": 1},
		_shield_arm(Vector2(elbow.x, elbow.y - 2), Vector2(fist.x + 0.5, fist.y - 3.5), {"wl": weapon_length})))


static func _attack(stance: UnitPose, shove: UnitPose, cut: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.12, RigClips.Easing.OUT, stance.with_fields({"torso": 6, "uaF": -10, "laF": -30, "blade": 60, "hip": 24.6})),
		RigClips.ClipKey.new(0.1, RigClips.Easing.IN, shove), RigClips.ClipKey.new(0.1, RigClips.Easing.OUT, cut), RigClips.ClipKey.new(0.12, RigClips.Easing.LINEAR, cut.with_fields({"trail": 0})),
		RigClips.ClipKey.new(0.26, RigClips.Easing.IN_OUT, stance),
	]


static func _skill(stance: UnitPose, shove: UnitPose, cut: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.3, RigClips.Easing.OUT, stance.with_fields({"hip": 23.4, "glow": 1})),
		RigClips.ClipKey.new(0.12, RigClips.Easing.IN, shove.with_fields({"glow": 1, "dx": 8})),
		RigClips.ClipKey.new(0.12, RigClips.Easing.OUT, cut.with_fields({"glow": 1, "dx": 8.5})),
		RigClips.ClipKey.new(0.2, RigClips.Easing.LINEAR, cut.with_fields({"glow": 0.4, "dx": 8.5, "trail": 0})),
		RigClips.ClipKey.new(0.32, RigClips.Easing.IN_OUT, stance),
	]


static func _hit(stance: UnitPose, brace: UnitPose) -> Array[RigClips.ClipKey]:
	return [RigClips.ClipKey.new(0.07, RigClips.Easing.OUT, brace), RigClips.ClipKey.new(0.16, RigClips.Easing.LINEAR, brace.with_fields({"flash": 0})), RigClips.ClipKey.new(0.26, RigClips.Easing.IN_OUT, stance)]


static func _joined(first: Dictionary, second: Dictionary) -> Dictionary:
	var fields := first.duplicate()
	fields.merge(second, true)
	return fields
