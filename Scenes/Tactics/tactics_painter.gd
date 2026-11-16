class_name TacticsPainter
extends RefCounted
## Flat paper-cut drawing for the tactics map, in the folk-print palette:
## terrain tiles, unit tokens (round for our side, diamond for the enemy;
## leaders larger, cream-faced with a gold rim and a pennant), troop
## glyphs, hp bars, skill pips and the order and intent icons. Static,
## cheap draw calls only; callers redraw when something changes.
## [codeblock]
## TacticsPainter.draw_terrain(self, &"terrain.forest", Rect2(0, 0, 58, 58))
## TacticsPainter.draw_token(self, Vector2(29, 26), 0, true, &"class.spear", false)
## [/codeblock]

const OUTLINE := Palette.INK
const PLAYER_FILL := Color("3f6fc4")
const ENEMY_FILL := Color("c9412b")
const PLAYER_DARK := Color("24427a")
const ENEMY_DARK := Color("7e2416")
const GRID := Color(0.17, 0.14, 0.13, 0.22)
const MAX_PIPS: int = 5

const TERRAIN_FILLS: Dictionary[StringName, Color] = {
	&"terrain.plain": Color("c9c58f"), &"terrain.forest": Color("7f9c5c"), &"terrain.hill": Color("cfb07a"),
	&"terrain.river": Color("4f7fae"), &"terrain.ford": Color("8db0c8"), &"terrain.bridge": Color("4f7fae"),
	&"terrain.fort": Color("b9ab92"), &"terrain.village": Color("c9c58f"),
}

static var _terrain_details: Dictionary[StringName, Callable] = {}
static var _glyphs: Dictionary[StringName, Callable] = {}
static var _order_icons: Dictionary[StringName, Callable] = {}


## The side's token colour (fill), our side 0 blue, the enemy red.
static func side_color(side: int) -> Color:
	return PLAYER_FILL if side == 0 else ENEMY_FILL


## One terrain cell filling `rect`; unknown terrains draw as plain.
static func draw_terrain(canvas: CanvasItem, terrain_id: StringName, rect: Rect2) -> void:
	_ensure_registries()
	canvas.draw_rect(rect, TERRAIN_FILLS.get(terrain_id, TERRAIN_FILLS[&"terrain.plain"]))
	var detail: Callable = _terrain_details.get(terrain_id, Callable())
	if detail.is_valid():
		detail.call(canvas, rect)


## A unit token centred on `c`. `glyph` is a class id or `glyph.flying`.
static func draw_token(canvas: CanvasItem, c: Vector2, side: int, is_leader: bool, glyph: StringName, is_done: bool) -> void:
	_ensure_registries()
	var r := 21.0 if is_leader else 15.0
	var fill := side_color(side)
	if is_done:
		fill = fill.lerp(Color("8a8378"), 0.55)
	var shape := _token_shape(c, r, side)
	canvas.draw_colored_polygon(_token_shape(c + Vector2(0, 3), r, side), Color(OUTLINE, 0.45))
	canvas.draw_colored_polygon(shape, fill)
	if is_leader:
		var face := _token_shape(c, r - 6.0, side)
		canvas.draw_polyline(_closed(shape), Palette.GOLD, 4.0, true)
		canvas.draw_colored_polygon(face, Palette.CREAM)
		_draw_pennant(canvas, c + Vector2(r * 0.55, -r * 0.75), side)
	canvas.draw_polyline(_closed(shape), OUTLINE, 2.0, true)
	var glyph_color := (PLAYER_DARK if side == 0 else ENEMY_DARK) if is_leader else Palette.CREAM
	var drawer: Callable = _glyphs.get(glyph, _glyphs[&"class.sword"])
	drawer.call(canvas, c, r * (0.62 if is_leader else 0.7), glyph_color)


## A translucent outline of a token: where a soldier will stand.
static func draw_ghost(canvas: CanvasItem, c: Vector2, side: int, is_leader: bool) -> void:
	var r := 21.0 if is_leader else 15.0
	var shape := _token_shape(c, r, side)
	canvas.draw_colored_polygon(shape, Color(side_color(side), 0.35))
	canvas.draw_polyline(_closed(shape), Color(Palette.CREAM, 0.95), 3.0, true)


