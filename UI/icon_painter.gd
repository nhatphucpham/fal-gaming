class_name IconPainter
extends RefCounted
## Small icons drawn in code, in the folk-print style of the units: a
## square-holed coin (gold), a rice sack (supply), a war banner (morale), a
## rank badge (level), a helmet (units on the board) and the reward icons
## (tent, bow, lantern). Every function draws centred on `center`, about
## `size` pixels across. Kinds are looked up by name with draw().
## [codeblock]
## IconPainter.draw(self, &"coin", Vector2(20, 20), 32.0)
## [/codeblock]

const OUTLINE_PX: float = 2.5

static var _drawers: Dictionary[StringName, Callable] = {}


## Draws the icon `kind` (coin, supply, morale, level, troops, tent, bow,
## lantern); an unknown kind draws nothing.
static func draw(canvas: CanvasItem, kind: StringName, center: Vector2, size: float) -> void:
	if _drawers.is_empty():
		_drawers = {
			&"coin": _coin, &"supply": _supply, &"morale": _morale, &"level": _level,
			&"troops": _troops, &"tent": _tent, &"bow": _bow, &"lantern": _lantern,
		}
	var drawer: Callable = _drawers.get(kind, Callable())
	if drawer.is_valid():
		drawer.call(canvas, center, size / 2.0)


static func _coin(canvas: CanvasItem, c: Vector2, r: float) -> void:
	canvas.draw_circle(c, r, Palette.INK)
	canvas.draw_circle(c, r - OUTLINE_PX, Palette.GOLD)
	canvas.draw_arc(c, r * 0.72, 0.0, TAU, 24, Palette.OCHRE, maxf(1.5, r * 0.1), true)
	var hole := r * 0.28
	canvas.draw_rect(Rect2(c - Vector2(hole, hole), Vector2(hole, hole) * 2.0), Palette.INK)


static func _supply(canvas: CanvasItem, c: Vector2, r: float) -> void:
	var sack := PackedVector2Array([
		c + Vector2(-r * 0.35, -r * 0.62), c + Vector2(r * 0.35, -r * 0.62),
		c + Vector2(r * 0.85, r * 0.2), c + Vector2(r * 0.7, r * 0.9),
		c + Vector2(-r * 0.7, r * 0.9), c + Vector2(-r * 0.85, r * 0.2),
	])
	_fill_outlined(canvas, sack, Color("c9a26b"))
	var neck := PackedVector2Array([
		c + Vector2(-r * 0.42, -r * 0.95), c + Vector2(r * 0.42, -r * 0.95),
		c + Vector2(r * 0.3, -r * 0.6), c + Vector2(-r * 0.3, -r * 0.6),
	])
	_fill_outlined(canvas, neck, Color("b08a55"))
	canvas.draw_line(c + Vector2(-r * 0.38, -r * 0.6), c + Vector2(r * 0.38, -r * 0.6), Palette.VERMILION, maxf(2.0, r * 0.18))
	for offset: Vector2 in [Vector2(-0.25, 0.25), Vector2(0.2, 0.15), Vector2(0.0, 0.55)]:
		canvas.draw_circle(c + offset * r, r * 0.11, Palette.CREAM)


static func _morale(canvas: CanvasItem, c: Vector2, r: float) -> void:
	var pole_x := c.x - r * 0.62
	canvas.draw_line(Vector2(pole_x, c.y - r), Vector2(pole_x, c.y + r), Palette.INK, maxf(3.0, r * 0.2))
	canvas.draw_line(Vector2(pole_x, c.y - r), Vector2(pole_x, c.y + r), Palette.WOOD, maxf(1.5, r * 0.1))
	var flag := PackedVector2Array([
		Vector2(pole_x, c.y - r * 0.9), c + Vector2(r * 0.95, -r * 0.75),
		c + Vector2(r * 0.55, -r * 0.2), c + Vector2(r * 0.95, r * 0.35), Vector2(pole_x, c.y + r * 0.3),
	])
	_fill_outlined(canvas, flag, Palette.VERMILION)
	canvas.draw_circle(c + Vector2(-r * 0.08, -r * 0.28), r * 0.2, Palette.GOLD)


