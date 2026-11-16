class_name TacticsMapView
extends Control
## The tactics map: terrain (drawn once into a texture, so the whole board
## costs one draw call), zones, selection marks, enemy intents, unit tokens
## and floating text, each its own layer that redraws only when its content
## changes, so an idle map draws nothing new. A tap
## (press and release on the same cell) emits cell_tapped. It shows what
## it is told; it never reads or changes the battle.
## [codeblock]
## map.setup(battle, catalog)
## map.cell_tapped.connect(_on_cell_tapped)
## map.set_marks({"reachable": cells, "selected": Vector2i(3, 13)})
## [/codeblock]

signal cell_tapped(cell: Vector2i)

const CELL_PX: float = 58.0
## How far a press may slide and still count as a tap, in pixels.
const TAP_SLOP_PX: float = 24.0

const ZONE_COLORS: Dictionary[StringName, Color] = {
	&"zone.fire": Color("ff7a2a"), &"zone.wind": Color("bfe8ff"),
}
const REACH_COLOR := Color(0.36, 0.62, 1.0, 0.42)
const THREAT_COLOR := Color(1.0, 0.36, 0.24, 0.3)
const ATTACK_COLOR := Color("ff4a3a")
const SKILL_COLOR := Color(1.0, 0.82, 0.3, 0.45)
const AREA_COLOR := Color(1.0, 0.5, 0.2, 0.5)
const INTENT_COLOR := Color("ffb347")

var map_width: int = 0
var map_height: int = 0
var _terrain_ids: Array[StringName] = []
var _objective := Vector2i(-1, -1)
var _marks: Dictionary = {}
var _intents: Array = []
var _zones: Array = []
var _pieces: Dictionary[int, TacticsPieceView] = {}
var _terrain_viewport: SubViewport
var _terrain_layer: _Layer
var _terrain_image: TextureRect
var _zone_layer: _Layer
var _mark_layer: _Layer
var _intent_layer: _Layer
var _piece_layer: Node2D
var _fx_layer: Control
var _press_cell := Vector2i(-1, -1)
var _press_position := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The terrain is painted once in its own viewport; the map shows the
	# result as a texture.
	_terrain_viewport = SubViewport.new()
	_terrain_viewport.disable_3d = true
	_terrain_viewport.transparent_bg = true
	_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_terrain_viewport)
	_terrain_layer = _Layer.new()
	_terrain_layer.drawer = _draw_terrain
	_terrain_viewport.add_child(_terrain_layer)
	_terrain_image = TextureRect.new()
	_terrain_image.texture = _terrain_viewport.get_texture()
	_terrain_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_terrain_image.stretch_mode = TextureRect.STRETCH_SCALE
	_terrain_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_terrain_image)
	_zone_layer = _add_layer(_draw_zones)
	_mark_layer = _add_layer(_draw_marks)
	_piece_layer = Node2D.new()
	_piece_layer.y_sort_enabled = true
	add_child(_piece_layer)
	_intent_layer = _add_layer(_draw_intents)
	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)


## Reads the map's terrain once and sizes the view to it.
func setup(battle: TacticsBattle, objective: Vector2i) -> void:
	map_width = battle.get_map_width()
	map_height = battle.get_map_height()
	_objective = objective
	_terrain_ids.clear()
	for row: int in map_height:
		for col: int in map_width:
			_terrain_ids.append(battle.get_terrain_id(Vector2i(col, row)))
	custom_minimum_size = Vector2(map_width, map_height) * CELL_PX
	size = custom_minimum_size
	_paint_terrain()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and map_width > 0:
		_paint_terrain()


# Renders the terrain once, at the screen's pixel scale so it stays sharp
# on a phone where the 720-wide layout is stretched.
func _paint_terrain() -> void:
	if not is_inside_tree():
		return
	var pixel_scale := clampf(get_viewport().get_final_transform().get_scale().x, 1.0, 3.0)
	var board := Vector2(map_width, map_height) * CELL_PX
	_terrain_viewport.size = Vector2i((board * pixel_scale).ceil())
	_terrain_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(pixel_scale, pixel_scale))
	_terrain_layer.size = board
	_terrain_layer.queue_redraw()
	_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The centre of a cell in this view's coordinates.
