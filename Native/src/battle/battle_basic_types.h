#pragma once

// Board constants, sides, cells and damage kinds: the smallest types, shared
// by the battle and skill simulations. Plain C++, no Godot headers.

namespace battle {

constexpr int BOARD_COLS = 7;
constexpr int BOARD_ROWS = 8;
constexpr int SIDE_RANKS = 4;
constexpr int CENTER_COL = 3;
constexpr int NO_UNIT = -1;
constexpr int NO_WINNER = -1;

enum Side {
	SIDE_A = 0,
	SIDE_B = 1,
};

// A global board cell: col 0..6, row 0..7. Side A owns rows 0..3.
struct Cell {
	int col = 0;
	int row = 0;
};

inline bool operator==(const Cell &p_a, const Cell &p_b) {
	return p_a.col == p_b.col && p_a.row == p_b.row;
}

inline bool operator!=(const Cell &p_a, const Cell &p_b) {
	return !(p_a == p_b);
}

enum class DamageKind {
	PHYSICAL = 0,
	MAGIC = 1,
};

} // namespace battle
