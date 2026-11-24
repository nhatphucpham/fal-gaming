class_name UnitPainter
extends RefCounted
## Draws a unit figure from its UnitData: the six classes (and any unknown
## one) as the bone rig of the approved sketch (RigKit, RigPainter), seen
## from behind for the player (FACING_UP) and from the front for the enemy
## (FACING_DOWN), in a UnitPose (the class's idle pose when none is given);
## the boss and the sage with their own drawers (ExtraFigures). The race
## picks the colours and, for wolf folk, ears and a muzzle. Coordinates are
## figure units: feet at (0, 0), about 60 up. Every figure is one triangle
## array: one draw call. Shared by the board pieces, the cutscenes and the
## portraits; see Docs/systems/board.md.
## [codeblock]
## func _draw(): UnitPainter.draw_figure(self, unit_data, UnitPainter.FACING_UP, 0.0)
## [/codeblock]

## The figure looks toward the top of the screen (player side, seen from behind).
const FACING_UP: int = -1
## The figure looks toward the bottom of the screen (enemy side, seen from the front).
const FACING_DOWN: int = 1
## The chest, where a bust portrait is centred.
const BUST_FOCUS := Vector2(0.0, -38.0)
const OUTLINE_PX: float = 2.0
## How white a rigged figure gets at full flash (the sketch's 80%).
const FLASH_WHITE: float = 0.8

const FUR := Color("8f7f6e")
const FUR_DARK := Color("6b5d50")
const WOLF_TUNIC := Color("8a5233")
const WOLF_TUNIC_DARK := Color("6c3e25")
const WOLF_HORSE := Color("6d625a")
const WOLF_HORSE_DARK := Color("524941")
## Colours by race id (swapped for the sketch's human ones) and whether
## the race has fur (wolf ears and muzzle); unknown races look human.
const RACE_LOOKS: Dictionary[StringName, Dictionary] = {
	&"race.human": {
		"skin": RigPalette.SKIN, "tunic": RigPalette.TUNIC, "tunic_dark": RigPalette.TUNIC_DARK, "mount": RigPalette.HORSE,
		"mount_dark": RigPalette.HORSE_DARK, "hair": RigPalette.HAIR, "has_fur": false,
	},
	&"race.wolf": {
		"skin": FUR, "tunic": WOLF_TUNIC, "tunic_dark": WOLF_TUNIC_DARK, "mount": WOLF_HORSE, "mount_dark": WOLF_HORSE_DARK,
		"hair": FUR_DARK, "has_fur": true,
	},
}

static var _no_indices := PackedInt32Array()
## Recorded base rings by [colour, radius] (see draw_ring): one per side
## colour and size (4 today). Keys must stay few: never an animated radius.
static var _rings: Dictionary = {}


## Draws the whole figure on `canvas` around `origin` (the feet), scaled, in
## `pose` (the class's idle pose when null). `flash` 0..1 blends the fills
## of a figure outside the rig toward white; a rigged figure flashes through
## UnitFigure's shader instead. `animator`, when given, adds the weapon trail
## and the idle sway clock. `pixels_per_unit` (0: `figure_scale`) is the
## on-screen size of a figure unit, which sets how soft lines are.
static func draw_figure(canvas: CanvasItem, unit: UnitData, facing: int, flash: float, origin: Vector2 = Vector2.ZERO, figure_scale: float = 1.0, pose: UnitPose = null, animator: PoseAnimator = null, pixels_per_unit: float = 0.0) -> void:
	var base := Transform2D(0.0, Vector2(figure_scale, figure_scale), 0.0, origin)
	if not is_posable(unit.class_id):
		var brush := FigureBrush.new(canvas, unit, facing, flash, base)
		Callable(ExtraFigures, ExtraFigures.DRAWERS[unit.class_id]).call(brush)
		brush.finish()
		return
	var kit := RigKit.get_kit(unit.class_id)
	var view := view_of(facing)
	var look := RigPainter.Look.new()
	var race_id: StringName = unit.race_id if RACE_LOOKS.has(unit.race_id) else &"race.human"
	look.race_id = race_id
	look.palette = RigPalette.get_palette(race_id, RACE_LOOKS[race_id])
	look.has_fur = RACE_LOOKS[race_id]["has_fur"]
	look.pixels_per_unit = pixels_per_unit if pixels_per_unit > 0.0 else figure_scale
	if animator != null:
		look.clock = animator.get_clock()
		look.trail = animator.trail.points
		look.trail_weights = animator.trail.weights
	var shown := pose if pose != null else kit.idle[view]
	# The board turns the pose's step toward the target into a push of the
	# whole figure (UnitView), so the rig itself stays over its feet.
	if shown.values[UnitPose.DX] != 0.0:
		shown = shown.merged({"dx": 0})
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var lights := RigPainter.paint(points, colors, kit, shown, view, look, base)
	if points.is_empty():
		return
	# UV.x marks what a hit flash whitens (UnitFigure's shader): the pieces
	# (1), not the weapon trail and the glow before them (0).
	var marks := PackedVector2Array()
	marks.resize(lights)
	var pieces := PackedVector2Array()
	pieces.resize(points.size() - lights)
	pieces.fill(Vector2.RIGHT)
	marks.append_array(pieces)
	# The points are already in canvas space.
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _no_indices, points, colors, marks)