func cell_to_local(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_PX


## The cell under a local point, or (-1, -1) off the map.
func local_to_cell(point: Vector2) -> Vector2i:
	var cell := Vector2i(floori(point.x / CELL_PX), floori(point.y / CELL_PX))
	return cell if is_on_map(cell) else Vector2i(-1, -1)


func is_on_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_width and cell.y < map_height


## The terrain id of a cell; empty off the map.
func get_terrain_at(cell: Vector2i) -> StringName:
	return _terrain_ids[cell.y * map_width + cell.x] if is_on_map(cell) else &""


func get_piece_layer() -> Node2D:
	return _piece_layer


func get_fx_layer() -> Control:
	return _fx_layer


func add_piece(piece: TacticsPieceView, cell: Vector2i) -> void:
	_pieces[piece.unit_index] = piece
	piece.position = cell_to_local(cell)
	_piece_layer.add_child(piece)


func get_piece(unit: int) -> TacticsPieceView:
	return _pieces.get(unit, null)


func get_pieces() -> Array[TacticsPieceView]:
	var pieces: Array[TacticsPieceView] = []
	pieces.assign(_pieces.values())
	return pieces


## Selection marks; every key is optional: `reachable`, `attackable`,
## `threat` (where an enemy can go), `skill_cells`, `area` (cells),
## `selected` (a cell), `target` (a cell), `path` (cells),
## `ghosts` ([{cell, from, side, is_leader}]).
func set_marks(marks: Dictionary) -> void:
	_marks = marks
	_mark_layer.queue_redraw()


func get_marks() -> Dictionary:
	return _marks


## Enemy intents: [{from, to, action, target_cell}]; empty hides them.
func set_intents(intents: Array) -> void:
	_intents = intents
	_intent_layer.queue_redraw()


func get_intents() -> Array:
	return _intents


## Active zones: [{zone, cells}] as get_zones() gives them.
func set_zones(zones: Array) -> void:
	_zones = zones
	_zone_layer.queue_redraw()


func get_zones() -> Array:
	return _zones


## Text rising from a cell and fading, such as a damage number.
func float_text(at: Vector2, text: String, color: Color, font_px: int = 26, rise_px: float = 36.0, seconds: float = 0.9) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_px)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Palette.INK)
	label.add_theme_constant_override(&"outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(label)
	label.reset_size()
	# Kept inside the map so a number at the edge is not cut off, and above
	# any text still rising from the same spot.
	var x := clampf(at.x - label.size.x / 2.0, 0.0, maxf(size.x - label.size.x, 0.0))
	var y := at.y - label.size.y
	for other: Node in _fx_layer.get_children():
		var rising := other as Label
		if rising != null and rising != label and absf(rising.position.x + rising.size.x / 2.0 - at.x) < CELL_PX and absf(rising.position.y - y) < label.size.y:
			y = minf(y, rising.position.y - label.size.y + 4.0)
	label.position = Vector2(x, y)
	var tween := label.create_tween()
	tween.tween_property(label, ^"position:y", label.position.y - rise_px, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, ^"modulate:a", 0.0, seconds * 0.4).set_delay(seconds * 0.6)
	tween.tween_callback(label.queue_free)
	return label


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_cell = local_to_cell(button.position)
		_press_position = button.position
		return
	var cell := local_to_cell(button.position)
	if cell == _press_cell and button.position.distance_to(_press_position) <= TAP_SLOP_PX and is_on_map(cell):
		accept_event()
		cell_tapped.emit(cell)
	_press_cell = Vector2i(-1, -1)


func _add_layer(drawer: Callable) -> _Layer:
	var layer := _Layer.new()
	layer.drawer = drawer
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	return layer


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * CELL_PX, Vector2(CELL_PX, CELL_PX))


func _draw_terrain(canvas: Control) -> void:
	for index: int in _terrain_ids.size():
		var cell := Vector2i(index % map_width, index / map_width)
		TacticsPainter.draw_terrain(canvas, _terrain_ids[index], _cell_rect(cell))
	for col: int in map_width + 1:
		canvas.draw_line(Vector2(col * CELL_PX, 0), Vector2(col * CELL_PX, map_height * CELL_PX), TacticsPainter.GRID, 1.0)
	for row: int in map_height + 1:
		canvas.draw_line(Vector2(0, row * CELL_PX), Vector2(map_width * CELL_PX, row * CELL_PX), TacticsPainter.GRID, 1.0)
	if is_on_map(_objective):
		var rect := _cell_rect(_objective).grow(-2.0)
		canvas.draw_rect(rect, Palette.GOLD, false, 4.0)
		var pole := rect.position + Vector2(rect.size.x * 0.72, rect.size.y * 0.86)
		canvas.draw_line(pole, pole + Vector2(0, -40), Palette.INK, 3.0)
		canvas.draw_colored_polygon(PackedVector2Array([pole + Vector2(0, -40), pole + Vector2(-20, -33), pole + Vector2(0, -26)]), Palette.GOLD)
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(map_width, map_height) * CELL_PX), Palette.INK, false, 3.0)


func _draw_zones(canvas: Control) -> void:
	for zone: Dictionary in _zones:
		var color: Color = ZONE_COLORS.get(zone["zone"], Color(0.8, 0.8, 0.8))
		for cell: Vector2i in zone["cells"]:
			if not is_on_map(cell):
				continue
			var rect := _cell_rect(cell)
			canvas.draw_rect(rect, Color(color, 0.32))
			canvas.draw_rect(rect.grow(-3.0), Color(color, 0.85), false, 2.0)
			_draw_zone_motif(canvas, zone["zone"], rect, color)


