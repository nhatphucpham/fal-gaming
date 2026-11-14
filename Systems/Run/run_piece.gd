class_name RunPiece
extends RefCounted
## One unit the player owns in a run, on the bench or on the board. Owned
## and changed only by RunState; others read it. `id` stays the same while
## the piece moves and when it is the one a merge keeps.

const NO_BENCH: int = -1
## The cell of a piece that is not on the board.
const NO_CELL := Vector2i.ZERO

var id: int = 0
var unit_id: StringName = &""
var star: int = 1
## True once the piece was on the board when a battle started.
var has_fought: bool = false
## Bench slot 0..5, or NO_BENCH.
var bench_slot: int = NO_BENCH
## Local (col 1..7, rank 1..4) on the board, or NO_CELL.
var cell: Vector2i = NO_CELL


func is_on_board() -> bool:
	return cell != NO_CELL


func is_on_bench() -> bool:
	return bench_slot != NO_BENCH
