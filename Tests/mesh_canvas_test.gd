extends SceneTree

# MeshCanvas records shapes as triangles the way a CanvasItem would
# draw them: a filled rect is two triangles, a filled circle a fan, a
# polygon its triangulation, a line a quad strip (three strips when
# antialiased, the soft edges fading to clear), a closed outline mitres its
# corners onto the shape's corners pushed out by half the width, a thin
# shape is never thinner than 1 px, and commit() empties the recording.
# A token from TacticsPainter records into one canvas. Dashed lines and
# multilines draw like CanvasItem's, open()/finish() serve both a canvas
# item and a MeshCanvas, and the shared painters (IconPainter, UnitPainter's
# pips and ring) record into one. Checks return true
# only when every step succeeded.


func _initialize() -> void:
	if _run():
		print("Mesh canvas test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	return _check_shapes() and _check_line() and _check_outline() and _check_commit() and _check_token() \
		and _check_dashes() and _check_multiline() and _check_open() and _check_painters()


func _fail(message: String) -> bool:
	push_error("Mesh canvas test: " + message)
	return false


func _check_shapes() -> bool:
	var canvas := MeshCanvas.new()
	canvas.draw_rect(Rect2(0, 0, 10, 10), Color.WHITE)
	if canvas.get_triangle_count() != 2:
		return _fail("a filled rect should be 2 triangles, got %d" % canvas.get_triangle_count())
	canvas = MeshCanvas.new()
	canvas.draw_circle(Vector2.ZERO, 20.0, Color.WHITE)
	# 20 px: 24 segments (1.2 a px, kept between 8 and 32), one triangle each.
	if canvas.get_triangle_count() != 24:
		return _fail("a filled 20-px circle should be 24 triangles, got %d" % canvas.get_triangle_count())
	canvas = MeshCanvas.new()
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(5, 4), Vector2(0, 10)]), Color.WHITE)
	if canvas.get_triangle_count() != 3:
		return _fail("a five-point polygon should be 3 triangles, got %d" % canvas.get_triangle_count())
	canvas.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), Color.WHITE)
	if canvas.get_triangle_count() != 3:
		return _fail("a polygon of two points should add nothing")
	return true


func _check_line() -> bool:
	var canvas := MeshCanvas.new()
	canvas.draw_line(Vector2(0, 0), Vector2(10, 0), Color.WHITE, 4.0)
	if canvas.get_triangle_count() != 2:
		return _fail("a plain line should be one quad, got %d triangles" % canvas.get_triangle_count())
	var bounds := _bounds(canvas)
	if not bounds.is_equal_approx(Rect2(0, -2, 10, 4)):
		return _fail("a 4-px line along x should span y -2..2, got %s" % bounds)
	canvas = MeshCanvas.new()
	canvas.draw_line(Vector2(0, 0), Vector2(10, 0), Color.WHITE, 4.0, true)
	if canvas.get_triangle_count() != 6:
		return _fail("an antialiased line should be three quads, got %d triangles" % canvas.get_triangle_count())
	bounds = _bounds(canvas)
	if not bounds.is_equal_approx(Rect2(0, -3, 10, 6)):
		return _fail("an antialiased 4-px line should feather 1 px each side, got %s" % bounds)
	var colors: PackedColorArray = canvas.get("_colors")
	var points: PackedVector2Array = canvas.get("_points")
	for index: int in points.size():
		var is_edge := absf(absf(points[index].y) - 3.0) < 0.01
		if is_edge and colors[index].a != 0.0:
			return _fail("a feathered edge should fade to clear, got %s at %s" % [colors[index], points[index]])
	canvas = MeshCanvas.new()
	canvas.draw_line(Vector2(0, 0), Vector2(10, 0), Color.WHITE, 0.2)
	if not _bounds(canvas).is_equal_approx(Rect2(0, -0.5, 10, 1)):
		return _fail("a hairline should still be 1 px wide, got %s" % _bounds(canvas))
	canvas.draw_line(Vector2(3, 3), Vector2(3, 3), Color.WHITE, 2.0)
	if canvas.get_triangle_count() != 2:
		return _fail("a line of no length should add nothing")
	return true


func _check_outline() -> bool:
	var canvas := MeshCanvas.new()
	canvas.draw_rect(Rect2(0, 0, 10, 10), Color.WHITE, false, 2.0)
	# Closed: 4 corners, 4 quads, no seam where the outline starts.
	if canvas.get_triangle_count() != 8:
		return _fail("a rect outline should be 4 quads, got %d triangles" % canvas.get_triangle_count())
	if not _bounds(canvas).is_equal_approx(Rect2(-1, -1, 12, 12)):
		return _fail("a 2-px rect outline's mitred corners should reach 1 px out, got %s" % _bounds(canvas))
	var points: PackedVector2Array = canvas.get("_points")
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, 1), Vector2(11, -1), Vector2(9, 1), Vector2(11, 11), Vector2(9, 9), Vector2(-1, 11), Vector2(1, 9)]:
		if not Array(points).any(func(point: Vector2) -> bool: return point.is_equal_approx(corner)):
			return _fail("a rect outline should have a mitred corner at %s, got %s" % [corner, points])
	canvas = MeshCanvas.new()
	canvas.draw_circle(Vector2.ZERO, 10.0, Color.WHITE, false, 2.0)
	# 10 px: 12 segments, a closed ring of 12 quads.
	if canvas.get_triangle_count() != 24:
		return _fail("a 10-px circle outline should be 12 quads, got %d triangles" % canvas.get_triangle_count())
	return true


