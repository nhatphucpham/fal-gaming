class_name RigMesh
extends RefCounted
## Triangles with a colour per vertex, built once from RigPaths with the
## sketch's canvas operations (fill, stroke, filled rectangles, clipping,
## dashes, global alpha, a transform stack). Piece meshes are cached and
## only transformed per frame; RigPainter puts a whole figure into one
## triangle array (one draw call). Colours go through `palette` (a race's
## recolouring) as they are added.
## [codeblock]
## var mesh := RigMesh.new()
## mesh.shape(RigPath.new().arc(0, 0, 2, 0, 7), RigPalette.GOLD)
## canvas_points.append_array(bone_transform * mesh.points)
## [/codeblock]

## The soft edge every line gets (antialiased without a draw call), in
## screen pixels; see `feather`.
const FEATHER_PX: float = 0.75
## Feather sizes are kept for whole pixels-per-unit from 1 to this.
const FEATHER_LEVELS: int = 5
const OUTLINE_WIDTH: float = 2.2
const FLASH_LEVELS: int = 8
const DISC_SIDES: int = 10

var points := PackedVector2Array()
var colors := PackedColorArray()
## Colour swaps applied to every colour added (a race's palette).
var palette: Dictionary = {}
## Multiplies the alpha of colours added (the canvas's globalAlpha).
var alpha: float = 1.0
## The soft edge of lines in mesh units: about FEATHER_PX on screen at the
## scale the mesh is drawn (see feather_for).
var feather: float = FEATHER_PX
## Where added shapes go: composed with push() and pop().
var transform := Transform2D.IDENTITY

var _stack: Array[Transform2D] = []
var _tinted: Dictionary[int, PackedColorArray] = {}

static var _disc := PackedVector2Array()


## The feather level for a mesh drawn `pixels_per_unit` large: whole
## steps from 1 to FEATHER_LEVELS, so cached meshes stay few.
static func feather_level(pixels_per_unit: float) -> int:
	return clampi(roundi(pixels_per_unit), 1, FEATHER_LEVELS)


## The feather in mesh units for `level` (see feather_level).
static func feather_for(level: int) -> float:
	return FEATHER_PX / level


func push(local: Transform2D) -> void:
	_stack.append(transform)
	transform = transform * local


func pop() -> void:
	transform = _stack.pop_back()


func color_of(color: Color) -> Color:
	var out: Color = palette.get(color, color)
	out.a *= alpha
	return out


## The sketch's `shp`: an ink stroke of `line_width`, then the fill over it.
func shape(path: RigPath, fill_color: Color, line_width: float = OUTLINE_WIDTH) -> void:
	stroke(path, RigPalette.INK, line_width)
	fill(path, fill_color)


## A fill with a stroke of `line_width` over it (the sketch's
## `fill(); stroke()`, thin lines that stay whole).
func fill_stroke(path: RigPath, fill_color: Color, line_width: float) -> void:
	fill(path, fill_color)
	stroke(path, RigPalette.INK, line_width)


func fill(path: RigPath, color: Color) -> void:
	path.done()
	var tint := color_of(color)
	for polyline: PackedVector2Array in path.polylines:
		_add_polygon(polyline, tint)


## Strokes every subpath; `round_caps` rounds the ends of open ones.
func stroke(path: RigPath, color: Color, width: float, round_caps: bool = false) -> void:
	path.done()
	var tint := color_of(color)
	for index: int in path.polylines.size():
		_add_polyline(path.polylines[index], path.closed[index], tint, width, round_caps)


## Fills the parts of `path` inside `clip` (a polygon).
func fill_clipped(path: RigPath, clip: PackedVector2Array, color: Color) -> void:
	path.done()
	var tint := color_of(color)
	for polyline: PackedVector2Array in path.polylines:
		for part: PackedVector2Array in Geometry2D.intersect_polygons(polyline, clip):
			_add_polygon(part, tint)


## Strokes the parts of `path` inside `clip` (a polygon).
func stroke_clipped(path: RigPath, clip: PackedVector2Array, color: Color, width: float) -> void:
	path.done()
	var tint := color_of(color)
	for index: int in path.polylines.size():
		var polyline := path.polylines[index]
		if path.closed[index]:
			polyline = polyline.duplicate()
			polyline.append(polyline[0])
		for part: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(polyline, clip):
			_add_polyline(part, false, tint, width, false)


## Strokes `path` in dashes of `dash` with `gap` between, round-ended.
func stroke_dashed(path: RigPath, color: Color, width: float, dash: float, gap: float) -> void:
	path.done()
	var tint := color_of(color)
	for polyline: PackedVector2Array in path.polylines:
		for part: PackedVector2Array in _dashes(polyline, dash, gap):
			_add_polyline(part, false, tint, width, true)


func fill_rect(x: float, y: float, width: float, height: float, color: Color) -> void:
	_add_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + width, y), Vector2(x + width, y + height), Vector2(x, y + height)]), color_of(color))


