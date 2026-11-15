class_name Backdrop
extends Control
## The screen background: deep indigo with a faint printed lattice, filling
## the whole window (also beside the game column in landscape). Two draw
## calls: the fill and every diamond in one triangle array.

const SPACING_PX: float = 64.0
## One lattice diamond (4 px from its centre to each corner) as two triangles.
const DIAMOND_TRIANGLES: Array[Vector2] = [
	Vector2(0, -4), Vector2(4, 0), Vector2(0, 4),
	Vector2(0, -4), Vector2(0, 4), Vector2(-4, 0),
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKDROP)
	var columns := ceili(size.x / SPACING_PX) + 1
	var rows := ceili(size.y / SPACING_PX) + 1
	# Every diamond goes into one triangle array: one draw call, where a
	# polygon each would cost one per diamond (about 270 on a phone).
	var points := PackedVector2Array()
	points.resize(rows * columns * 6)
	var index := 0
	for row: int in rows:
		for col: int in columns:
			var center := Vector2(col * SPACING_PX + (SPACING_PX / 2.0 if row % 2 == 1 else 0.0), row * SPACING_PX)
			for corner: Vector2 in DIAMOND_TRIANGLES:
				points[index] = center + corner
				index += 1
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(Palette.BACKDROP_LINE)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), points, colors)
