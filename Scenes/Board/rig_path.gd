class_name RigPath
extends RefCounted
## A canvas-style path (move, line, quadratic and cubic curves, arcs,
## ellipses, rectangles) flattened into polylines as it is built, so the
## sketch's piece drawings port line by line. Build a path once and cache
## the mesh made from it (RigMesh); never rebuild curves per frame.
## Angles are the canvas's: 0 toward +x, growing clockwise on screen.
## [codeblock]
## var path := RigPath.new().arc(0, 1.5, 2.3, 0, 7)
## mesh.shape(path, RigPalette.SKIN)
## [/codeblock]

const CURVE_STEPS: int = 8
# Arc segments per radian: fewer for small circles.
const SMALL_ARC_STEPS_PER_RAD: float = 2.6
const ARC_STEPS_PER_RAD: float = 3.8
const SMALL_RADIUS: float = 3.0
const SAME_POINT: float = 0.0004

## Each subpath's points; a closed one does not repeat its first point.
var polylines: Array[PackedVector2Array] = []
var closed: Array[bool] = []

var _open := PackedVector2Array()


func move_to(x: float, y: float) -> RigPath:
	_flush(false)
	_open = PackedVector2Array([Vector2(x, y)])
	return self


func line_to(x: float, y: float) -> RigPath:
	if _open.is_empty():
		return move_to(x, y)
	_add(Vector2(x, y))
	return self


func quad_to(control_x: float, control_y: float, x: float, y: float) -> RigPath:
	if _open.is_empty():
		move_to(control_x, control_y)
	var start := _open[_open.size() - 1]
	var control := Vector2(control_x, control_y)
	var end := Vector2(x, y)
	for step: int in range(1, CURVE_STEPS + 1):
		var t := float(step) / CURVE_STEPS
		_add(start.lerp(control, t).lerp(control.lerp(end, t), t))
	return self


func bezier_to(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> RigPath:
	if _open.is_empty():
		move_to(c1x, c1y)
	var start := _open[_open.size() - 1]
	var first := Vector2(c1x, c1y)
	var second := Vector2(c2x, c2y)
	var end := Vector2(x, y)
	for step: int in range(1, CURVE_STEPS + 3):
		_add(start.bezier_interpolate(first, second, end, float(step) / (CURVE_STEPS + 2)))
	return self


## A circular arc; like the canvas, a sweep of a full turn or more (such as
## 0 to 7) is a whole circle, and the arc joins the current subpath.
func arc(center_x: float, center_y: float, radius: float, from_angle: float, to_angle: float, counterclockwise: bool = false) -> RigPath:
	return ellipse(center_x, center_y, radius, radius, 0.0, from_angle, to_angle, counterclockwise)


func ellipse(center_x: float, center_y: float, radius_x: float, radius_y: float, rotation: float, from_angle: float, to_angle: float, counterclockwise: bool = false) -> RigPath:
	var sweep := 0.0
	if counterclockwise:
		sweep = -TAU if from_angle - to_angle >= TAU else -fposmod(from_angle - to_angle, TAU)
	else:
		sweep = TAU if to_angle - from_angle >= TAU else fposmod(to_angle - from_angle, TAU)
	var per_rad := SMALL_ARC_STEPS_PER_RAD if maxf(radius_x, radius_y) < SMALL_RADIUS else ARC_STEPS_PER_RAD
	var steps := maxi(2, ceili(absf(sweep) * per_rad))
	var frame := Transform2D(rotation, Vector2(center_x, center_y))
	for step: int in steps + 1:
		var angle := from_angle + sweep * step / steps
		var point := frame * Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
		if step == 0 and _open.is_empty():
			_open = PackedVector2Array([point])
		else:
			_add(point)
	return self


func rect(x: float, y: float, width: float, height: float) -> RigPath:
	_flush(false)
	_open = PackedVector2Array([Vector2(x, y), Vector2(x + width, y), Vector2(x + width, y + height), Vector2(x, y + height)])
	_flush(true)
	_open = PackedVector2Array([Vector2(x, y)])
	return self


## Closes the current subpath; the next one starts at its first point.
func close() -> RigPath:
	if _open.is_empty():
		return self
	var first := _open[0]
	_flush(true)
	_open = PackedVector2Array([first])
	return self


## Ends the path; call before reading `polylines`.
func done() -> RigPath:
	_flush(false)
	return self


func _add(point: Vector2) -> void:
	if _open.is_empty() or _open[_open.size() - 1].distance_squared_to(point) > SAME_POINT:
		_open.append(point)


func _flush(is_closed: bool) -> void:
	if is_closed and _open.size() > 2 and _open[0].distance_squared_to(_open[_open.size() - 1]) <= SAME_POINT:
		_open.remove_at(_open.size() - 1)
	if _open.size() >= 2:
		polylines.append(_open)
		closed.append(is_closed)
	_open = PackedVector2Array()
