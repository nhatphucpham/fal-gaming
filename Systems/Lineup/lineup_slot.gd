class_name LineupSlot
extends Resource
## One unit of a formation: which unit, its star level and its cell in local
## coordinates of its side (col 1..7 from the side's left, rank 1..4 with 1
## the front rank; see Docs/systems/battle.md).
## [codeblock]
## var slot := LineupSlot.create(&"unit.archer", 1, 4, 3)
## [/codeblock]

@export var unit_id: StringName = &""
@export_range(1, 3) var star: int = 1
@export_range(1, 7) var local_col: int = 1
@export_range(1, 4) var local_rank: int = 1


## A new slot with these values.
static func create(unit: StringName, star_level: int, col: int, rank: int) -> LineupSlot:
	var slot := LineupSlot.new()
	slot.unit_id = unit
	slot.star = star_level
	slot.local_col = col
	slot.local_rank = rank
	return slot


## The slot's cell as a Vector2i (local col, rank).
func get_cell() -> Vector2i:
	return Vector2i(local_col, local_rank)
