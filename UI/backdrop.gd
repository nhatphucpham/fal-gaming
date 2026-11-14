class_name Backdrop
extends Control
## The screen background: deep indigo with a faint printed lattice, filling
## the whole window (also beside the game column in landscape).

const SPACING_PX: float = 64.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKDROP)
	var columns := ceili(size.x / SPACING_PX) + 1
	var rows := ceili(size.y / SPACING_PX) + 1
	for row: int in rows:
		for col: int in columns:
			var center := Vector2(col * SPACING_PX + (SPACING_PX / 2.0 if row % 2 == 1 else 0.0), row * SPACING_PX)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -4), center + Vector2(4, 0), center + Vector2(0, 4), center + Vector2(-4, 0),
			]), Palette.BACKDROP_LINE)
