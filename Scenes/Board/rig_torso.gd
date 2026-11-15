class_name RigTorso
extends RefCounted
## The torso dressings of the sketch's `torsoKit`: the armour over the
## tunic (plate, lamellar, quilt, vest or a robe's collar), the belt, and
## from behind the scabbard strap and the red scarf's knot and tails; from
## the front the buckle, a cross belt and the scarf knot.

const THIN: float = 0.7


## Draws the dressing `options` (see RigBody.torso_piece) seen from args.view.
static func dress(mesh: RigMesh, args: RigPiece.Args, options: Dictionary) -> void:
	var armor: StringName = options.get("armor", &"")
	match armor:
		&"plate":
			mesh.fill(_plate(), RigPalette.STEEL)
			mesh.stroke(_plate(), RigPalette.INK, THIN)
		&"lamellar":
			_lamellar(mesh)
		&"quilt":
			_quilt(mesh)
		&"vest":
			mesh.fill(_plate(), RigPalette.VEST)
			mesh.stroke(_plate(), RigPalette.INK, THIN)
		&"robe":
			_robe(mesh, args.view)
			return
	mesh.fill_rect(-6.1, -1.6, 12.2, 2.6, RigPalette.LEATHER)
	if args.view == RigSolver.VIEW_BACK:
		_dress_back(mesh, options)
	else:
		_dress_front(mesh, options)


static func _dress_back(mesh: RigMesh, options: Dictionary) -> void:
	if options.get("armor") == &"plate":
		mesh.stroke(RigPath.new().move_to(0, -16.6).line_to(0, -5.2).move_to(-5.4, -10.5).quad_to(0, -8.6, 5.4, -10.5), RigPalette.STEEL_DARK, THIN)
	if options.get("strap", false):
		var strap := RigPath.new().move_to(-6.6, -15).line_to(7.4, 2.6)
		mesh.stroke(strap, RigPalette.INK, 3.4, true)
		mesh.stroke(strap, RigPalette.WOOD, 2.2, true)
		mesh.fill(RigPath.new().arc(7.4, 2.6, 1.3, 0, 7), RigPalette.GOLD)


## The red scarf seen from behind: two tails swaying under the knot. Its
## own piece (see RigBody.scarf_piece) so the torso is not rebuilt per sway.
static func paint_scarf_back(mesh: RigMesh, args: RigPiece.Args) -> void:
	var sway := args.sway * 0.8
	for tail: Array in [[-1.6, 2.6, 12.0, 1.0], [1.4, 2.4, 9.5, -0.7]]:
		var x: float = tail[0]
		var half: float = tail[1] / 2.0
		var length: float = tail[2]
		var bend: float = tail[3]
		var path := RigPath.new().move_to(x - half, -16.6)
		path.quad_to(x - half + sway * bend, -16.6 + length / 2.0, x - half + sway * 1.8 * bend - 0.6, -16.6 + length)
		path.line_to(x + half + sway * 1.8 * bend + 0.4, -16.6 + length - 1.2)
		path.quad_to(x + half + sway * bend, -16.6 + length / 2.0, x + half, -16.6).close()
		mesh.fill(path, RigPalette.VERMILION)
		mesh.stroke(path, RigPalette.INK, THIN)
	var knot := RigPath.new().ellipse(0, -17.2, 4.6, 2, 0, 0, 7)
	mesh.fill(knot, RigPalette.VERMILION)
	mesh.stroke(knot, RigPalette.INK, THIN)


static func _dress_front(mesh: RigMesh, options: Dictionary) -> void:
	if options.get("armor") == &"plate":
		mesh.stroke(RigPath.new().move_to(1, -16.6).line_to(1.1, -5.2), RigPalette.STEEL_DARK, THIN)
		mesh.alpha = 0.55
		mesh.fill(RigPath.new().ellipse(4.2, -12.4, 1, 3, 0.1, 0, 7), Color.WHITE)
		mesh.alpha = 1.0
	if options.get("belt2", false):
		mesh.stroke(RigPath.new().move_to(6.4, -16.4).line_to(-6, -3), RigPalette.LEATHER, 1.8)
	mesh.fill_rect(-0.2, -1.5, 2.4, 2.4, RigPalette.GOLD)
	if options.get("scarf", false):
		var knot := RigPath.new().ellipse(0.2, -17.3, 4.8, 2, 0, 0, 7)
		mesh.fill(knot, RigPalette.VERMILION)
		mesh.stroke(knot, RigPalette.INK, THIN)


static func _lamellar(mesh: RigMesh) -> void:
	var clip := _plate().done().polylines[0]
	mesh.fill(_plate(), RigPalette.IRON)
	var rows := RigPath.new()
	var row := 0
	var y := -15.6
	while y < -5.0:
		rows.move_to(-8, y).line_to(8, y)
		var x := -7.0 + (row % 2) * 1.1
		while x < 8.0:
			rows.move_to(x, y).line_to(x, y + 2.1)
			x += 2.2
		y += 2.1
		row += 1
	mesh.stroke_clipped(rows, clip, RigPalette.STEEL_DARK, 0.55)
	mesh.stroke(_plate(), RigPalette.INK, THIN)


static func _quilt(mesh: RigMesh) -> void:
	var clip := _plate().done().polylines[0]
	mesh.fill(_plate(), RigPalette.CREAM)
	var seams := RigPath.new()
	for x: float in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		seams.move_to(x, -18).line_to(x, -4)
	mesh.stroke_clipped(seams, clip, RigPalette.QUILT_SEAM, 0.6)
	mesh.stroke(_plate(), RigPalette.INK, THIN)
	mesh.stroke(RigPath.new().move_to(-6.6, -6.6).quad_to(0, -4.6, 6.6, -6.6), RigPalette.VERMILION, 1.1)


# A gold-edged collar in front, a gold seam behind, a red sash.
static func _robe(mesh: RigMesh, view: StringName) -> void:
	var seams := RigPath.new()
	if view == RigSolver.VIEW_BACK:
		seams.move_to(-5, -17.4).quad_to(0, -15.8, 5, -17.4).move_to(0, -16.4).line_to(0, -2)
	else:
		seams.move_to(-3.6, -17.6).line_to(1.2, -9.6).line_to(5, -17.6).move_to(1.2, -9.6).line_to(1.2, -2)
	mesh.stroke(seams, RigPalette.GOLD, 1.2)
	mesh.fill_rect(-6.1, -2.4, 12.2, 3, RigPalette.VERMILION)
	mesh.stroke_rect(-6.1, -2.4, 12.2, 3, RigPalette.INK, 0.6)
	if view != RigSolver.VIEW_BACK:
		var tail := RigPath.new().move_to(2.4, 0.4).line_to(1.4, 4.6).line_to(3.4, 4.2).close()
		mesh.fill(tail, RigPalette.VERMILION)
		mesh.stroke(tail, RigPalette.INK, 0.6)


static func _plate() -> RigPath:
	return RigPath.new().move_to(-6.4, -6.2).quad_to(0, -4.2, 6.4, -6.2).line_to(7.2, -11.6).quad_to(7.2, -16.5, 3.2, -17.1) \
		.line_to(-3.2, -17.1).quad_to(-7.2, -16.5, -7.2, -11.6).close()
