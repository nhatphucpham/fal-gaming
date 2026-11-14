class_name SetupController
extends Node
## Setup-phase interaction of the sandbox: picking roster cards, placing,
## moving, swapping and removing the player's units by tap or drag, and the
## valid-cell highlights. Gestures from the board and the roster call the
## public tap_* and drop_* methods, which tests call directly. Cells here are
## global board cells; the Lineup gets local ones.

## A long press asked for a unit's details.
signal info_requested(unit: UnitData, star: int)
## Something was refused (board full, bad drop), for extra feedback.
signal action_refused()

const STAR: int = 1

## While false, taps and drags do nothing (during a battle).
var is_enabled: bool = true:
	set(value):
		is_enabled = value
		if not value:
			_cancel_drag()
			deselect()

var _board: BoardView
var _roster: RosterStrip
var _ghost: DragGhost
var _catalog: Catalog
var _lineup: Lineup
var _views: LineupViews
var _enemy_lineup: Lineup
var _enemy_views: LineupViews
var _selected_unit: StringName = &""
var _selected_entry: int = Lineup.NO_ENTRY
var _drag_unit: StringName = &""
var _drag_entry: int = Lineup.NO_ENTRY


## Wires the controller to the screen's pieces.
func setup(board: BoardView, roster: RosterStrip, ghost: DragGhost, catalog: Catalog, player: LineupViews, player_lineup: Lineup, enemy: LineupViews, enemy_lineup: Lineup) -> void:
	_board = board
	_roster = roster
	_ghost = ghost
	_catalog = catalog
	_views = player
	_lineup = player_lineup
	_enemy_views = enemy
	_enemy_lineup = enemy_lineup
	board.cell_tapped.connect(tap_cell)
	board.cell_long_pressed.connect(_on_cell_long_pressed)
	board.drag_started.connect(_on_board_drag_started)
	board.drag_moved.connect(_on_drag_moved)
	board.drag_ended.connect(_on_board_drag_ended)
	board.drag_cancelled.connect(_cancel_drag)
	roster.card_tapped.connect(tap_roster_card)
	roster.card_long_pressed.connect(func(unit_id: StringName) -> void: info_requested.emit(_catalog.get_unit(unit_id), STAR))
	roster.card_drag_started.connect(_on_card_drag_started)
	roster.card_drag_moved.connect(_on_drag_moved)
	roster.card_drag_ended.connect(_on_card_drag_ended)
	roster.card_drag_cancelled.connect(_cancel_drag)


## Tap on a roster card: select it, or deselect it when already selected.
func tap_roster_card(unit_id: StringName) -> void:
	if not is_enabled:
		return
	var was_selected := _selected_unit == unit_id
	deselect()
	if not was_selected:
		_selected_unit = unit_id
		_roster.set_selected(unit_id)
		_refresh_targets()


## Tap on a board cell: place, select, move, swap or deselect.
func tap_cell(cell: Vector2i) -> void:
	if not is_enabled:
		return
	if BoardView.side_of_cell(cell) != _views.side:
		deselect()
		return
	var local := _views.to_local_cell(cell)
	var entry := _lineup.get_entry_at(local)
	if entry != Lineup.NO_ENTRY:
		_tap_unit(entry)
	elif _selected_entry != Lineup.NO_ENTRY:
		_lineup.move(_selected_entry, local)
		deselect()
	elif _selected_unit != &"":
		if _lineup.place(_selected_unit, STAR, local) == Lineup.NO_ENTRY:
			action_refused.emit()
		_refresh_targets()


## Drops a dragged roster card on `cell` (INVALID_CELL when off the board).
## True when a unit was placed.
func drop_card(unit_id: StringName, cell: Vector2i) -> bool:
	if not is_enabled or not BoardView.is_on_board(cell) or BoardView.side_of_cell(cell) != _views.side:
		return false
	return _lineup.place(unit_id, STAR, _views.to_local_cell(cell)) != Lineup.NO_ENTRY


## Drops a dragged placed unit: onto a free player cell it moves, onto
## another unit it swaps, off the board it is removed. False when refused.
func drop_piece(entry_id: int, cell: Vector2i) -> bool:
	if not is_enabled or _lineup.get_slot(entry_id) == null:
		return false
	if not BoardView.is_on_board(cell):
		return _lineup.remove(entry_id)
	if BoardView.side_of_cell(cell) != _views.side:
		return false
	var local := _views.to_local_cell(cell)
	var other := _lineup.get_entry_at(local)
	if other == entry_id:
		return false
	if other != Lineup.NO_ENTRY:
		return _lineup.swap(entry_id, other)
	return _lineup.move(entry_id, local)


## True while a card or a placed unit is being dragged.
func is_dragging() -> bool:
	return _drag_unit != &"" or _drag_entry != Lineup.NO_ENTRY


func deselect() -> void:
	_selected_unit = &""
	_selected_entry = Lineup.NO_ENTRY
	if _roster != null:
		_roster.set_selected(&"")
		_board.clear_marks()


