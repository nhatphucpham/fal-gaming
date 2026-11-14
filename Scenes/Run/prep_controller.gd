class_name PrepController
extends Node
## Preparation input of the run screen: buying from the shop, placing,
## moving and swapping pieces between bench and board, and selling, by tap
## or drag. It sends commands to RunState and shows targets; it never edits
## the run. Tap-tap: tap a card or a piece to select it (targets light up,
## the shop turns into the sell zone for a piece), then tap where it goes;
## tap a selected card again to buy it onto the bench. Gestures call the
## public tap_* and drop_* methods, which tests call directly. Board cells
## here are global; RunState gets local ones.

## A long press asked for a unit's details; `side` is whose unit it is
## (a shop card counts as the player's).
signal info_requested(unit: UnitData, star: int, side: int)
## A command was refused; the screen shows why (shake, flash).
signal action_refused(result: RunState.Result)
## A dragged piece (`piece_id`) or shop card (`shop_unit`) is over a new
## cell of the player's half (`local_cell`): show what the drop would make.
signal preview_requested(piece_id: int, shop_unit: UnitData, local_cell: Vector2i)
## The drag left the player's half or ended: stop previewing.
signal preview_ended()

const NO_PIECE: int = 0
const NO_SLOT: int = -1

## While false, taps and drags do nothing (battles, rewards).
var is_enabled: bool = true:
	set(value):
		is_enabled = value
		if not value:
			_cancel_drag()
			deselect()

var _run: RunState
var _board: BoardView
var _bench: BenchBar
var _shop: ShopBar
var _sell_zone: SellZone
var _views: PieceViews
var _enemy: LineupViews
var _enemy_lineup: Lineup
var _drag: PieceDrag
var _selected_shop: int = NO_SLOT
var _selected_piece: int = NO_PIECE
var _drag_shop: int = NO_SLOT
var _drag_piece: int = NO_PIECE
# The cell last previewed, so a drag evaluates only when it changes.
var _preview_cell: Vector2i = BoardView.INVALID_CELL


## Wires the controller to the screen's pieces.
func setup(run: RunState, board: BoardView, bench: BenchBar, shop: ShopBar, sell_zone: SellZone, ghost: DragGhost, views: PieceViews, enemy: LineupViews, enemy_lineup: Lineup) -> void:
	_run = run
	_board = board
	_bench = bench
	_shop = shop
	_sell_zone = sell_zone
	_views = views
	_enemy = enemy
	_enemy_lineup = enemy_lineup
	_drag = PieceDrag.new(board, ghost)
	board.cell_tapped.connect(tap_cell)
	board.cell_long_pressed.connect(_on_cell_long_pressed)
	board.drag_started.connect(func(cell: Vector2i, pointer: Vector2) -> void: _start_piece_drag(_piece_at_cell(cell), pointer))
	board.drag_moved.connect(_on_drag_moved)
	board.drag_ended.connect(_on_drag_ended)
	board.drag_cancelled.connect(_cancel_drag)
	bench.slot_tapped.connect(tap_bench_slot)
	bench.slot_long_pressed.connect(func(slot: int) -> void: _request_info(_run.get_bench_piece(slot)))
	bench.drag_started.connect(func(slot: int, pointer: Vector2) -> void: _start_piece_drag(_run.get_bench_piece(slot), pointer))
	bench.drag_moved.connect(_on_drag_moved)
	bench.drag_ended.connect(_on_drag_ended)
	bench.drag_cancelled.connect(_cancel_drag)
	shop.card_tapped.connect(tap_shop_card)
	shop.card_long_pressed.connect(func(slot: int) -> void: info_requested.emit(_shop_unit(slot), 1, Battle.SIDE_A))
	shop.card_drag_started.connect(_start_shop_drag)
	shop.card_drag_moved.connect(_on_drag_moved)
	shop.card_drag_ended.connect(_on_drag_ended)
	shop.card_drag_cancelled.connect(_cancel_drag)
	sell_zone.tapped.connect(tap_sell_zone)


## Tap on a shop card: select it, or buy it onto the bench when selected.
func tap_shop_card(slot: int) -> void:
	if not is_enabled or _shop_unit(slot) == null:
		return
	if _selected_shop == slot:
		deselect()
		_report(_run.buy(slot))
		return
	deselect()
	_selected_shop = slot
	_shop.set_selected(slot)
	_refresh_targets()


## Tap on a bench slot: place the selected card or piece there, or select
## the piece on it.
func tap_bench_slot(slot: int) -> void:
	if not is_enabled:
		return
	var piece := _run.get_bench_piece(slot)
	if _selected_shop != NO_SLOT and piece == null:
		var shop_slot := _selected_shop
		deselect()
		_report(_run.buy_to(shop_slot, slot, RunPiece.NO_CELL))
	elif _selected_piece != NO_PIECE and (piece == null or piece.id != _selected_piece):
		var moving := _selected_piece
		deselect()
		_report(_run.move_to_bench(moving, slot))
	else:
		_toggle_piece(piece)


