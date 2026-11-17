class_name TacticsMapView
extends Control
## The tactics map: a window onto the board that zooms and pans. The board
## holds the terrain (drawn once into a texture, so the whole board costs
## one draw call), zones, selection marks, enemy intents, unit tokens and
## floating text, each its own layer that redraws only when its content
## changes (shapes recorded into one triangle array, one draw call each); moving the camera only moves the board, so an idle map draws
## nothing new. Under fog of war one small texture (a pixel per cell,
## smoothly filtered) darkens what is not seen and tints the night; it is
## rewritten only when what is seen changes, with a short blend. Enemies
## remembered where they were last seen show as dim "?" tokens. One finger drags to pan, two pinch to zoom; a tap (press
## and release on one cell) emits cell_tapped; a press on a cell listed in
## `hold_cells` follows the finger instead (cell_held while it moves,
## hold_released where it lifts). It shows what it is told; it never reads
## or changes the battle. Board coordinates are those of cell_to_local().
## [codeblock]
## map.setup(battle, objective_cell)
## map.cell_tapped.connect(_on_cell_tapped)
## map.set_marks({"reachable": cells, "selected": Vector2i(3, 13)})
## map.follow(map.cell_to_local(Vector2i(3, 13)))
## [/codeblock]

signal cell_tapped(cell: Vector2i)
## A press on one of `hold_cells`, then each new cell under the finger.
signal cell_held(cell: Vector2i)
## The finger of a hold lifted over this cell ((-1, -1) off the map).
signal hold_released(cell: Vector2i)
## A pinch or drag stopped a hold before it was released.
signal hold_cancelled()
## The camera came to rest after a glide, a jump, a pan or a pinch.
signal camera_settled()

const CELL_PX: float = 58.0
## How far a press may slide and still count as a tap, in pixels.
const TAP_SLOP_PX: float = 24.0
## Columns the default zoom fits across the view: 8 on a 720-wide layout
## gives 90-px cells, 45 px on a 360-px phone.
const DEFAULT_COLUMNS: float = 8.0
const MAX_ZOOM_OVER_DEFAULT: float = 1.4
const CAMERA_SEC: float = 0.28
## The camera follows a point only once it is this close to the edge.
const FOLLOW_MARGIN_PX: float = 90.0
## The terrain texture is baked for at most this many pixels per board pixel.
const MAX_BAKE_SCALE: float = 2.5

const ZONE_COLORS: Dictionary[StringName, Color] = {
	&"zone.fire": Color("ff7a2a"), &"zone.wind": Color("bfe8ff"),
}
const REACH_COLOR := Color(0.36, 0.62, 1.0, 0.42)
const THREAT_COLOR := Color(1.0, 0.36, 0.24, 0.3)
const ATTACK_COLOR := Color("ff4a3a")
const SKILL_COLOR := Color(1.0, 0.82, 0.3, 0.45)
const AREA_COLOR := Color(1.0, 0.5, 0.2, 0.5)
const INTENT_COLOR := Color("ffb347")
## Fog of war: never seen, seen before, the night over what is seen (its
## alpha scaled by the time of day's darkness) and the warm light of a lit
## cell at night.
const FOG_NEVER_COLOR := Color(0.04, 0.05, 0.08, 0.88)
const FOG_SEEN_COLOR := Color(0.07, 0.08, 0.12, 0.55)
const NIGHT_COLOR := Color(0.02, 0.04, 0.16, 0.62)
const LIGHT_COLOR := Color(1.0, 0.7, 0.32, 0.1)
## A fog change blends over this long unless told otherwise (a walk blends
## over its own frames).
const FOG_BLEND_SEC: float = 0.25
const EDGE_MARK_PX: float = 30.0

