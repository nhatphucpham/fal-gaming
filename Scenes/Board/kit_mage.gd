class_name KitMage
extends RefCounted
## Pháp (class.mage): a long robe over the legs, a drooping hat and white
## beard, a staff with a crescent holding an orb. The attack raises the
## staff, the orb flares, then the staff thrusts toward the enemy.



static func build() -> RigKit:
	var stance := UnitPose.make({"torso": 2, "head": -2, "uaF": -22, "laF": -74, "blade": -96, "uaB": 20, "laB": -38, "hip": 26, "fF": 5.6, "fB": -5.6})
	var raised := stance.with_fields({"uaF": -168, "laF": -6, "blade": -94, "head": -4, "glow": 0.8, "hip": 26.8})
	var forward_back := raised.with_fields({"uaF": -150, "laF": -10, "blade": -76, "glow": 0.3, "dx": 2})
	var forward_front := stance.with_fields({"uaF": -46, "laF": -14, "blade": 42, "wl": 0.8, "glow": 0.3, "dx": 2, "head": 4})
	var kit := RigKit.new()
	var robe := Callable(KitMage, &"robe_path")
	var changes := {
		&"head": {"detail": Callable(RigHeads, &"dress_head").bind(Callable(RigHeads, &"mage_hat")), "depends": RigPiece.USES_VIEW | RigPiece.USES_EYES | RigPiece.USES_SWAY, "sway_period_sec": 0.5},
		&"torso": {"color": RigPalette.PLUM, "detail": Callable(RigTorso, &"dress").bind({"armor": &"robe"}), "depends": RigPiece.USES_VIEW},
		&"skirt": {"color": RigPalette.PLUM, "path": robe, "detail": Callable(KitMage, &"robe_detail")},
		&"uaF": {"color": RigPalette.PLUM},
		&"uaB": {"color": RigPalette.dark(RigPalette.PLUM)},
	}
	kit.pieces = RigKit.remix(RigBody.base_pieces(), changes, [&"sword", &"pauldron", &"pauldronB"], [RigWeapons.staff_piece()])
	kit.stance = RigKit.both_views(stance)
	kit.idle = RigKit.both_views(UnitPose.make({"uaF": -10, "laF": -40, "blade": -94, "uaB": 12, "laB": -12}))
	kit.clips = {
		&"attackUp": _attack(stance, raised, forward_back),
		&"attackDown": _attack(stance, raised, forward_front),
		&"skillUp": _skill(stance, raised, forward_back),
		&"skillDown": _skill(stance, raised, forward_front),
	}
	kit.walk = Callable(KitMage, &"walk")
	kit.tip = Vector2(30, 22)
	kit.is_tip_on_weapon = true
	kit.glow_x = 28.6
	kit.is_glow_on_weapon = true
	return kit


## The run with the staff held upright, bobbing with the stride.
static func walk(phase: float, _view: StringName) -> UnitPose:
	return RigClips.walk_pose(phase).with_fields({"blade": -88 + 5 * sin(TAU * phase), "uaF": -12, "laF": -40})


static func robe_path(path: RigPath, _args: RigPiece.Args) -> void:
	path.move_to(-6.4, -1).line_to(6.4, -1).line_to(9.8, 20.6).quad_to(0, 22.6, -9.8, 20.6).close()


static func robe_detail(mesh: RigMesh, _args: RigPiece.Args) -> void:
	mesh.stroke(RigPath.new().move_to(-9.4, 19).quad_to(0, 21, 9.4, 19), RigPalette.GOLD, 1.2)
	mesh.stroke(RigPath.new().move_to(1.2, 1).line_to(1.6, 20).move_to(-4, 2).line_to(-6, 19), RigPalette.PLUM_DARK, 0.8)


static func _attack(stance: UnitPose, raised: UnitPose, forward: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.28, RigClips.Easing.OUT, raised), RigClips.ClipKey.new(0.12, RigClips.Easing.LINEAR, raised), RigClips.ClipKey.new(0.08, RigClips.Easing.OUT, forward),
		RigClips.ClipKey.new(0.22, RigClips.Easing.LINEAR, forward.with_fields({"glow": 0})), RigClips.ClipKey.new(0.28, RigClips.Easing.IN_OUT, stance),
	]


static func _skill(stance: UnitPose, raised: UnitPose, forward: UnitPose) -> Array[RigClips.ClipKey]:
	return [
		RigClips.ClipKey.new(0.36, RigClips.Easing.OUT, raised.with_fields({"glow": 1, "jump": 2})),
		RigClips.ClipKey.new(0.24, RigClips.Easing.LINEAR, raised.with_fields({"glow": 1, "jump": 2.4})),
		RigClips.ClipKey.new(0.08, RigClips.Easing.OUT, forward.with_fields({"glow": 1})),
		RigClips.ClipKey.new(0.26, RigClips.Easing.LINEAR, forward.with_fields({"glow": 0.3})),
		RigClips.ClipKey.new(0.32, RigClips.Easing.IN_OUT, stance),
	]