## True when the class's figure is the bone rig and follows a UnitPose (not
## the boss or the sage).
static func is_posable(class_id: StringName) -> bool:
	return not ExtraFigures.DRAWERS.has(class_id)


## The rig view for a facing: the player's units are seen from behind.
static func view_of(facing: int) -> StringName:
	return RigSolver.VIEW_BACK if facing == FACING_UP else RigSolver.VIEW_FRONT


## Draws `count` star pips (gold diamonds) in a row centred on `center`,
## on a CanvasItem (one draw call) or into a MeshCanvas.
## Stars are always drawn, never typed: the default font has no star glyph.
static func draw_star_pips(canvas: Object, center: Vector2, count: int, radius: float = 4.5) -> void:
	var mesh := MeshCanvas.open(canvas)
	var spacing := radius * 2.2
	for index: int in count:
		var pip_center := center + Vector2((index - (count - 1) / 2.0) * spacing, 0.0)
		var pip := PackedVector2Array([
			pip_center + Vector2(0, -radius), pip_center + Vector2(radius, 0),
			pip_center + Vector2(0, radius), pip_center + Vector2(-radius, 0),
		])
		mesh.draw_colored_polygon(pip, Palette.GOLD)
		pip.append(pip[0])
		mesh.draw_polyline(pip, Palette.INK, maxf(1.5, radius / 3.0), true)
	mesh.finish(canvas)


## Draws the base ring under a unit's feet at `center` (`radius` for its
## two half axes), and a puff of dust spreading out with `dust` in 0..1
## (none at 0 or 1), on a CanvasItem (one draw call) or into a MeshCanvas.
static func draw_ring(canvas: Object, center: Vector2, radius: Vector2, color: Color, dust: float) -> void:
	var mesh := MeshCanvas.open(canvas)
	# The ring itself is recorded once per colour and size, then reused: a
	# unit's bar redraws it with every hp or Khí change.
	var key := [color, radius]
	var ring_mesh: MeshCanvas = _rings.get(key)
	if ring_mesh == null:
		ring_mesh = MeshCanvas.new()
		var ring := FigureBrush.ellipse(Vector2.ZERO, radius.x, radius.y, 20)
		ring_mesh.draw_colored_polygon(ring, Color(color, 0.35))
		ring.append(ring[0])
		ring_mesh.draw_polyline(ring, color, 2.5, true)
		_rings[key] = ring_mesh
	mesh.append(ring_mesh, center)
	if dust > 0.0 and dust < 1.0:
		for index: int in 6:
			var angle := TAU * index / 6.0 + 0.4
			var offset := Vector2(cos(angle) * (10.0 + 26.0 * dust), sin(angle) * (4.0 + 8.0 * dust))
			mesh.draw_circle(center + offset, 5.0 * (1.0 - dust * 0.5), Color(Palette.PAPER_DARK, (1.0 - dust) * 0.9))
	mesh.finish(canvas)


## Draws the upper body centred on `center`, seen from the front, for portraits.
static func draw_bust(canvas: CanvasItem, unit: UnitData, center: Vector2, bust_scale: float) -> void:
	draw_figure(canvas, unit, FACING_DOWN, 0.0, center - BUST_FOCUS * bust_scale, bust_scale)