var map_width: int = 0
var map_height: int = 0
## Cells where a press starts a hold (the screen sets them).
var hold_cells: Array = []
## Tests: camera moves end at once.
var is_instant: bool = false
var _terrain_ids: Array[StringName] = []
var _objective := Vector2i(-1, -1)
var _marks: Dictionary = {}
var _intents: Array = []
var _zones: Array = []
var _pieces: Dictionary[int, TacticsPieceView] = {}
var _board: Control
var _terrain_viewport: SubViewport
var _terrain_layer: _Layer
var _terrain_image: TextureRect
var _fog_rect: TextureRect
var _fog_image: Image
var _fog_texture: ImageTexture
## The fog colour of each cell now and the blend toward new ones.
var _fog_colors := PackedColorArray()
var _fog_from := PackedColorArray()
var _fog_to := PackedColorArray()
## The cells the running blend changes; only they are written each frame.
var _fog_blend_cells := PackedInt32Array()
var _fog_tween: Tween
var _fog_states := PackedByteArray()
var _lit_cells := PackedByteArray()
var _darkness: float = 0.0
## How many times the fog texture was rewritten, for tests.
var fog_write_count: int = 0
## Fog changes begun (a blend, or one write when instant), for tests.
var fog_change_count: int = 0
var _memory_layer: _Layer
var _last_seen: Array = []
## Sites as our side knows them and the objective's marks (exits, the
## road, the convoy's path, where enemy waves come in), over the fog.
var _site_layer: _Layer
var _sites: Array = []
var _objective_marks: Dictionary = {}
var _edge_layer: _Layer
var _edge_cells: Array = []
var _zone_layer: _Layer
var _mark_layer: _Layer
var _intent_layer: _Layer
var _piece_layer: Node2D
var _fx_layer: Control
var _whole_button: PressButton
var _zoom: float = 1.0
var _is_whole_map: bool = false
var _camera_tween: Tween
var _baked_scale: float = 0.0
## Whether the board fills the whole view: then the view draws no backdrop
## under it (one full-screen fill less a frame).
var _is_view_covered: bool = false
## Until the view first has a size, the default zoom waits, with the board
## point it should centre.
var _is_laid_out: bool = false
var _first_focus := Vector2(-1, -1)
## Input: the press (view coordinates), what it became, and the touches
## down for a pinch.
enum _Gesture {NONE, TAP, HOLD, PAN, PINCH}
var _gesture: _Gesture = _Gesture.NONE
var _press_cell := Vector2i(-1, -1)
var _press_position := Vector2.ZERO
var _held_cell := Vector2i(-1, -1)
var _touches: Dictionary[int, Vector2] = {}
var _pinch_distance: float = 0.0
var _pinch_zoom: float = 1.0
var _pinch_middle := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_board = Control.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	# The terrain is painted once in its own viewport; the board shows the
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
	_board.add_child(_terrain_image)
	_fog_rect = TextureRect.new()
	_fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fog_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog_rect.visible = false
	_board.add_child(_fog_rect)
	_site_layer = _add_layer(_draw_sites)
	_zone_layer = _add_layer(_draw_zones)
	_mark_layer = _add_layer(_draw_marks)
	_memory_layer = _add_layer(_draw_last_seen)
	_piece_layer = Node2D.new()
	_piece_layer.y_sort_enabled = true
	_board.add_child(_piece_layer)
	_intent_layer = _add_layer(_draw_intents)
	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_fx_layer)
	# Marks pointing at our wavering soldiers outside the view, in view
	# coordinates over the board.
	_edge_layer = _Layer.new()
	_edge_layer.drawer = _draw_edge_marks
	_edge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_edge_layer)
	_whole_button = PressButton.new()
	_whole_button.text = "TACTICS_WHOLE_MAP"
	_whole_button.focus_mode = Control.FOCUS_NONE
	_whole_button.custom_minimum_size = Vector2(150, 88)
	_whole_button.add_theme_font_size_override(&"font_size", 22)
	_whole_button.anchor_left = 1.0
	_whole_button.anchor_right = 1.0
	_whole_button.offset_left = -158.0
	_whole_button.offset_right = -8.0
	_whole_button.offset_top = 8.0
	_whole_button.offset_bottom = 96.0
	_whole_button.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		toggle_whole_map())
	add_child(_whole_button)


## Reads the map's terrain once and shows it at the default zoom.
func setup(battle: TacticsBattle, objective: Vector2i) -> void:
	map_width = battle.get_map_width()
	map_height = battle.get_map_height()
	_objective = objective
	_terrain_ids.clear()
	for row: int in map_height:
		for col: int in map_width:
			_terrain_ids.append(battle.get_terrain_id(Vector2i(col, row)))
	_board.size = get_board_size()
	_is_laid_out = false
	_lay_out()
	_paint_terrain()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and map_width > 0:
		_paint_terrain()
	elif what == NOTIFICATION_RESIZED and map_width > 0:
		if not _lay_out():
			_zoom = get_whole_zoom() if _is_whole_map else clampf(_zoom, get_whole_zoom(), get_max_zoom())
			_apply_camera(_board.position, _zoom)
		_paint_terrain()


# The first time the view has a size: the default zoom, centred on the
# point asked for (the board's centre if none). True if it laid out now.
func _lay_out() -> bool:
	if _is_laid_out or size.x <= 0.0 or size.y <= 0.0:
		return false
	_is_laid_out = true
	var point := _first_focus if _first_focus.x >= 0.0 else get_board_size() / 2.0
	_zoom = get_default_zoom()
	_apply_camera(size / 2.0 - _snap_to_columns(point) * _zoom, _zoom)
	return true


## Centres a board point at once (before the first layout too).
func center_on(board_point: Vector2) -> void:
	if not _is_laid_out:
		_first_focus = board_point
		return
	_move_camera(size / 2.0 - _snap_to_columns(board_point) * _zoom, _zoom, false)


