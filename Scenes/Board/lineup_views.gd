class_name LineupViews
extends RefCounted
## Keeps one UnitView per entry of a Lineup on a BoardView, animating every
## change the Lineup reports (drop in, glide on move or swap, pop out). The
## Lineup stays the only owner of the formation; this class only observes it.
## [codeblock]
## var views := LineupViews.new(lineup, Battle.SIDE_A, board, catalog)
## lineup.place(&"unit.archer", 1, Vector2i(4, 3))  # a view drops in
## [/codeblock]

const MOVE_SEC: float = 0.16

var side: int
var _lineup: Lineup
var _board: BoardView
var _catalog: Catalog
var _views: Dictionary[int, UnitView] = {}
var _dim: float = 0.0


func _init(lineup: Lineup, lineup_side: int, board: BoardView, catalog: Catalog) -> void:
	_lineup = lineup
	side = lineup_side
	_board = board
	_catalog = catalog
	lineup.entry_added.connect(_on_entry_added)
	lineup.entry_moved.connect(_on_entry_moved)
	lineup.entries_swapped.connect(_on_entries_swapped)
	lineup.entry_removed.connect(_on_entry_removed)
	lineup.cleared.connect(_on_cleared)


## Global board cell of a local (col, rank) of this side.
func to_board_cell(local_cell: Vector2i) -> Vector2i:
	return Battle.local_to_global(side, local_cell.x, local_cell.y)


## Local (col, rank) of a global board cell; off the side's half when the
## cell belongs to the other side.
func to_local_cell(board_cell: Vector2i) -> Vector2i:
	return Battle.global_to_local(side, board_cell.x, board_cell.y)


func get_view(entry_id: int) -> UnitView:
	return _views.get(entry_id, null)


## The views by entry id. The caller may animate them but not free them.
func get_views() -> Dictionary[int, UnitView]:
	return _views


## Frees every view and makes new ones from the lineup, dropping in.
func rebuild() -> void:
	for view: UnitView in _views.values():
		view.queue_free()
	_views.clear()
	for entry_id: int in _lineup.get_entry_ids():
		_on_entry_added(entry_id)


## Darkens every view by `amount` 0..1, now and for views added later.
func set_dim(amount: float) -> void:
	_dim = amount
	for view: UnitView in _views.values():
		view.set_dim(amount)


## Fades every view out and frees it, without touching the lineup.
func fade_out_all() -> void:
	for view: UnitView in _views.values():
		var tween := view.create_tween()
		tween.tween_property(view, ^"modulate:a", 0.0, 0.18)
		tween.tween_callback(view.queue_free)
	_views.clear()


func _on_entry_added(entry_id: int) -> void:
	var slot := _lineup.get_slot(entry_id)
	var unit := _catalog.get_unit(slot.unit_id)
	if unit == null:
		push_error("LineupViews: unknown unit %s" % slot.unit_id)
		return
	var view := UnitView.new()
	view.setup(unit, side, slot.star)
	view.position = _board.cell_to_local(to_board_cell(slot.get_cell()))
	_board.get_piece_layer().add_child(view)
	_views[entry_id] = view
	view.drop_in()
	if _dim > 0.0:
		view.set_dim(_dim)


func _on_entry_moved(entry_id: int, _from_cell: Vector2i, to_cell: Vector2i) -> void:
	_glide(entry_id, to_cell)


func _on_entries_swapped(first_id: int, second_id: int) -> void:
	_glide(first_id, _lineup.get_slot(first_id).get_cell())
	_glide(second_id, _lineup.get_slot(second_id).get_cell())


func _on_entry_removed(entry_id: int, _slot: LineupSlot) -> void:
	var view: UnitView = _views.get(entry_id, null)
	_views.erase(entry_id)
	if view != null:
		view.pop_out()


func _on_cleared() -> void:
	for view: UnitView in _views.values():
		view.pop_out()
	_views.clear()


func _glide(entry_id: int, local_cell: Vector2i) -> void:
	var view := get_view(entry_id)
	if view != null:
		view.glide_to(_board.cell_to_local(to_board_cell(local_cell)), MOVE_SEC, &"walk")
