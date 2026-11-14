class_name FigureBrush
extends RefCounted
## Drawing state for one figure: the target canvas, the unit's colours, its
## pose, and outlined shapes (ink edge, flat fill) in figure units. A
## transform stack (push/pop) lets body parts be drawn in their own frame,
## composed with the base transform from UnitPainter.draw_figure.
## Every shape is drawn from canvas primitives (quads and lines) that the
## Compatibility renderer batches, so a whole figure costs a few draw calls
## instead of one per shape (draw_colored_polygon and draw_circle cost one
## each). Only thin lines are antialiased: antialiased thick lines cost
## many triangles each and look the same at board size. Lines have square
## ends, so sticks get small round caps and joints.

const ELLIPSE_POINTS: int = 16
## Lines thinner than this are antialiased (eyes, mouths, small details).
const SMOOTH_UNDER_WIDTH: float = 2.0
# Concentric circles that stand in for a radial gradient.
const GLOW_RINGS: int = 4
# Circles at or under these radii (figure units) use fewer sides.
const SMALL_RADIUS: float = 4.5
const MEDIUM_RADIUS: float = 7.0

var canvas: CanvasItem
var unit: UnitData
var pose: UnitPose
var facing: int
var flash: float
var skin: Color
var tunic: Color
var mount: Color
var trim: Color
var look: Dictionary
## True for a furred race (wolf folk): no hair knot or nose guard, a fur collar.
var has_fur: bool = false
## Where a crown sits, set by the head and the headgear.
var crown_y: float = -60.0
## Cost 5 (not a boss): the figure still owes its crown.
var wears_crown: bool = false
## Draws the class headgear: func(brush, head_center). May be invalid.
var headgear: Callable

var _current: Transform2D
var _stack: Array[Transform2D] = []

# Unit circles by side count: the outline points, and segment pairs for
# draw_multiline. Built once.
static var _rings: Dictionary[int, PackedVector2Array] = {}
static var _ring_pairs: Dictionary[int, PackedVector2Array] = {}
static var _no_uvs := PackedVector2Array()


func _init(target: CanvasItem, data: UnitData, facing_sign: int, flash_amount: float, figure_pose: UnitPose = null, base := Transform2D.IDENTITY) -> void:
	canvas = target
	unit = data
	facing = facing_sign
	flash = clampf(flash_amount, 0.0, 1.0)
	pose = figure_pose if figure_pose != null else UnitPose.get_rest()
	look = UnitPainter.RACE_LOOKS.get(data.race_id, UnitPainter.RACE_LOOKS[&"race.human"])
	skin = look["skin"]
	tunic = look["tunic"]
	mount = look["mount"]
	has_fur = look["has_fur"]
	trim = Palette.cost_color(data.cost)
	wears_crown = data.cost >= Catalog.MAX_COST and not data.is_boss
	_current = base
	canvas.draw_set_transform_matrix(_current)


static func ellipse(center: Vector2, radius_x: float, radius_y: float, points: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points)
	for index: int in points:
		var angle := TAU * index / points
		result[index] = center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
	return result


