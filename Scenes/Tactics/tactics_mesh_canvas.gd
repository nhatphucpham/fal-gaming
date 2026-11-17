class_name TacticsMeshCanvas
extends RefCounted
## Records flat shapes the way a CanvasItem draws them (the draw_* calls
## TacticsPainter uses) into one triangle array, then adds it to a canvas
## item as a single command: a token that took 7 to 12 draw calls (each
## polygon, polyline and circle its own) costs one. Lines and outlines are
## thick strips with mitred corners; an antialiased one gets a 1-px soft
## edge. Shapes keep their order, so later ones paint over earlier ones.
## [codeblock]
## func _draw() -> void:
## 	var mesh := TacticsMeshCanvas.new()
## 	TacticsPainter.draw_token(mesh, Vector2.ZERO, 0, true, &"class.sword", false)
## 	mesh.commit(get_canvas_item())
## [/codeblock]

## A miter is cut at this many half-widths so a sharp corner stays short.
const MITER_LIMIT: float = 2.0
const FEATHER_PX: float = 1.0

var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


## Adds what was recorded to `item` as one triangle array (nothing when
## empty) and clears the recording.
func commit(item: RID) -> void:
	if not _indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(item, _indices, _points, _colors)
	_points.clear()
	_colors.clear()
	_indices.clear()


## Triangles recorded so far (for tests).
func get_triangle_count() -> int:
	return _indices.size() / 3


func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		return
	var base := _points.size()
	_points.append_array(points)
	for index: int in points.size():
		_colors.append(color)
	for index: int in triangles:
		_indices.append(base + index)


func draw_circle(center: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	var segments := _circle_segments(radius)
	var points := PackedVector2Array()
	for index: int in segments:
		points.append(center + Vector2.from_angle(TAU * index / segments) * radius)
	if not filled:
		points.append(points[0])
		draw_polyline(points, color, maxf(width, 1.0), antialiased)
		return
	var base := _points.size()
	_points.append(center)
	_colors.append(color)
	_points.append_array(points)
	for index: int in segments:
		_colors.append(color)
	for index: int in segments:
		_indices.append_array([base, base + 1 + index, base + 1 + (index + 1) % segments])


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	if not filled:
		var p := rect.position
		var e := rect.end
		draw_polyline(PackedVector2Array([p, Vector2(e.x, p.y), e, Vector2(p.x, e.y), p]), color, maxf(width, 1.0), antialiased)
		return
	var base := _points.size()
	_points.append_array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	_colors.append_array([color, color, color, color])
	_indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	draw_polyline(PackedVector2Array([from, to]), color, width, antialiased)


func draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	var points := PackedVector2Array()
	for index: int in point_count:
		points.append(center + Vector2.from_angle(lerpf(start_angle, end_angle, float(index) / maxi(point_count - 1, 1))) * radius)
	draw_polyline(points, color, width, antialiased)


## A strip `width` px wide along the points (closed when the last point is
## the first), its corners mitred; antialiased, a soft 1-px edge each side.
func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	var path := _without_repeats(points)
	if path.size() < 2:
		return
	var is_closed := path.size() > 2 and path[0].is_equal_approx(path[path.size() - 1])
	if is_closed:
		path.remove_at(path.size() - 1)
	var half := maxf(width, 1.0) / 2.0
	var offsets := _miter_offsets(path, is_closed)
	_add_strip(path, offsets, half, half, color, color, is_closed)
	if antialiased:
		var clear := Color(color, 0.0)
		_add_strip(path, offsets, half, half + FEATHER_PX, color, clear, is_closed)
		_add_strip(path, offsets, -half, -half - FEATHER_PX, color, clear, is_closed)


# One band of quads between the offsets `inner` and `outer` (multiples of
# each point's unit miter) along the path; `inner` == `outer` means the
# solid band from -inner to +inner.
func _add_strip(path: PackedVector2Array, offsets: PackedVector2Array, inner: float, outer: float, inner_color: Color, outer_color: Color, is_closed: bool) -> void:
	var base := _points.size()
	var is_solid := inner == outer
	for index: int in path.size():
		_points.append(path[index] + offsets[index] * (-inner if is_solid else inner))
		_points.append(path[index] + offsets[index] * outer)
		_colors.append(inner_color)
		_colors.append(outer_color)
	var count := path.size()
	var segments := count if is_closed else count - 1
	for index: int in segments:
		var a := base + index * 2
		var b := base + ((index + 1) % count) * 2
		_indices.append_array([a, a + 1, b + 1, a, b + 1, b])


# The unit miter at each point (its length grows at sharp corners, up to
# MITER_LIMIT).
func _miter_offsets(path: PackedVector2Array, is_closed: bool) -> PackedVector2Array:
	var offsets := PackedVector2Array()
	var count := path.size()
	for index: int in count:
		var has_before := index > 0 or is_closed
		var has_after := index < count - 1 or is_closed
		var before := (path[index] - path[(index - 1 + count) % count]).normalized() if has_before else Vector2.ZERO
		var after := (path[(index + 1) % count] - path[index]).normalized() if has_after else Vector2.ZERO
		var normal_after := Vector2(-after.y, after.x)
		var normal_before := Vector2(-before.y, before.x)
		if not has_before:
			offsets.append(normal_after)
			continue
		if not has_after:
			offsets.append(normal_before)
			continue
		var miter := (normal_before + normal_after).normalized()
		if miter == Vector2.ZERO:
			offsets.append(normal_after)
			continue
		offsets.append(miter * minf(1.0 / maxf(miter.dot(normal_after), 0.001), MITER_LIMIT))
	return offsets


func _without_repeats(points: PackedVector2Array) -> PackedVector2Array:
	var path := PackedVector2Array()
	for point: Vector2 in points:
		if path.is_empty() or not path[path.size() - 1].is_equal_approx(point):
			path.append(point)
	return path


func _circle_segments(radius: float) -> int:
	return clampi(int(radius * 1.2), 8, 32)
