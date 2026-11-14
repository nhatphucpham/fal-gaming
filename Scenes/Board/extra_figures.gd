class_name ExtraFigures
extends RefCounted
## Figures that are not one of the six classes, drawn with UnitPainter's
## Brush: the boss Cự Nham (a stone giant, `class.colossus`) and the sage
## who speaks in Kỳ Ngộ cutscenes (`class.sage`, presentation only). Their
## drawers are registered in UnitPainter's class registry.

const STONE := Color("8d8a83")
const STONE_LIGHT := Color("b3aea3")
const STONE_DARK := Color("5e5b56")
const MOSS := Color("6f8a4a")
const EMBER := Color("ffb347")
const ROBE := Color("ece2c9")
const BEARD := Color("f5f2ea")
const STRAW := Color("d6b56a")
## A unit id for the sage, so cutscenes can draw it without catalog data.
const SAGE_UNIT_ID: StringName = &"unit.sage"


## A UnitData for the cutscene sage (not in the catalog, never in a battle).
static func make_sage() -> UnitData:
	var sage := UnitData.new()
	sage.id = SAGE_UNIT_ID
	sage.name_key = "CUTSCENE_SAGE"
	sage.class_id = &"class.sage"
	sage.race_id = &"race.human"
	sage.cost = 1
	return sage


## Cự Nham: boulder legs and body, slab arms, a small head with ember eyes,
## moss on the shoulders. About as tall as a normal figure; the view scales it.
static func draw_colossus(brush: UnitPainter.Brush) -> void:
	for side: float in [-1.0, 1.0]:
		brush.poly(PackedVector2Array([
			Vector2(side * 4, -18), Vector2(side * 16, -20), Vector2(side * 18, 0), Vector2(side * 5, 0),
		]), STONE_DARK)
	brush.poly(PackedVector2Array([
		Vector2(-22, -50), Vector2(-8, -58), Vector2(10, -57), Vector2(24, -48), Vector2(22, -22),
		Vector2(12, -14), Vector2(-12, -14), Vector2(-23, -24),
	]), STONE)
	brush.poly(PackedVector2Array([Vector2(-12, -46), Vector2(4, -50), Vector2(10, -38), Vector2(-6, -32)]), STONE_LIGHT)
	for side: float in [-1.0, 1.0]:
		brush.poly(PackedVector2Array([
			Vector2(side * 20, -52), Vector2(side * 34, -46), Vector2(side * 36, -14), Vector2(side * 26, -8), Vector2(side * 22, -28),
		]), STONE)
		brush.poly(_ellipse(Vector2(side * 30, -10), 8.0, 6.0), STONE_DARK)
		brush.poly(PackedVector2Array([Vector2(side * 14, -57), Vector2(side * 28, -52), Vector2(side * 20, -48)]), MOSS)
	brush.poly(PackedVector2Array([Vector2(-9, -56), Vector2(9, -56), Vector2(11, -68), Vector2(0, -74), Vector2(-11, -68)]), STONE_LIGHT)
	for side: float in [-1.0, 1.0]:
		brush.canvas.draw_circle(Vector2(side * 4.5, -64 + brush.facing), 2.4, brush.tint(EMBER))
	# Cracks in the chest.
	brush.canvas.draw_polyline(PackedVector2Array([Vector2(-4, -44), Vector2(0, -36), Vector2(-3, -28), Vector2(2, -20)]), Palette.INK, 1.5, true)
	brush.crown_y = -76.0


## The sage: a long cream robe, a straw cone hat, a white beard and a staff.
static func draw_sage(brush: UnitPainter.Brush) -> void:
	brush.stick(Vector2(-17, 2), Vector2(-15, -62), 3.0, Palette.WOOD)
	brush.circle(Vector2(-15, -64), 3.5, Palette.JADE)
	brush.poly(PackedVector2Array([Vector2(-10, -36), Vector2(10, -36), Vector2(16, 0), Vector2(-16, 0)]), ROBE)
	brush.stick(Vector2(0, -35), Vector2(0, -2), 2.0, Palette.OCHRE)
	brush.stick(Vector2(-9, -33), Vector2(-15, -36), 4.0, ROBE)
	brush.stick(Vector2(9, -33), Vector2(10, -20), 4.0, ROBE)
	brush.circle(Vector2(0, -45), 8.5, UnitPainter.SKIN)
	brush.poly(PackedVector2Array([Vector2(-7, -42), Vector2(7, -42), Vector2(3, -26), Vector2(0, -22), Vector2(-3, -26)]), BEARD)
	for side: float in [-1.0, 1.0]:
		brush.canvas.draw_circle(Vector2(side * 3.2, -46 + brush.facing), 1.3, Palette.INK)
	brush.poly(PackedVector2Array([Vector2(-17, -49), Vector2(17, -49), Vector2(0, -64)]), STRAW)
	brush.crown_y = -66.0


static func _ellipse(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	return UnitPainter.Brush.ellipse(center, radius_x, radius_y, 12)
