class_name BoardView
extends Control
## The 7 x 8 battlefield: draws the grid, maps cells to pixels, lights cells
## and turns pointer input into cell signals. It shows the pieces it is given
## (UnitViews added to get_piece_layer()) and knows nothing about who owns
## them or what a tap means. Cells are global (col 0..6, row 0..7), row 0 at
## the bottom; rows 0..3 are side 0 (the player). See Docs/systems/board.md.
## [codeblock]
## board.cell_tapped.connect(func(cell): print(cell))
## view.position = board.cell_to_local(Vector2i(3, 3))
## board.set_target_cells([Vector2i(0, 0), Vector2i(1, 0)])
## [/codeblock]

signal cell_tapped(cell: Vector2i)
## A long press or right click; also fires during battles.
signal cell_long_pressed(cell: Vector2i)
## A press on `cell` moved far enough to become a drag.
signal drag_started(cell: Vector2i, global_pointer: Vector2)
signal drag_moved(global_pointer: Vector2)
signal drag_ended(global_pointer: Vector2)
## A drag stopped without a drop (lost focus, second finger, cancel_gesture).
signal drag_cancelled()

const COLS: int = 7
const ROWS: int = 8
const ROWS_PER_SIDE: int = 4
const CELL_PX: float = 88.0
const INVALID_CELL := Vector2i(-1, -1)
const CELL_INSET_PX: float = 3.0
const FRAME_PX: float = 10.0

const CELL_COLOR := Palette.CREAM
const ENEMY_CELL_COLOR := Color("f0dcc0")
const TARGET_COLOR := Color("3e9c7e40")
const HOVER_COLOR := Color("3e9c7eb0")

var _gesture := PointerGesture.new()
var _marks: Node2D
var _outlines: Node2D
var _pieces: Node2D
var _fx: Node2D
var _select_ring: Node2D
var _ring_tween: Tween
var _target_cells: Array[Vector2i] = []
var _hover_cell: Vector2i = INVALID_CELL
var _enemy_dim: float = 0.0
var _cell_box: StyleBoxFlat
var _frame_box: StyleBoxFlat


func _init() -> void:
	custom_minimum_size = Vector2(COLS * CELL_PX, ROWS * CELL_PX)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cell_box = StyleBoxFlat.new()
	_cell_box.set_corner_radius_all(8)
	_cell_box.anti_aliasing = true
	_frame_box = GameTheme.make_panel(Palette.PAPER, 16, 8)
	_marks = _add_layer(&"Marks")
	_marks.draw.connect(_draw_marks)
	_select_ring = _add_layer(&"SelectRing")
	_select_ring.draw.connect(_draw_select_ring)
	_select_ring.hide()
	_outlines = _add_layer(&"Outlines")
	_pieces = _add_layer(&"Pieces")
	_pieces.y_sort_enabled = true
	_fx = _add_layer(&"Fx")
	_gesture.tapped.connect(func(pointer: Vector2) -> void: _emit_if_cell(cell_tapped, pointer))
	_gesture.long_pressed.connect(func(pointer: Vector2) -> void: _emit_if_cell(cell_long_pressed, pointer))
	_gesture.drag_started.connect(func(start: Vector2, pointer: Vector2) -> void: drag_started.emit(cell_at_global(start), pointer))
	_gesture.drag_moved.connect(func(pointer: Vector2) -> void: drag_moved.emit(pointer))
	_gesture.drag_ended.connect(func(pointer: Vector2) -> void: drag_ended.emit(pointer))
	_gesture.drag_cancelled.connect(func() -> void: drag_cancelled.emit())


func _gui_input(event: InputEvent) -> void:
	if _gesture.handle_input(event):
		accept_event()


func _input(event: InputEvent) -> void:
	_gesture.handle_global_input(event)


func _notification(what: int) -> void:
	if _gesture != null:
		_gesture.handle_notification(what)


func _process(delta: float) -> void:
	_gesture.update(delta)


## Node where UnitViews go; children are drawn sorted by y.
func get_piece_layer() -> Node2D:
	return _pieces


## Node under the pieces for drawings that belong to cells, such as
## formation outlines.
func get_outline_layer() -> Node2D:
	return _outlines


## Node above the pieces for projectiles, flashes and numbers.
func get_fx_layer() -> Node2D:
	return _fx


## Centre of a cell in this control's local coordinates.
func cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * CELL_PX, (ROWS - 1 - cell.y + 0.5) * CELL_PX)


## Centre of a cell in global canvas coordinates.
func cell_to_global(cell: Vector2i) -> Vector2:
	return get_global_transform_with_canvas() * cell_to_local(cell)


## The cell under a global canvas position, or INVALID_CELL.
func cell_at_global(global_pointer: Vector2) -> Vector2i:
	var local := get_global_transform_with_canvas().affine_inverse() * global_pointer
	var cell := Vector2i(floori(local.x / CELL_PX), ROWS - 1 - floori(local.y / CELL_PX))
	return cell if is_on_board(cell) else INVALID_CELL


