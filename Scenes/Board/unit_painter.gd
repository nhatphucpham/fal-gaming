class_name UnitPainter
extends RefCounted
## Draws a unit as a small paper-cut figure with flat fills and ink outlines,
## from its UnitData and a UnitPose: the class picks the figure and its
## headgear (registries by class id, ClassFigures and FigureParts), the race
## picks the head and palette, the cost the trim colour, pauldrons (3+), a
## cape (4+) and a crown (5). Coordinates are figure units: feet at (0, 0),
## about 64 up. Shared by the board pieces and the roster portraits; see
## Docs/systems/board.md.
## [codeblock]
## func _draw(): UnitPainter.draw_figure(self, unit_data, UnitPainter.FACING_UP, 0.0)
## [/codeblock]

## The figure looks toward the top of the screen (player side).
const FACING_UP: int = -1
## The figure looks toward the bottom of the screen (enemy side).
const FACING_DOWN: int = 1
## Figure units from the feet to the top of the head.
const FIGURE_HEIGHT: float = 60.0
## The chest, where a bust portrait is centred.
const BUST_FOCUS := Vector2(0.0, -38.0)
const OUTLINE_PX: float = 2.0

const SKIN := Color("e8b48a")
const HAIR := Color("3a2a22")
const FUR := Color("8f7f6e")
const FUR_LIGHT := Color("d3c3aa")
const EAR_PINK := Color("c98f8f")
const HUMAN_TUNIC := Color("3c5a99")
const WOLF_TUNIC := Color("8a5233")
const TROUSERS := Color("4a3b33")
const BOOT := Color("2f2622")
const LEATHER := Color("5b3d2a")
const STEEL_DARK := Color("8f98a3")
const STRAW := Color("d6b56a")
const HORSE := Color("a0643a")
const WOLF_HORSE := Color("6d625a")
## Palette, head drawer (a FigureParts function) and fur by race id;
## unknown races look human.
const RACE_LOOKS: Dictionary[StringName, Dictionary] = {
	&"race.human": {"skin": SKIN, "tunic": HUMAN_TUNIC, "mount": HORSE, "head": &"draw_human_head", "has_fur": false},
	&"race.wolf": {"skin": FUR, "tunic": WOLF_TUNIC, "mount": WOLF_HORSE, "head": &"draw_wolf_head", "has_fur": true},
}
const ELEMENT_COLORS: Dictionary[StringName, Color] = {
	&"element.fire": Color("ff7a3d"),
	&"element.ice": Color("9fdcf5"),
	&"element.wind": Color("8fe0a8"),
	&"element.lightning": Color("ffe066"),
}

static var _class_drawers: Dictionary[StringName, Callable] = {}
static var _headgear: Dictionary[StringName, Callable] = {}


## Draws the whole figure on `canvas` around `origin` (the feet), scaled, in
## `pose` (the rest pose when null). `flash` 0..1 blends every fill toward
## white (hit flash).
static func draw_figure(canvas: CanvasItem, unit: UnitData, facing: int, flash: float, origin: Vector2 = Vector2.ZERO, figure_scale: float = 1.0, pose: UnitPose = null) -> void:
	var base := Transform2D(0.0, Vector2(figure_scale, figure_scale), 0.0, origin)
	var brush := FigureBrush.new(canvas, unit, facing, flash, pose, base)
	brush.headgear = _get_headgear().get(unit.class_id, Callable())
	var drawer: Callable = _get_drawers().get(unit.class_id, Callable(ClassFigures, &"draw_plain"))
	drawer.call(brush)
	# Figures outside the six classes do not place their own crown.
	FigureParts.draw_crown(brush, 0.0)
	brush.finish()


## True when the class's figure follows a UnitPose (not the boss or sage).
static func is_posable(class_id: StringName) -> bool:
	return not ExtraFigures.CLASS_IDS.has(class_id)


## Draws `count` star pips (gold diamonds) in a row centred on `center`.
## Stars are always drawn, never typed: the default font has no star glyph.
static func draw_star_pips(canvas: CanvasItem, center: Vector2, count: int, radius: float = 4.5) -> void:
	var spacing := radius * 2.2
	for index: int in count:
		var pip_center := center + Vector2((index - (count - 1) / 2.0) * spacing, 0.0)
		var pip := PackedVector2Array([
			pip_center + Vector2(0, -radius), pip_center + Vector2(radius, 0),
			pip_center + Vector2(0, radius), pip_center + Vector2(-radius, 0),
		])
		canvas.draw_colored_polygon(pip, Palette.GOLD)
		pip.append(pip[0])
		canvas.draw_polyline(pip, Palette.INK, maxf(1.5, radius / 3.0), true)


## Draws the upper body centred on `center`, for portraits.
static func draw_bust(canvas: CanvasItem, unit: UnitData, center: Vector2, bust_scale: float) -> void:
	draw_figure(canvas, unit, FACING_DOWN, 0.0, center - BUST_FOCUS * bust_scale, bust_scale)


static func _get_drawers() -> Dictionary[StringName, Callable]:
	if _class_drawers.is_empty():
		_class_drawers = {
			&"class.shield": Callable(ClassFigures, &"draw_shield"),
			&"class.sword": Callable(ClassFigures, &"draw_sword"),
			&"class.spear": Callable(ClassFigures, &"draw_spear"),
			&"class.cavalry": Callable(ClassFigures, &"draw_cavalry"),
			&"class.archer": Callable(ClassFigures, &"draw_archer"),
			&"class.mage": Callable(ClassFigures, &"draw_mage"),
			&"class.colossus": Callable(ExtraFigures, &"draw_colossus"),
			&"class.sage": Callable(ExtraFigures, &"draw_sage"),
		}
	return _class_drawers


static func _get_headgear() -> Dictionary[StringName, Callable]:
	if _headgear.is_empty():
		_headgear = {
			&"class.shield": Callable(FigureParts, &"draw_helmet"),
			&"class.sword": Callable(FigureParts, &"draw_headband"),
			&"class.spear": Callable(FigureParts, &"draw_war_hat"),
			&"class.cavalry": Callable(FigureParts, &"draw_plumed_helmet"),
			&"class.archer": Callable(FigureParts, &"draw_feather_band"),
			&"class.mage": Callable(FigureParts, &"draw_pointed_hat"),
		}
	return _headgear
