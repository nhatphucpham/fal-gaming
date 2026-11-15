class_name RigHorse
extends RefCounted
## Kỵ's horse (port of the sketch's `HORSE`): a separate simple rig in
## figure space whose back sits under the rider's hips, so the rider's bob,
## the gallop and a kneel move it; its legs lift and shorten in a gallop.
## From behind: rump, tail, hind legs, the far forelegs between them. From
## the front: far hind legs, saddle cloth, forelegs, chest, the long face.
## Curved parts are cached meshes moved per frame; legs are plain quads.

const SWAY_STEP: float = 0.4
const NECK_STEP: float = 0.25

static var _parts: Dictionary[String, RigMesh] = {}


## The horse pieces with their draw order (none of them is seen both ways).
static func pieces() -> Array[RigPiece]:
	var list: Array[RigPiece] = []
	for entry: Array in [
		[&"h_foreB", NAN, -0.6, &"paint_fore_back"], [&"h_hindB", NAN, 2.5, &"paint_hind_back"],
		[&"h_rumpB", NAN, 3.0, &"paint_rump_back"], [&"h_hindF", -1.0, NAN, &"paint_hind_front"],
		[&"h_saddleF", -0.6, NAN, &"paint_saddle_front"], [&"h_foreF", 1.2, NAN, &"paint_fore_front"],
		[&"h_chestF", 1.5, NAN, &"paint_chest_front"], [&"h_headF", 4.6, NAN, &"paint_head_front"],
	]:
		var piece := RigPiece.make(entry[0], RigSolver.WORLD, entry[1], entry[2])
		piece.paint = Callable(RigHorse, entry[3])
		piece.is_live = true
		# The tail's idle sway (the sketch's sin(t / 600 ms)).
		piece.sway_period_sec = 0.6
		list.append(piece)
	return list


static func paint_fore_back(mesh: RigMesh, args: RigPiece.Args) -> void:
	var rig := _rig(args)
	for leg: Vector2 in [Vector2(-1, 0.5), Vector2(1, 0.65)]:
		_leg(mesh, RigPalette.HORSE_DARK, rig.x + leg.x * 3.6, rig.y + 12, -2.4 - _lift(args, leg.y), 3.4)


static func paint_hind_back(mesh: RigMesh, args: RigPiece.Args) -> void:
	var rig := _rig(args)
	for leg: Vector2 in [Vector2(-1, 0), Vector2(1, 0.15)]:
		_leg(mesh, RigPalette.HORSE, rig.x + leg.x * 6.2, rig.y + 13, -_lift(args, leg.y), 4.4)


static func paint_rump_back(mesh: RigMesh, args: RigPiece.Args) -> void:
	var p := args.pose.values
	var rig := _rig(args)
	var at := Vector2(rig.x, rig.y + p[UnitPose.HL] * 1.5)
	var gallop := p[UnitPose.HG]
	var swing := sin(TAU * p[UnitPose.HPH]) * gallop * 2.4 + args.sway * 0.6
	mesh.append_mesh(_part("rump", mesh, Callable(RigHorse, &"_build_rump")), Transform2D(0.0, at))
	var swing_key := roundi(swing / SWAY_STEP)
	var gallop_key := roundi(gallop * 4.0)
	var tail := _part("tail%d,%d" % [swing_key, gallop_key], mesh, Callable(RigHorse, &"_build_tail").bind(swing_key * SWAY_STEP, gallop_key / 4.0))
	mesh.append_mesh(tail, Transform2D(0.0, at))


static func paint_hind_front(mesh: RigMesh, args: RigPiece.Args) -> void:
	var rig := _rig(args)
	for leg: Vector2 in [Vector2(-1, 0), Vector2(1, 0.15)]:
		_leg(mesh, RigPalette.HORSE_DARK, rig.x + leg.x * 7.4, rig.y + 12, -2.4 - _lift(args, leg.y), 3.4)


static func paint_saddle_front(mesh: RigMesh, args: RigPiece.Args) -> void:
	var rig := _rig(args)
	mesh.append_mesh(_part("saddle", mesh, Callable(RigHorse, &"_build_saddle")), Transform2D(0.0, rig))


