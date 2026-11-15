class_name RigWeapons
extends RefCounted
## Weapons held in the sword hand (hand space: x runs along the weapon, its
## centre line at y = 1.5): Kiếm's sword, Thương's willow-leaf spear, Pháp's
## staff with a crescent and orb, Kỵ's lance with a pennant; and Khiên's
## shield on the off hand. A weapon length below 1 foreshortens a pole that
## points at or away from the viewer, and its head grows a little (nearer).
## The slide along the weapon is a translation (`place_slid`), and the parts
## that sway or glow are pieces of their own, so the long shafts are cached
## per length only.

## Where the spear's tassel and the lance's pennant start, per unit length.
const SPEAR_BASE: float = 33.0
const LANCE_BASE: float = 40.0
const PENNANT_START: float = 31.0
const ORB_CENTER: float = 27.0
## The pennant's and the orb's shapes follow the weapon length only in
## these steps (they are placed exactly), so their meshes stay few.
const PENNANT_LENGTH_STEP: float = 0.1
const HEAD_LENGTH_STEP: float = 0.05


static func sword_piece() -> RigPiece:
	return _piece(&"sword", 5, 3, RigPalette.STEEL, &"sword_path", &"sword_detail", 0)


## The spear, then its swaying red tassel with the gold ferrule.
static func spear_pieces() -> Array[RigPiece]:
	var tassel := _part(&"spear_tassel", 3.5, 3, &"paint_tassel", RigPiece.USES_SWAY, 0.3)
	tassel.place = Callable(RigWeapons, &"place_at").bind(SPEAR_BASE)
	return [_piece(&"spear", 3.5, 3, RigPalette.WOOD, &"spear_path", &"spear_detail", RigPiece.USES_WEAPON), tassel]


## The staff, then its crescent and orb (which flares with the glow).
static func staff_pieces() -> Array[RigPiece]:
	var shaft := _piece(&"staff", 5, 3, RigPalette.WOOD, &"staff_path", &"", RigPiece.USES_WEAPON)
	var orb := _part(&"staff_orb", 5, 3, &"paint_orb", RigPiece.USES_WEAPON | RigPiece.USES_GLOW, 0.0)
	orb.place = Callable(RigWeapons, &"place_at").bind(ORB_CENTER)
	orb.weapon_length_step = HEAD_LENGTH_STEP
	return [shaft, orb]


## The lance, then its fluttering pennant.
static func lance_pieces() -> Array[RigPiece]:
	var pennant := _part(&"lance_pennant", 5, 3, &"paint_pennant", RigPiece.USES_WEAPON | RigPiece.USES_SWAY, 0.16)
	pennant.place = Callable(RigWeapons, &"place_at").bind(PENNANT_START)
	pennant.weapon_length_step = PENNANT_LENGTH_STEP
	return [_piece(&"lance", 5, 3, RigPalette.WOOD, &"lance_path", &"lance_detail", RigPiece.USES_WEAPON), pennant]


## The shield stays upright whatever the forearm does: its painted face
## from the front, the wooden inside from behind.
static func shield_piece() -> RigPiece:
	var piece := RigPiece.make(&"shield", RigSolver.H_B, 4.5, -0.5)
	piece.paint = Callable(RigWeapons, &"paint_shield")
	piece.place = Callable(RigWeapons, &"place_shield")
	piece.depends = RigPiece.USES_VIEW
	return piece


static func sword_path(path: RigPath, _args: RigPiece.Args) -> void:
	path.move_to(3.6, 0.1).line_to(23.5, 0.2).line_to(27, 1.5).line_to(23.5, 2.9).line_to(3.6, 3).close()
	path.rect(2.6, -1.6, 1.8, 6.2).rect(-3.4, 0.6, 6, 1.9).arc(-4, 1.5, 1.5, 0, 7)


static func sword_detail(mesh: RigMesh, _args: RigPiece.Args) -> void:
	mesh.fill_rect(2.6, -1.6, 1.8, 6.2, RigPalette.GOLD)
	mesh.fill(RigPath.new().arc(-4, 1.5, 1.5, 0, 7), RigPalette.GOLD)
	mesh.fill_rect(-3.4, 0.6, 6, 1.9, RigPalette.LEATHER)
	mesh.stroke(RigPath.new().move_to(4.6, 1.5).line_to(25.4, 1.5), RigPalette.STEEL_DARK, 0.5)
	mesh.stroke_rect(2.6, -1.6, 1.8, 6.2, RigPalette.INK, 0.5)


static func spear_path(path: RigPath, args: RigPiece.Args) -> void:
	var length := args.weapon_length
	var butt := -17.0 * length
	var base := SPEAR_BASE * length
	path.rect(butt, 0.65, base - butt, 1.7)
	_leaf(path, base, _head_scale(length), _head_length(length))


