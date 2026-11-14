class_name SkillFx
extends BattleFx
## Short-lived skill effects drawn in code: the lit skill area, the skill name
## popup, the shield's ground ring and taunt marks, the sword's wide slash,
## the spear's thrust, the cavalry's impact burst, falling arrows and the
## mage's glyph. Same life cycle as BattleFx: make one with a factory, add it
## to the board's fx layer, call play(speed).
## [codeblock]
## var fx := SkillFx.glyph(board.cell_to_local(cell), Palette.class_color(&"class.mage"))
## board.get_fx_layer().add_child(fx)
## fx.play(speed)
## [/codeblock]

const NAME_FONT_SIZE: int = 26
const NAME_SEC: float = 0.6
const FALL_HEIGHT_PX: float = 150.0

var radius_px: float = 0.0
# Cell centres of the lit area (area_glow).
var _centers: Array[Vector2] = []
# The outer edges of that area, as pairs of points.
var _edges := PackedVector2Array()


## The skill's cells lit in its colour for the whole cast: a light fill with
## one outline around the whole area. `centers` are board-local cell centres.
static func area_glow(centers: Array[Vector2], glow_color: Color, seconds: float) -> SkillFx:
	var fx := _make_skill(Vector2.ZERO, Vector2.ZERO, seconds, glow_color)
	fx._centers = centers
	fx._edges = _outline_edges(centers)
	fx._painter = fx._paint_area_glow
	return fx


## The skill's name rising over the caster for 0.6 s.
static func name_popup(at: Vector2, label: String, label_color: Color) -> SkillFx:
	var fx := _make_skill(at, at + Vector2(0, -26), NAME_SEC, label_color)
	fx.text = label
	fx.font_size = NAME_FONT_SIZE
	fx._painter = fx._paint_name
	return fx


## A ring spreading over the ground to `radius_px` (Trấn Thủ).
static func ground_ring(center: Vector2, reach_px: float, ring_color: Color) -> SkillFx:
	var fx := _make_skill(center, center, 0.55, ring_color)
	fx.radius_px = reach_px
	fx._painter = fx._paint_ground_ring
	return fx


## A bouncing "!" over a taunted unit.
static func taunt_mark(at: Vector2) -> SkillFx:
	var fx := _make_skill(at, at + Vector2(0, -12), 0.6, Palette.VERMILION)
	fx._painter = fx._paint_taunt_mark
	return fx


## A wide arc over the three cells in front (Hoành Tảo).
static func wide_slash(center: Vector2, direction: Vector2, slash_color: Color) -> SkillFx:
	var fx := _make_skill(center, center + direction.normalized(), 0.28, slash_color)
	fx.radius_px = BoardView.CELL_PX * 1.2
	fx._painter = fx._paint_wide_slash
	return fx


## A long thrust line shooting down the column (Xuyên Tâm).
static func thrust(from: Vector2, to: Vector2, thrust_color: Color) -> SkillFx:
	var fx := _make_skill(from, to, 0.3, thrust_color)
	fx._painter = fx._paint_thrust
	return fx


## A star of rays where a charge hits (Đột Trận).
static func burst(at: Vector2, burst_color: Color) -> SkillFx:
	var fx := _make_skill(at, at, 0.35, burst_color)
	fx._painter = fx._paint_burst
	return fx


## An arrow dropping onto `at` over `seconds` (Tiễn Vũ).
static func falling_arrow(at: Vector2, seconds: float) -> SkillFx:
	var fx := _make_skill(at + Vector2(-30, -FALL_HEIGHT_PX), at, seconds, Palette.WOOD)
	fx._painter = fx._paint_falling_arrow
	return fx


## A glowing circle glyph on one cell (Pháp Trận).
static func glyph(center: Vector2, glyph_color: Color) -> SkillFx:
	var fx := _make_skill(center, center, 0.5, glyph_color)
	fx._painter = fx._paint_glyph
	return fx


static func _make_skill(from: Vector2, to: Vector2, seconds: float, fx_color: Color) -> SkillFx:
	var fx := SkillFx.new()
	fx.from_point = from
	fx.to_point = to
	fx.duration_sec = seconds
	fx.color = fx_color
	return fx


# Edges of the cells in `centers` that face a cell outside the area.
static func _outline_edges(centers: Array[Vector2]) -> PackedVector2Array:
	var inside: Dictionary[Vector2i, bool] = {}
	for center: Vector2 in centers:
		inside[Vector2i((center / BoardView.CELL_PX).floor())] = true
	var half := BoardView.CELL_PX * 0.5 - 2.0
	var edges := PackedVector2Array()
	for center: Vector2 in centers:
		var key := Vector2i((center / BoardView.CELL_PX).floor())
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if inside.has(key + side):
				continue
			var normal := Vector2(side) * half
			var along := normal.orthogonal()
			edges.append(center + normal - along)
			edges.append(center + normal + along)
	return edges


func _paint_area_glow() -> void:
	var fade_in := minf(progress * 6.0, 1.0)
	var alpha := fade_in * (1.0 - maxf(progress - 0.8, 0.0) / 0.2) * (0.75 + 0.25 * sin(progress * TAU * 3.0))
	var half := BoardView.CELL_PX * 0.5 - 2.0
	for center: Vector2 in _centers:
		draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), Color(color, 0.2 * alpha))
	draw_multiline(_edges, Color(color, 0.95 * alpha), 3.0)


