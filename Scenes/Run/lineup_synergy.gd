class_name LineupSynergy
extends RefCounted
## Builds Synergy.evaluate() pieces from the run's board, from an enemy
## Lineup, or from the board as a move would leave it (the drag preview).
## Nothing here changes the run: a preview works on a copied list.
## [codeblock]
## var result := catalog.get_synergy().evaluate(LineupSynergy.run_pieces(run))
## [/codeblock]

const NO_CELL := Vector2i(-1, -1)


## The run's board pieces as evaluate() pieces (local cells).
static func run_pieces(run: RunState) -> Array:
	var list: Array = []
	for piece: RunPiece in run.get_board_pieces():
		list.append(_piece(run.catalog.get_unit(piece.unit_id), piece.cell))
	return list


## An enemy line-up as evaluate() pieces (its own local cells).
static func lineup_pieces(catalog: Catalog, lineup: Lineup) -> Array:
	var list: Array = []
	for entry_id: int in lineup.get_entry_ids():
		var slot := lineup.get_slot(entry_id)
		list.append(_piece(catalog.get_unit(slot.unit_id), Vector2i(slot.local_col, slot.local_rank)))
	return list


## The board as dropping piece `piece_id` (or buying `shop_unit`) on local
## cell `to` would leave it, from RunState.preview_board(), so the preview
## follows RunState's own rules (swaps, merging purchases, capacity, the
## legend limit); an empty array when RunState would refuse it.
static func preview_pieces(run: RunState, piece_id: int, shop_unit: UnitData, to: Vector2i) -> Array:
	var board: Array[RunPiece] = []
	var unit_id := shop_unit.id if shop_unit != null else &""
	if run.preview_board(piece_id, unit_id, to, board) != RunState.Result.OK:
		return []
	var list: Array = []
	for piece: RunPiece in board:
		list.append(_piece(run.catalog.get_unit(piece.unit_id), piece.cell))
	return list


static func _piece(unit: UnitData, cell: Vector2i) -> Dictionary:
	return {"unit": unit, "col": cell.x, "rank": cell.y}
