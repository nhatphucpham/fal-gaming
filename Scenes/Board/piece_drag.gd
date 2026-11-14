class_name PieceDrag
extends RefCounted
## One drag of a unit over the board, shared by the sandbox and the run
## screens: the DragGhost follows the finger, the source view (if any)
## fades, the board lights the cell under the ghost's feet; at the end the
## caller accepts (the piece landed) or rejects (it flies home and shakes),
## or cancels (focus lost, second finger: everything is put back).
## [codeblock]
## drag.begin(unit, pointer, view)
## drag.follow(pointer)               # returns the drop point
## if placed: drag.accept() else: drag.reject(home)
## [/codeblock]

var _board: BoardView
var _ghost: DragGhost
var _source: UnitView
var _is_active: bool = false


func _init(board: BoardView, ghost: DragGhost) -> void:
	_board = board
	_ghost = ghost


## Starts dragging `unit`; `source` is the view being moved, or null for a
## card being dragged from a strip.
func begin(unit: UnitData, pointer: Vector2, source: UnitView) -> void:
	_is_active = true
	_source = source
	if _is_alive(source):
		source.fade_to(0.3, 0.1)
	_ghost.begin(unit, pointer)
	follow(pointer)


func is_active() -> bool:
	return _is_active


## Moves the ghost; lights the board cell under it. Returns the drop point
## (global), where the ghost's feet appear to stand.
func follow(pointer: Vector2) -> Vector2:
	_ghost.follow(pointer)
	var point := _ghost.get_drop_point(pointer)
	_board.set_hover_cell(_board.cell_at_global(point))
	return point


## The global drop point for a pointer position.
func get_drop_point(pointer: Vector2) -> Vector2:
	return _ghost.get_drop_point(pointer)


## The piece landed: hide the ghost, show the source view again.
func accept() -> void:
	_finish(0.1)
	_ghost.finish()


## The drop was refused: the ghost flies back to `home` (global) and
## shakes, and the source view shakes in place.
func reject(home: Vector2) -> void:
	var source := _source
	_finish(0.3)
	_ghost.reject(home)
	if _is_alive(source):
		source.shake()


## Undoes the drag without a drop. Safe to call when nothing is dragged.
func cancel() -> void:
	if not _is_active:
		return
	_finish(0.1)
	_ghost.finish()


func _finish(fade_sec: float) -> void:
	if _is_alive(_source):
		_source.fade_to(1.0, fade_sec)
	_source = null
	_is_active = false
	_board.set_hover_cell(BoardView.INVALID_CELL)


func _is_alive(view: UnitView) -> bool:
	return view != null and is_instance_valid(view) and not view.is_dead