# At a zoom that fits a whole number of columns across the view, a point
# to centre moves across to the nearest line between columns, so the
# view's edges cut no column (and no token) in half.
func _snap_to_columns(board_point: Vector2) -> Vector2:
	var columns := size.x / (CELL_PX * _zoom)
	if absf(columns - roundf(columns)) > 0.01:
		return board_point
	var shift := 0.0 if int(roundf(columns)) % 2 == 0 else 0.5
	return Vector2((roundf(board_point.x / CELL_PX - shift) + shift) * CELL_PX, board_point.y)


func get_board_size() -> Vector2:
	return Vector2(map_width, map_height) * CELL_PX


## The zoom that fits DEFAULT_COLUMNS across the view (never below the
## whole map).
func get_default_zoom() -> float:
	if size.x <= 0.0:
		return 1.0
	return maxf(size.x / (minf(DEFAULT_COLUMNS, map_width) * CELL_PX), get_whole_zoom())


## The zoom that shows the whole board.
func get_whole_zoom() -> float:
	var board := get_board_size()
	if board.x <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	return minf(size.x / board.x, size.y / board.y)


func get_max_zoom() -> float:
	return get_default_zoom() * MAX_ZOOM_OVER_DEFAULT


func get_zoom() -> float:
	return _zoom


## A cell's size on screen now, in layout pixels.
func get_cell_px() -> float:
	return CELL_PX * _zoom


func is_whole_map() -> bool:
	return _is_whole_map


## The board's offset in the view (its top-left corner).
func get_camera_offset() -> Vector2:
	return _board.position


## Switches between the whole map and the default zoom around the centre.
func toggle_whole_map() -> void:
	_is_whole_map = not _is_whole_map
	_whole_button.text = "TACTICS_ZOOM_IN" if _is_whole_map else "TACTICS_WHOLE_MAP"
	var center := view_to_board(size / 2.0)
	zoom_to(get_whole_zoom() if _is_whole_map else get_default_zoom(), center, true)


## Zooms so that `board_point` sits at the view's centre.
func zoom_to(zoom: float, board_point: Vector2, smooth: bool) -> void:
	var target_zoom := clampf(zoom, get_whole_zoom(), get_max_zoom())
	_move_camera(size / 2.0 - board_point * target_zoom, target_zoom, smooth)


## Brings a board point into view, smoothly, unless it is already well
## inside it; at the whole-map zoom nothing moves.
func follow(board_point: Vector2) -> void:
	var at := board_to_view(board_point)
	var inner := Rect2(Vector2.ZERO, size).grow(-FOLLOW_MARGIN_PX)
	if inner.has_point(at) or _is_whole_map:
		return
	_move_camera(size / 2.0 - _snap_to_columns(board_point) * _zoom, _zoom, true)


## Brings a board point into view only when it is outside the view now.
## What a finger just tapped is in view, so the board stays still under a
## second tap (a double tap on an enemy lands on that enemy).
func reveal(board_point: Vector2) -> void:
	if not is_in_view(board_point):
		follow(board_point)