## An hp bar of `width` px centred under the token.
static func draw_hp_bar(canvas: CanvasItem, center: Vector2, width: float, ratio: float, side: int) -> void:
	var rect := Rect2(center - Vector2(width / 2.0, 3.0), Vector2(width, 6.0))
	canvas.draw_rect(rect.grow(1.5), OUTLINE)
	canvas.draw_rect(rect, Color("3a302b"))
	var fill := Palette.PLAYER_HP if side == 0 else Palette.ENEMY_HP
	canvas.draw_rect(Rect2(rect.position, Vector2(width * clampf(ratio, 0.0, 1.0), rect.size.y)), fill)


## Skill pips: up to MAX_PIPS dots, filled by value / threshold; all gold
## when the skill is ready.
static func draw_pips(canvas: CanvasItem, center: Vector2, value: int, threshold: int) -> void:
	var count := mini(maxi(threshold, 1), MAX_PIPS)
	var filled := float(value) / maxf(threshold, 1) * count
	var is_ready := value >= threshold
	var spacing := 8.0
	var start := center.x - spacing * (count - 1) / 2.0
	for index: int in count:
		var p := Vector2(start + index * spacing, center.y)
		canvas.draw_circle(p, 3.6, OUTLINE)
		var share := clampf(filled - index, 0.0, 1.0)
		if is_ready:
			canvas.draw_circle(p, 2.6, Palette.GOLD)
		elif share >= 1.0:
			canvas.draw_circle(p, 2.6, Palette.QI)
		elif share > 0.0:
			canvas.draw_circle(p, 2.6 * share, Palette.QI)


## The icon of an order (`order.follow`, ...), about `size` px across.
static func draw_order_icon(canvas: CanvasItem, order: StringName, c: Vector2, size: float, color: Color) -> void:
	_ensure_registries()
	var drawer: Callable = _order_icons.get(order, Callable())
	if drawer.is_valid():
		drawer.call(canvas, c, size / 2.0, color)


## A small intent icon: `attack` crossed blades, `skill` a star, `wait` a bar.
static func draw_intent_icon(canvas: CanvasItem, action: StringName, c: Vector2, r: float) -> void:
	canvas.draw_circle(c, r + 2.0, OUTLINE)
	canvas.draw_circle(c, r, Palette.OCHRE)
	if action == &"attack":
		canvas.draw_line(c + Vector2(-r, -r) * 0.55, c + Vector2(r, r) * 0.55, OUTLINE, 3.0)
		canvas.draw_line(c + Vector2(r, -r) * 0.55, c + Vector2(-r, r) * 0.55, OUTLINE, 3.0)
	elif action == &"skill":
		canvas.draw_colored_polygon(star_points(c, r * 0.75, r * 0.32, 5), OUTLINE)
	else:
		canvas.draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, 0), OUTLINE, 3.0)


## A small round badge with a troop glyph, for a face that needs its troop.
static func draw_glyph_badge(canvas: CanvasItem, c: Vector2, r: float, glyph: StringName) -> void:
	_ensure_registries()
	canvas.draw_circle(c, r + 2.0, OUTLINE)
	canvas.draw_circle(c, r, PLAYER_FILL)
	var drawer: Callable = _glyphs.get(glyph, _glyphs[&"class.sword"])
	drawer.call(canvas, c, r * 0.75, Palette.CREAM)


## The wavering mark (dao động) of radius `r`: a gold bubble with a star
## for a good incident, a red one with "!" for a bad one.
static func draw_wavering(canvas: CanvasItem, c: Vector2, r: float, is_good: bool) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, r * 0.6), c + Vector2(-r * 0.9, r * 1.35), c + Vector2(0, r * 0.85)]), OUTLINE)
	canvas.draw_circle(c, r + 2.0, OUTLINE)
	canvas.draw_circle(c, r, Palette.GOLD if is_good else Palette.VERMILION)
	if is_good:
		canvas.draw_colored_polygon(star_points(c, r * 0.72, r * 0.3, 5), OUTLINE)
	else:
		canvas.draw_rect(Rect2(c + Vector2(-r * 0.16, -r * 0.62), Vector2(r * 0.32, r * 0.78)), Palette.CREAM)
		canvas.draw_circle(c + Vector2(0, r * 0.45), r * 0.17, Palette.CREAM)


