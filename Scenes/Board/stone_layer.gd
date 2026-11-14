class_name StoneLayer
extends Node2D
## Drawn over a UnitView's figure: the stone of Hóa Đá (a pale sheen and
## short cracks while petrified) and the cracks of a crumbling boss, which
## spread from the chest as `cracks` goes 0 to 1.

## How far the cracks of a petrified unit reach (crumbling goes to 1).
const PETRIFIED_CRACKS: float = 0.45

## True while the unit is stone (and alive).
var is_stone: bool = false:
	set(value):
		is_stone = value
		queue_redraw()
## 0..1, how far the crumbling cracks have spread.
var cracks: float = 0.0:
	set(value):
		cracks = value
		queue_redraw()
## The view's size factor (BOSS_SCALE for a boss).
var size_scale: float = 1.0


func _draw() -> void:
	var amount := maxf(cracks, PETRIFIED_CRACKS if is_stone else 0.0)
	if amount <= 0.0:
		return
	var center := UnitView.FEET + Vector2(0.0, -38.0 * size_scale)
	if is_stone:
		draw_circle(center, 34.0 * size_scale, Color(Palette.STEEL, 0.3))
	for index: int in 5:
		var angle := TAU * index / 5.0 + 0.3
		var points := PackedVector2Array([center])
		for step: int in 3:
			var reach := (step + 1) * 14.0 * amount * size_scale
			points.append(center + Vector2(cos(angle + 0.35 * (step % 2 * 2 - 1)), sin(angle)) * reach)
		draw_polyline(points, Palette.INK, 2.5, true)