func _tap_unit(entry: int) -> void:
	if _selected_entry == entry:
		deselect()
	elif _selected_entry != Lineup.NO_ENTRY:
		_lineup.swap(_selected_entry, entry)
		deselect()
	else:
		deselect()
		_selected_entry = entry
		_board.set_selected_cell(_views.to_board_cell(_lineup.get_slot(entry).get_cell()))
		_refresh_targets()


# Free player cells while something can be placed or moved there; a moving
# unit may also swap, so its targets include the other units.
func _refresh_targets() -> void:
	var cells: Array[Vector2i] = []
	var placing := _selected_unit != &"" or _drag_unit != &""
	var moving := _selected_entry != Lineup.NO_ENTRY or _drag_entry != Lineup.NO_ENTRY
	if placing and _lineup.is_full():
		_board.set_target_cells(cells)
		return
	for rank: int in range(1, Lineup.RANKS + 1):
		for col: int in range(1, Lineup.COLS + 1):
			var entry := _lineup.get_entry_at(Vector2i(col, rank))
			var is_self := entry != Lineup.NO_ENTRY and (entry == _selected_entry or entry == _drag_entry)
			if (placing and entry == Lineup.NO_ENTRY) or (moving and not is_self):
				cells.append(_views.to_board_cell(Vector2i(col, rank)))
	_board.set_target_cells(cells)


func _on_cell_long_pressed(cell: Vector2i) -> void:
	if not is_enabled:
		return
	var lineup := _lineup if BoardView.side_of_cell(cell) == _views.side else _enemy_lineup
	var views := _views if lineup == _lineup else _enemy_views
	var entry := lineup.get_entry_at(views.to_local_cell(cell))
	if entry != Lineup.NO_ENTRY:
		var slot := lineup.get_slot(entry)
		info_requested.emit(_catalog.get_unit(slot.unit_id), slot.star)


func _on_card_drag_started(unit_id: StringName, pointer: Vector2) -> void:
	if not is_enabled:
		return
	deselect()
	_drag_unit = unit_id
	_ghost.begin(_catalog.get_unit(unit_id), pointer)
	_refresh_targets()
	_on_drag_moved(pointer)


func _on_board_drag_started(cell: Vector2i, pointer: Vector2) -> void:
	if not is_enabled or not BoardView.is_on_board(cell) or BoardView.side_of_cell(cell) != _views.side:
		return
	var entry := _lineup.get_entry_at(_views.to_local_cell(cell))
	if entry == Lineup.NO_ENTRY:
		return
	deselect()
	_drag_entry = entry
	_views.get_view(entry).fade_to(0.3, 0.1)
	_ghost.begin(_catalog.get_unit(_lineup.get_slot(entry).unit_id), pointer)
	_refresh_targets()
	_on_drag_moved(pointer)


func _on_drag_moved(pointer: Vector2) -> void:
	if _drag_unit == &"" and _drag_entry == Lineup.NO_ENTRY:
		return
	_ghost.follow(pointer)
	_board.set_hover_cell(_board.cell_at_global(_ghost.get_drop_point(pointer)))


func _on_card_drag_ended(pointer: Vector2) -> void:
	if _drag_unit == &"":
		return
	var unit_id := _drag_unit
	var cell := _board.cell_at_global(_ghost.get_drop_point(pointer))
	_drag_unit = &""
	_board.clear_marks()
	if drop_card(unit_id, cell):
		_ghost.finish()
		return
	var card := _roster.get_card(unit_id)
	_ghost.reject(card.get_portrait_center() if card != null else pointer)
	action_refused.emit()


func _on_board_drag_ended(pointer: Vector2) -> void:
	if _drag_entry == Lineup.NO_ENTRY:
		return
	var entry := _drag_entry
	var cell := _board.cell_at_global(_ghost.get_drop_point(pointer))
	_drag_entry = Lineup.NO_ENTRY
	_board.clear_marks()
	var view := _views.get_view(entry)
	var home_cell := _views.to_board_cell(_lineup.get_slot(entry).get_cell())
	if cell == home_cell:
		_ghost.finish()
		view.fade_to(1.0, 0.1)
		return
	var home := _board.cell_to_global(home_cell)
	if drop_piece(entry, cell):
		_ghost.finish()
		if view != null and is_instance_valid(view) and not view.is_dead:
			view.fade_to(1.0, 0.1)
		return
	_ghost.reject(home)
	if view != null:
		view.fade_to(1.0, 0.3)
		view.shake()
	action_refused.emit()


# Undoes a drag without a drop: the piece shows again where it stood, the
# ghost and the cell marks go. Safe to call when nothing is dragged.
func _cancel_drag() -> void:
	var was_dragging := is_dragging()
	if _drag_entry != Lineup.NO_ENTRY:
		var view := _views.get_view(_drag_entry)
		if view != null:
			view.fade_to(1.0, 0.1)
	_drag_unit = &""
	_drag_entry = Lineup.NO_ENTRY
	if _ghost != null:
		_ghost.finish()
	if _board == null:
		return
	if was_dragging:
		_board.set_hover_cell(BoardView.INVALID_CELL)
		_board.set_target_cells([])
	_board.cancel_gesture()
	_roster.cancel_gesture()
