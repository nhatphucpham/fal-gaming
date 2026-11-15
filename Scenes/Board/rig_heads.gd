class_name RigHeads
extends RefCounted
## Heads and headgear (port of the sketch's heads): the face, hair, the
## helmets of Kiếm (plume), Khiên (iron, cheek guards) and Kỵ (pheasant
## feathers), Thương's conical war hat, Cung's hood and Pháp's drooping
## hat with a beard. Head space: skull centre (0, -8), radius 7, the face
## turned a little toward the sword side. Wolf folk get ears under the
## headgear and a muzzle over the face.

const THIN: float = 0.7
const FUR_LIGHT := Color("d3c3aa")
const EAR_INNER := Color("c98f8f")
const NOSE := Color("2b2320")


## The head piece wearing `headgear` (func(mesh, args) -> void); `depends`
## adds the inputs the headgear reads besides the view. The eyes are a
## piece of their own (face_piece), so a blink does not rebuild the head.
static func head_piece(headgear: Callable, depends: int) -> RigPiece:
	var piece := RigPiece.make(&"head", RigSolver.HEAD, 3, 6)
	piece.color = RigPalette.SKIN
	piece.path = Callable(RigHeads, &"skull_path")
	piece.detail = Callable(RigHeads, &"dress_head").bind(headgear)
	piece.depends = RigPiece.USES_VIEW | depends
	if depends & RigPiece.USES_SWAY:
		piece.sway_period_sec = 0.38
	return piece


## The eyes and mouth over the head, seen from the front only, and a wolf's
## muzzle over them; `has_mouth` false under a beard.
static func face_piece(has_mouth: bool) -> RigPiece:
	var piece := RigPiece.make(&"face", RigSolver.HEAD, 3, NAN)
	piece.paint = Callable(RigHeads, &"paint_face").bind(has_mouth)
	piece.depends = RigPiece.USES_EYES
	return piece


static func paint_face(mesh: RigMesh, args: RigPiece.Args, has_mouth: bool) -> void:
	face(mesh, args.eyes, has_mouth)
	if args.has_fur:
		_wolf_muzzle(mesh)


static func skull_path(path: RigPath, _args: RigPiece.Args) -> void:
	path.arc(0, -8, 7, 0, 7).rect(-2, -2.4, 4, 3.4)


static func dress_head(mesh: RigMesh, args: RigPiece.Args, headgear: Callable) -> void:
	if args.has_fur:
		_wolf_ears(mesh)
	headgear.call(mesh, args)


## Helmet: `plume` (Kiếm), `feathers` (Kỵ), `iron` with `cheeks` (Khiên).
static func helm(mesh: RigMesh, args: RigPiece.Args, options: Dictionary) -> void:
	var dome := RigPalette.IRON if options.get("iron", false) else RigPalette.STEEL
	var band := RigPalette.STEEL_DARK if options.get("iron", false) else RigPalette.GOLD
	if options.get("feathers", false):
		var sway := args.sway * 0.8
		_feather(mesh, [-1.2, -15, -2.4, -21 + sway, -6.5, -24.5, -10.5, -22 + sway])
		_feather(mesh, [1.4, -15, 3, -21 - sway, 7, -25, 11, -22.5 - sway])
	if args.view == RigSolver.VIEW_BACK:
		_helm_back(mesh, options, dome, band)
		return
	hair_front(mesh, RigPalette.HAIR)
	if options.get("plume", false):
		mesh.fill_stroke(RigPath.new().move_to(-0.8, -15.8).quad_to(-5.6, -21.6, -9.4, -16.4).quad_to(-5.8, -17.6, -2.4, -14.6).close(), RigPalette.VERMILION, THIN)
	if options.get("iron", false):
		_spike(mesh)
	mesh.fill_stroke(RigPath.new().arc(0, -8.6, 7.5, PI * 1.02, PI * 1.98).line_to(8.4, -9.2).line_to(8.2, -7.7).line_to(-7.6, -7.7).close(), dome, THIN)
	mesh.fill_rect(-7.4, -9.6, 15.4, 1.3, band)
	if options.get("cheeks", false):
		# Cheek guards hang from the rim over both cheeks; the far one is narrow.
		mesh.fill_stroke(RigPath.new().move_to(-7.7, -7.9).line_to(-3.4, -7.9).line_to(-3.2, -3.6).quad_to(-5, -1.2, -7.2, -2.2).close(), dome, THIN)
		mesh.fill_stroke(RigPath.new().move_to(6.6, -7.9).line_to(8.3, -7.9).line_to(8, -2.8).line_to(6.6, -2.4).close(), dome, THIN)
		mesh.fill(RigPath.new().arc(-5.4, -5.6, 0.6, 0, 7), RigPalette.GOLD)
	else:
		mesh.fill_stroke(RigPath.new().move_to(1.4, -8.4).line_to(3, -8.4).line_to(2.6, -4.6).line_to(1.8, -4.6).close(), RigPalette.STEEL, THIN)
	_shine(mesh, Vector2(3, -13))