## Is the board point inside the view now?
func is_in_view(board_point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(board_to_view(board_point))


func board_to_view(board_point: Vector2) -> Vector2:
	return _board.position + board_point * _zoom


func view_to_board(view_point: Vector2) -> Vector2:
	return (view_point - _board.position) / _zoom


func is_camera_moving() -> bool:
	return _camera_tween != null and _camera_tween.is_valid() and _camera_tween.is_running()


# Moves the board to `offset` and `zoom` (clamped to the map's edges),
# through a short tween when smooth.
func _move_camera(offset: Vector2, zoom: float, smooth: bool) -> void:
	var target := _clamp_offset(offset, zoom)
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	if not smooth or is_instant or not is_inside_tree():
		_apply_camera(target, zoom)
		camera_settled.emit()
		return
	var from_offset := _board.position
	var from_zoom := _zoom
	_camera_tween = create_tween()
	_camera_tween.tween_method(func(weight: float) -> void:
		_apply_camera(from_offset.lerp(target, weight), lerpf(from_zoom, zoom, weight), false), 0.0, 1.0, CAMERA_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_callback(camera_settled.emit)


# Writes the board's transform only when it changes (an unchanged write
# would still make the renderer draw a frame).
func _apply_camera(offset: Vector2, zoom: float, clamps: bool = true) -> void:
	_zoom = zoom
	var target := _clamp_offset(offset, zoom) if clamps else offset
	if _board.scale != Vector2(zoom, zoom):
		_board.scale = Vector2(zoom, zoom)
	if _board.position != target:
		_board.position = target
		if not _edge_cells.is_empty() or is_on_map(_objective) or _objective_marks.has("exits"):
			_edge_layer.queue_redraw()
	if _baked_scale > 0.0 and _bake_scale() > _baked_scale + 0.01:
		_paint_terrain()
	var is_covered := Rect2(target, get_board_size() * zoom).encloses(Rect2(Vector2.ZERO, size).grow(-0.5))
	if is_covered != _is_view_covered:
		_is_view_covered = is_covered
		queue_redraw()


# The backdrop around a board smaller than the view; none under a board
# that covers it.
func _draw() -> void:
	if not _is_view_covered:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKDROP)


# A board smaller than the view is centred; a larger one cannot leave a gap
# at its edges.
func _clamp_offset(offset: Vector2, zoom: float) -> Vector2:
	var board := get_board_size() * zoom
	var result := offset
	for axis: int in 2:
		if board[axis] <= size[axis]:
			result[axis] = (size[axis] - board[axis]) / 2.0
		else:
			result[axis] = clampf(offset[axis], size[axis] - board[axis], 0.0)
	return result


func _bake_scale() -> float:
	var pixel_scale := 1.0
	if is_inside_tree():
		pixel_scale = maxf(get_viewport().get_final_transform().get_scale().x, 0.5)
	return clampf(pixel_scale * maxf(_zoom, get_default_zoom()), 1.0, MAX_BAKE_SCALE)


# Renders the terrain once, at the pixel scale it shows at (the screen's
# scale times the zoom), so it stays sharp on a phone.
func _paint_terrain() -> void:
	if not is_inside_tree() or map_width == 0:
		return
	var bake := _bake_scale()
	var board := get_board_size()
	_baked_scale = bake
	_terrain_viewport.size = Vector2i((board * bake).ceil())
	_terrain_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(bake, bake))
	_terrain_layer.size = board
	_terrain_layer.queue_redraw()
	_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The centre of a cell in board coordinates.
