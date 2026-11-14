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


## The board after moving piece `piece_id` (or placing a new `shop_unit`) to
## local cell `to`, swapping with the piece there like RunState does; an
## empty array when RunState would refuse the move (a full board, a card
## onto a taken cell).
static func preview_pieces(run: RunState, piece_id: int, shop_unit: UnitData, to: Vector2i) -> Array:
	var moving := run.get_piece(piece_id) if shop_unit == null else null
	if shop_unit == null and moving == null:
		return []
	var occupant := run.get_board_piece(to)
	if shop_unit != null and occupant != null:
		return []
	var joins_board := shop_unit != null or not moving.is_on_board()
	if joins_board and occupant == null and run.get_board_count() >= run.get_capacity():
		return []
	var list: Array = []
	for piece: RunPiece in run.get_board_pieces():
		if piece == moving:
			continue
		var cell := piece.cell
		if piece == occupant:
			# A swap: the piece there takes the mover's old cell or the bench.
			if moving == null or not moving.is_on_board():
				continue
			cell = moving.cell
		list.append(_piece(run.catalog.get_unit(piece.unit_id), cell))
	var unit := shop_unit if shop_unit != null else run.catalog.get_unit(moving.unit_id)
	list.append(_piece(unit, to))
	return list


static func _piece(unit: UnitData, cell: Vector2i) -> Dictionary:
	return {"unit": unit, "col": cell.x, "rank": cell.y}