## The nón trận (Thương): a conical war hat, gold knob, red chin strap.
static func war_hat(mesh: RigMesh, args: RigPiece.Args) -> void:
	if args.view == RigSolver.VIEW_BACK:
		hair_back(mesh, RigPalette.HAIR)
		mesh.fill(RigPath.new().arc(0, -8, 7, PI, 0), RigPalette.HAIR)
		mesh.stroke(RigPath.new().move_to(-4.6, -7).quad_to(-3.6, -3.4, -1.6, -2).move_to(4.6, -7).quad_to(3.6, -3.4, 1.6, -2), RigPalette.NON_HAIR_LINE, THIN)
		mesh.shape(RigPath.new().arc(0, -4.6, 2.4, 0, 7), RigPalette.HAIR, 1.2)
		mesh.fill_rect(-2.2, -6.2, 4.4, 1, RigPalette.VERMILION)
	else:
		hair_front(mesh, RigPalette.HAIR)
		mesh.stroke(RigPath.new().move_to(-6.4, -9).quad_to(-5.4, -0.6, 1.8, -0.8).quad_to(6.6, -1, 7.2, -9), RigPalette.VERMILION, 0.9)
	mesh.shape(RigPath.new().move_to(-12.6, -9.6).line_to(0, -23).line_to(12.6, -9.6).ellipse(0, -9.6, 12.6, 2.6, 0, 0, PI).close(), RigPalette.STRAW, 1.8)
	var ribs := RigPath.new()
	for x: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		ribs.move_to(0, -22.4).line_to(x, -7.6 + absf(x) * -0.1)
	mesh.stroke(ribs, RigPalette.HAT_STRAW_DARK, 0.55)
	mesh.stroke(RigPath.new().ellipse(0, -9.6, 12.2, 2.3, 0, 0, PI), RigPalette.VERMILION, 1.3)
	mesh.shape(RigPath.new().arc(0, -23, 1.5, 0, 7), RigPalette.GOLD, 1.4)


## The hood (Cung): green, with a point at the back.
static func hood(mesh: RigMesh, args: RigPiece.Args) -> void:
	var outline := RigPath.new().move_to(-8.6, -0.6).quad_to(-10.4, -12, -5, -16.4).quad_to(-7.6, -19.6, -10.6, -19.4) \
		.quad_to(-5, -21.4, 0.6, -16.6).quad_to(9.6, -15, 9, -0.6).quad_to(0, 1.4, -8.6, -0.6).close()
	mesh.shape(outline, RigPalette.MOSS, 1.8)
	if args.view == RigSolver.VIEW_BACK:
		mesh.stroke(RigPath.new().move_to(0.4, -16.4).quad_to(-0.6, -8, 0.2, 0), RigPalette.MOSS_DARK, 0.9)
		mesh.shape(RigPath.new().move_to(-1.6, -1.2).line_to(1.8, -1.2).line_to(0.4, 4.6).close(), RigPalette.MOSS_DARK, 1.4)
		return
	mesh.shape(RigPath.new().ellipse(2.1, -6.4, 5.4, 5.6, 0, 0, 7), RigPalette.SKIN, 1.2)
	mesh.fill(RigPath.new().ellipse(1.4, -10.6, 4.6, 1.7, 0, PI, 0), RigPalette.HAIR)