func cell_to_local(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_PX


## The cell under a board point, or (-1, -1) off the map.
func local_to_cell(point: Vector2) -> Vector2i:
	var cell := Vector2i(floori(point.x / CELL_PX), floori(point.y / CELL_PX))
	return cell if is_on_map(cell) else Vector2i(-1, -1)


## The cell under a point of this view, or (-1, -1).
func view_to_cell(view_point: Vector2) -> Vector2i:
	return local_to_cell(view_to_board(view_point))


func is_on_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_width and cell.y < map_height


## The terrain id of a cell; empty off the map.
func get_terrain_at(cell: Vector2i) -> StringName:
	return _terrain_ids[cell.y * map_width + cell.x] if is_on_map(cell) else &""


func get_piece_layer() -> Node2D:
	return _piece_layer


func get_fx_layer() -> Control:
	return _fx_layer


func get_whole_map_button() -> PressButton:
	return _whole_button


## Redraws of the mark, zone, intent and memory layers so far, for tests.
func get_layer_draw_count() -> int:
	return _zone_layer.draw_count + _mark_layer.draw_count + _intent_layer.draw_count + _memory_layer.draw_count + _site_layer.draw_count


## Fog of war and the time of day: one state per cell (0 never seen, 1 seen
## before, 2 visible), the lit cells (1) and the night's darkness (0..1).
## An empty `states` shows everything. The texture is rewritten only when
## a colour changes, blending over `seconds` when `smooth`.
func set_fog(states: PackedByteArray, lit: PackedByteArray, darkness: float, smooth: bool, seconds: float = FOG_BLEND_SEC) -> void:
	if states == _fog_states and lit == _lit_cells and is_equal_approx(darkness, _darkness) and _fog_image != null:
		return
	_fog_states = states
	_lit_cells = lit
	_darkness = darkness
	var count := map_width * map_height
	var target := PackedColorArray()
	target.resize(count)
	var is_clear := true
	for index: int in count:
		target[index] = _fog_color(index)
		is_clear = is_clear and target[index].a <= 0.0
	if _fog_image == null or _fog_colors.size() != count:
		_fog_image = Image.create_empty(maxi(map_width, 1), maxi(map_height, 1), false, Image.FORMAT_RGBA8)
		_fog_texture = null
		_fog_colors = target.duplicate()
		_fog_colors.fill(Color(0, 0, 0, 0))
	if target == _fog_colors:
		_fog_rect.visible = not is_clear
		return
	if _fog_tween != null and _fog_tween.is_valid():
		_fog_tween.kill()
	fog_change_count += 1
	# A blend cut short starts from where it got to.
	_fog_from = _fog_colors.duplicate()
	_fog_to = target
	_fog_blend_cells.clear()
	for index: int in count:
		if _fog_from[index] != target[index]:
			_fog_blend_cells.append(index)
	_fog_rect.visible = true
	if not smooth or is_instant or not is_inside_tree():
		_blend_fog(1.0)
		_fog_rect.visible = not is_clear
		return
	_fog_tween = create_tween()
	_fog_tween.tween_method(_blend_fog, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE)
	_fog_tween.tween_callback(func() -> void: _fog_rect.visible = not is_clear)


## New fog states, the lights and the night kept, blending over `seconds`.
func update_fog_states(states: PackedByteArray, smooth: bool, seconds: float = FOG_BLEND_SEC) -> void:
	set_fog(states, _lit_cells, _darkness, smooth, seconds)


## New lights and darkness (a new time of day, a leader that moved), the
## fog states kept.
func update_night(lit: PackedByteArray, darkness: float, smooth: bool) -> void:
	set_fog(_fog_states, lit, darkness, smooth)


## The fog states shown now (empty without fog of war).
func get_fog() -> PackedByteArray:
	return _fog_states


## The fog and night colour shown over `cell` now (clear without fog).
func get_fog_color(cell: Vector2i) -> Color:
	var index := cell.y * map_width + cell.x
	if not is_on_map(cell) or index >= _fog_colors.size():
		return Color(0, 0, 0, 0)
	return _fog_colors[index]


func is_fog_blending() -> bool:
	return _fog_tween != null and _fog_tween.is_valid() and _fog_tween.is_running()


## Sites as our side knows them (TacticsBattle.get_sites()); an unknown
## one draws nothing over the terrain.
func set_sites(sites: Array) -> void:
	if sites == _sites:
		return
	_sites = sites
	_site_layer.queue_redraw()


func get_sites() -> Array:
	return _sites


## The objective's marks; every key is optional: `exits` (cells, gold),
## `enemy_exits` (cells, red), `road` (cells), `convoy_path` (cells),
## `entries` (cells where enemies come in next round).
func set_objective_marks(marks: Dictionary) -> void:
	if marks == _objective_marks:
		return
	_objective_marks = marks
	_site_layer.queue_redraw()
	_edge_layer.queue_redraw()


func get_objective_marks() -> Dictionary:
	return _objective_marks


## Enemies remembered where they were last seen: [{unit, cell, is_leader}].
func set_last_seen(ghosts: Array) -> void:
	if ghosts == _last_seen:
		return
	_last_seen = ghosts
	_memory_layer.queue_redraw()


func get_last_seen() -> Array:
	return _last_seen


## Cells of our wavering soldiers: those outside the view show a mark on
## its edge, pointing at them.
func set_edge_marks(cells: Array) -> void:
	if cells == _edge_cells:
		return
	_edge_cells = cells
	_edge_layer.queue_redraw()


## The marks shown on the view's edge now: [{cell, at, is_objective}] in
## view coordinates: our wavering soldiers and the objective outside it,
## and each edge of our exits with none of its cells in view.
func get_edge_marks() -> Array:
	var marks: Array = []
	# Room for the bubble and its pointer, which reaches 12 px past it.
	var inner := Rect2(Vector2.ZERO, size).grow(-EDGE_MARK_PX - 16.0)
	var cells: Array = _edge_cells.duplicate()
	if is_on_map(_objective):
		cells.append(_objective)
	cells.append_array(_exits_out_of_view())
	for at_index: int in cells.size():
		var cell: Vector2i = cells[at_index]
		var at := board_to_view(cell_to_local(cell))
		if Rect2(Vector2.ZERO, size).has_point(at) or not inner.has_area():
			continue
		var is_objective := at_index >= _edge_cells.size()
		marks.append({"cell": cell, "at": Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y)), "is_objective": is_objective})
	return marks


# Per edge of the map holding our exits, the exit nearest the view's
# centre when no exit of that edge is in view.
func _exits_out_of_view() -> Array:
	var nearest: Dictionary = {}
	var center := view_to_board(size / 2.0)
	for cell: Vector2i in _objective_marks.get("exits", []):
		var edge := _outward(cell)
		if is_in_view(cell_to_local(cell)):
			nearest[edge] = null
			continue
		if nearest.has(edge) and (nearest[edge] == null or cell_to_local(nearest[edge]).distance_to(center) <= cell_to_local(cell).distance_to(center)):
			continue
		nearest[edge] = cell
	return nearest.values().filter(func(cell: Variant) -> bool: return cell != null)


func _fog_color(index: int) -> Color:
	var state := 2 if _fog_states.is_empty() else int(_fog_states[index])
	# The objective is known from the map: never darker than a cell seen.
	if state == 0 and index == _objective.y * map_width + _objective.x and is_on_map(_objective):
		state = 1
	if state == 0:
		return FOG_NEVER_COLOR
	var night := Color(NIGHT_COLOR, NIGHT_COLOR.a * _darkness)
	if state == 1:
		return FOG_SEEN_COLOR if FOG_SEEN_COLOR.a >= night.a else Color(FOG_SEEN_COLOR, night.a)
	if _darkness <= 0.0:
		return Color(0, 0, 0, 0)
	return LIGHT_COLOR if index < _lit_cells.size() and _lit_cells[index] != 0 else night


