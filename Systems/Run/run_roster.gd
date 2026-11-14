class_name RunRoster
extends RefCounted
## The pieces a run owns and where they stand (bench slots and board
## cells), with the placement rules: capacity, the legend limit, swaps and
## star merges. Owned by RunState, which checks the phase and forwards the
## signals; nothing else calls it. Pieces are kept by id.

signal piece_moved(piece_id: int)
signal pieces_merged(result_id: int, consumed_ids: Array[int])

const Result := RunState.Result

var bench_size: int
var _catalog: Catalog
var _rules: RunRules
var _pieces: Dictionary[int, RunPiece] = {}
var _next_id: int = 1


func _init(catalog: Catalog, rules: RunRules) -> void:
	_catalog = catalog
	_rules = rules
	bench_size = rules.bench_slots


## True when one more 1-star copy of this unit would complete a merge.
func would_merge(unit_id: StringName) -> bool:
	var limits := _merge_limits(unit_id)
	return limits[1] > 1 and count_copies(unit_id, 1) + 1 >= limits[0]


## Whether a bought `unit` may go to this bench slot or board cell (both
## unset: the first free bench slot).
func check_buy_target(unit: UnitData, bench_slot: int, cell: Vector2i, capacity: int) -> Result:
	if cell != RunPiece.NO_CELL:
		if not Lineup.is_valid_cell(cell) or get_board_piece(cell) != null:
			return Result.BAD_TARGET
		if count_board() >= capacity:
			return Result.BOARD_FULL
		if unit.cost == _rules.legend_cost and _count_board_legends() >= _rules.legend_board_limit:
			return Result.LEGEND_LIMIT
		return Result.OK
	if bench_slot != RunPiece.NO_BENCH:
		if bench_slot < 0 or bench_slot >= bench_size or get_bench_piece(bench_slot) != null:
			return Result.BAD_TARGET
		return Result.OK
	return Result.BENCH_FULL if first_free_bench_slot() == RunPiece.NO_BENCH else Result.OK


## Moves a piece onto a board cell, swapping with a piece there; refused
## over `capacity` or past the legend limit.
func move_to_board(piece: RunPiece, cell: Vector2i, capacity: int) -> Result:
	if not Lineup.is_valid_cell(cell):
		return Result.BAD_TARGET
	var other := get_board_piece(cell)
	if other == piece:
		return Result.OK
	if not piece.is_on_board():
		if other == null and count_board() >= capacity:
			return Result.BOARD_FULL
		if not _legends_fit(piece, other):
			return Result.LEGEND_LIMIT
	_swap_places(piece, other, RunPiece.NO_BENCH, cell)
	return Result.OK


## Moves a piece onto a bench slot, swapping with a piece there.
func move_to_bench(piece: RunPiece, slot: int) -> Result:
	if slot < 0 or slot >= bench_size:
		return Result.BAD_TARGET
	var other := get_bench_piece(slot)
	if other == piece:
		return Result.OK
	if piece.is_on_board() and other != null and not _legends_fit(other, piece):
		return Result.LEGEND_LIMIT
	_swap_places(piece, other, slot, RunPiece.NO_CELL)
	return Result.OK


## Merges every group that can merge, one at a time, so merges chain. The
## kept piece is the first in keep order (see find_merge()).
func merge_all() -> void:
	var group := find_merge(_merge_limits)
	while not group.is_empty():
		var keep: RunPiece = group[0]
		var consumed: Array[int] = []
		for piece: RunPiece in group.slice(1):
			keep.has_fought = keep.has_fought or piece.has_fought
			consumed.append(piece.id)
			remove(piece.id)
		if not keep.is_on_board() and not keep.is_on_bench():
			keep.bench_slot = first_free_bench_slot()
		keep.star += 1
		pieces_merged.emit(keep.id, consumed)
		group = find_merge(_merge_limits)
	# A purchase that did not end up merged still needs a bench slot.
	for piece: RunPiece in get_all():
		if not piece.is_on_board() and not piece.is_on_bench():
			piece.bench_slot = first_free_bench_slot()
			piece_moved.emit(piece.id)


## A new piece at a bench slot, a board cell, or nowhere yet (both unset:
## a purchase about to merge).
func add(unit_id: StringName, star: int, bench_slot: int, cell: Vector2i) -> RunPiece:
	var piece := RunPiece.new()
	piece.id = _next_id
	_next_id += 1
	piece.unit_id = unit_id
	piece.star = star
	piece.bench_slot = bench_slot
	piece.cell = cell
	_pieces[piece.id] = piece
	return piece


func remove(piece_id: int) -> void:
	_pieces.erase(piece_id)


func get_piece(piece_id: int) -> RunPiece:
	return _pieces.get(piece_id, null)


## Every piece, by id (the order they were made).
func get_all() -> Array[RunPiece]:
	var ids: Array[int] = []
	ids.assign(_pieces.keys())
	ids.sort()
	var pieces: Array[RunPiece] = []
	for piece_id: int in ids:
		pieces.append(_pieces[piece_id])
	return pieces


func get_bench_piece(slot: int) -> RunPiece:
	for piece: RunPiece in _pieces.values():
		if piece.bench_slot == slot:
			return piece
	return null


func get_board_piece(cell: Vector2i) -> RunPiece:
	if cell == RunPiece.NO_CELL:
		return null
	for piece: RunPiece in _pieces.values():
		if piece.cell == cell:
			return piece
	return null


## The lowest free bench slot, or RunPiece.NO_BENCH when the bench is full.
func first_free_bench_slot() -> int:
	for slot: int in bench_size:
		if get_bench_piece(slot) == null:
			return slot
	return RunPiece.NO_BENCH