## A star polygon with `points` tips.
static func star_points(c: Vector2, outer: float, inner: float, points: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in points * 2:
		var angle := -PI / 2.0 + PI * index / points
		result.append(c + Vector2.from_angle(angle) * (outer if index % 2 == 0 else inner))
	return result


## The glyph a unit shows: its class, or a kite for flyers.
static func glyph_for(class_id: StringName, keywords: Array) -> StringName:
	return &"glyph.flying" if keywords.has(&"keyword.flying") else class_id


static func _token_shape(c: Vector2, r: float, side: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if side == 0:
		for index: int in 20:
			points.append(c + Vector2.from_angle(TAU * index / 20.0) * r)
		return points
	# The enemy's diamond, its corners slightly cut so it reads as paper.
	var d := r * 1.14
	var cut := r * 0.18
	for corner: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var side_a := Vector2(-corner.y, corner.x)
		points.append(c + corner * d - corner * cut - side_a * cut)
		points.append(c + corner * d - corner * cut + side_a * cut)
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed


static func _draw_pennant(canvas: CanvasItem, base: Vector2, side: int) -> void:
	canvas.draw_line(base, base + Vector2(0, -16), OUTLINE, 2.5)
	var flag := PackedVector2Array([base + Vector2(0, -16), base + Vector2(13, -12), base + Vector2(0, -7)])
	canvas.draw_colored_polygon(flag, Palette.GOLD if side == 0 else Palette.VERMILION_DARK)
	canvas.draw_polyline(_closed(flag), OUTLINE, 1.5)


static func _ensure_registries() -> void:
	if not _terrain_details.is_empty():
		return
	_terrain_details = {
		&"terrain.plain": _grass, &"terrain.forest": _forest, &"terrain.hill": _hill,
		&"terrain.river": _river, &"terrain.ford": _ford, &"terrain.bridge": _bridge,
		&"terrain.fort": _fort, &"terrain.village": _village,
	}
	_glyphs = {
		&"class.spear": _glyph_spear, &"class.sword": _glyph_sword, &"class.archer": _glyph_bow,
		&"class.shield": _glyph_shield, &"class.cavalry": _glyph_horse, &"class.mage": _glyph_staff,
		&"glyph.flying": _glyph_kite,
	}
	_order_icons = {
		&"order.follow": _order_follow, &"order.vanguard": _order_vanguard, &"order.flank": _order_flank,
		&"order.hold": _order_hold, &"order.free": _order_free,
	}


static func _grass(canvas: CanvasItem, rect: Rect2) -> void:
	var c := rect.get_center()
	var tint := Color("a9a86d")
	canvas.draw_line(c + Vector2(-14, 10), c + Vector2(-12, 4), tint, 2.0)
	canvas.draw_line(c + Vector2(-10, 10), c + Vector2(-11, 5), tint, 2.0)
	canvas.draw_line(c + Vector2(10, -8), c + Vector2(12, -14), tint, 2.0)


static func _forest(canvas: CanvasItem, rect: Rect2) -> void:
	var dark := Color("2f5a3a")
	for spot: Vector2 in [Vector2(0.3, 0.42), Vector2(0.7, 0.36), Vector2(0.5, 0.72)]:
		var base := rect.position + rect.size * spot
		var tree := PackedVector2Array([base + Vector2(-10, 8), base + Vector2(10, 8), base + Vector2(0, -12)])
		canvas.draw_colored_polygon(tree, dark)
		canvas.draw_line(base + Vector2(0, 8), base + Vector2(0, 12), Palette.WOOD, 2.0)


static func _hill(canvas: CanvasItem, rect: Rect2) -> void:
	var line := Color("8f6c3c")
	var c := rect.get_center()
	canvas.draw_arc(c + Vector2(-7, 8), 14.0, PI * 1.05, PI * 1.95, 10, line, 3.0)
	canvas.draw_arc(c + Vector2(9, 12), 11.0, PI * 1.05, PI * 1.95, 10, line, 3.0)


static func _river(canvas: CanvasItem, rect: Rect2) -> void:
	var wave := Color("8fb7d8")
	for row: float in [0.35, 0.68]:
		var points := PackedVector2Array()
		for step: int in 7:
			var x := rect.position.x + rect.size.x * step / 6.0
			points.append(Vector2(x, rect.position.y + rect.size.y * row + (3.0 if step % 2 == 0 else -3.0)))
		canvas.draw_polyline(points, wave, 2.0)


static func _ford(canvas: CanvasItem, rect: Rect2) -> void:
	_river(canvas, rect)
	var stone := Color("e4dcc4")
	for spot: Vector2 in [Vector2(0.25, 0.5), Vector2(0.52, 0.3), Vector2(0.75, 0.62)]:
		var p := rect.position + rect.size * spot
		canvas.draw_set_transform(p, 0.0, Vector2(1.0, 0.65))
		canvas.draw_circle(Vector2.ZERO, 7.0, stone)
		canvas.draw_set_transform(Vector2.ZERO)


static func _bridge(canvas: CanvasItem, rect: Rect2) -> void:
	_river(canvas, rect)
	var deck := Rect2(rect.position + Vector2(rect.size.x * 0.18, -1), Vector2(rect.size.x * 0.64, rect.size.y + 2))
	canvas.draw_rect(deck, Palette.WOOD)
	for step: int in 5:
		var y := deck.position.y + deck.size.y * (step + 0.5) / 5.0
		canvas.draw_line(Vector2(deck.position.x, y), Vector2(deck.end.x, y), Color("5e3c22"), 2.0)
	canvas.draw_line(deck.position, Vector2(deck.position.x, deck.end.y), OUTLINE, 2.0)
	canvas.draw_line(Vector2(deck.end.x, deck.position.y), deck.end, OUTLINE, 2.0)


static func _fort(canvas: CanvasItem, rect: Rect2) -> void:
	var wall := Color("7d7264")
	var inner := rect.grow(-8.0)
	canvas.draw_rect(inner, wall, false, 4.0)
	for step: int in 4:
		var x := inner.position.x + inner.size.x * step / 3.0
		canvas.draw_rect(Rect2(Vector2(x - 3, inner.position.y - 4), Vector2(6, 6)), wall)


static func _village(canvas: CanvasItem, rect: Rect2) -> void:
	_grass(canvas, rect)
	var c := rect.get_center() + Vector2(2, 2)
	canvas.draw_rect(Rect2(c + Vector2(-11, -2), Vector2(22, 13)), Palette.CREAM)
	canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-15, -1), c + Vector2(15, -1), c + Vector2(0, -15)]), Palette.VERMILION_DARK)
	canvas.draw_rect(Rect2(c + Vector2(-3, 4), Vector2(6, 7)), Palette.WOOD)