func _blend_fog(weight: float) -> void:
	for index: int in _fog_blend_cells:
		var color := _fog_from[index].lerp(_fog_to[index], weight)
		_fog_colors[index] = color
		_fog_image.set_pixel(index % map_width, index / map_width, color)
	if _fog_texture == null:
		_fog_texture = ImageTexture.create_from_image(_fog_image)
		_fog_rect.texture = _fog_texture
	else:
		_fog_texture.update(_fog_image)
	fog_write_count += 1


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
## `selected` (a cell), `target` (a cell), `path` (cells), `slots`
## (formation slot cells), `ghosts` ([{cell, from, side, is_leader}]).
func set_marks(marks: Dictionary) -> void:
	if marks == _marks:
		return
	_marks = marks
	_mark_layer.queue_redraw()


func get_marks() -> Dictionary:
	return _marks


## Enemy intents: [{from, to, action, target_cell}]; empty hides them.
func set_intents(intents: Array) -> void:
	if intents == _intents:
		return
	_intents = intents
	_intent_layer.queue_redraw()


func get_intents() -> Array:
	return _intents


## Active zones: [{zone, cells}] as get_zones() gives them.
func set_zones(zones: Array) -> void:
	if zones == _zones:
		return
	_zones = zones
	_zone_layer.queue_redraw()


func get_zones() -> Array:
	return _zones


## Text rising from a board point and fading, such as a damage number;
## never under the small font size.
func float_text(at: Vector2, text: String, color: Color, font_px: int = 26, rise_px: float = 36.0, seconds: float = 0.9) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", maxi(font_px, GameTheme.SMALL_FONT_SIZE))
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Palette.INK)
	label.add_theme_constant_override(&"outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(label)
	label.reset_size()
	# Kept inside the part of the board on screen, its rise included, so a
	# text at the edge of the view is not cut off, and above any text still
	# rising from the same spot.
	var shown := Rect2(Vector2.ZERO, get_board_size()).intersection(Rect2(view_to_board(Vector2.ZERO), size / _zoom))
	if not shown.has_area():
		shown = Rect2(Vector2.ZERO, get_board_size())
	var x := clampf(at.x - label.size.x / 2.0, shown.position.x, maxf(shown.end.x - label.size.x, shown.position.x))
	var top := shown.position.y + rise_px
	var start := clampf(at.y - label.size.y, top, maxf(shown.end.y - label.size.y, top))
	var y := _free_float_y(label, x, start, -1.0)
	if y < top:
		y = _free_float_y(label, x, start, 1.0)
	label.position = Vector2(x, y)
	var tween := label.create_tween()
	tween.tween_property(label, ^"position:y", label.position.y - rise_px, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, ^"modulate:a", 0.0, seconds * 0.4).set_delay(seconds * 0.6)
	tween.tween_callback(label.queue_free)
	return label


# The first y from `start`, going up (-1) or down (1), where the label
# covers no text still rising at that spot.
func _free_float_y(label: Label, x: float, start: float, direction: float) -> float:
	var y := start
	for attempt: int in _fx_layer.get_child_count():
		var is_free := true
		for other: Node in _fx_layer.get_children():
			var rising := other as Label
			if rising == null or rising == label or absf(rising.position.x + rising.size.x / 2.0 - x - label.size.x / 2.0) >= CELL_PX or absf(rising.position.y - y) >= label.size.y - 4.0:
				continue
			y = rising.position.y + (rising.size.y - 4.0 if direction > 0.0 else 4.0 - label.size.y)
			is_free = false
		if is_free:
			break
	return y


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom_about(_zoom * magnify.factor, magnify.position)
		accept_event()
	elif event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)


func _on_button(button: InputEventMouseButton) -> void:
	if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and button.pressed:
		_zoom_about(_zoom * (1.1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), button.position)
		accept_event()
		return
	if button.button_index != MOUSE_BUTTON_LEFT or _gesture == _Gesture.PINCH:
		return
	accept_event()
	if button.pressed:
		_press_position = button.position
		_press_cell = view_to_cell(button.position)
		if hold_cells.has(_press_cell):
			_gesture = _Gesture.HOLD
			_held_cell = _press_cell
			cell_held.emit(_press_cell)
		else:
			_gesture = _Gesture.TAP
		return
	var cell := view_to_cell(button.position)
	match _gesture:
		_Gesture.HOLD:
			_gesture = _Gesture.NONE
			hold_released.emit(cell)
		_Gesture.TAP:
			_gesture = _Gesture.NONE
			if cell == _press_cell and button.position.distance_to(_press_position) <= TAP_SLOP_PX and is_on_map(cell):
				cell_tapped.emit(cell)
		_Gesture.PAN:
			_gesture = _Gesture.NONE
			camera_settled.emit()
		_:
			_gesture = _Gesture.NONE