func _draw_zone_motif(canvas: Control, zone_id: StringName, rect: Rect2, color: Color) -> void:
	var c := rect.get_center()
	if zone_id == &"zone.fire":
		canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 18), c + Vector2(-8, 18), c + Vector2(-12, 4)]), color)
		canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(10, 18), c + Vector2(18, 18), c + Vector2(14, 6)]), color)
	else:
		canvas.draw_arc(c + Vector2(-10, -14), 8.0, PI, TAU * 0.95, 8, color, 2.0)
		canvas.draw_arc(c + Vector2(12, 14), 7.0, PI, TAU * 0.95, 8, color, 2.0)


func _draw_marks(canvas: Control) -> void:
	for cell: Vector2i in _marks.get("reachable", []):
		canvas.draw_rect(_cell_rect(cell).grow(-2.0), REACH_COLOR)
	for cell: Vector2i in _marks.get("threat", []):
		canvas.draw_rect(_cell_rect(cell).grow(-2.0), THREAT_COLOR)
	for cell: Vector2i in _marks.get("skill_cells", []):
		canvas.draw_rect(_cell_rect(cell).grow(-2.0), SKILL_COLOR)
	for cell: Vector2i in _marks.get("area", []):
		if is_on_map(cell):
			canvas.draw_rect(_cell_rect(cell).grow(-1.0), AREA_COLOR)
	for cell: Vector2i in _marks.get("attackable", []):
		var rect := _cell_rect(cell).grow(-3.0)
		canvas.draw_rect(rect, ATTACK_COLOR, false, 4.0)
	var selected: Vector2i = _marks.get("selected", Vector2i(-1, -1))
	if is_on_map(selected):
		canvas.draw_rect(_cell_rect(selected).grow(-1.5), Palette.GOLD, false, 4.0)
	var target: Vector2i = _marks.get("target", Vector2i(-1, -1))
	if is_on_map(target):
		var c := cell_to_local(target)
		canvas.draw_arc(c, CELL_PX * 0.46, 0.0, TAU, 24, ATTACK_COLOR, 4.0)
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			canvas.draw_line(c + direction * CELL_PX * 0.3, c + direction * CELL_PX * 0.52, ATTACK_COLOR, 4.0)
	var path: Array = _marks.get("path", [])
	if path.size() > 1:
		var points := PackedVector2Array()
		for cell: Vector2i in path:
			points.append(cell_to_local(cell))
		canvas.draw_polyline(points, Color(Palette.CREAM, 0.9), 5.0, true)
	for ghost: Dictionary in _marks.get("ghosts", []):
		var from: Vector2i = ghost.get("from", ghost["cell"])
		if from != ghost["cell"]:
			_draw_dashes(canvas, cell_to_local(from), cell_to_local(ghost["cell"]), Color(Palette.CREAM, 0.7), 2.0)
		TacticsPainter.draw_ghost(canvas, cell_to_local(ghost["cell"]) + TacticsPieceView.TOKEN_OFFSET, ghost["side"], ghost["is_leader"])


func _draw_intents(canvas: Control) -> void:
	for intent: Dictionary in _intents:
		var from := cell_to_local(intent["from"])
		var to := cell_to_local(intent["to"])
		if intent["from"] != intent["to"]:
			_draw_dashes(canvas, from, to, INTENT_COLOR, 4.0)
		canvas.draw_arc(to, CELL_PX * 0.4, 0.0, TAU, 24, INTENT_COLOR, 4.0)
		var target: Vector2i = intent["target_cell"]
		var icon_at := to + Vector2(CELL_PX * 0.32, -CELL_PX * 0.32)
		# Only an attack or a skill aims at someone; a wait just marches.
		if intent["action"] != &"wait" and is_on_map(target) and target != intent["to"]:
			var aim := cell_to_local(target)
			canvas.draw_line(to, aim, Color(ATTACK_COLOR, 0.85), 3.0)
			icon_at = aim + Vector2(-CELL_PX * 0.32, -CELL_PX * 0.32)
		TacticsPainter.draw_intent_icon(canvas, intent["action"], icon_at, 12.0)


func _draw_dashes(canvas: Control, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var length := from.distance_to(to)
	var step := 12.0
	var direction := (to - from) / maxf(length, 0.001)
	var travelled := 0.0
	while travelled < length:
		var end := minf(travelled + step * 0.6, length)
		canvas.draw_line(from + direction * travelled, from + direction * end, color, width)
		travelled += step


## A drawing layer: calls its drawer when it redraws.
class _Layer extends Control:
	var drawer: Callable

	func _draw() -> void:
		drawer.call(self)