## The mage's pointed drooping hat and white beard (Pháp).
static func mage_hat(mesh: RigMesh, args: RigPiece.Args) -> void:
	var sway := args.sway * 0.6
	if args.view == RigSolver.VIEW_BACK:
		mesh.fill(RigPath.new().arc(0, -8, 7, 0, 7), RigPalette.BEARD_BACK)
		var strands := RigPath.new()
		for x: float in [-3.4, 0.0, 3.4]:
			strands.move_to(x, -9).quad_to(x * 1.1, -4, x * 0.9, -1.4)
		mesh.stroke(strands, RigPalette.BEARD_LINE, 0.6)
	else:
		hair_front(mesh, RigPalette.BEARD)
		mesh.shape(RigPath.new().move_to(-2.6, -3.6).quad_to(-2.4, 1.6, 2.6, 4.2).quad_to(7.6, 1.2, 7, -3.6).quad_to(4.6, -2.2, 2.2, -3)
			.quad_to(0, -2.2, -2.6, -3.6).close(), RigPalette.BEARD, 1.2)
	mesh.shape(RigPath.new().ellipse(0.4, -10.2, 12.6, 2.8, 0, 0, 7), RigPalette.PLUM_DARK, 1.8)
	mesh.shape(RigPath.new().move_to(-6.6, -10.6).quad_to(-4, -21, 0.6, -25.6).quad_to(7, -28.6, 11 + sway, -22).quad_to(6.6, -24, 4.2, -21.4)
		.quad_to(5.6, -15, 7.2, -10.6).quad_to(0, -9.2, -6.6, -10.6).close(), RigPalette.PLUM, 1.8)
	mesh.fill(RigPath.new().move_to(-6.3, -12.4).quad_to(0.4, -11, 6.9, -12.4).line_to(7.2, -10.6).quad_to(0.4, -9.2, -6.6, -10.6).close(), RigPalette.GOLD)
	if args.view != RigSolver.VIEW_BACK:
		var star := RigPath.new()
		for index: int in 10:
			var radius := 0.8 if index % 2 else 2.0
			var angle := index * PI / 5.0 - PI / 2.0
			star.line_to(0.9 + radius * cos(angle), -16.4 + radius * sin(angle))
		mesh.fill(star.close(), RigPalette.GOLD)


## Eyes 0 open, 1 shut or hurt, 2 happy; and a mouth unless a beard hides it.
static func face(mesh: RigMesh, eyes: int, has_mouth: bool) -> void:
	for x: float in [-0.6, 4.8]:
		var s := 0.95
		if eyes == 0:
			mesh.fill(RigPath.new().ellipse(x, -5.3, 0.85 * s, 1.25 * s, 0, 0, 7), RigPalette.INK)
		elif eyes == 1:
			mesh.stroke(RigPath.new().move_to(x - 1.1 * s, -5.6).line_to(x + 1.0 * s, -5), RigPalette.INK, 0.8, true)
		else:
			mesh.stroke(RigPath.new().arc(x, -4.9, 1.1 * s, PI * 1.1, PI * 1.9), RigPalette.INK, 0.8, true)
	if not has_mouth:
		return
	if eyes == 2:
		mesh.stroke(RigPath.new().arc(2.2, -3, 1.4, 0.1, PI * 0.9), RigPalette.INK, 0.6, true)
	else:
		mesh.stroke(RigPath.new().move_to(1.3, -2.5).line_to(3.2, -2.5), RigPalette.INK, 0.6, true)


static func hair_front(mesh: RigMesh, color: Color) -> void:
	mesh.fill(RigPath.new().arc(0, -8, 7, PI * 0.7, PI * 1.05).line_to(-4.4, -8).close(), color)


