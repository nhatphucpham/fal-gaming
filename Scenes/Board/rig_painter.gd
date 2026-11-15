class_name RigPainter
extends RefCounted
## Paints a rigged figure (port of the sketch's `drawFigure`) into a
## triangle list: the weapon trail, the glow, then the pieces in draw order;
## within one draw order the ink strokes of all path pieces go first so
## touching pieces (an arm, its forearm and fist) read as one shape. Piece
## meshes are cached (RigPiece.key_of) and only transformed here; live
## pieces (bow, horse) paint per frame. UnitPainter submits the list as one
## triangle array: one draw call per figure.

const GLOW_RADIUS: float = 20.0
const GLOW_RINGS: int = 4
const GLOW_PEAK: float = 0.75
const TRAIL_PEAK: float = 0.75

static var _meshes: Dictionary[String, Array] = {}


## What to paint besides the pose: race colours, flash and idle clock, and
## the weapon trail in figure space.
class Look:
	extends RefCounted
	var race_id: StringName = &"race.human"
	var palette: Dictionary = {}
	var has_fur: bool = false
	## 0..1, the hit flash on top of the pose's own.
	var flash: float = 0.0
	## Seconds, drives the idle sway of cloth, plumes and tails.
	var clock: float = 0.0
	## Pairs of points (tip, inner edge) per sample, oldest first.
	var trail := PackedVector2Array()
	## Weight 0..1 per trail sample.
	var trail_weights := PackedFloat32Array()
	## Screen pixels per figure unit, which sets how soft lines are; 0
	## takes the scale of the paint's `base`.
	var pixels_per_unit: float = 0.0


## Adds the figure of `kit` in `pose` seen from `view` to `points` and
## `colors`, placed by `base` (feet at its origin).
static func paint(points: PackedVector2Array, colors: PackedColorArray, kit: RigKit, pose: UnitPose, view: StringName, look: Look, base: Transform2D) -> void:
	var frame := RigSolver.solve(pose, view)
	var flash := maxf(look.flash, pose.values[UnitPose.FLASH])
	_paint_trail(points, colors, look, base)
	var glow := pose.values[UnitPose.GLOW]
	if glow > 0.02:
		_paint_glow(points, colors, base * kit.get_glow_point(frame, pose), base.get_scale().x, glow)
	var level := RigMesh.feather_level(look.pixels_per_unit if look.pixels_per_unit > 0.0 else absf(base.get_scale().y))
	var args := RigPiece.Args.new()
	args.view = view
	args.weapon_length = pose.values[UnitPose.WL]
	args.weapon_slide = pose.values[UnitPose.WO]
	args.glow = glow
	args.has_fur = look.has_fur
	var eyes := pose.values[UnitPose.EYES]
	args.eyes = 0 if eyes < 0.5 else (1 if eyes < 1.5 else 2)
	args.pose = pose
	args.frame = frame
	var bodies: Array[RigMesh] = []
	var places: Array[Transform2D] = []
	for group: Array in kit.get_z_sets(view):
		bodies.clear()
		places.clear()
		for piece: RigPiece in group:
			var placed := _place(piece, frame, pose, view, base)
			_set_piece_args(piece, args, frame, look)
			var body: RigMesh
			if piece.is_live:
				body = RigMesh.new()
				body.palette = look.palette
				body.feather = RigMesh.feather_for(level)
				piece.paint.call(body, args)
			else:
				var meshes := _get_meshes(kit, piece, args, look, level)
				if piece.path.is_valid():
					var stroke: RigMesh = meshes[0]
					points.append_array(placed * stroke.points)
					colors.append_array(stroke.get_colors(flash))
				body = meshes[1]
			bodies.append(body)
			places.append(placed)
		for index: int in bodies.size():
			points.append_array(places[index] * bodies[index].points)
			colors.append_array(bodies[index].get_colors(flash))


# Sets the piece's own inputs from the solved frame into `args`.
static func _set_piece_args(piece: RigPiece, args: RigPiece.Args, frame: RigSolver.Frame, look: Look) -> void:
	var bone := piece.bone
	args.scale = frame.scales[bone] if bone >= 0 else 1.0
	args.heel = frame.heel_front if bone == RigSolver.FT_F else (frame.heel_back if bone == RigSolver.FT_B else 0.0)
	args.sway = sin(look.clock / piece.sway_period_sec) if piece.sway_period_sec > 0.0 else 0.0


# [stroke, body] meshes of a cached piece, lines feathered for `level`,
# built from `args` rounded to the cache steps on a miss.
static func _get_meshes(kit: RigKit, piece: RigPiece, raw_args: RigPiece.Args, look: Look, level: int) -> Array:
	var key := "%s|%d|%s" % [kit.class_id, level, piece.key_of(raw_args, look.race_id)]
	var cached: Array = _meshes.get(key, [])
	if not cached.is_empty():
		return cached
	var args := piece.quantize(raw_args)
	var stroke := RigMesh.new()
	var body := RigMesh.new()
	stroke.palette = look.palette
	body.palette = look.palette
	stroke.feather = RigMesh.feather_for(level)
	body.feather = stroke.feather
	if piece.path.is_valid():
		var outline := RigPath.new()
		piece.path.call(outline, args)
		stroke.stroke(outline, RigPalette.INK, RigMesh.OUTLINE_WIDTH)
		var fill := RigPath.new()
		piece.path.call(fill, args)
		body.fill(fill, piece.color)
		if piece.detail.is_valid():
			piece.detail.call(body, args)
	else:
		piece.paint.call(body, args)
	_meshes[key] = [stroke, body]
	return _meshes[key]


static func _place(piece: RigPiece, frame: RigSolver.Frame, pose: UnitPose, view: StringName, base: Transform2D) -> Transform2D:
	var placed := base if piece.bone < 0 else base * frame.bones[piece.bone]
	if piece.place.is_valid():
		placed = placed * (piece.place.call(frame, pose, view) as Transform2D)
	return placed


# A soft smear between the weapon's past tips and inner edges.
static func _paint_trail(points: PackedVector2Array, colors: PackedColorArray, look: Look, base: Transform2D) -> void:
	var samples := look.trail_weights.size()
	if samples < 2:
		return
	for index: int in range(1, samples):
		var alpha := float(index) / samples * TRAIL_PEAK * look.trail_weights[index]
		if alpha <= 0.0:
			continue
		var tip_from := look.trail[(index - 1) * 2]
		var mid_from := look.trail[(index - 1) * 2 + 1]
		var tip_to := look.trail[index * 2]
		var mid_to := look.trail[index * 2 + 1]
		points.append_array(base * PackedVector2Array([tip_from, tip_to, mid_to, tip_from, mid_to, mid_from]))
		var color := Color(RigPalette.TRAIL, alpha)
		colors.append_array(PackedColorArray([color, color, color, color, color, color]))


# Rings that stand in for the sketch's radial gradient: each smaller ring
# adds just enough alpha that the stack fades from the peak to nothing.
static func _paint_glow(points: PackedVector2Array, colors: PackedColorArray, center: Vector2, scale: float, amount: float) -> void:
	var mesh := RigMesh.new()
	var covered := 0.0
	for ring: int in GLOW_RINGS:
		var target := GLOW_PEAK * amount * (ring + 0.5) / GLOW_RINGS
		var alpha := 1.0 - (1.0 - target) / (1.0 - covered)
		covered = target
		mesh.disc_raw(center, GLOW_RADIUS * scale * (1.0 - float(ring) / GLOW_RINGS), Color(RigPalette.GLOW, alpha))
	points.append_array(mesh.points)
	colors.append_array(mesh.colors)