## Tap on a board cell: place the selected card or piece there, or select
## the piece on it. The enemy half deselects.
func tap_cell(cell: Vector2i) -> void:
	if not is_enabled:
		return
	if BoardView.side_of_cell(cell) != Battle.SIDE_A:
		deselect()
		return
	var local := _to_local(cell)
	var piece := _run.get_board_piece(local)
	if _selected_shop != NO_SLOT and piece == null:
		var shop_slot := _selected_shop
		deselect()
		_report(_run.buy_to(shop_slot, RunPiece.NO_BENCH, local))
	elif _selected_piece != NO_PIECE and (piece == null or piece.id != _selected_piece):
		var moving := _selected_piece
		deselect()
		_report(_run.move_to_board(moving, local))
	else:
		_toggle_piece(piece)


## Tap on the sell zone: sells the selected piece.
func tap_sell_zone() -> void:
	if not is_enabled or _selected_piece == NO_PIECE:
		return
	var piece_id := _selected_piece
	deselect()
	_report(_run.sell(piece_id))


## Drops a dragged shop card at a global point (bench slot or board cell).
func drop_shop_card(slot: int, drop_point: Vector2) -> RunState.Result:
	var bench_slot := _bench.slot_at_global(drop_point)
	var cell := _board.cell_at_global(drop_point)
	if bench_slot != NO_SLOT:
		return _run.buy_to(slot, bench_slot, RunPiece.NO_CELL)
	if BoardView.is_on_board(cell) and BoardView.side_of_cell(cell) == Battle.SIDE_A:
		return _run.buy_to(slot, RunPiece.NO_BENCH, _to_local(cell))
	return RunState.Result.BAD_TARGET


## Drops a dragged piece: on the sell zone (`pointer`) it sells, on a bench
## slot or a board cell (`drop_point`) it moves or swaps.
func drop_piece(piece_id: int, pointer: Vector2, drop_point: Vector2) -> RunState.Result:
	if _sell_zone.contains_global(pointer):
		return _run.sell(piece_id)
	var bench_slot := _bench.slot_at_global(drop_point)
	if bench_slot != NO_SLOT:
		return _run.move_to_bench(piece_id, bench_slot)
	var cell := _board.cell_at_global(drop_point)
	if BoardView.is_on_board(cell) and BoardView.side_of_cell(cell) == Battle.SIDE_A:
		return _run.move_to_board(piece_id, _to_local(cell))
	return RunState.Result.BAD_TARGET


func is_dragging() -> bool:
	return _drag_shop != NO_SLOT or _drag_piece != NO_PIECE


func get_selected_piece() -> int:
	return _selected_piece


func deselect() -> void:
	_selected_shop = NO_SLOT
	_selected_piece = NO_PIECE
	if _board == null:
		return
	_shop.set_selected(NO_SLOT)
	_board.clear_marks()
	_bench.clear_marks()
	_sell_zone.vanish()


func _toggle_piece(piece: RunPiece) -> void:
	var was_selected := piece != null and piece.id == _selected_piece
	deselect()
	if piece == null or was_selected:
		return
	_selected_piece = piece.id
	if piece.is_on_board():
		_board.set_selected_cell(_to_board(piece.cell))
	else:
		_bench.set_selected_slot(piece.bench_slot)
	_sell_zone.appear(_run.get_sell_value(piece.id).x)
	_refresh_targets()


# Lights where the selected or dragged card or piece may go.
func _refresh_targets() -> void:
	var shop_slot := _drag_shop if _drag_shop != NO_SLOT else _selected_shop
	var piece := _run.get_piece(_drag_piece if _drag_piece != NO_PIECE else _selected_piece)
	var cells: Array[Vector2i] = []
	var slots: Array[int] = []
	var board_has_room := _run.get_board_count() < _run.get_capacity()
	for slot: int in _bench.get_slot_count():
		var other := _run.get_bench_piece(slot)
		if (shop_slot != NO_SLOT and other == null) or (piece != null and other != piece):
			slots.append(slot)
	for rank: int in range(1, Lineup.RANKS + 1):
		for col: int in range(1, Lineup.COLS + 1):
			var other := _run.get_board_piece(Vector2i(col, rank))
			var free_ok := other == null and (board_has_room or (piece != null and piece.is_on_board()))
			if (shop_slot != NO_SLOT and free_ok) or (piece != null and other != piece and (other != null or free_ok)):
				cells.append(_to_board(Vector2i(col, rank)))
	_board.set_target_cells(cells)
	_bench.set_target_slots(slots)


func _start_shop_drag(slot: int, pointer: Vector2) -> void:
	if not is_enabled or _shop_unit(slot) == null:
		return
	deselect()
	_drag_shop = slot
	_refresh_targets()
	_drag.begin(_shop_unit(slot), pointer, null)