static func paint_fore_front(mesh: RigMesh, args: RigPiece.Args) -> void:
	var rig := _rig(args)
	var rear := args.pose.values[UnitPose.HL]
	for leg: Vector2 in [Vector2(-1, 0.5), Vector2(1, 0.65)]:
		_leg(mesh, RigPalette.HORSE, rig.x + leg.x * 5, rig.y - rear * 4 + 14, -_lift(args, leg.y) - rear * 3, 4.4)


static func paint_chest_front(mesh: RigMesh, args: RigPiece.Args) -> void:
	var rig := _rig(args)
	var chest := Vector2(rig.x, rig.y - args.pose.values[UnitPose.HL] * 4)
	mesh.append_mesh(_part("chest", mesh, Callable(RigHorse, &"_build_chest")), Transform2D(0.0, chest))


## The horse faces the viewer: its neck rises from the chest and the long
## face hangs in front of the rider's lap.
static func paint_head_front(mesh: RigMesh, args: RigPiece.Args) -> void:
	var p := args.pose.values
	var rig := _rig(args)
	var rear := p[UnitPose.HL]
	var bob := p[UnitPose.HG] * 1.2 * sin(TAU * (p[UnitPose.HPH] + 0.25))
	var head := Vector2(rig.x - 1.5, rig.y - 1 - rear * 6 + bob)
	var neck_key := roundi((rig.y - rear * 4 + 9 - head.y) / NECK_STEP)
	var neck := _part("neck%d" % neck_key, mesh, Callable(RigHorse, &"_build_neck").bind(neck_key * NECK_STEP))
	mesh.append_mesh(neck, Transform2D(0.0, head))
	mesh.append_mesh(_part("face", mesh, Callable(RigHorse, &"_build_face")), Transform2D(0.0, head))


# The horse's back under the rider's hips, at (dx, -hip - jump).
static func _rig(args: RigPiece.Args) -> Vector2:
	var p := args.pose.values
	return Vector2(p[UnitPose.DX], -p[UnitPose.HIP] - p[UnitPose.JUMP])


static func _lift(args: RigPiece.Args, phase_offset: float) -> float:
	var p := args.pose.values
	return p[UnitPose.HG] * 6.0 * maxf(0.0, sin(TAU * (p[UnitPose.HPH] + phase_offset)))


static func _leg(mesh: RigMesh, color: Color, x: float, top: float, bottom: float, width: float) -> void:
	var length := maxf(2.6, bottom - top)
	mesh.shape(RigPath.new().move_to(x - width / 2, top).line_to(x + width / 2, top).line_to(x + width * 0.38, top + length - 1)
		.line_to(x - width * 0.38, top + length - 1).close(), color)
	mesh.shape(RigPath.new().rect(x - width * 0.46, top + length - 2.6, width * 0.92, 2.6), RigPalette.BOOT)


# A cached part built with the palette and feather of `owner`.
static func _part(key: String, owner: RigMesh, build: Callable) -> RigMesh:
	var full_key := "%s|%d|%.3f" % [key, owner.palette.hash(), owner.feather]
	if not _parts.has(full_key):
		var mesh := RigMesh.new()
		mesh.palette = owner.palette
		mesh.feather = owner.feather
		build.call(mesh)
		_parts[full_key] = mesh
	return _parts[full_key]


static func _build_rump(mesh: RigMesh) -> void:
	mesh.shape(RigPath.new().move_to(-13.4, -1.6).line_to(13.4, -1.6).line_to(12.8, 5).line_to(-12.8, 5).close(), RigPalette.VERMILION)
	mesh.fill_rect(-13, 2.6, 26, 1.2, RigPalette.GOLD)
	mesh.shape(RigPath.new().move_to(0, 2.4).bezier_to(-3, -0.2, -12.6, 0.4, -12.6, 8).bezier_to(-12.6, 15, -8, 18, -4, 18).line_to(4, 18)
		.bezier_to(8, 18, 12.6, 15, 12.6, 8).bezier_to(12.6, 0.4, 3, -0.2, 0, 2.4).close(), RigPalette.HORSE)
	mesh.alpha = 0.3
	mesh.fill(RigPath.new().ellipse(7, 6, 2.6, 3.6, 0.3, 0, 7), Color.WHITE)
	mesh.alpha = 1.0