## Board pieces in board order: rank 1 first, then lower column.
func get_board_pieces() -> Array[RunPiece]:
	var pieces: Array[RunPiece] = []
	for piece: RunPiece in get_all():
		if piece.is_on_board():
			pieces.append(piece)
	pieces.sort_custom(func(a: RunPiece, b: RunPiece) -> bool:
		return a.cell.y < b.cell.y or (a.cell.y == b.cell.y and a.cell.x < b.cell.x))
	return pieces


## Bench pieces by slot.
func get_bench_pieces() -> Array[RunPiece]:
	var pieces: Array[RunPiece] = []
	for slot: int in bench_size:
		var piece := get_bench_piece(slot)
		if piece != null:
			pieces.append(piece)
	return pieces


func count_board() -> int:
	return get_board_pieces().size()


## Copies of (unit_id, star) owned anywhere, purchases in flight included.
func count_copies(unit_id: StringName, star: int) -> int:
	var count := 0
	for piece: RunPiece in _pieces.values():
		if piece.unit_id == unit_id and piece.star == star:
			count += 1
	return count


## The first group of `needed` copies of one unit and star that may merge
## (star below `max_star`), in keep order: board order, then bench slots,
## then pieces not placed yet. Empty when nothing merges.
## `rule` maps a unit id to [copies needed, max star].
func find_merge(rule: Callable) -> Array[RunPiece]:
	var ordered := get_board_pieces()
	ordered.append_array(get_bench_pieces())
	for piece: RunPiece in get_all():
		if not piece.is_on_board() and not piece.is_on_bench():
			ordered.append(piece)
	for candidate: RunPiece in ordered:
		var limits: Array = rule.call(candidate.unit_id)
		if candidate.star >= limits[1]:
			continue
		var group: Array[RunPiece] = []
		for piece: RunPiece in ordered:
			if piece.unit_id == candidate.unit_id and piece.star == candidate.star:
				group.append(piece)
		if group.size() >= limits[0]:
			return group.slice(0, limits[0])
	return []


## Pieces as plain dictionaries, for the save file.
func to_save_data() -> Array:
	var rows: Array = []
	for piece: RunPiece in get_all():
		rows.append({
			"id": piece.id, "unit_id": String(piece.unit_id), "star": piece.star,
			"has_fought": piece.has_fought, "bench": piece.bench_slot,
			"col": piece.cell.x, "rank": piece.cell.y,
		})
	return rows


## Replaces every piece from save rows. False when a row is malformed.
func load_save_data(rows: Array, next_id: int) -> bool:
	_pieces.clear()
	for row: Variant in rows:
		if not row is Dictionary or not _is_valid_row(row):
			return false
		var piece := RunPiece.new()
		piece.id = int(row["id"])
		piece.unit_id = StringName(row["unit_id"])
		piece.star = int(row["star"])
		piece.has_fought = bool(row["has_fought"])
		piece.bench_slot = int(row["bench"])
		piece.cell = Vector2i(int(row["col"]), int(row["rank"]))
		if _pieces.has(piece.id) or not _is_free(piece):
			return false
		_pieces[piece.id] = piece
	_next_id = next_id
	for piece_id: int in _pieces:
		_next_id = maxi(_next_id, piece_id + 1)
	return true


func get_next_id() -> int:
	return _next_id


# [copies needed, highest star]: legends merge from two copies and stop at
# their own max star.
func _merge_limits(unit_id: StringName) -> Array:
	var unit := _catalog.get_unit(unit_id)
	if unit != null and unit.cost == _rules.legend_cost:
		return [_rules.legend_copies_to_merge, _rules.legend_max_star]
	return [_rules.copies_to_merge, _rules.max_star]


# Puts `piece` at the target and `other` (may be null) where piece stood.
func _swap_places(piece: RunPiece, other: RunPiece, bench_slot: int, cell: Vector2i) -> void:
	var old_bench := piece.bench_slot
	var old_cell := piece.cell
	piece.bench_slot = bench_slot
	piece.cell = cell
	if other != null:
		other.bench_slot = old_bench
		other.cell = old_cell
	piece_moved.emit(piece.id)
	if other != null:
		piece_moved.emit(other.id)


# True when `incoming` may join the board in place of `outgoing` (or of
# nobody) without passing the legend limit.
func _legends_fit(incoming: RunPiece, outgoing: RunPiece) -> bool:
	var count := _count_board_legends()
	if outgoing != null and _is_legend(outgoing):
		count -= 1
	if _is_legend(incoming):
		count += 1
	return count <= _rules.legend_board_limit


func _count_board_legends() -> int:
	var count := 0
	for piece: RunPiece in get_board_pieces():
		if _is_legend(piece):
			count += 1
	return count


func _is_legend(piece: RunPiece) -> bool:
	return _catalog.get_unit(piece.unit_id).cost == _rules.legend_cost


func _is_valid_row(row: Dictionary) -> bool:
	for key: String in ["id", "unit_id", "star", "has_fought", "bench", "col", "rank"]:
		if not row.has(key):
			return false
	var on_bench := int(row["bench"]) >= 0 and int(row["bench"]) < bench_size
	var on_board := Lineup.is_valid_cell(Vector2i(int(row["col"]), int(row["rank"])))
	return on_bench != on_board and int(row["star"]) >= 1 and int(row["star"]) <= 3


func _is_free(piece: RunPiece) -> bool:
	if piece.is_on_bench():
		return get_bench_piece(piece.bench_slot) == null
	return get_board_piece(piece.cell) == null