static func _glyph_spear(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	canvas.draw_line(c + Vector2(-r, r) * 0.8, c + Vector2(r, -r) * 0.55, color, 3.0)
	var tip := c + Vector2(r, -r) * 0.8
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-r * 0.55, r * 0.15), tip + Vector2(-r * 0.15, r * 0.55)]), color)


static func _glyph_sword(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	canvas.draw_line(c + Vector2(0, r * 0.75), c + Vector2(0, -r * 0.85), color, 4.0)
	canvas.draw_line(c + Vector2(-r * 0.45, r * 0.35), c + Vector2(r * 0.45, r * 0.35), color, 3.0)


static func _glyph_bow(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	canvas.draw_arc(c + Vector2(-r * 0.25, 0), r * 0.85, -PI * 0.42, PI * 0.42, 12, color, 3.0)
	var top := c + Vector2(-r * 0.25, 0) + Vector2.from_angle(-PI * 0.42) * r * 0.85
	var bottom := c + Vector2(-r * 0.25, 0) + Vector2.from_angle(PI * 0.42) * r * 0.85
	canvas.draw_line(top, bottom, color, 1.5)
	canvas.draw_line(c + Vector2(-r * 0.6, 0), c + Vector2(r * 0.8, 0), color, 2.0)


static func _glyph_shield(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var shape := PackedVector2Array([
		c + Vector2(-r * 0.7, -r * 0.7), c + Vector2(r * 0.7, -r * 0.7), c + Vector2(r * 0.6, r * 0.15), c + Vector2(0, r * 0.85), c + Vector2(-r * 0.6, r * 0.15),
	])
	canvas.draw_colored_polygon(shape, color)


static func _glyph_horse(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	# A horseshoe, open at the bottom.
	canvas.draw_arc(c + Vector2(0, -r * 0.1), r * 0.62, PI * 0.9, PI * 2.1, 14, color, 4.0)
	canvas.draw_line(c + Vector2(-r * 0.6, r * 0.1), c + Vector2(-r * 0.6, r * 0.65), color, 4.0)
	canvas.draw_line(c + Vector2(r * 0.6, r * 0.1), c + Vector2(r * 0.6, r * 0.65), color, 4.0)


static func _glyph_staff(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	canvas.draw_line(c + Vector2(-r * 0.2, r * 0.85), c + Vector2(r * 0.1, -r * 0.3), color, 3.0)
	canvas.draw_colored_polygon(star_points(c + Vector2(r * 0.2, -r * 0.45), r * 0.5, r * 0.22, 4), color)


static func _glyph_kite(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.6, -r * 0.1), c + Vector2(0, r * 0.55), c + Vector2(-r * 0.6, -r * 0.1)]), color)
	canvas.draw_line(c + Vector2(0, r * 0.55), c + Vector2(r * 0.25, r * 0.9), color, 1.5)


# Order icons: a big dot is the leader, small dots its soldiers, the arrow
# the way it marches.
static func _order_follow(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_march_arrow(canvas, c + Vector2(0, -r * 0.62), r, color)
	canvas.draw_circle(c + Vector2(0, -r * 0.08), r * 0.26, color)
	for x: float in [-0.42, 0.0, 0.42]:
		canvas.draw_circle(c + Vector2(r * x, r * 0.62), r * 0.14, color)


static func _order_vanguard(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_march_arrow(canvas, c + Vector2(0, -r * 0.72), r, color)
	for x: float in [-0.42, 0.0, 0.42]:
		canvas.draw_circle(c + Vector2(r * x, -r * 0.18), r * 0.14, color)
	canvas.draw_circle(c + Vector2(0, r * 0.5), r * 0.26, color)


static func _order_flank(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_march_arrow(canvas, c + Vector2(0, -r * 0.62), r, color)
	canvas.draw_circle(c + Vector2(0, r * 0.2), r * 0.26, color)
	for y: float in [-0.05, 0.45]:
		canvas.draw_circle(c + Vector2(-r * 0.7, r * y), r * 0.14, color)
		canvas.draw_circle(c + Vector2(r * 0.7, r * y), r * 0.14, color)


static func _order_hold(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	# A wall the soldiers stand behind: no arrow, they do not move.
	canvas.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.55), Vector2(r * 1.6, r * 0.3)), color)
	for x: float in [-0.5, 0.0, 0.5]:
		canvas.draw_circle(c + Vector2(r * x, r * 0.15), r * 0.14, color)
	canvas.draw_circle(c + Vector2(0, r * 0.62), r * 0.22, color)


static func _order_free(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	# Soldiers scattering on their own, each with its own arrow.
	for angle: float in [-2.4, -0.6, 1.2]:
		var dir := Vector2.from_angle(angle)
		var dot := c + dir * r * 0.35
		canvas.draw_circle(dot, r * 0.14, color)
		var tip := c + dir * r * 0.85
		canvas.draw_line(dot + dir * r * 0.18, tip, color, 2.5)
		canvas.draw_colored_polygon(PackedVector2Array([tip + dir * r * 0.12, tip + dir.rotated(2.3) * r * 0.2, tip + dir.rotated(-2.3) * r * 0.2]), color)


static func _march_arrow(canvas: CanvasItem, tip: Vector2, r: float, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-r * 0.34, r * 0.3), tip + Vector2(r * 0.34, r * 0.3)]), color)
