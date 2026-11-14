class_name UnitPainter
extends RefCounted
## Draws a unit as a small paper-cut figure with flat fills and ink outlines,
## from its UnitData: the class picks the silhouette (a registry of drawers by
## class id), the race picks the head and palette, the cost the trim colour.
## Coordinates are figure units: feet at (0, 0), about 64 up. Shared by the
## board pieces and the roster portraits; see Docs/systems/board.md.
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
const HUMAN_TUNIC := Color("3c5a99")
const WOLF_TUNIC := Color("8a5233")
const TROUSERS := Color("4a3b33")
const HORSE := Color("a0643a")
const WOLF_HORSE := Color("6d625a")
## Head drawer and palette by race id; unknown races look human.
const RACE_LOOKS: Dictionary[StringName, Dictionary] = {
	&"race.human": {"skin": SKIN, "tunic": HUMAN_TUNIC, "mount": HORSE, "head": &"_human_head"},
	&"race.wolf": {"skin": FUR, "tunic": WOLF_TUNIC, "mount": WOLF_HORSE, "head": &"_wolf_head"},
}
const ELEMENT_COLORS: Dictionary[StringName, Color] = {
	&"element.fire": Color("ff7a3d"),
	&"element.ice": Color("9fdcf5"),
	&"element.wind": Color("8fe0a8"),
	&"element.lightning": Color("ffe066"),
}

static var _class_drawers: Dictionary[StringName, Callable] = {}


## Draws the whole figure on `canvas` around `origin` (the feet), scaled.
## `flash` 0..1 blends every fill toward white (hit flash).
static func draw_figure(canvas: CanvasItem, unit: UnitData, facing: int, flash: float, origin: Vector2 = Vector2.ZERO, figure_scale: float = 1.0) -> void:
	canvas.draw_set_transform(origin, 0.0, Vector2(figure_scale, figure_scale))
	var brush := Brush.new(canvas, unit, facing, flash)
	var drawer: Callable = _get_drawers().get(unit.class_id, Callable(UnitPainter, &"_draw_plain"))
	drawer.call(brush)
	if unit.cost >= Catalog.MAX_COST and not unit.is_boss:
		brush.draw_crown()
	canvas.draw_set_transform(Vector2.ZERO)


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
			&"class.shield": Callable(UnitPainter, &"_draw_shield"),
			&"class.sword": Callable(UnitPainter, &"_draw_sword"),
			&"class.spear": Callable(UnitPainter, &"_draw_spear"),
			&"class.cavalry": Callable(UnitPainter, &"_draw_cavalry"),
			&"class.archer": Callable(UnitPainter, &"_draw_archer"),
			&"class.mage": Callable(UnitPainter, &"_draw_mage"),
			&"class.colossus": Callable(ExtraFigures, &"draw_colossus"),
			&"class.sage": Callable(ExtraFigures, &"draw_sage"),
		}
	return _class_drawers


static func _draw_plain(brush: Brush) -> void:
	brush.draw_legs()
	brush.draw_torso()
	brush.draw_head()


static func _draw_shield(brush: Brush) -> void:
	brush.draw_legs()
	brush.draw_torso()
	brush.stick(Vector2(9, -32), Vector2(17, -20), 4.0, brush.skin)
	brush.stick(Vector2(17, -20), Vector2(22, -38), 3.0, Palette.STEEL)
	brush.draw_head()
	var kite := PackedVector2Array([
		Vector2(-27, -40), Vector2(-1, -40), Vector2(0, -24), Vector2(-13, -2), Vector2(-28, -24),
	])
	brush.poly(kite, Palette.VERMILION)
	var inner := PackedVector2Array([
		Vector2(-23, -36), Vector2(-5, -36), Vector2(-4.5, -24), Vector2(-13.5, -8), Vector2(-23.5, -24),
	])
	brush.outline(inner, brush.trim, 2.0)
	brush.circle(Vector2(-14, -27), 4.5, Palette.OCHRE)


static func _draw_sword(brush: Brush) -> void:
	brush.draw_legs()
	brush.draw_torso()
	brush.stick(Vector2(-9, -32), Vector2(-13, -18), 4.0, brush.skin)
	brush.stick(Vector2(19, -42), Vector2(24, -70), 4.0, Palette.STEEL)
	brush.stick(Vector2(13, -43), Vector2(25, -40), 3.0, Palette.OCHRE)
	brush.stick(Vector2(9, -32), Vector2(18, -42), 4.0, brush.skin)
	brush.draw_head()