static func is_on_board(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS


## 0 for the bottom half (rows 0..3), 1 for the top half.
static func side_of_cell(cell: Vector2i) -> int:
	return 0 if cell.y < ROWS_PER_SIDE else 1


## Lights these cells as valid targets; an empty array clears them.
func set_target_cells(cells: Array[Vector2i]) -> void:
	_target_cells = cells.duplicate()
	_marks.queue_redraw()


## Lights one cell strongly (the cell under a dragged piece).
func set_hover_cell(cell: Vector2i) -> void:
	if cell == _hover_cell:
		return
	_hover_cell = cell
	_marks.queue_redraw()


## Shows a pulsing ring around `cell`, or hides it for INVALID_CELL.
func set_selected_cell(cell: Vector2i) -> void:
	if _ring_tween != null:
		_ring_tween.kill()
	if not is_on_board(cell):
		_select_ring.hide()
		return
	_select_ring.position = cell_to_local(cell)
	_select_ring.show()
	_select_ring.scale = Vector2(0.8, 0.8)
	_ring_tween = create_tween()
	_ring_tween.tween_property(_select_ring, ^"scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(_select_ring, ^"scale", Vector2(1.06, 1.06), 0.45).set_trans(Tween.TRANS_SINE)
	_ring_tween.tween_property(_select_ring, ^"scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	_ring_tween.set_loops()


func clear_marks() -> void:
	set_target_cells([])
	set_hover_cell(INVALID_CELL)
	set_selected_cell(INVALID_CELL)


## Darkens the top half's cells by `amount` 0..1, animated.
func set_top_half_dim(amount: float) -> void:
	create_tween().tween_method(_set_enemy_dim, _enemy_dim, amount, 0.25)


## Stops any press in progress, for example when input is turned off.
func cancel_gesture() -> void:
	_gesture.cancel()


func _draw() -> void:
	var board_rect := Rect2(Vector2.ZERO, custom_minimum_size)
	_frame_box.draw(get_canvas_item(), board_rect.grow(FRAME_PX))
	for row: int in ROWS:
		for col: int in COLS:
			var cell := Vector2i(col, row)
			var color := CELL_COLOR if side_of_cell(cell) == 0 else ENEMY_CELL_COLOR.lerp(Palette.PAPER_DARK, _enemy_dim)
			_cell_box.bg_color = color
			_cell_box.draw(get_canvas_item(), _cell_rect(cell))
	_draw_corner_marks()
	var middle_y := ROWS_PER_SIDE * CELL_PX
	draw_line(Vector2(-FRAME_PX + 4, middle_y), Vector2(COLS * CELL_PX + FRAME_PX - 4, middle_y), Palette.INK, 4.0, true)
	for end_x: float in [-FRAME_PX + 4, COLS * CELL_PX + FRAME_PX - 4]:
		draw_circle(Vector2(end_x, middle_y), 6.0, Palette.VERMILION)
		draw_arc(Vector2(end_x, middle_y), 6.0, 0, TAU, 16, Palette.INK, 2.0, true)


# Small ink crosses where four cells meet, like a printed game board.
func _draw_corner_marks() -> void:
	for row: int in range(1, ROWS):
		if row == ROWS_PER_SIDE:
			continue
		for col: int in range(1, COLS):
			var point := Vector2(col * CELL_PX, row * CELL_PX)
			draw_line(point - Vector2(5, 0), point + Vector2(5, 0), Palette.PAPER_DARK, 2.0)
			draw_line(point - Vector2(0, 5), point + Vector2(0, 5), Palette.PAPER_DARK, 2.0)


func _draw_marks() -> void:
	for cell: Vector2i in _target_cells:
		_marks.draw_rect(_cell_rect(cell).grow(-5.0), TARGET_COLOR)
		_marks.draw_rect(_cell_rect(cell).grow(-5.0), Color(Palette.JADE, 0.8), false, 2.0)
	if is_on_board(_hover_cell):
		var color := HOVER_COLOR if _target_cells.has(_hover_cell) else Color(Palette.VERMILION, 0.45)
		_marks.draw_rect(_cell_rect(_hover_cell).grow(-2.0), color)
		_marks.draw_rect(_cell_rect(_hover_cell).grow(-2.0), Palette.INK, false, 3.0)


func _draw_select_ring() -> void:
	var half := CELL_PX / 2.0 - 2.0
	var rect := Rect2(-half, -half, half * 2.0, half * 2.0)
	_select_ring.draw_rect(rect, Palette.INK, false, 7.0)
	_select_ring.draw_rect(rect, Palette.GOLD, false, 4.0)


func _cell_rect(cell: Vector2i) -> Rect2:
	var center := cell_to_local(cell)
	var half := CELL_PX / 2.0 - CELL_INSET_PX
	return Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)


func _set_enemy_dim(value: float) -> void:
	_enemy_dim = value
	queue_redraw()


func _add_layer(layer_name: StringName) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	return layer


func _emit_if_cell(board_signal: Signal, pointer: Vector2) -> void:
	var cell := cell_at_global(pointer)
	if is_on_board(cell):
		board_signal.emit(cell)