func _paint_name() -> void:
	var font := ThemeDB.fallback_font
	var pop := 1.0 + 0.3 * maxf(0.0, 1.0 - progress * 5.0)
	var point := from_point.lerp(to_point, ease(progress, 0.3))
	var alpha := 1.0 if progress < 0.75 else 1.0 - (progress - 0.75) / 0.25
	var size := int(font_size * pop)
	var width := 260.0
	var origin := point + Vector2(-width / 2.0, size * 0.35)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 9, Color(Palette.INK, alpha))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, Color(color.lightened(0.35), alpha))


func _paint_ground_ring() -> void:
	var reach := radius_px * ease(progress, 0.4)
	var alpha := 1.0 - progress
	_draw_flat_ring(from_point + UnitView.FEET * 0.5, reach, Color(color, 0.25 * alpha), 0.0)
	_draw_flat_ring(from_point + UnitView.FEET * 0.5, reach, Color(color, alpha), 5.0)


func _paint_taunt_mark() -> void:
	var lift := absf(sin(progress * PI * 2.0)) * 8.0
	var point := from_point.lerp(to_point, progress) + Vector2(0, -lift)
	var alpha := 1.0 - maxf(progress - 0.7, 0.0) / 0.3
	draw_circle(point, 11.0, Color(Palette.INK, alpha))
	draw_circle(point, 9.0, Color(color, alpha))
	draw_line(point + Vector2(0, -5), point + Vector2(0, 1.5), Color(Palette.CREAM, alpha), 3.0, true)
	draw_circle(point + Vector2(0, 5), 1.7, Color(Palette.CREAM, alpha))


func _paint_wide_slash() -> void:
	var direction := (to_point - from_point).normalized()
	var angle := direction.angle()
	var sweep := lerpf(-1.3, 1.3, ease(progress, 0.5))
	var alpha := 1.0 - progress * 0.7
	var center := from_point - direction * BoardView.CELL_PX * 0.6
	draw_arc(center, radius_px, angle - 1.3, angle + sweep, 24, Color(Palette.INK, alpha * 0.5), 12.0, true)
	draw_arc(center, radius_px, angle - 1.3, angle + sweep, 24, Color(color, alpha), 7.0, true)
	draw_arc(center, radius_px - 4.0, angle - 1.3, angle + sweep, 24, Color(Palette.CREAM, alpha), 2.5, true)


func _paint_thrust() -> void:
	var head := from_point.lerp(to_point, ease(minf(progress * 1.6, 1.0), 0.4))
	var alpha := 1.0 - maxf(progress - 0.6, 0.0) / 0.4
	draw_line(from_point, head, Color(Palette.INK, alpha * 0.6), 10.0, true)
	draw_line(from_point, head, Color(color, alpha), 6.0, true)
	draw_line(from_point, head, Color(Palette.CREAM, alpha), 2.0, true)
	var direction := (to_point - from_point).normalized()
	var side := direction.orthogonal() * 8.0
	draw_colored_polygon(PackedVector2Array([head + direction * 16.0, head + side, head - side]), Color(Palette.STEEL, alpha))


func _paint_burst() -> void:
	var alpha := 1.0 - progress
	for ray: int in 8:
		var angle := TAU * ray / 8.0 + 0.3
		var inner := from_point + Vector2.from_angle(angle) * (8.0 + 20.0 * progress)
		var outer := from_point + Vector2.from_angle(angle) * (18.0 + 34.0 * progress)
		draw_line(inner, outer, Color(color, alpha), 5.0, true)
	draw_circle(from_point, 14.0 * (1.0 - progress), Color(Palette.CREAM, alpha))


func _paint_falling_arrow() -> void:
	var head := from_point.lerp(to_point, ease(progress, 1.8))
	var direction := (to_point - from_point).normalized()
	var tail := head - direction * 28.0
	draw_line(tail, head, Palette.INK, 5.0, true)
	draw_line(tail, head, color, 2.5, true)
	var side := direction.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([head + direction * 7.0, head + side, head - side]), Palette.STEEL)
	draw_line(tail, tail - direction * 6.0 + side, Palette.VERMILION, 2.5, true)
	draw_line(tail, tail - direction * 6.0 - side, Palette.VERMILION, 2.5, true)


func _paint_glyph() -> void:
	var alpha := minf(progress * 5.0, 1.0) * (1.0 - maxf(progress - 0.6, 0.0) / 0.4)
	var radius := BoardView.CELL_PX * (0.32 + 0.06 * progress)
	var spin := progress * 1.5
	draw_circle(from_point, radius, Color(color, 0.25 * alpha))
	draw_arc(from_point, radius, 0.0, TAU, 28, Color(color, alpha), 3.0, true)
	draw_arc(from_point, radius * 0.62, 0.0, TAU, 20, Color(Palette.CREAM, alpha * 0.9), 2.0, true)
	var points := PackedVector2Array()
	for corner: int in 6:
		points.append(from_point + Vector2.from_angle(spin + TAU * corner * 2.0 / 6.0 + PI / 2.0) * radius * 0.9)
	points.append(points[0])
	draw_polyline(points, Color(color.lightened(0.4), alpha), 2.0, true)


# A ring squashed like the ground, so it reads as lying on the board.
func _draw_flat_ring(center: Vector2, radius: float, ring_color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index: int in 33:
		var angle := TAU * index / 32.0
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.55))
	if width <= 0.0:
		draw_colored_polygon(points, ring_color)
	else:
		draw_polyline(points, ring_color, width, true)
