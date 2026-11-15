class_name RigBody
extends RefCounted
## The body pieces every class starts from (the sketch's Kiếm `PIECES`):
## limbs, fists, feet, skirt, torso and its dressings, pauldrons, in their
## per-view draw order. Seen from the front the arms and weapon lie over
## the body; seen from behind the body covers them. Classes swap, drop or
## add pieces in their RigKit.


## The Kiếm pieces in draw order (heads and the sword come from RigHeads
## and RigWeapons).
static func base_pieces() -> Array[RigPiece]:
	var limb := RigPiece.USES_SCALE
	var pieces: Array[RigPiece] = [
		_piece(&"uaB", RigSolver.UA_B, 4, 0, RigPalette.dark(RigPalette.TUNIC), &"arm_path", &"", limb),
		_piece(&"laB", RigSolver.LA_B, 4, 0, RigPalette.dark(RigPalette.SKIN), &"forearm_path", &"bracer_detail", limb),
		_piece(&"hB", RigSolver.H_B, 4, 0, RigPalette.dark(RigPalette.SKIN), &"fist_path", &"", 0),
		_piece(&"thB", RigSolver.TH_B, 0, 1, RigPalette.dark(RigPalette.TROUSERS), &"thigh_path", &"", limb),
		_piece(&"shB", RigSolver.SH_B, 0, 1, RigPalette.dark(RigPalette.BOOT), &"shin_path", &"cuff_detail", limb),
		_piece(&"ftB", RigSolver.FT_B, 0, 1, RigPalette.dark(RigPalette.BOOT), &"foot_path", &"foot_detail", RigPiece.USES_HEEL | RigPiece.USES_VIEW),
		_piece(&"thF", RigSolver.TH_F, 1, 2, RigPalette.TROUSERS, &"thigh_path", &"", limb),
		_piece(&"shF", RigSolver.SH_F, 1, 2, RigPalette.BOOT, &"shin_path", &"cuff_detail", limb),
		_piece(&"ftF", RigSolver.FT_F, 1, 2, RigPalette.BOOT, &"foot_path", &"foot_detail", RigPiece.USES_HEEL | RigPiece.USES_VIEW),
		_piece(&"skirt", RigSolver.ROOT, 2, 5, RigPalette.TUNIC_DARK, &"skirt_path", &"skirt_detail", 0),
		torso_piece({"armor": &"plate", "strap": true, "scarf": true}),
		scarf_piece(),
		RigHeads.head_piece(Callable(RigHeads, &"helm").bind({"plume": true}), 0),
		RigHeads.face_piece(true),
		RigWeapons.sword_piece(),
		_piece(&"uaF", RigSolver.UA_F, 6, 4, RigPalette.TUNIC, &"arm_path", &"", limb),
		_piece(&"laF", RigSolver.LA_F, 6, 4, RigPalette.SKIN, &"forearm_path", &"bracer_detail", limb),
		_piece(&"hF", RigSolver.H_F, 6, 4, RigPalette.SKIN, &"fist_path", &"", 0),
		_piece(&"pauldronB", RigSolver.UA_B, 7, 7, RigPalette.STEEL, &"pauldron_path", &"pauldron_detail", 0),
		_piece(&"pauldron", RigSolver.UA_F, 7, 7, RigPalette.STEEL, &"pauldron_path", &"pauldron_detail", 0),
	]
	return pieces


## The torso with its dressing: `armor` plate (Kiếm, Kỵ), lamellar (Khiên),
## quilt (Thương), vest (Cung) or robe (Pháp); `strap`, `scarf` (its knot
## in front; scarf_piece draws it from behind), `belt2`.
static func torso_piece(options: Dictionary) -> RigPiece:
	var piece := _piece(&"torso", RigSolver.TORSO, 2, 5, RigPalette.TUNIC, &"torso_path", &"", RigPiece.USES_VIEW)
	piece.detail = Callable(RigTorso, &"dress").bind(options)
	return piece


## The scarf's swaying tails and knot over the back (from the front its knot
## is part of the torso's dressing).
static func scarf_piece() -> RigPiece:
	var piece := RigPiece.make(&"scarf", RigSolver.TORSO, NAN, 5)
	piece.paint = Callable(RigTorso, &"paint_scarf_back")
	piece.depends = RigPiece.USES_SWAY
	piece.sway_period_sec = 0.42
	return piece


static func arm_path(path: RigPath, args: RigPiece.Args) -> void:
	_capsule(path, 2.8, 2.4, RigSolver.UPPER_ARM * args.scale)


static func forearm_path(path: RigPath, args: RigPiece.Args) -> void:
	_capsule(path, 2.4, 2.0, RigSolver.FOREARM * args.scale)


static func fist_path(path: RigPath, _args: RigPiece.Args) -> void:
	path.arc(0, 1.5, 2.3, 0, 7)


