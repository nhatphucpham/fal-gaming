class_name RigBow
extends RefCounted
## Cung's recurve bow and quiver. The bow sits in the off hand; the arrow
## runs from the drawing hand through the grip. The limbs lie across that
## line, or stand upright with bowUp (aiming at or away from the viewer,
## the arrow foreshortened). Not drawn (draw = 0), the bow hangs upright at
## the side. The limbs are cached in the bow's own frame; only the string
## and arrow (straight lines) are built per frame.

const RADIUS_STEP: float = 0.15

static var _limbs: Dictionary[String, RigMesh] = {}


static func bow_piece() -> RigPiece:
	var piece := RigPiece.make(&"bow", RigSolver.WORLD, 4.5, 0.5)
	piece.paint = Callable(RigBow, &"paint_bow")
	piece.is_live = true
	return piece


static func quiver_piece() -> RigPiece:
	var piece := RigPiece.make(&"quiver", RigSolver.TORSO, 1.5, 5.5)
	piece.paint = Callable(RigBow, &"paint_quiver")
	return piece


## The bow for the live pose in `args`, in figure space.
static func paint_bow(mesh: RigMesh, args: RigPiece.Args) -> void:
	var p := args.pose.values
	var grip_hand := args.frame.bones[RigSolver.H_B] * Vector2(0, 1.5)
	var draw_hand := args.frame.bones[RigSolver.H_F] * Vector2(0, 1.5)
	var along := grip_hand - draw_hand
	var distance := along.length()
	var drawn := p[UnitPose.DRAW]
	if distance < 3.0 or drawn < 0.05:
		var hang := 1.0 if drawn < 0.05 else 0.0
		var safe := distance if distance > 0.0 else 1.0
		along = Vector2(lerpf(along.x / safe, -1.0, hang), lerpf(along.y / safe, 0.0, hang))
		distance = along.length() if along.length() > 0.0 else 1.0
	along /= distance
	var upright := p[UnitPose.BOW_UP]
	var across := Vector2(along.y, -along.x)
	var up_sign := 1.0 if across.y >= 0.0 else -1.0
	var normal := Vector2(lerpf(across.x, 0.0, upright), lerpf(across.y, up_sign, upright))
	normal = normal / (normal.length() if normal.length() > 0.0 else 1.0)
	var belly := Vector2(-normal.y, normal.x)
	if belly.dot(along) < 0.0:
		belly = -belly
	var radius := 13.0 + (1.5 if args.view == RigSolver.VIEW_BACK else -1.5) * upright
	var bow_frame := Transform2D(normal, belly, grip_hand)
	var nock := (grip_hand - along * 3.0).lerp(draw_hand, drawn)
	var near_tip := bow_frame * Vector2(radius, -2.4)
	var far_tip := bow_frame * Vector2(-radius, -2.4)
	var string := RigPath.new().move_to(near_tip.x, near_tip.y).line_to(nock.x, nock.y).line_to(far_tip.x, far_tip.y)
	mesh.stroke(string, RigPalette.INK, 1.2, true)
	mesh.stroke(string, RigPalette.CREAM, 0.5, true)
	if p[UnitPose.NOCK] > 0.5:
		var length := maxf(8.0 if upright > 0.5 else 20.0, grip_hand.distance_to(nock) + 5.0)
		arrow(mesh, nock, along, length)
	mesh.append_mesh(_get_limbs(roundi(radius / RADIUS_STEP) * RADIUS_STEP, mesh), bow_frame)


## An arrow from `tail` along `direction` (unit) with a shaft of `length`.
static func arrow(mesh: RigMesh, tail: Vector2, direction: Vector2, length: float) -> void:
	mesh.push(Transform2D(direction, direction.orthogonal(), tail))
	var shaft := RigPath.new().move_to(0, 0).line_to(length, 0)
	mesh.stroke(shaft, RigPalette.INK, 1.7, true)
	mesh.stroke(shaft, RigPalette.WOOD, 0.8, true)
	mesh.shape(RigPath.new().move_to(length + 3.4, 0).line_to(length, 1.4).line_to(length, -1.4).close(), RigPalette.STEEL, 1.2)
	for side: float in [1.0, -1.0]:
		mesh.shape(RigPath.new().move_to(1, 0).line_to(4.4, 0).line_to(0.4, side * 1.8).close(), RigPalette.VERMILION, 1.0)
	mesh.pop()


static func paint_quiver(mesh: RigMesh, _args: RigPiece.Args) -> void:
	mesh.push(Transform2D(0.55, Vector2(-3.4, -2)))
	for fletch: Array in [[-1.4, RigPalette.VERMILION, 4.6], [0.4, RigPalette.CREAM, 5.4], [1.8, RigPalette.VERMILION, 4.2], [-0.2, RigPalette.CREAM, 3.8]]:
		var x: float = fletch[0]
		var height: float = fletch[2]
		mesh.shape(RigPath.new().move_to(x, -19).line_to(x - 1.2, -19 - height * 0.6).line_to(x, -19 - height).line_to(x + 1.2, -19 - height * 0.6).close(), fletch[1], 1.2)
	mesh.shape(RigPath.new().move_to(-3, -19.5).line_to(3, -19.5).line_to(2.6, -1).quad_to(0, 1, -2.6, -1).close(), RigPalette.LEATHER)
	mesh.fill_rect(-3, -19.5, 6, 2.4, RigPalette.WOOD)
	mesh.fill_rect(-2.8, -9, 5.6, 1.2, RigPalette.GOLD)
	mesh.pop()


# The limbs and grip wrap in the bow frame: x across the limbs, y the belly.
static func _get_limbs(radius: float, owner: RigMesh) -> RigMesh:
	var key := "%.2f|%d|%.3f" % [radius, owner.palette.hash(), owner.feather]
	if _limbs.has(key):
		return _limbs[key]
	var mesh := RigMesh.new()
	mesh.palette = owner.palette
	mesh.feather = owner.feather
	var limbs := RigPath.new().move_to(radius + 0.6, 0.6).bezier_to(radius * 0.8, -5, 4, 2.2, 0, 1.6).bezier_to(-4, 2.2, -radius * 0.8, -5, -radius - 0.6, 0.6)
	mesh.stroke(limbs, RigPalette.INK, 3.4, true)
	mesh.stroke(limbs, RigPalette.WOOD, 1.9, true)
	mesh.stroke(RigPath.new().move_to(1.6, 1.8).line_to(-1.6, 1.8), RigPalette.GOLD, 1.9, true)
	_limbs[key] = mesh
	return mesh