static func spear_detail(mesh: RigMesh, args: RigPiece.Args) -> void:
	var length := args.weapon_length
	var base := SPEAR_BASE * length
	var head := _head_length(length)
	mesh.fill(_leaf(RigPath.new(), base, _head_scale(length), head), RigPalette.STEEL)
	mesh.stroke(RigPath.new().move_to(base + 1, 1.5).line_to(base + 10 * head, 1.5), RigPalette.STEEL_DARK, 0.5)


## The tassel and ferrule at the spear head's base (x = 0 here).
static func paint_tassel(mesh: RigMesh, args: RigPiece.Args) -> void:
	var sway := args.sway * 0.7
	mesh.shape(RigPath.new().move_to(0, -0.2).quad_to(-3, -2.6, -6.6, -1.8 + sway).line_to(-5, 1.5)
		.line_to(-6.6, 4.8 + sway).quad_to(-3, 5.6, 0, 3.2).close(), RigPalette.VERMILION, 1.4)
	mesh.fill_rect(-0.6, 0.1, 1.4, 2.8, RigPalette.GOLD)


static func staff_path(path: RigPath, args: RigPiece.Args) -> void:
	path.rect(-15.0 * args.weapon_length, 0.55, 38.0 * args.weapon_length, 1.9)


## The crescent, the orb (brighter and larger with the glow) and the gold
## collar, around the crescent's centre (x = 0 here; the sketch's is 27 *
## length).
static func paint_orb(mesh: RigMesh, args: RigPiece.Args) -> void:
	var length := args.weapon_length
	var center := 0.0
	var s := _head_scale(length)
	mesh.shape(RigPath.new().arc(center, 1.5, 5.4 * s, 0.32 * PI, 1.68 * PI).arc(center + 2.6 * s, 1.5, 4.4 * s, 1.62 * PI, 0.38 * PI, true).close(), RigPalette.GOLD, 1.6)
	var flare := args.glow
	var radius := 2.9 * s * (1.0 + 0.25 * flare)
	mesh.shape(RigPath.new().arc(center + 1.6 * s, 1.5, radius, 0, 7), RigPalette.ORB_BRIGHT if flare > 0.3 else RigPalette.ORB, 1.5)
	mesh.fill(RigPath.new().arc(center + 0.6 * s, 0.4, radius * 0.35, 0, 7), Color.WHITE)
	mesh.fill_rect((22.4 - ORB_CENTER) * length - 1.6, 0, 1.8, 3, RigPalette.GOLD)


static func lance_path(path: RigPath, args: RigPiece.Args) -> void:
	var length := args.weapon_length
	var butt := -13.0 * length
	var base := LANCE_BASE * length
	path.rect(butt, 0.7, base - butt, 1.6)
	_lance_head(path, base, _head_scale(length), _head_length(length))
	_lance_guard(path, length)


static func lance_detail(mesh: RigMesh, args: RigPiece.Args) -> void:
	var length := args.weapon_length
	var base := LANCE_BASE * length
	mesh.fill(_lance_head(RigPath.new(), base, _head_scale(length), _head_length(length)), RigPalette.STEEL)
	mesh.fill_rect(base - 1, 0.2, 1.4, 2.6, RigPalette.GOLD)
	mesh.fill(_lance_guard(RigPath.new(), length), RigPalette.GOLD)


static func paint_pennant(mesh: RigMesh, args: RigPiece.Args) -> void:
	var length := args.weapon_length
	var flutter := args.sway * 1.2
	# Drawn from its start (x = 0 here); the sketch's start is 31 * length.
	var start := 0.0
	var end := 7.0 * length
	mesh.shape(RigPath.new().move_to(start, 2.4).line_to(end, 2.4).quad_to(end - 2, 5.6 + flutter, end - 6 + flutter, 9.4 + flutter)
		.quad_to(start + 1, 6, start, 2.4).close(), RigPalette.VERMILION, 1.4)