static func thigh_path(path: RigPath, args: RigPiece.Args) -> void:
	_capsule(path, 3.3, 2.8, RigSolver.LEG * args.scale)


static func shin_path(path: RigPath, args: RigPiece.Args) -> void:
	_capsule(path, 2.8, 2.2, RigSolver.LEG * args.scale)


static func cuff_detail(mesh: RigMesh, _args: RigPiece.Args) -> void:
	mesh.fill_rect(-3, -0.2, 6, 2.2, RigPalette.LEATHER)


## A foot seen end on: from behind a heel block, the sole showing below it
## when the heel lifts; from the front a toe cap that tucks up instead.
static func foot_path(path: RigPath, args: RigPiece.Args) -> void:
	var heel := args.heel
	var is_back := args.view == RigSolver.VIEW_BACK
	var bottom := RigSolver.ANKLE + 6.5 * heel if is_back else RigSolver.ANKLE + 1.2 - 1.6 * heel
	var width := 2.7 + (0.5 * heel if is_back else 0.3)
	path.move_to(-2.4, -2.2).line_to(2.4, -2.2).quad_to(width + 0.4, bottom - 2, width - 0.6, bottom)
	path.quad_to(0, bottom + 1.1, -width + 0.6, bottom).quad_to(-width - 0.4, bottom - 2, -2.4, -2.2).close()


static func foot_detail(mesh: RigMesh, args: RigPiece.Args) -> void:
	if args.view == RigSolver.VIEW_BACK:
		if args.heel > 0.12:
			var bottom := RigSolver.ANKLE + 6.5 * args.heel
			mesh.fill(RigPath.new().move_to(-2.1, 0.6).line_to(2.1, 0.6).quad_to(2.8, bottom - 2, 1.7, bottom - 0.5)
				.quad_to(0, bottom + 0.3, -1.7, bottom - 0.5).quad_to(-2.8, bottom - 2, -2.1, 0.6).close(), RigPalette.SOLE)
		return
	mesh.stroke(RigPath.new().move_to(-2.3, 0.9).quad_to(0, -0.4, 2.3, 0.9), RigPalette.LEATHER, 0.7)


static func bracer_detail(mesh: RigMesh, args: RigPiece.Args) -> void:
	var s := args.scale
	mesh.fill(RigPath.new().move_to(-2.4, 2.6 * s).line_to(2.4, 2.6 * s).line_to(2.1, 7.6 * s).line_to(-2.1, 7.6 * s).close(), RigPalette.LEATHER)
	mesh.stroke(RigPath.new().move_to(-2.3, 3.2 * s).line_to(2.3, 3.2 * s), RigPalette.GOLD, 0.6)


static func skirt_path(path: RigPath, _args: RigPiece.Args) -> void:
	path.move_to(-6.4, -1).line_to(6.4, -1).line_to(7.8, 5).line_to(-7.8, 5).close()


static func skirt_detail(mesh: RigMesh, _args: RigPiece.Args) -> void:
	mesh.stroke(RigPath.new().move_to(-7.4, 3.9).line_to(7.4, 3.9), RigPalette.GOLD, 0.9)
	mesh.stroke(RigPath.new().move_to(0, 0.5).line_to(0, 4.8), RigPalette.INK, 0.6)


static func torso_path(path: RigPath, _args: RigPiece.Args) -> void:
	path.move_to(-6, 1.2).line_to(6, 1.2).line_to(7.2, -11.6).quad_to(7.3, -17.4, 2.4, -18.1)
	path.line_to(-2.4, -18.1).quad_to(-7.3, -17.4, -7.2, -11.6).close()


static func pauldron_path(path: RigPath, _args: RigPiece.Args) -> void:
	path.arc(0, 0.2, 4.1, PI * 0.95, PI * 2.05).quad_to(0, 4.6, -4.1, 0.9).close()


static func pauldron_detail(mesh: RigMesh, _args: RigPiece.Args) -> void:
	mesh.stroke(RigPath.new().arc(0, 0.6, 2.6, PI * 1.1, PI * 1.9), RigPalette.STEEL_DARK, 0.7)
	mesh.fill(RigPath.new().arc(0, 1.6, 0.8, 0, 7), RigPalette.GOLD)


## A piece drawn from RigBody functions named `path_name` and `detail_name`.
static func _piece(id: StringName, bone: int, front: float, back: float, color: Color, path_name: StringName, detail_name: StringName, depends: int) -> RigPiece:
	var piece := RigPiece.make(id, bone, front, back)
	piece.color = color
	piece.path = Callable(RigBody, path_name)
	if detail_name != &"":
		piece.detail = Callable(RigBody, detail_name)
	piece.depends = depends
	return piece


static func _capsule(path: RigPath, top_radius: float, bottom_radius: float, length: float) -> void:
	path.arc(0, 0, top_radius, PI, 0).line_to(bottom_radius, length).arc(0, length, bottom_radius, 0, PI).close()