static func _draw_spear(brush: Brush) -> void:
	brush.stick(Vector2(16, 2), Vector2(16, -64), 3.0, Palette.WOOD)
	brush.poly(PackedVector2Array([Vector2(16, -78), Vector2(21, -64), Vector2(11, -64)]), Palette.STEEL)
	brush.circle(Vector2(16, -62), 3.0, Palette.VERMILION)
	brush.draw_legs()
	brush.draw_torso()
	brush.stick(Vector2(-9, -32), Vector2(-12, -18), 4.0, brush.skin)
	brush.stick(Vector2(9, -32), Vector2(16, -30), 4.0, brush.skin)
	brush.draw_head()


static func _draw_cavalry(brush: Brush) -> void:
	var horse: Color = brush.look["mount"]
	for leg_x: float in [-17.0, -9.0, 9.0, 17.0]:
		brush.stick(Vector2(leg_x, -10), Vector2(leg_x, 0), 4.0, horse.darkened(0.2))
	brush.stick(Vector2(-22, -18), Vector2(-30, -8), 4.0, HAIR)
	brush.poly(Brush.ellipse(Vector2(0, -15), 23.0, 9.0, 18), horse)
	brush.poly(PackedVector2Array([
		Vector2(14, -20), Vector2(22, -33), Vector2(31, -32), Vector2(31, -26), Vector2(23, -23), Vector2(21, -12),
	]), horse)
	brush.circle(Vector2(27, -29), 1.3, Palette.INK)
	brush.stick(Vector2(-6, -17), Vector2(8, -17), 3.0, brush.trim)
	brush.torso(Vector2(0, -24), 9.0, 7.5, 16.0)
	brush.stick(Vector2(2, -22), Vector2(4, -10), 4.0, TROUSERS)
	brush.stick(Vector2(7, -34), Vector2(20, -40), 3.0, Palette.WOOD)
	brush.poly(PackedVector2Array([Vector2(28, -44), Vector2(19, -43), Vector2(21, -37)]), Palette.STEEL)
	brush.head(Vector2(0, -46))


static func _draw_archer(brush: Brush) -> void:
	brush.poly(PackedVector2Array([Vector2(6, -40), Vector2(12, -42), Vector2(15, -24), Vector2(9, -22)]), Palette.WOOD)
	brush.stick(Vector2(10, -42), Vector2(9, -47), 2.0, Palette.CREAM)
	brush.stick(Vector2(13, -43), Vector2(13, -48), 2.0, Palette.VERMILION)
	brush.draw_legs()
	brush.draw_torso()
	brush.stick(Vector2(9, -32), Vector2(-4, -28), 4.0, brush.skin)
	brush.draw_head()
	var bow_center := Vector2(-6, -28)
	brush.canvas.draw_line(bow_center + Vector2(-8, -19), bow_center + Vector2(-8, 19), Palette.CREAM, 1.5, true)
	brush.canvas.draw_arc(bow_center, 21.0, PI - 1.15, PI + 1.15, 16, Palette.INK, 6.0, true)
	brush.canvas.draw_arc(bow_center, 21.0, PI - 1.15, PI + 1.15, 16, brush.tint(Palette.WOOD), 3.0, true)
	brush.stick(Vector2(-9, -32), Vector2(-24, -28), 4.0, brush.skin)


static func _draw_mage(brush: Brush) -> void:
	var orb: Color = ELEMENT_COLORS.get(brush.unit.element_id, Palette.OCHRE)
	brush.stick(Vector2(17, 2), Vector2(17, -56), 3.0, Palette.WOOD)
	brush.circle(Vector2(17, -60), 5.5, orb)
	brush.poly(PackedVector2Array([Vector2(-10, -34), Vector2(10, -34), Vector2(15, 0), Vector2(-15, 0)]), brush.tunic)
	brush.stick(Vector2(-13, -2), Vector2(13, -2), 3.0, brush.trim)
	brush.stick(Vector2(0, -33), Vector2(0, -4), 2.0, brush.trim)
	brush.stick(Vector2(-9, -32), Vector2(-13, -18), 4.0, brush.skin)
	brush.stick(Vector2(9, -32), Vector2(17, -36), 4.0, brush.skin)
	brush.head(Vector2(0, -44), false)
	brush.poly(PackedVector2Array([Vector2(-15, -50), Vector2(15, -50), Vector2(5, -70), Vector2(0, -63)]), Palette.INDIGO)
	brush.stick(Vector2(-12, -51), Vector2(12, -51), 3.0, brush.trim)
	brush.crown_y = -71.0