static func paint_shield(mesh: RigMesh, args: RigPiece.Args) -> void:
	var rim := func() -> RigPath: return RigPath.new().ellipse(0, 0, 10.4, 12.2, 0, 0, 7)
	if args.view == RigSolver.VIEW_BACK:
		mesh.shape(rim.call(), RigPalette.WOOD)
		var clip: PackedVector2Array = (rim.call() as RigPath).done().polylines[0]
		var planks := RigPath.new()
		for x: float in [-5.0, -1.7, 1.7, 5.0]:
			planks.move_to(x, -12).line_to(x, 12)
		mesh.stroke_clipped(planks, clip, RigPalette.PLANK, 0.7)
		mesh.fill_clipped(RigPath.new().rect(-10, -3.6, 20, 2.2).rect(-10, 2.2, 20, 2.2), clip, RigPalette.LEATHER)
		mesh.stroke(RigPath.new().ellipse(0, 0, 9.6, 11.4, 0, 0, 7), RigPalette.STEEL_DARK, 1.3)
		return
	mesh.shape(rim.call(), RigPalette.VERMILION)
	mesh.stroke(RigPath.new().ellipse(0, 0, 9.2, 11, 0, 0, 7), RigPalette.GOLD, 1.4)
	mesh.stroke(RigPath.new().ellipse(0, 0, 6.2, 7.4, 0, 0, 7), RigPalette.GOLD, 0.7)
	var star := RigPath.new()
	for index: int in 16:
		var radius := 2.6 if index % 2 else 4.8
		var angle := index * PI / 8.0
		star.line_to(radius * cos(angle) * 0.86, radius * sin(angle))
	mesh.fill(star.close(), RigPalette.GOLD)
	mesh.shape(RigPath.new().arc(0, 0, 2.1, 0, 7), RigPalette.STEEL, 1.4)
	mesh.alpha = 0.5
	mesh.fill(RigPath.new().ellipse(3.6, -6, 1.4, 2.6, 0.3, 0, 7), Color.WHITE)
	mesh.alpha = 1.0


## Where the shield sits in the off hand's space: upright on screen (tilted
## by the pose), scaled by the weapon length, a little toward the far side.
static func place_shield(frame: RigSolver.Frame, pose: UnitPose, view: StringName) -> Transform2D:
	var hand := frame.bones[RigSolver.H_B]
	var turn := -hand.get_rotation() + deg_to_rad(pose.values[UnitPose.TILT])
	var size := pose.values[UnitPose.WL]
	var nudge := 0.6 if view == RigSolver.VIEW_BACK else -0.6
	return Transform2D(0.0, Vector2(0, 1.5)) * Transform2D(turn, Vector2.ZERO) * Transform2D(0.0, Vector2(size, size), 0.0, Vector2.ZERO) \
		* Transform2D(0.0, Vector2(nudge, 0))


static func _head_scale(length: float) -> float:
	return 1.0 + (1.0 - length) * 0.9


static func _head_length(length: float) -> float:
	return clampf(length * 1.25, 0.55, 1.0)


static func _leaf(path: RigPath, base: float, head_scale: float, head: float) -> RigPath:
	return path.move_to(base, 1.5 - 1.1 * head_scale).quad_to(base + 4 * head, 1.5 - 2.9 * head_scale, base + 12 * head, 1.5) \
		.quad_to(base + 4 * head, 1.5 + 2.9 * head_scale, base, 1.5 + 1.1 * head_scale).close()


static func _lance_head(path: RigPath, base: float, head_scale: float, head: float) -> RigPath:
	return path.move_to(base, 1.5 - 1.7 * head_scale).line_to(base + 10 * head, 1.5).line_to(base, 1.5 + 1.7 * head_scale).close()


static func _lance_guard(path: RigPath, length: float) -> RigPath:
	return path.move_to(4 * length, -0.6).line_to(7 * length, 0.7).line_to(7 * length, 2.3).line_to(4 * length, 3.6).close()


## Where a weapon piece sits along the sword hand: moved by the slide.
static func place_slid(_frame: RigSolver.Frame, pose: UnitPose, _view: StringName) -> Transform2D:
	return Transform2D(0.0, Vector2(pose.values[UnitPose.WO], 0.0))


## A point `along` units of weapon length up the weapon, slide included.
static func place_at(_frame: RigSolver.Frame, pose: UnitPose, _view: StringName, along: float) -> Transform2D:
	return Transform2D(0.0, Vector2(along * pose.values[UnitPose.WL] + pose.values[UnitPose.WO], 0.0))


static func _piece(id: StringName, front: float, back: float, color: Color, path_name: StringName, detail_name: StringName, depends: int) -> RigPiece:
	var piece := RigPiece.make(id, RigSolver.H_F, front, back)
	piece.color = color
	piece.path = Callable(RigWeapons, path_name)
	if detail_name != &"":
		piece.detail = Callable(RigWeapons, detail_name)
	piece.depends = depends
	if depends & RigPiece.USES_WEAPON:
		piece.place = Callable(RigWeapons, &"place_slid")
	return piece


# A painted weapon part (outline included) that slides with the weapon.
static func _part(id: StringName, front: float, back: float, paint_name: StringName, depends: int, sway_period_sec: float) -> RigPiece:
	var piece := RigPiece.make(id, RigSolver.H_F, front, back)
	piece.paint = Callable(RigWeapons, paint_name)
	piece.place = Callable(RigWeapons, &"place_slid")
	piece.depends = depends
	piece.sway_period_sec = sway_period_sec
	return piece