static func _build_tail(mesh: RigMesh, swing: float, gallop: float) -> void:
	mesh.shape(RigPath.new().move_to(-2.2, 3).quad_to(-3.4 + swing, 12, -1.8 + swing * 1.6, 22 - gallop * 3).line_to(2.4 + swing * 1.6, 21 - gallop * 3)
		.quad_to(3.4 + swing, 12, 2.2, 3).close(), RigPalette.HAIR)


static func _build_saddle(mesh: RigMesh) -> void:
	mesh.shape(RigPath.new().rect(-13.6, -2, 27.2, 9), RigPalette.VERMILION)
	mesh.fill_rect(-13.2, 4.6, 26.4, 1.2, RigPalette.GOLD)


static func _build_chest(mesh: RigMesh) -> void:
	mesh.shape(RigPath.new().move_to(-9.6, 1).quad_to(0, -2, 9.6, 1).bezier_to(10.6, 10, 7, 17, 3, 17.4).line_to(-3, 17.4)
		.bezier_to(-7, 17, -10.6, 10, -9.6, 1).close(), RigPalette.HORSE)
	mesh.stroke(RigPath.new().move_to(-9.8, 5).quad_to(0, 10.5, 9.8, 5), RigPalette.LEATHER, 1.7)
	for stud: float in [-6.0, -2.0, 2.0, 6.0]:
		mesh.fill(RigPath.new().arc(stud, 5 + 5.5 * (1 - pow(stud / 9.8, 2)) * 0.9, 0.7, 0, 7), RigPalette.GOLD)
	mesh.shape(RigPath.new().move_to(-1.2, 9.4).line_to(1.2, 9.4).line_to(2.4, 15).line_to(-2.4, 15).close(), RigPalette.VERMILION, 1.6)


# The neck from the chest (`drop` below the head) up to the head.
static func _build_neck(mesh: RigMesh, drop: float) -> void:
	mesh.shape(RigPath.new().move_to(-6.5, drop).quad_to(-6.6, 2, -5, -7).line_to(5, -7).quad_to(6.6, 2, 9.5, drop).close(), RigPalette.HORSE)


static func _build_face(mesh: RigMesh) -> void:
	for ear: float in [-3.6, 3.6]:
		mesh.shape(RigPath.new().move_to(ear - 1.7, -8).line_to(ear * 1.25, -13.6).line_to(ear + 1.7, -8).close(), RigPalette.HORSE, 1.8)
	mesh.shape(RigPath.new().move_to(-5, -7.4).quad_to(0, -11.6, 5, -7.4).quad_to(4.8, 2, 3.6, 8.6).quad_to(0, 10.4, -3.6, 8.6)
		.quad_to(-4.8, 2, -5, -7.4).close(), RigPalette.HORSE)
	mesh.fill(RigPath.new().move_to(-1.1, -7).line_to(1.1, -7).line_to(0.8, 4).line_to(-0.8, 4).close(), RigPalette.CREAM)
	mesh.shape(RigPath.new().ellipse(0, 8, 4, 2.9, 0, 0, 7), RigPalette.MUZZLE, 1.6)
	for side: float in [-1.0, 1.0]:
		mesh.fill(RigPath.new().ellipse(side * 1.7, 8.4, 0.65, 0.95, 0, 0, 7), RigPalette.INK)
		mesh.fill(RigPath.new().ellipse(side * 3.3, -2.6, 0.9, 1.3, 0, 0, 7), RigPalette.INK)
	mesh.stroke(RigPath.new().move_to(-4.2, 4.6).line_to(4.2, 4.6).move_to(-4.8, -5).line_to(-4.2, 4.6).move_to(4.8, -5).line_to(4.2, 4.6), RigPalette.LEATHER, 0.9)
	mesh.shape(RigPath.new().move_to(-2.8, -9.6).quad_to(0, -12.6, 2.8, -9.6).line_to(0.8, -5).line_to(-1, -6).close(), RigPalette.HAIR, 1.4)
	for side: float in [-1.0, 1.0]:
		mesh.fill(RigPath.new().arc(side * 4.2, 4.6, 0.8, 0, 7), RigPalette.GOLD)
