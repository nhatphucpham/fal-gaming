class_name InkWipe
extends Control
## An ink-wash wipe over the cutscene band: a brush front with a ragged
## edge sweeps left to right. `cover` 1 hides the band behind ink, 0 shows
## it; opening sweeps the ink off, closing sweeps it back on.

const EDGE_PX: float = 70.0

## 0: band shown, 1: band covered.
var cover: float = 1.0:
	set(value):
		cover = value
		queue_redraw()
## True while closing: the ink comes in from the left instead of leaving.
var is_closing: bool = false
var ink: Color = Palette.BACKDROP


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if cover <= 0.0 or size.x < 1.0 or size.y < 1.0:
		return
	var span := size.x + EDGE_PX * 2.0
	# Opening: the covered part is right of the front. Closing: left of it.
	var front := (span * (1.0 - cover) if not is_closing else span * cover) - EDGE_PX
	var edge := PackedVector2Array()
	var steps := 24
	for step: int in steps + 1:
		var y := size.y * step / steps
		var ragged := sin(step * 1.9) * 14.0 + sin(step * 4.3 + 1.0) * 8.0
		edge.append(Vector2(front + ragged, y))
	var body := PackedVector2Array()
	# The far side lies past the ragged front's widest reach, so the shape
	# never folds over itself near either end of the sweep.
	if is_closing:
		body.append(Vector2(-EDGE_PX * 2.0, size.y))
		body.append(Vector2(-EDGE_PX * 2.0, 0))
		body.append_array(edge)
	else:
		body.append_array(edge)
		body.append(Vector2(size.x + EDGE_PX * 2.0, size.y))
		body.append(Vector2(size.x + EDGE_PX * 2.0, 0))
	draw_colored_polygon(body, ink)
	# The wet brush line along the front.
	draw_polyline(edge, Palette.INK, 10.0, true)
	for index: int in 5:
		var drop := edge[index * 5 % edge.size()]
		draw_circle(drop + Vector2(10.0 if is_closing else -10.0, 0), 5.0 + index % 3 * 2.0, Color(Palette.INK, 0.8))
