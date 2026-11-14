class_name EpiphanySeal
extends Control
## The small gold seal of a mutated milestone (Kỳ Ngộ): a round gold stamp
## with an ink rim and a red mark, drawn in code.


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0
	draw_circle(center, radius, Palette.GOLD)
	draw_arc(center, radius - 1.0, 0.0, TAU, 24, Palette.INK, 2.0, true)
	draw_rect(Rect2(center - Vector2(radius, radius) * 0.38, Vector2(radius, radius) * 0.76), Palette.VERMILION)