func _start_piece_drag(piece: RunPiece, pointer: Vector2) -> void:
	if not is_enabled or piece == null:
		return
	deselect()
	_drag_piece = piece.id
	_sell_zone.appear(_run.get_sell_value(piece.id).x)
	_refresh_targets()
	_drag.begin(_run.catalog.get_unit(piece.unit_id), pointer, _views.get_view(piece.id))


func _on_drag_moved(pointer: Vector2) -> void:
	if not is_dragging():
		return
	var point := _drag.follow(pointer)
	var over_sell := _drag_piece != NO_PIECE and _sell_zone.contains_global(pointer)
	_sell_zone.set_hover(over_sell)
	_bench.set_hover_slot(NO_SLOT if over_sell else _bench.slot_at_global(point))
	if over_sell:
		_board.set_hover_cell(BoardView.INVALID_CELL)
	var cell := BoardView.INVALID_CELL if over_sell else _board.cell_at_global(point)
	_update_preview(cell if BoardView.is_on_board(cell) and BoardView.side_of_cell(cell) == Battle.SIDE_A else BoardView.INVALID_CELL)


func _on_drag_ended(pointer: Vector2) -> void:
	if not is_dragging():
		return
	var point := _drag.get_drop_point(pointer)
	var shop_slot := _drag_shop
	var piece := _run.get_piece(_drag_piece)
	var home := _home_global(shop_slot, piece)
	_update_preview(BoardView.INVALID_CELL)
	_drag_shop = NO_SLOT
	_drag_piece = NO_PIECE
	var result := drop_shop_card(shop_slot, point) if shop_slot != NO_SLOT else drop_piece(piece.id, pointer, point)
	deselect()
	if result == RunState.Result.OK or (piece != null and _is_own_place(piece, point)):
		_drag.accept()
		return
	_drag.reject(home)
	action_refused.emit(result)


func _update_preview(cell: Vector2i) -> void:
	if cell == _preview_cell:
		return
	_preview_cell = cell
	if cell == BoardView.INVALID_CELL:
		preview_ended.emit()
		return
	preview_requested.emit(_drag_piece, _shop_unit(_drag_shop) if _drag_shop != NO_SLOT else null, _to_local(cell))


func _is_own_place(piece: RunPiece, drop_point: Vector2) -> bool:
	if piece.is_on_bench():
		return _bench.slot_at_global(drop_point) == piece.bench_slot
	return _board.cell_at_global(drop_point) == _to_board(piece.cell)


func _home_global(shop_slot: int, piece: RunPiece) -> Vector2:
	if shop_slot != NO_SLOT:
		return _shop.get_card(shop_slot).get_portrait_center()
	if piece != null and piece.is_on_board():
		return _board.cell_to_global(_to_board(piece.cell))
	if piece != null:
		return _bench.get_slot_anchor(piece.bench_slot).get_global_transform_with_canvas().origin
	return Vector2.ZERO


# Undoes a drag without a drop. Safe to call when nothing is dragged.
func _cancel_drag() -> void:
	var was_dragging := is_dragging()
	_update_preview(BoardView.INVALID_CELL)
	_drag_shop = NO_SLOT
	_drag_piece = NO_PIECE
	if _board == null:
		return
	_drag.cancel()
	if was_dragging:
		deselect()
	_board.cancel_gesture()
	_bench.cancel_gesture()
	_shop.cancel_gesture()


func _on_cell_long_pressed(cell: Vector2i) -> void:
	if not is_enabled:
		return
	if BoardView.side_of_cell(cell) == Battle.SIDE_A:
		_request_info(_piece_at_cell(cell))
		return
	var entry := _enemy_lineup.get_entry_at(_enemy.to_local_cell(cell))
	if entry != Lineup.NO_ENTRY:
		var slot := _enemy_lineup.get_slot(entry)
		info_requested.emit(_run.catalog.get_unit(slot.unit_id), slot.star, Battle.SIDE_B)


func _request_info(piece: RunPiece) -> void:
	if is_enabled and piece != null:
		info_requested.emit(_run.catalog.get_unit(piece.unit_id), piece.star, Battle.SIDE_A)


func _report(result: RunState.Result) -> void:
	if result != RunState.Result.OK:
		action_refused.emit(result)


func _piece_at_cell(cell: Vector2i) -> RunPiece:
	if not BoardView.is_on_board(cell) or BoardView.side_of_cell(cell) != Battle.SIDE_A:
		return null
	return _run.get_board_piece(_to_local(cell))


func _shop_unit(slot: int) -> UnitData:
	var unit_id := _run.get_shop_offers()[slot] if slot >= 0 and slot < _run.get_shop_offers().size() else &""
	return _run.catalog.get_unit(unit_id) if unit_id != &"" else null


func _to_local(cell: Vector2i) -> Vector2i:
	return Battle.global_to_local(Battle.SIDE_A, cell.x, cell.y)


func _to_board(local: Vector2i) -> Vector2i:
	return Battle.local_to_global(Battle.SIDE_A, local.x, local.y)