static func _level(canvas: CanvasItem, c: Vector2, r: float) -> void:
	var points := PackedVector2Array()
	for index: int in 6:
		var angle := TAU * index / 6.0 - PI / 2.0
		points.append(c + Vector2(cos(angle), sin(angle)) * r)
	_fill_outlined(canvas, points, Palette.JADE)
	var inner := PackedVector2Array()
	for point: Vector2 in points:
		inner.append(c + (point - c) * 0.7)
	inner.append(inner[0])
	canvas.draw_polyline(inner, Palette.JADE_LIGHT, maxf(1.5, r * 0.1), true)


static func _troops(canvas: CanvasItem, c: Vector2, r: float) -> void:
	var dome := PackedVector2Array()
	for index: int in 13:
		var angle := PI + PI * index / 12.0
		dome.append(c + Vector2(cos(angle) * r * 0.8, sin(angle) * r * 0.85 + r * 0.25))
	_fill_outlined(canvas, dome, Palette.STEEL)
	canvas.draw_rect(Rect2(c + Vector2(-r, r * 0.2), Vector2(r * 2.0, r * 0.3)), Palette.INK)
	canvas.draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, -r), Palette.VERMILION, maxf(3.0, r * 0.25))


static func _tent(canvas: CanvasItem, c: Vector2, r: float) -> void:
	var tent := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.75), c + Vector2(-r, r * 0.75)])
	_fill_outlined(canvas, tent, Palette.OCHRE)
	var door := PackedVector2Array([c + Vector2(0, -r * 0.2), c + Vector2(r * 0.32, r * 0.75), c + Vector2(-r * 0.32, r * 0.75)])
	canvas.draw_colored_polygon(door, Palette.INK)
	for side: float in [-1.0, 1.0]:
		var flame := PackedVector2Array([
			c + Vector2(side * r * 0.75, r * 0.95), c + Vector2(side * r * 0.62, r * 0.55), c + Vector2(side * r * 0.88, r * 0.55),
		])
		if side > 0.0:
			canvas.draw_colored_polygon(flame, Palette.VERMILION)


static func _bow(canvas: CanvasItem, c: Vector2, r: float) -> void:
	var arc_center := c + Vector2(r * 0.35, 0)
	canvas.draw_arc(arc_center, r * 0.95, PI * 0.62, PI * 1.38, 20, Palette.INK, maxf(5.0, r * 0.26), true)
	canvas.draw_arc(arc_center, r * 0.95, PI * 0.62, PI * 1.38, 20, Palette.WOOD, maxf(3.0, r * 0.15), true)
	var top := arc_center + Vector2(cos(PI * 0.62), sin(PI * 0.62)) * r * 0.95
	var bottom := arc_center + Vector2(cos(PI * 1.38), sin(PI * 1.38)) * r * 0.95
	canvas.draw_line(top, bottom, Palette.CREAM, 2.0, true)
	canvas.draw_line(c + Vector2(-r * 0.9, 0), c + Vector2(r * 0.9, 0), Palette.INK, maxf(2.5, r * 0.12), true)
	var head := PackedVector2Array([c + Vector2(r * 1.0, 0), c + Vector2(r * 0.7, -r * 0.18), c + Vector2(r * 0.7, r * 0.18)])
	canvas.draw_colored_polygon(head, Palette.STEEL)


static func _lantern(canvas: CanvasItem, c: Vector2, r: float) -> void:
	canvas.draw_line(c + Vector2(0, -r), c + Vector2(0, -r * 0.7), Palette.INK, 3.0)
	var body := Rect2(c + Vector2(-r * 0.62, -r * 0.7), Vector2(r * 1.24, r * 1.35))
	var points := PackedVector2Array()
	for index: int in 16:
		var angle := TAU * index / 16.0
		points.append(c + Vector2(cos(angle) * r * 0.66, sin(angle) * r * 0.62 - r * 0.02))
	_fill_outlined(canvas, points, Palette.VERMILION)
	canvas.draw_circle(c, r * 0.3, Color(Palette.GOLD, 0.85))
	canvas.draw_rect(Rect2(body.position.x + r * 0.2, body.position.y - r * 0.06, r * 0.84, r * 0.16), Palette.INK)
	canvas.draw_rect(Rect2(body.position.x + r * 0.2, body.end.y - r * 0.12, r * 0.84, r * 0.16), Palette.INK)
	canvas.draw_line(c + Vector2(0, r * 0.75), c + Vector2(0, r), Palette.GOLD, 3.0)


static func _fill_outlined(canvas: CanvasItem, points: PackedVector2Array, fill: Color) -> void:
	canvas.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	canvas.draw_polyline(closed, Palette.INK, OUTLINE_PX, true)