func _on_motion(motion: InputEventMouseMotion) -> void:
	if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	match _gesture:
		_Gesture.HOLD:
			var cell := view_to_cell(motion.position)
			if cell != _held_cell:
				_held_cell = cell
				cell_held.emit(cell)
			accept_event()
		_Gesture.TAP:
			if motion.position.distance_to(_press_position) > TAP_SLOP_PX:
				_gesture = _Gesture.PAN
				_pan_by(motion.position - _press_position)
			accept_event()
		_Gesture.PAN:
			_pan_by(motion.relative)
			accept_event()


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		_touches[touch.index] = touch.position
	else:
		_touches.erase(touch.index)
	if _touches.size() >= 2 and _gesture != _Gesture.PINCH:
		if _gesture == _Gesture.HOLD:
			hold_cancelled.emit()
		_gesture = _Gesture.PINCH
		_start_pinch()
	elif _touches.is_empty() and _gesture == _Gesture.PINCH:
		_gesture = _Gesture.NONE
		camera_settled.emit()
	accept_event()


func _on_touch_drag(drag: InputEventScreenDrag) -> void:
	_touches[drag.index] = drag.position
	if _gesture != _Gesture.PINCH or _touches.size() < 2:
		return
	var points := _touches.values()
	var distance: float = (points[0] as Vector2).distance_to(points[1])
	var middle: Vector2 = ((points[0] as Vector2) + (points[1] as Vector2)) / 2.0
	if _pinch_distance > 1.0:
		var anchor := (_pinch_middle - _board.position) / _zoom
		var zoom := clampf(_pinch_zoom * distance / _pinch_distance, get_whole_zoom(), get_max_zoom())
		_is_whole_map = false
		_apply_camera(middle - anchor * zoom, zoom)
		_pinch_middle = middle
		_pinch_zoom = zoom
		_pinch_distance = distance
	accept_event()


func _start_pinch() -> void:
	var points := _touches.values()
	_pinch_distance = (points[0] as Vector2).distance_to(points[1])
	_pinch_middle = ((points[0] as Vector2) + (points[1] as Vector2)) / 2.0
	_pinch_zoom = _zoom


func _pan_by(delta: Vector2) -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_apply_camera(_board.position + delta, _zoom)


func _zoom_about(zoom: float, view_point: Vector2) -> void:
	var anchor := view_to_board(view_point)
	var target := clampf(zoom, get_whole_zoom(), get_max_zoom())
	_is_whole_map = false
	_apply_camera(view_point - anchor * target, target)


func _add_layer(drawer: Callable) -> _Layer:
	var layer := _Layer.new()
	layer.drawer = drawer
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.add_child(layer)
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
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(map_width, map_height) * CELL_PX), Palette.INK, false, 3.0)


func _draw_zones(layer: Control) -> void:
	var canvas := TacticsMeshCanvas.new()
	for zone: Dictionary in _zones:
		var color: Color = ZONE_COLORS.get(zone["zone"], Color(0.8, 0.8, 0.8))
		for cell: Vector2i in zone["cells"]:
			if not is_on_map(cell):
				continue
			var rect := _cell_rect(cell)
			canvas.draw_rect(rect, Color(color, 0.32))
			canvas.draw_rect(rect.grow(-3.0), Color(color, 0.85), false, 2.0)
			_draw_zone_motif(canvas, zone["zone"], rect, color)
	canvas.commit(layer.get_canvas_item())


func _draw_zone_motif(canvas: TacticsMeshCanvas, zone_id: StringName, rect: Rect2, color: Color) -> void:
	var c := rect.get_center()
	if zone_id == &"zone.fire":
		canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 18), c + Vector2(-8, 18), c + Vector2(-12, 4)]), color)
		canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(10, 18), c + Vector2(18, 18), c + Vector2(14, 6)]), color)
	else:
		canvas.draw_arc(c + Vector2(-10, -14), 8.0, PI, TAU * 0.95, 8, color, 2.0)
		canvas.draw_arc(c + Vector2(12, 14), 7.0, PI, TAU * 0.95, 8, color, 2.0)