func _check_commit() -> bool:
	var canvas := MeshCanvas.new()
	canvas.draw_rect(Rect2(0, 0, 4, 4), Color.WHITE)
	var item := RenderingServer.canvas_item_create()
	canvas.commit(item)
	RenderingServer.free_rid(item)
	if canvas.get_triangle_count() != 0:
		return _fail("commit() should clear the recording")
	return true


func _check_token() -> bool:
	var canvas := MeshCanvas.new()
	TacticsPainter.draw_token(canvas, Vector2.ZERO, 0, true, &"class.sword", false)
	if canvas.get_triangle_count() == 0:
		return _fail("a leader token should record its shapes into the canvas")
	return true


# A dashed line is whole dashes (a quad each, two triangles) with gaps as
# long, both ends dashes when aligned; it stays on the line.
func _check_dashes() -> bool:
	var canvas := MeshCanvas.new()
	canvas.draw_dashed_line(Vector2.ZERO, Vector2(90, 0), Color.WHITE, 2.0, 10.0)
	# 90 px of 10-px dashes and gaps, aligned: 5 dashes, 4 gaps.
	if canvas.get_triangle_count() != 10:
		return _fail("an aligned 90-px line of 10-px dashes should be 5 dashes (10 triangles), got %d" % canvas.get_triangle_count())
	var bounds := _bounds(canvas)
	if not is_equal_approx(bounds.position.x, 0.0) or not is_equal_approx(bounds.end.x, 90.0):
		return _fail("the dashes should start and end with the line, got %s" % bounds)
	# 76 px: 7 steps centred, so dashes of 13, 10, 10 and 13 px.
	canvas = MeshCanvas.new()
	canvas.draw_dashed_line(Vector2.ZERO, Vector2(76, 0), Color.WHITE, 2.0, 10.0)
	var points: PackedVector2Array = canvas.get("_points")
	var starts := PackedFloat32Array()
	for index: int in range(0, points.size(), 4):
		starts.append(minf(points[index].x, points[index + 2].x))
	if canvas.get_triangle_count() != 8 or not is_equal_approx(starts[1], 23.0) or not is_equal_approx(_bounds(canvas).end.x, 76.0):
		return _fail("a 76-px line of 10-px dashes should centre 4 dashes (13, 10, 10, 13 px), got starts %s" % starts)
	canvas = MeshCanvas.new()
	canvas.draw_dashed_line(Vector2.ZERO, Vector2.ZERO, Color.WHITE, 2.0, 10.0)
	if canvas.get_triangle_count() != 0:
		return _fail("a dashed line of no length should draw nothing")
	return true


# Pairs of points are separate segments; an odd last point is left out.
func _check_multiline() -> bool:
	var canvas := MeshCanvas.new()
	canvas.draw_multiline(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(0, 5), Vector2(10, 5), Vector2(3, 3)]), Color.WHITE, 2.0)
	if canvas.get_triangle_count() != 4:
		return _fail("two segments should be 4 triangles, got %d" % canvas.get_triangle_count())
	return true


# open() hands back a MeshCanvas target itself and finish() leaves it
# recording; for a CanvasItem target, finish() commits and clears.
func _check_open() -> bool:
	var target := MeshCanvas.new()
	var mesh := MeshCanvas.open(target)
	if mesh != target:
		return _fail("open() on a MeshCanvas should return it")
	mesh.draw_rect(Rect2(0, 0, 4, 4), Color.WHITE)
	mesh.finish(target)
	if target.get_triangle_count() != 2:
		return _fail("finish() on a MeshCanvas should keep its recording")
	var item := Node2D.new()
	var own := MeshCanvas.open(item)
	if own == null or own == target:
		item.free()
		return _fail("open() on a CanvasItem should make a new recorder")
	own.draw_rect(Rect2(0, 0, 4, 4), Color.WHITE)
	own.finish(item)
	item.free()
	if own.get_triangle_count() != 0:
		return _fail("finish() on a CanvasItem should commit and clear")
	return true


# The shared painters record into a MeshCanvas instead of drawing.
func _check_painters() -> bool:
	for kind: StringName in [&"coin", &"supply", &"morale", &"level", &"troops", &"tent", &"bow", &"lantern"]:
		var canvas := MeshCanvas.new()
		IconPainter.draw(canvas, kind, Vector2.ZERO, 32.0)
		if canvas.get_triangle_count() == 0:
			return _fail("the %s icon should record into a MeshCanvas" % kind)
	var pips := MeshCanvas.new()
	UnitPainter.draw_star_pips(pips, Vector2.ZERO, 3)
	var ring := MeshCanvas.new()
	UnitPainter.draw_ring(ring, Vector2.ZERO, Vector2(28, 9), Color.BLUE, 0.5)
	if pips.get_triangle_count() == 0 or ring.get_triangle_count() == 0:
		return _fail("star pips and the ring should record into a MeshCanvas")
	return true


func _bounds(canvas: MeshCanvas) -> Rect2:
	var points: PackedVector2Array = canvas.get("_points")
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds
