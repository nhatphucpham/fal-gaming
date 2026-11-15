class_name FigureBrush
extends RefCounted
## Outlined shapes (ink edge, flat fill) in figure units for the figures
## drawn by hand outside the bone rig (ExtraFigures: the boss and the
## sage), placed by the base transform from UnitPainter.draw_figure.
## Shapes are not drawn one by one: each is turned into triangles already in
## canvas space (one native transform of a cached unit shape) and collected,
## and finish() draws them as one triangle array: one draw call per figure.
## Thin lines (eyes, mouths, strings) are antialiased like Godot's own lines,
## with a feather that fades to transparent on both sides. Thick lines are
## quads with an ink edge drawn under the fill, so they need no antialiasing.

## Lines thinner than this are antialiased (eyes, mouths, small details).
const SMOOTH_UNDER_WIDTH: float = 2.0
# How far a thin line fades out on each side, in figure units.
const FEATHER: float = 0.8
# Circles at or under these radii (figure units) use fewer sides.
const SMALL_RADIUS: float = 4.5
const MEDIUM_RADIUS: float = 7.0
# Two triangles of a unit segment: x from 0 to 1, y from -0.5 to 0.5.
const SEGMENT := [Vector2(0, -0.5), Vector2(1, -0.5), Vector2(1, 0.5), Vector2(0, -0.5), Vector2(1, 0.5), Vector2(0, 0.5)]

var canvas: CanvasItem
var unit: UnitData
var facing: int
var flash: float

var _current: Transform2D
# Triangles in canvas space and their vertex colours, not yet drawn.
var _points := PackedVector2Array()
var _colors := PackedColorArray()
# The colour of the last vertices added and how many still need it: runs
# of one colour (ink edges, caps, outlines) are filled in one go.
var _run_color := Color.TRANSPARENT
var _run_count: int = 0

# Unit circles by side count, as triangle fans. Built once.
static var _fans: Dictionary[int, PackedVector2Array] = {}
static var _segment := PackedVector2Array(SEGMENT)
static var _no_indices := PackedInt32Array()


func _init(target: CanvasItem, data: UnitData, facing_sign: int, flash_amount: float, base := Transform2D.IDENTITY) -> void:
	canvas = target
	unit = data
	facing = facing_sign
	flash = clampf(flash_amount, 0.0, 1.0)
	_current = base


static func ellipse(center: Vector2, radius_x: float, radius_y: float, points: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points)
	for index: int in points:
		var angle := TAU * index / points
		result[index] = center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
	return result


## Draws everything collected. Call once at the end of a figure.
func finish() -> void:
	if _points.is_empty():
		return
	_end_color_run()
	# The points are already in canvas space.
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _no_indices, _points, _colors)
	_points = PackedVector2Array()
	_colors = PackedColorArray()


func tint(color: Color) -> Color:
	return color.lerp(Color.WHITE, flash) if flash > 0.0 else color


func poly(points: PackedVector2Array, fill: Color) -> void:
	fill_shape(points, tint(fill))
	outline(points, Palette.INK, UnitPainter.OUTLINE_PX)


## The closed outline of `points`. Edges run on past the corners by half the
## width so the corners close.
func outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var count := points.size()
	if width < SMOOTH_UNDER_WIDTH:
		var closed := points.duplicate()
		closed.append(points[0])
		_smooth_lines(_pairs_of(closed), color, width)
		return
	# Every edge is a quad, run on by half the width at both ends.
	var quads := PackedVector2Array()
	quads.resize(count * 6)
	var half := width * 0.5
	var from := points[count - 1]
	for index: int in count:
		var to := points[index]
		var along := (to - from).normalized() * half
		var side := Vector2(-along.y, along.x)
		var start := from - along
		var end := to + along
		var at := index * 6
		quads[at] = start - side
		quads[at + 1] = end - side
		quads[at + 2] = end + side
		quads[at + 3] = start - side
		quads[at + 4] = end + side
		quads[at + 5] = start + side
		from = to
	_points.append_array(_current * quads)
	_add_colors(color, quads.size())


func circle(center: Vector2, radius: float, fill: Color) -> void:
	_add_oval(center, Vector2(radius, radius), tint(fill), _sides_for(radius))


## A filled spot without an outline or flash (eyes, noses, gems).
func dot(center: Vector2, radius: float, color: Color) -> void:
	fill_disc(center, radius, color)


## A plain line through `points` with round ends (opaque and thick enough
## only); smooth curves need no joint caps.
func line(points: PackedVector2Array, color: Color, width: float) -> void:
	if width < SMOOTH_UNDER_WIDTH:
		_smooth_lines(_pairs_of(points), color, width)
		return
	for index: int in points.size() - 1:
		_add_segment(points[index], points[index + 1], width, 0.0, 0.0)
	_add_colors(color, (points.size() - 1) * 6)
	if width >= UnitPainter.OUTLINE_PX and color.a >= 1.0:
		fill_disc(points[0], width * 0.5, color)
		fill_disc(points[points.size() - 1], width * 0.5, color)


## A thick line with an ink edge: limbs, poles, blades.
func stick(from: Vector2, to: Vector2, width: float, fill: Color) -> void:
	var ink_width := width + UnitPainter.OUTLINE_PX * 2.0
	_add_segment(from, to, ink_width, 0.0, 0.0)
	_add_colors(Palette.INK, 6)
	fill_disc(from, ink_width * 0.5, Palette.INK)
	fill_disc(to, ink_width * 0.5, Palette.INK)
	_add_segment(from, to, width, 0.0, 0.0)
	_add_colors(tint(fill), 6)


## A filled polygon without outline.
func fill_shape(points: PackedVector2Array, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	var triangles := PackedVector2Array()
	if indices.is_empty():
		# A shape folded over itself (a cape in a wild swing): fan it out.
		for index: int in range(1, points.size() - 1):
			triangles.append_array([points[0], points[index], points[index + 1]])
	else:
		triangles.resize(indices.size())
		for index: int in indices.size():
			triangles[index] = points[indices[index]]
	_points.append_array(_current * triangles)
	_add_colors(color, triangles.size())


## A filled circle without outline.
func fill_disc(center: Vector2, radius: float, color: Color) -> void:
	var fan := _get_fan(_sides_for(radius))
	_points.append_array((_current * Transform2D(0.0, Vector2(radius, radius), 0.0, center)) * fan)
	_add_colors(color, fan.size())


# An outlined circle or ellipse: an ink oval with the fill oval on top, as
# wide apart as the outline.
func _add_oval(center: Vector2, radii: Vector2, color: Color, sides: int) -> void:
	var fan := _get_fan(sides)
	var half := Vector2.ONE * UnitPainter.OUTLINE_PX * 0.5
	_points.append_array((_current * Transform2D(0.0, radii + half, 0.0, center)) * fan)
	_add_colors(Palette.INK, fan.size())
	_points.append_array((_current * Transform2D(0.0, (radii - half).max(Vector2.ZERO), 0.0, center)) * fan)
	_add_colors(color, fan.size())


# The two triangles of a segment from `from` to `to`, run on past its ends
# by `run_back` and `run_on`. Colours are added by the caller.
func _add_segment(from: Vector2, to: Vector2, width: float, run_back: float, run_on: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.0001:
		delta = Vector2(0.0, 0.0001)
		length = 0.0001
	var along := delta / length
	var frame := Transform2D(along * (length + run_back + run_on), Vector2(-along.y, along.x) * width, from - along * run_back)
	_points.append_array((_current * frame) * _segment)


func _add_colors(color: Color, count: int) -> void:
	if color != _run_color:
		_end_color_run()
		_run_color = color
	_run_count += count


func _end_color_run() -> void:
	if _run_count == 0:
		return
	var block := PackedColorArray()
	block.resize(_run_count)
	block.fill(_run_color)
	_colors.append_array(block)
	_run_count = 0


# Thin segments (`pairs` of ends) as a core quad with a feather quad on each
# side whose outer edge is transparent: antialiased without a draw call.
func _smooth_lines(pairs: PackedVector2Array, color: Color, width: float) -> void:
	var count := pairs.size() / 2
	var quads := PackedVector2Array()
	quads.resize(count * 18)
	var half := width * 0.5
	for index: int in count:
		var from := pairs[index * 2]
		var to := pairs[index * 2 + 1]
		var side := (to - from).normalized().orthogonal()
		var inner := side * half
		var outer := side * (half + FEATHER)
		var at := index * 18
		# Core, then the feather on the +side, then on the -side.
		quads[at] = from - inner
		quads[at + 1] = to - inner
		quads[at + 2] = to + inner
		quads[at + 3] = from - inner
		quads[at + 4] = to + inner
		quads[at + 5] = from + inner
		quads[at + 6] = from + inner
		quads[at + 7] = to + inner
		quads[at + 8] = to + outer
		quads[at + 9] = from + inner
		quads[at + 10] = to + outer
		quads[at + 11] = from + outer
		quads[at + 12] = from - inner
		quads[at + 13] = to - inner
		quads[at + 14] = to - outer
		quads[at + 15] = from - inner
		quads[at + 16] = to - outer
		quads[at + 17] = from - outer
	_points.append_array(_current * quads)
	_end_color_run()
	var clear := Color(color, 0.0)
	var segment := PackedColorArray([color, color, color, color, color, color, color, color, clear, color, clear, clear, color, color, clear, color, clear, clear])
	for index: int in count:
		_colors.append_array(segment)


# Segment pairs along an open path, for draw_multiline.
static func _pairs_of(points: PackedVector2Array) -> PackedVector2Array:
	var pairs := PackedVector2Array()
	pairs.resize((points.size() - 1) * 2)
	for index: int in points.size() - 1:
		pairs[index * 2] = points[index]
		pairs[index * 2 + 1] = points[index + 1]
	return pairs


static func _sides_for(radius: float) -> int:
	if radius <= SMALL_RADIUS:
		return 8
	return 12 if radius <= MEDIUM_RADIUS else 16


static func _get_fan(sides: int) -> PackedVector2Array:
	if not _fans.has(sides):
		var ring := ellipse(Vector2.ZERO, 1.0, 1.0, sides)
		var fan := PackedVector2Array()
		for index: int in range(1, sides - 1):
			fan.append_array([ring[0], ring[index], ring[index + 1]])
		_fans[sides] = fan
	return _fans[sides]