static func hair_back(mesh: RigMesh, color: Color) -> void:
	mesh.fill(RigPath.new().arc(0, -8, 7, 0.15 * PI, 0.85 * PI).close(), color)


static func _helm_back(mesh: RigMesh, options: Dictionary, dome: Color, band: Color) -> void:
	# The helmet from behind: the full dome, a neck guard, the plume falling toward the viewer.
	hair_back(mesh, RigPalette.HAIR)
	mesh.fill_stroke(RigPath.new().move_to(-7, -7).line_to(7, -7).line_to(7.8, -3.2).quad_to(0, -1.2, -7.8, -3.2).close(), RigPalette.STEEL_DARK, THIN)
	if options.get("cheeks", false):
		for side: float in [-1.0, 1.0]:
			mesh.fill_stroke(RigPath.new().move_to(side * 6.8, -7.4).line_to(side * 8.6, -7.4).line_to(side * 8.2, -2.6).line_to(side * 6.6, -2.2).close(), dome, THIN)
	mesh.fill_stroke(RigPath.new().arc(0, -8.6, 7.5, PI * 0.98, PI * 2.02).line_to(7.5, -6.4).line_to(-7.5, -6.4).close(), dome, THIN)
	mesh.fill_rect(-7.2, -8.2, 14.4, 1.3, band)
	_shine(mesh, Vector2(3.2, -12.6))
	if options.get("plume", false):
		mesh.fill_stroke(RigPath.new().move_to(-1.4, -16.4).quad_to(-4.6, -20.5, -0.4, -21).quad_to(3.6, -20, 2.2, -14.6)
			.quad_to(1.6, -11.4, 0.4, -9.6).quad_to(-1.8, -12, -1.4, -16.4).close(), RigPalette.VERMILION, THIN)
	if options.get("iron", false):
		_spike(mesh)


static func _spike(mesh: RigMesh) -> void:
	mesh.fill_stroke(RigPath.new().move_to(-1.2, -15.8).line_to(0, -19.4).line_to(1.2, -15.8).close(), RigPalette.GOLD, THIN)


static func _shine(mesh: RigMesh, center: Vector2) -> void:
	mesh.alpha = 0.5
	mesh.fill(RigPath.new().ellipse(center.x, center.y, 2.2, 1.1, -0.5, 0, 7), Color.WHITE)
	mesh.alpha = 1.0


# A pheasant tail feather (Kỵ): gold with dark bars.
static func _feather(mesh: RigMesh, points: Array) -> void:
	var path := RigPath.new().move_to(points[0], points[1]).bezier_to(points[2], points[3], points[4], points[5], points[6], points[7])
	mesh.stroke(path, RigPalette.INK, 2.8, true)
	mesh.stroke(path, RigPalette.GOLD, 1.5, true)
	mesh.stroke_dashed(path, RigPalette.LEATHER, 1.5, 1.1, 1.7)


# Pointed ears, drawn before the headgear so a helmet or hat covers their base.
static func _wolf_ears(mesh: RigMesh) -> void:
	for side: float in [-1.0, 1.0]:
		mesh.fill_stroke(RigPath.new().move_to(side * 2.6, -13.4).line_to(side * 6.6, -19.6).line_to(side * 7.4, -10.6).close(), RigPalette.SKIN, THIN)
		mesh.fill(RigPath.new().move_to(side * 4.0, -13.4).line_to(side * 6.2, -17.4).line_to(side * 6.6, -12.2).close(), EAR_INNER)


static func _wolf_muzzle(mesh: RigMesh) -> void:
	mesh.shape(RigPath.new().ellipse(2.4, -2.9, 3.4, 2.4, 0, 0, 7), FUR_LIGHT, 1.2)
	mesh.fill(RigPath.new().ellipse(2.4, -4.0, 1.2, 0.8, 0, 0, 7), NOSE)
	mesh.stroke(RigPath.new().move_to(2.4, -3.3).line_to(2.4, -2.2).move_to(1.2, -1.8).quad_to(2.4, -1.2, 3.6, -1.8), NOSE, 0.6, true)