func _draw_marks(layer: Control) -> void:
	var canvas := TacticsMeshCanvas.new()
	for cell: Vector2i in _marks.get("reachable", []):
		canvas.draw_rect(_cell_rect(cell).grow(-2.0), REACH_COLOR)
	for cell: Vector2i in _marks.get("threat", []):
		canvas.draw_rect(_cell_rect(cell).grow(-2.0), THREAT_COLOR)
	for cell: Vector2i in _marks.get("skill_cells", []):
		canvas.draw_rect(_cell_rect(cell).grow(-2.0), SKILL_COLOR)
	for cell: Vector2i in _marks.get("area", []):
		if is_on_map(cell):
			canvas.draw_rect(_cell_rect(cell).grow(-1.0), AREA_COLOR)
	for cell: Vector2i in _marks.get("slots", []):
		if is_on_map(cell):
			canvas.draw_arc(cell_to_local(cell), CELL_PX * 0.3, 0.0, TAU, 20, Color(Palette.CREAM, 0.55), 2.5)
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
	canvas.commit(layer.get_canvas_item())


# Over the fog: the road, the exits, the convoy's path and the known
# sites with their capture rings.
func _draw_sites(layer: Control) -> void:
	var canvas := TacticsMeshCanvas.new()
	var road: Array = _objective_marks.get("road", [])
	if road.size() > 1:
		for index: int in range(1, road.size()):
			_draw_dashes(canvas, cell_to_local(road[index - 1]), cell_to_local(road[index]), TacticsPainter.ROAD_COLOR, 6.0)
	for cell: Vector2i in _objective_marks.get("exits", []):
		TacticsPainter.draw_exit(canvas, _cell_rect(cell), _outward(cell), TacticsPainter.EXIT_COLOR)
	for cell: Vector2i in _objective_marks.get("enemy_exits", []):
		TacticsPainter.draw_exit(canvas, _cell_rect(cell), _outward(cell), TacticsPainter.ENEMY_EXIT_COLOR)
	for cell: Vector2i in _objective_marks.get("entries", []):
		TacticsPainter.draw_exit(canvas, _cell_rect(cell), -_outward(cell), TacticsPainter.ENEMY_EXIT_COLOR)
	var path: Array = _objective_marks.get("convoy_path", [])
	if path.size() > 1:
		var points := PackedVector2Array()
		for cell: Vector2i in path:
			points.append(cell_to_local(cell))
		canvas.draw_polyline(points, Color(Palette.INK, 0.6), 9.0, true)
		canvas.draw_polyline(points, Palette.CREAM, 5.0, true)
		var tip := points[points.size() - 1]
		var direction := (tip - points[points.size() - 2]).normalized()
		var side := Vector2(-direction.y, direction.x)
		canvas.draw_colored_polygon(PackedVector2Array([tip + direction * 14.0, tip - direction * 6.0 + side * 11.0, tip - direction * 6.0 - side * 11.0]), Palette.CREAM)
	for site: Dictionary in _sites:
		if not site.get("is_known", true):
			continue
		var cell: Vector2i = site["cell"]
		TacticsPainter.draw_site(canvas, _cell_rect(cell), site["kind"], site["status"], site["owner"])
		if int(site.get("capture_phases", 0)) > 0 and int(site.get("capture_progress", 0)) > 0:
			TacticsPainter.draw_capture_ring(canvas, cell_to_local(cell), CELL_PX * 0.47, site["capture_progress"], site["capture_phases"], site["capture_side"])
	canvas.commit(layer.get_canvas_item())


# The way out of the map from an edge cell.
func _outward(cell: Vector2i) -> Vector2:
	if cell.y == 0:
		return Vector2.UP
	if cell.y == map_height - 1:
		return Vector2.DOWN
	if cell.x == 0:
		return Vector2.LEFT
	return Vector2.RIGHT


# Over the fog: the objective (known from the map, so findable at night
# too) and each remembered enemy, its token dimmed, with a "?".
func _draw_last_seen(canvas: Control) -> void:
	if is_on_map(_objective):
		TacticsPainter.draw_objective(canvas, _cell_rect(_objective).grow(-2.0))
	for ghost: Dictionary in _last_seen:
		var c := cell_to_local(ghost["cell"]) + TacticsPieceView.TOKEN_OFFSET
		TacticsPainter.draw_last_seen(canvas, c, ghost["is_leader"])


func _draw_edge_marks(canvas: Control) -> void:
	for mark: Dictionary in get_edge_marks():
		var at: Vector2 = mark["at"]
		var toward := (board_to_view(cell_to_local(mark["cell"])) - at).normalized()
		if mark["is_objective"]:
			TacticsPainter.draw_objective_edge_mark(canvas, at, toward, EDGE_MARK_PX)
		else:
			TacticsPainter.draw_edge_mark(canvas, at, toward, EDGE_MARK_PX)


func _draw_intents(layer: Control) -> void:
	var canvas := TacticsMeshCanvas.new()
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
	canvas.commit(layer.get_canvas_item())


func _draw_dashes(canvas: Object, from: Vector2, to: Vector2, color: Color, width: float) -> void:
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
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		drawer.call(self)