func stroke_rect(x: float, y: float, width: float, height: float, color: Color, line_width: float) -> void:
	stroke(RigPath.new().rect(x, y, width, height), color, line_width)


## A filled circle without an outline (round line caps, glow rings).
func disc(center: Vector2, radius: float, color: Color) -> void:
	var fan := _get_disc()
	points.append_array((transform * Transform2D(0.0, Vector2(radius, radius), 0.0, center)) * fan)
	_add_colors(color_of(color), fan.size())


## Adds `other` placed by `local` (in this mesh's current frame).
func append_mesh(other: RigMesh, local: Transform2D = Transform2D.IDENTITY) -> void:
	points.append_array((transform * local) * other.points)
	colors.append_array(other.colors)


## The colours blended toward white by `flash` 0..1 like the sketch's hit
## flash (80% at most), in a few cached steps.
func get_colors(flash: float) -> PackedColorArray:
	var level := roundi(clampf(flash, 0.0, 1.0) * FLASH_LEVELS)
	if level == 0:
		return colors
	if not _tinted.has(level):
		var amount := 0.8 * level / FLASH_LEVELS
		var tinted := colors.duplicate()
		for index: int in tinted.size():
			var color := tinted[index]
			tinted[index] = Color(color.lerp(Color.WHITE, amount), color.a)
		_tinted[level] = tinted
	return _tinted[level]


func _add_polygon(polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(polygon)
	var triangles := PackedVector2Array()
	if indices.is_empty():
		# A shape that crosses itself: fan it out like a canvas fill would.
		for index: int in range(1, polygon.size() - 1):
			triangles.append_array([polygon[0], polygon[index], polygon[index + 1]])
	else:
		triangles.resize(indices.size())
		for index: int in indices.size():
			triangles[index] = polygon[indices[index]]
	points.append_array(transform * triangles)
	_add_colors(color, triangles.size())


# Segments as quads; inner joints run on by half the width to close them.
# Each side also gets a feather that fades to transparent.
func _add_polyline(polyline: PackedVector2Array, is_closed: bool, color: Color, width: float, round_caps: bool) -> void:
	var count := polyline.size()
	if count < 2:
		return
	var segments := count if is_closed else count - 1
	var half := width * 0.5
	var quads := PackedVector2Array()
	var quad_colors := PackedColorArray()
	var clear := Color(color, 0.0)
	for index: int in segments:
		var from := polyline[index]
		var to := polyline[(index + 1) % count]
		var along := (to - from).normalized()
		if along == Vector2.ZERO:
			continue
		var start := from - along * (half if is_closed or index > 0 else 0.0)
		var end := to + along * (half if is_closed or index < segments - 1 else 0.0)
		var side := along.orthogonal() * half
		quads.append_array([start - side, end - side, end + side, start - side, end + side, start + side])
		for corner: int in 6:
			quad_colors.append(color)
		var outer := along.orthogonal() * (half + feather)
		quads.append_array([start + side, end + side, end + outer, start + side, end + outer, start + outer])
		quads.append_array([start - side, end - side, end - outer, start - side, end - outer, start - outer])
		quad_colors.append_array([color, color, clear, color, clear, clear, color, color, clear, color, clear, clear])
	points.append_array(transform * quads)
	colors.append_array(quad_colors)
	if round_caps and not is_closed:
		disc_raw(polyline[0], half, color)
		disc_raw(polyline[count - 1], half, color)


## A disc in a colour already through the palette.
func disc_raw(center: Vector2, radius: float, color: Color) -> void:
	var fan := _get_disc()
	points.append_array((transform * Transform2D(0.0, Vector2(radius, radius), 0.0, center)) * fan)
	_add_colors(color, fan.size())


func _add_colors(color: Color, count: int) -> void:
	var block := PackedColorArray()
	block.resize(count)
	block.fill(color)
	colors.append_array(block)


static func _dashes(polyline: PackedVector2Array, dash: float, gap: float) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = []
	var current := PackedVector2Array([polyline[0]])
	var is_drawing := true
	var left := dash
	for index: int in range(1, polyline.size()):
		var from := polyline[index - 1]
		var to := polyline[index]
		var length := from.distance_to(to)
		var at := 0.0
		while length - at > left:
			at += left
			var point := from.lerp(to, at / length)
			if is_drawing:
				current.append(point)
				parts.append(current)
			current = PackedVector2Array([point])
			is_drawing = not is_drawing
			left = gap if not is_drawing else dash
		left -= length - at
		if is_drawing:
			current.append(to)
		else:
			current = PackedVector2Array([to])
	if is_drawing and current.size() >= 2:
		parts.append(current)
	return parts


static func _get_disc() -> PackedVector2Array:
	if _disc.is_empty():
		for index: int in DISC_SIDES:
			var first := TAU * index / DISC_SIDES
			var second := TAU * (index + 1) / DISC_SIDES
			_disc.append_array([Vector2.ZERO, Vector2(cos(first), sin(first)), Vector2(cos(second), sin(second))])
	return _disc