## Drawing state for one figure: target canvas, colours and outline helpers.
class Brush:
	var canvas: CanvasItem
	var unit: UnitData
	var facing: int
	var flash: float
	var skin: Color
	var tunic: Color
	var trim: Color
	var look: Dictionary
	var crown_y: float = -60.0

	func _init(target: CanvasItem, data: UnitData, facing_sign: int, flash_amount: float) -> void:
		canvas = target
		unit = data
		facing = facing_sign
		flash = clampf(flash_amount, 0.0, 1.0)
		look = RACE_LOOKS.get(data.race_id, RACE_LOOKS[&"race.human"])
		skin = look["skin"]
		tunic = look["tunic"]
		trim = Palette.cost_color(data.cost)

	static func ellipse(center: Vector2, radius_x: float, radius_y: float, points: int) -> PackedVector2Array:
		var result := PackedVector2Array()
		result.resize(points)
		for index: int in points:
			var angle := TAU * index / points
			result[index] = center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
		return result

	func tint(color: Color) -> Color:
		return color.lerp(Color.WHITE, flash) if flash > 0.0 else color

	func poly(points: PackedVector2Array, fill: Color) -> void:
		canvas.draw_colored_polygon(points, tint(fill))
		outline(points, Palette.INK, OUTLINE_PX)

	func outline(points: PackedVector2Array, color: Color, width: float) -> void:
		var closed := points.duplicate()
		closed.append(points[0])
		canvas.draw_polyline(closed, color, width, true)

	func circle(center: Vector2, radius: float, fill: Color) -> void:
		canvas.draw_circle(center, radius, tint(fill))
		canvas.draw_arc(center, radius, 0.0, TAU, 20, Palette.INK, OUTLINE_PX, true)

	## A thick line with an ink edge: limbs, poles, blades.
	func stick(from: Vector2, to: Vector2, width: float, fill: Color) -> void:
		canvas.draw_line(from, to, Palette.INK, width + OUTLINE_PX * 2.0, true)
		canvas.draw_line(from, to, tint(fill), width, true)

	func draw_legs() -> void:
		stick(Vector2(-5, -15), Vector2(-6, -1), 5.0, TROUSERS)
		stick(Vector2(5, -15), Vector2(6, -1), 5.0, TROUSERS)

	func draw_torso() -> void:
		torso(Vector2(0, -15), 11.0, 9.0, 20.0)

	## A tunic from the waist at `waist` up `height` units, with a cost-coloured belt.
	func torso(waist: Vector2, shoulder_half: float, waist_half: float, height: float) -> void:
		var top := waist.y - height
		poly(PackedVector2Array([
			Vector2(waist.x - shoulder_half, top), Vector2(waist.x + shoulder_half, top),
			Vector2(waist.x + waist_half, waist.y), Vector2(waist.x - waist_half, waist.y),
		]), tunic)
		stick(Vector2(waist.x - waist_half + 1, waist.y - 2), Vector2(waist.x + waist_half - 1, waist.y - 2), 3.0, trim)
		stick(Vector2(waist.x - 4, top + 1), Vector2(waist.x + 4, top + 1), 2.5, trim)

	func draw_head() -> void:
		head(Vector2(0, -44))

	## The race head at `center`; `with_hair_knot` is off under a hat.
	func head(center: Vector2, with_hair_knot: bool = true) -> void:
		crown_y = center.y - 16.0
		call(look["head"], center, with_hair_knot)

	func draw_crown() -> void:
		var base := crown_y
		poly(PackedVector2Array([
			Vector2(-7, base), Vector2(7, base), Vector2(8, base - 7), Vector2(3.5, base - 3),
			Vector2(0, base - 9), Vector2(-3.5, base - 3), Vector2(-8, base - 7),
		]), Palette.GOLD)

	func _human_head(center: Vector2, with_hair_knot: bool) -> void:
		if with_hair_knot:
			circle(center + Vector2(0, -10), 3.8, HAIR)
		circle(center, 9.0, skin)
		var hair := PackedVector2Array()
		for index: int in 9:
			var angle := PI + PI * index / 8.0
			hair.append(center + Vector2(cos(angle) * 9.5, sin(angle) * 9.5))
		hair.append(center + Vector2(6, -3 - facing))
		hair.append(center + Vector2(-6, -3 - facing))
		poly(hair, HAIR)
		_eyes(center + Vector2(0, 1))

	func _wolf_head(center: Vector2, _with_hair_knot: bool) -> void:
		for side: float in [-1.0, 1.0]:
			poly(PackedVector2Array([
				center + Vector2(side * 9, -3), center + Vector2(side * 7, -16), center + Vector2(side * 1.5, -7),
			]), skin)
		circle(center, 9.0, skin)
		var snout := center + Vector2(0, 4.0 + facing * 1.0)
		poly(Brush.ellipse(snout, 5.5, 4.0, 12), FUR_LIGHT)
		canvas.draw_circle(snout + Vector2(0, -1.5 + facing * 1.5), 1.8, Palette.INK)
		_eyes(center + Vector2(0, -2))

	func _eyes(center: Vector2) -> void:
		for side: float in [-1.0, 1.0]:
			canvas.draw_circle(center + Vector2(side * 3.6, facing * 1.4), 1.5, Palette.INK)
