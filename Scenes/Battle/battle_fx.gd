class_name BattleFx
extends Node2D
## A short-lived battle effect (arrow, bolt, slash, cell flash, damage number,
## shield flash, dust). It animates `progress` from 0 to 1, draws itself with
## a painter function and frees itself at the end. Make one with a factory:
## [codeblock]
## fx_layer.add_child(BattleFx.arrow(from, to))
## [/codeblock]
## Call play() after adding it to the tree.

const NUMBER_FONT_SIZE: int = 24
const COUNTER_FONT_SIZE: int = 36
const CRIT_FONT_SIZE: int = 30

## 0 at the start, 1 at the end.
var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()
var duration_sec: float = 0.3
var from_point: Vector2 = Vector2.ZERO
var to_point: Vector2 = Vector2.ZERO
var color: Color = Color.WHITE
var text: String = ""
var font_size: int = NUMBER_FONT_SIZE

var _painter: Callable


## Starts the animation; `speed` scales it with the battle speed.
func play(speed: float) -> void:
	var tween := create_tween()
	tween.set_speed_scale(speed)
	tween.tween_property(self, ^"progress", 1.0, duration_sec)
	tween.tween_callback(queue_free)


func _draw() -> void:
	_painter.call()


static func arrow(from: Vector2, to: Vector2, flight_sec: float) -> BattleFx:
	var fx := _make(from, to, flight_sec, Palette.WOOD)
	fx._painter = fx._paint_arrow
	return fx


static func bolt(from: Vector2, to: Vector2, flight_sec: float, bolt_color: Color) -> BattleFx:
	var fx := _make(from, to, flight_sec, bolt_color)
	fx._painter = fx._paint_bolt
	return fx


static func cell_flash(center: Vector2, flash_color: Color) -> BattleFx:
	var fx := _make(center, center, 0.35, flash_color)
	fx._painter = fx._paint_cell_flash
	return fx


static func slash(at: Vector2, direction: Vector2) -> BattleFx:
	var fx := _make(at, at + direction.normalized(), 0.2, Palette.CREAM)
	fx._painter = fx._paint_slash
	return fx


## A damage number; counters are big and gold, critical hits gold.
static func number(at: Vector2, amount: int, is_counter: bool, is_crit: bool = false) -> BattleFx:
	var fx := _make(at, at + Vector2(0, -32), 0.6, Palette.GOLD if is_counter or is_crit else Palette.CREAM)
	fx.text = str(amount) + ("!" if is_crit else "")
	fx.font_size = COUNTER_FONT_SIZE if is_counter else (CRIT_FONT_SIZE if is_crit else NUMBER_FONT_SIZE)
	fx._painter = fx._paint_number
	return fx


static func shield_flash(at: Vector2, facing_up: bool) -> BattleFx:
	var fx := _make(at, at + Vector2(0, -1 if facing_up else 1), 0.3, Color("bfe3ff"))
	fx._painter = fx._paint_shield
	return fx


static func dust(at: Vector2) -> BattleFx:
	var fx := _make(at, at, 0.35, Palette.PAPER_DARK)
	fx._painter = fx._paint_dust
	return fx


static func _make(from: Vector2, to: Vector2, seconds: float, fx_color: Color) -> BattleFx:
	var fx := BattleFx.new()
	fx.from_point = from
	fx.to_point = to
	fx.duration_sec = seconds
	fx.color = fx_color
	fx.position = Vector2.ZERO
	return fx


func _paint_arrow() -> void:
	var lift := sin(progress * PI) * 18.0
	var head := from_point.lerp(to_point, progress) + Vector2(0, -lift)
	var ahead := from_point.lerp(to_point, minf(progress + 0.05, 1.0)) + Vector2(0, -sin(minf(progress + 0.05, 1.0) * PI) * 18.0)
	var direction := (ahead - head).normalized() if ahead != head else (to_point - from_point).normalized()
	var tail := head - direction * 26.0
	draw_line(tail, head, Palette.INK, 5.0, true)
	draw_line(tail, head, color, 2.5, true)
	var side := direction.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([head + direction * 7.0, head + side, head - side]), Palette.STEEL)
	draw_line(tail, tail - direction * 6.0 + side, Palette.VERMILION, 2.5, true)
	draw_line(tail, tail - direction * 6.0 - side, Palette.VERMILION, 2.5, true)


func _paint_bolt() -> void:
	var head := from_point.lerp(to_point, progress)
	for index: int in 4:
		var trail := from_point.lerp(to_point, maxf(progress - index * 0.06, 0.0))
		draw_circle(trail, 9.0 - index * 2.0, Color(color, 0.8 - index * 0.18))
	draw_circle(head, 5.0, Color.WHITE)


func _paint_cell_flash() -> void:
	var half := BoardView.CELL_PX * (0.4 + progress * 0.1)
	var rect := Rect2(from_point - Vector2(half, half), Vector2(half, half) * 2.0)
	var alpha := 1.0 - progress
	draw_rect(rect, Color(color, 0.55 * alpha))
	draw_rect(rect, Color(Color.WHITE, alpha), false, 3.0)


func _paint_slash() -> void:
	var direction := (to_point - from_point).normalized()
	var base_angle := direction.angle()
	var sweep := lerpf(-1.1, 1.1, progress)
	var alpha := 1.0 - progress * 0.8
	draw_arc(from_point - direction * 10.0, 26.0, base_angle - 1.1, base_angle + sweep, 12, Color(Palette.INK, alpha * 0.6), 7.0, true)
	draw_arc(from_point - direction * 10.0, 26.0, base_angle - 1.1, base_angle + sweep, 12, Color(color, alpha), 4.0, true)


func _paint_number() -> void:
	var font := ThemeDB.fallback_font
	var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - progress * 6.0)
	var point := from_point.lerp(to_point, ease(progress, 0.4))
	var alpha := 1.0 if progress < 0.6 else 1.0 - (progress - 0.6) / 0.4
	var size := int(font_size * pop)
	var width := 120.0
	var origin := point + Vector2(-width / 2.0, size * 0.35)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 8, Color(Palette.INK, alpha))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, Color(color, alpha))


func _paint_shield() -> void:
	var direction := (to_point - from_point).normalized()
	var radius := 20.0 + progress * 12.0
	var alpha := 1.0 - progress
	var center := from_point + direction * 8.0
	draw_arc(center, radius, direction.angle() - 1.2, direction.angle() + 1.2, 14, Color(Palette.INDIGO, alpha), 7.0, true)
	draw_arc(center, radius, direction.angle() - 1.2, direction.angle() + 1.2, 14, Color(color, alpha), 4.0, true)


func _paint_dust() -> void:
	var alpha := 1.0 - progress
	for index: int in 4:
		var angle := TAU * index / 4.0 + 0.6
		var offset := Vector2(cos(angle), sin(angle) * 0.4) * (6.0 + 16.0 * progress)
		draw_circle(from_point + offset, 6.0 * (1.0 - progress * 0.4), Color(color, alpha * 0.85))