## The unit vector of a figure angle (0 up, positive toward +x).
static func dir_of(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


## Moves the drawing frame to `origin`, turned by `rotation` and scaled.
func push(origin: Vector2, rotation: float = 0.0, frame_scale := Vector2.ONE) -> void:
	_stack.append(_current)
	_current = _current * Transform2D(rotation, frame_scale, 0.0, origin)
	canvas.draw_set_transform_matrix(_current)


func pop() -> void:
	_current = _stack.pop_back()
	canvas.draw_set_transform_matrix(_current)


func tint(color: Color) -> Color:
	return color.lerp(Color.WHITE, flash) if flash > 0.0 else color


func poly(points: PackedVector2Array, fill: Color) -> void:
	fill_shape(points, tint(fill))
	outline(points, Palette.INK, UnitPainter.OUTLINE_PX)


## The closed outline of `points`. Edges run on past the corners by half the
## width so the corners close.
func outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var count := points.size()
	var pairs := PackedVector2Array()
	pairs.resize(count * 2)
	for index: int in count:
		var from := points[index]
		var to := points[(index + 1) % count]
		var run_on := (to - from).normalized() * width * 0.5
		pairs[index * 2] = from - run_on
		pairs[index * 2 + 1] = to + run_on
	canvas.draw_multiline(pairs, color, width, width < SMOOTH_UNDER_WIDTH)


func circle(center: Vector2, radius: float, fill: Color) -> void:
	_fill_oval(center, Vector2(radius, radius), tint(fill), _sides_for(radius))


## A filled spot without an outline or flash (eyes, noses, gems).
func dot(center: Vector2, radius: float, color: Color) -> void:
	fill_disc(center, radius, color)


## An outlined ellipse (boots, snouts, pauldrons).
func fill_ellipse(center: Vector2, radius_x: float, radius_y: float, fill: Color) -> void:
	_fill_oval(center, Vector2(radius_x, radius_y), tint(fill), ELLIPSE_POINTS)


## A plain line through `points` with round ends (opaque and thick enough
## only); smooth curves need no joint caps.
func line(points: PackedVector2Array, color: Color, width: float) -> void:
	canvas.draw_multiline(_pairs_of(points), color, width, width < SMOOTH_UNDER_WIDTH)
	if width >= UnitPainter.OUTLINE_PX and color.a >= 1.0:
		fill_disc(points[0], width * 0.5, color)
		fill_disc(points[points.size() - 1], width * 0.5, color)


## A thick line with an ink edge: limbs, poles, blades.
func stick(from: Vector2, to: Vector2, width: float, fill: Color) -> void:
	stick_path(PackedVector2Array([from, to]), width, fill)


## A thick line through `points` with an ink edge and round ends; it may
## bend (limbs). At a bend both segments run on past the joint to close it.
func stick_path(points: PackedVector2Array, width: float, fill: Color) -> void:
	var ink_width := width + UnitPainter.OUTLINE_PX * 2.0
	canvas.draw_multiline(_joined_pairs(points, ink_width * 0.5), Palette.INK, ink_width)
	fill_disc(points[0], ink_width * 0.5, Palette.INK)
	fill_disc(points[points.size() - 1], ink_width * 0.5, Palette.INK)
	# The fill needs no end caps: the ink's round ends frame the tips.
	canvas.draw_multiline(_joined_pairs(points, width * 0.5), tint(fill), width)


## A two-bone limb from `root` toward `tip`; `bend` +1/-1 picks the elbow
## side. Returns where the tip ends (pulled in when out of reach).
func limb(root: Vector2, tip: Vector2, upper: float, lower: float, bend: float, width: float, fill: Color) -> Vector2:
	var delta := tip - root
	var distance := maxf(delta.length(), 0.001)
	var reach := upper + lower - 0.01
	if distance > reach:
		delta *= reach / distance
		distance = reach
		tip = root + delta
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var off := sqrt(maxf(0.0, upper * upper - along * along)) * bend
	var joint := root + Vector2(delta.x * along - delta.y * off, delta.y * along + delta.x * off) / distance
	stick_path(PackedVector2Array([root, joint, tip]), width, fill)
	return tip


## A soft glow of `amount` 0..1 around `center`, fading out at `radius`.
func glow(center: Vector2, radius: float, color: Color, amount: float) -> void:
	if amount <= 0.0:
		return
	# Each smaller ring adds just enough alpha that the stack fades linearly
	# from 0.8 at the centre to nothing at the rim, like the gradient it mimics.
	var covered := 0.0
	for ring: int in GLOW_RINGS:
		var target := 0.8 * amount * (ring + 0.5) / GLOW_RINGS
		var alpha := 1.0 - (1.0 - target) / (1.0 - covered)
		covered = target
		fill_disc(center, radius * (1.0 - float(ring) / GLOW_RINGS), Color(color, alpha))


## An unfilled arc; angles are the canvas's (0 toward +x, clockwise).
func arc(center: Vector2, radius: float, from_angle: float, to_angle: float, color: Color, width: float) -> void:
	var steps := 10
	var directions := PackedVector2Array()
	for index: int in steps + 1:
		var angle := lerpf(from_angle, to_angle, float(index) / steps)
		directions.append(Vector2(cos(angle), sin(angle)))
	if width < SMOOTH_UNDER_WIDTH:
		canvas.draw_multiline(_pairs_of(Transform2D(0.0, Vector2(radius, radius), 0.0, center) * directions), color, width, true)
		return
	# A band of quads: thick translucent segments would overlap in stripes.
	var colors := PackedColorArray([color])
	var inner := radius - width * 0.5
	var outer := radius + width * 0.5
	for index: int in steps:
		var here := directions[index]
		var next := directions[index + 1]
		canvas.draw_primitive(PackedVector2Array([
			center + here * inner, center + here * outer, center + next * outer, center + next * inner,
		]), colors, _no_uvs)


## A filled polygon without outline, as batched triangles.
func fill_shape(points: PackedVector2Array, color: Color) -> void:
	var colors := PackedColorArray([color])
	# A convex shape keeps all its corners on its hull and fans out in quads.
	if Geometry2D.convex_hull(points).size() == points.size() + 1:
		_fill_fan(points, colors)
		return
	var triangles := Geometry2D.triangulate_polygon(points)
	for index: int in range(0, triangles.size(), 3):
		var last := points[triangles[index + 2]]
		# A quad with its last corner doubled: switching between triangles
		# and quads would split the batch.
		canvas.draw_primitive(PackedVector2Array([points[triangles[index]], points[triangles[index + 1]], last, last]), colors, _no_uvs)


## A filled circle without outline, as batched quads.
func fill_disc(center: Vector2, radius: float, color: Color) -> void:
	var ring := Transform2D(0.0, Vector2(radius, radius), 0.0, center) * _get_ring(_sides_for(radius))
	_fill_fan(ring, PackedColorArray([color]))


# An outlined circle or ellipse from the cached unit ring of `sides` sides.
func _fill_oval(center: Vector2, radii: Vector2, color: Color, sides: int) -> void:
	var shape := Transform2D(0.0, radii, 0.0, center)
	_fill_fan(shape * _get_ring(sides), PackedColorArray([color]))
	canvas.draw_multiline(shape * _get_ring_pairs(sides), Palette.INK, UnitPainter.OUTLINE_PX)


func _fill_fan(points: PackedVector2Array, colors: PackedColorArray) -> void:
	var count := points.size()
	var index := 1
	while index + 2 < count:
		canvas.draw_primitive(PackedVector2Array([points[0], points[index], points[index + 1], points[index + 2]]), colors, _no_uvs)
		index += 2
	if index + 1 < count:
		canvas.draw_primitive(PackedVector2Array([points[0], points[index], points[index + 1], points[index + 1]]), colors, _no_uvs)


# Segment pairs along an open path whose inner ends run on by `run_on`.
static func _joined_pairs(points: PackedVector2Array, run_on: float) -> PackedVector2Array:
	var pairs := _pairs_of(points)
	for index: int in range(1, points.size() - 1):
		var before := pairs[index * 2 - 1] - pairs[index * 2 - 2]
		var after := pairs[index * 2 + 1] - pairs[index * 2]
		pairs[index * 2 - 1] += before.normalized() * run_on
		pairs[index * 2] -= after.normalized() * run_on
	return pairs


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


static func _get_ring(sides: int) -> PackedVector2Array:
	if not _rings.has(sides):
		_rings[sides] = ellipse(Vector2.ZERO, 1.0, 1.0, sides)
	return _rings[sides]


static func _get_ring_pairs(sides: int) -> PackedVector2Array:
	if not _ring_pairs.has(sides):
		var ring := _get_ring(sides)
		ring.append(ring[0])
		_ring_pairs[sides] = _pairs_of(ring)
	return _ring_pairs[sides]
