class_name Lineup
extends RefCounted
## The single owner of one side's formation: which units stand where, in
## local coordinates (col 1..7, rank 1..4). Pure data, no nodes; views listen
## to its signals. Each placed unit gets an entry id that stays the same when
## it moves or swaps, so a view can follow it.
## [codeblock]
## var lineup := Lineup.new(8)
## lineup.entry_added.connect(_on_entry_added)
## var id := lineup.place(&"unit.archer", 1, Vector2i(4, 3))
## lineup.move(id, Vector2i(5, 3))
## [/codeblock]

signal entry_added(entry_id: int)
signal entry_moved(entry_id: int, from_cell: Vector2i, to_cell: Vector2i)
## Two entries traded cells; each now stands where the other stood.
signal entries_swapped(first_id: int, second_id: int)
signal entry_removed(entry_id: int, slot: LineupSlot)
## Every entry was removed at once (clear or load_slots).
signal cleared()

const COLS: int = 7
const RANKS: int = 4
const NO_ENTRY: int = -1

## Most units this side may field.
var max_size: int = 8

var _slots: Dictionary[int, LineupSlot] = {}
var _next_id: int = 1


func _init(size_limit: int = 8) -> void:
	max_size = size_limit


## True when (col, rank) is on the side's half of the board.
static func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 1 and cell.x <= COLS and cell.y >= 1 and cell.y <= RANKS


## Places a unit on a free cell; returns its entry id, or NO_ENTRY when the
## cell is taken or off the half, or the lineup is full.
func place(unit_id: StringName, star: int, cell: Vector2i) -> int:
	if is_full() or not is_valid_cell(cell) or get_entry_at(cell) != NO_ENTRY:
		return NO_ENTRY
	var entry_id := _next_id
	_next_id += 1
	_slots[entry_id] = LineupSlot.create(unit_id, star, cell.x, cell.y)
	entry_added.emit(entry_id)
	return entry_id


## Moves an entry to a free cell. False when the cell is taken or invalid.
func move(entry_id: int, cell: Vector2i) -> bool:
	if not _slots.has(entry_id) or not is_valid_cell(cell) or get_entry_at(cell) != NO_ENTRY:
		return false
	var slot: LineupSlot = _slots[entry_id]
	var from_cell := slot.get_cell()
	slot.local_col = cell.x
	slot.local_rank = cell.y
	entry_moved.emit(entry_id, from_cell, cell)
	return true


## Trades the cells of two different entries.
func swap(first_id: int, second_id: int) -> bool:
	if first_id == second_id or not _slots.has(first_id) or not _slots.has(second_id):
		return false
	var first: LineupSlot = _slots[first_id]
	var second: LineupSlot = _slots[second_id]
	var first_cell := first.get_cell()
	first.local_col = second.local_col
	first.local_rank = second.local_rank
	second.local_col = first_cell.x
	second.local_rank = first_cell.y
	entries_swapped.emit(first_id, second_id)
	return true


func remove(entry_id: int) -> bool:
	if not _slots.has(entry_id):
		return false
	var slot: LineupSlot = _slots[entry_id]
	_slots.erase(entry_id)
	entry_removed.emit(entry_id, slot)
	return true


func clear() -> void:
	_slots.clear()
	cleared.emit()


## Replaces every entry with copies of these slots (extra slots past
## max_size and slots on taken cells are skipped with an error).
func load_slots(slots: Array[LineupSlot]) -> void:
	_slots.clear()
	cleared.emit()
	for slot: LineupSlot in slots:
		if place(slot.unit_id, slot.star, slot.get_cell()) == NO_ENTRY:
			push_error("Lineup: could not load %s at %s" % [slot.unit_id, slot.get_cell()])


## The entry standing on (col, rank), or NO_ENTRY.
func get_entry_at(cell: Vector2i) -> int:
	for entry_id: int in _slots:
		if _slots[entry_id].get_cell() == cell:
			return entry_id
	return NO_ENTRY


## The entry's slot, or null. Read only: change it through this class.
func get_slot(entry_id: int) -> LineupSlot:
	return _slots.get(entry_id, null)


## Entry ids in the order they were placed.
func get_entry_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_slots.keys())
	ids.sort()
	return ids


## Copies of every slot, in placement order.
func to_slots() -> Array[LineupSlot]:
	var copies: Array[LineupSlot] = []
	for entry_id: int in get_entry_ids():
		copies.append(_slots[entry_id].duplicate() as LineupSlot)
	return copies


func size() -> int:
	return _slots.size()


func is_full() -> bool:
	return _slots.size() >= max_size
