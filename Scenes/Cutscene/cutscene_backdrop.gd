class_name CutsceneBackdrop
extends Control
## The painted band behind a cutscene: a washed sky, a low sun, ink-wash
## mountain ridges and mist, and a strip of ground the speakers stand on.
## `kind` picks the scene (CutsceneData.BACKDROPS): the mountain pass of a
## Kỳ Ngộ, the war camp of the story or the dirt road of a road encounter.
## Drawn once; the mist drifts.

const GROUND_RATIO: float = 0.82
const MIST_SPEED: float = 9.0

var kind: StringName = &"backdrop.mountain":
	set(value):
		kind = value
		queue_redraw()

var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Where the speakers' feet are, in this control's coordinates.
func get_ground_y() -> float:
	return size.y * GROUND_RATIO


func _draw() -> void:
	var width := size.x
	var height := size.y
	var is_camp := kind == &"backdrop.camp"
	var sky_top := Color("3b3a5c") if is_camp else Color("47607a")
	var sky_low := Color("d98a5a") if is_camp else Color("e9d6ae")
	var bands := 12
	for index: int in bands:
		var top := height * GROUND_RATIO * index / bands
		draw_rect(Rect2(0, top, width, height * GROUND_RATIO / bands + 1.0), sky_top.lerp(sky_low, float(index) / (bands - 1)))
	var sun := Vector2(width * (0.7 if is_camp else 0.32), height * 0.36)
	draw_circle(sun, height * 0.13, Color(Palette.VERMILION if is_camp else Palette.CREAM, 0.85))
	draw_circle(sun, height * 0.17, Color(Palette.GOLD, 0.12))
	_draw_ridge(height * 0.5, height * 0.2, 5.0, 0.3, Color(Palette.INDIGO_DARK, 0.35))
	_draw_ridge(height * 0.62, height * 0.16, 8.0, 1.7, Color(Palette.INDIGO_DARK, 0.55))
	_draw_mist(height * 0.6, 0.0)
	_draw_ridge(height * 0.74, height * 0.1, 11.0, 4.1, Color(Palette.INK, 0.7))
	_draw_mist(height * 0.72, 120.0)
	var ground := get_ground_y()
	draw_rect(Rect2(0, ground, width, height - ground), Color("5b4a35") if is_camp else Color("6f6a4a"))
	draw_rect(Rect2(0, ground, width, 4.0), Color(Palette.INK, 0.5))
	if is_camp:
		_draw_camp(ground)
	elif kind == &"backdrop.road":
		_draw_road(ground)
	else:
		_draw_pines(ground)
	# Ink edges top and bottom, like a mounted scroll painting.
	draw_rect(Rect2(0, 0, width, 6.0), Palette.INK)
	draw_rect(Rect2(0, height - 6.0, width, 6.0), Palette.INK)


# A soft mountain line: summed sines, filled down to the band's bottom.
func _draw_ridge(base_y: float, amplitude: float, frequency: float, phase: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 48
	for step: int in steps + 1:
		var x := size.x * step / steps
		var t := float(step) / steps
		var y := base_y - amplitude * (0.55 * absf(sin(t * frequency + phase)) + 0.3 * sin(t * frequency * 2.3 + phase * 1.7) + 0.15)
		points.append(Vector2(x, y))
	points.append(Vector2(size.x, size.y))
	points.append(Vector2(0, size.y))
	draw_colored_polygon(points, color)


func _draw_mist(y: float, offset: float) -> void:
	for index: int in 4:
		var x := fposmod(index * size.x * 0.33 + offset + _time * MIST_SPEED, size.x * 1.3) - size.x * 0.15
		draw_set_transform(Vector2(x, y + index % 2 * 10.0), 0.0, Vector2(1.0, 0.18))
		draw_circle(Vector2.ZERO, 120.0, Color(Palette.CREAM, 0.14))
	draw_set_transform(Vector2.ZERO)


func _draw_pines(ground: float) -> void:
	for spot: Vector2 in [Vector2(0.06, 1.0), Vector2(0.14, 0.75), Vector2(0.9, 1.1), Vector2(0.97, 0.8)]:
		_draw_pine(Vector2(size.x * spot.x, ground), spot.y)


# A dirt road winding back to the ridges, a milestone and a lone pine.
func _draw_road(ground: float) -> void:
	var road := PackedVector2Array()
	var steps := 16
	for step: int in steps + 1:
		var t := float(step) / steps
		var y := lerpf(size.y * 0.56, size.y, t)
		var half := lerpf(6.0, size.x * 0.22, t * t)
		road.append(Vector2(size.x * (0.5 + 0.08 * sin(t * 4.0)) - half, y))
	for step: int in range(steps, -1, -1):
		var t := float(step) / steps
		var y := lerpf(size.y * 0.56, size.y, t)
		var half := lerpf(6.0, size.x * 0.22, t * t)
		road.append(Vector2(size.x * (0.5 + 0.08 * sin(t * 4.0)) + half, y))
	draw_colored_polygon(road, Color("a88a5c"))
	draw_polyline(road, Color(Palette.INK, 0.35), 2.0)
	var post := Vector2(size.x * 0.84, ground)
	draw_rect(Rect2(post + Vector2(-9, -46), Vector2(18, 46)), Palette.PAPER_DARK)
	draw_rect(Rect2(post + Vector2(-12, -52), Vector2(24, 8)), Palette.WOOD)
	draw_line(post + Vector2(-5, -34), post + Vector2(5, -34), Palette.VERMILION, 3.0)
	_draw_pine(Vector2(size.x * 0.08, ground), 1.05)


func _draw_pine(base: Vector2, scale_by: float) -> void:
	var tall := 90.0 * scale_by
	draw_line(base, base - Vector2(0, tall), Palette.INK, 4.0)
	for layer: int in 3:
		var y := base.y - tall * (0.45 + layer * 0.22)
		var half := 26.0 * scale_by * (1.0 - layer * 0.25)
		draw_colored_polygon(PackedVector2Array([Vector2(base.x - half, y), Vector2(base.x + half, y), Vector2(base.x, y - 28.0 * scale_by)]), Color("2f4a3a"))


func _draw_camp(ground: float) -> void:
	for spot: float in [0.08, 0.92]:
		var x := size.x * spot
		draw_colored_polygon(PackedVector2Array([Vector2(x - 60, ground), Vector2(x + 60, ground), Vector2(x, ground - 80)]), Palette.PAPER_DARK)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 12, ground), Vector2(x + 12, ground), Vector2(x, ground - 50)]), Palette.INK)
		draw_line(Vector2(x, ground - 80), Vector2(x, ground - 110), Palette.WOOD, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, ground - 110), Vector2(x + 24, ground - 102), Vector2(x, ground - 94)]), Palette.VERMILION)
	var fire := Vector2(size.x * 0.5, ground + 6.0)
	var flicker := 1.0 + 0.12 * sin(_time * 11.0)
	draw_circle(fire, 40.0 * flicker, Color(Palette.GOLD, 0.18))
	draw_colored_polygon(PackedVector2Array([fire + Vector2(-14, 0), fire + Vector2(14, 0), fire + Vector2(0, -34 * flicker)]), Palette.VERMILION)
	draw_colored_polygon(PackedVector2Array([fire + Vector2(-7, 0), fire + Vector2(7, 0), fire + Vector2(0, -20 * flicker)]), Palette.GOLD)
