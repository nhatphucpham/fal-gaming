#pragma once

// Board occupancy, coordinates, distance and path search for the battle.

#include "battle_types.h"

#include <array>

namespace battle {

// Which unit occupies each cell. A moving unit already occupies its
// destination, so a cell is free only when nobody is in it or moving into it.
class Board {
	std::array<int, BOARD_COLS * BOARD_ROWS> occupants;

	static int get_slot(const Cell &p_cell);

public:
	Board();

	void clear();
	int get_occupant(const Cell &p_cell) const;
	bool is_free(const Cell &p_cell) const;
	void place(const Cell &p_cell, int p_unit);
	void remove(const Cell &p_cell);
};

bool is_on_board(const Cell &p_cell);
// Chebyshev distance: a diagonal step counts 1.
int get_distance_cells(const Cell &p_a, const Cell &p_b);
// +1 for side A, -1 for side B.
int get_forward_row_step(int p_side);
bool is_local_cell_valid(int p_local_col, int p_local_rank);
// Local col 1..7, rank 1..4 (1 is the front rank) to a global cell.
Cell local_to_global(int p_side, int p_local_col, int p_local_rank);
// Inverse of local_to_global; returns {local col, rank}. The rank is outside
// 1..4 for cells in the enemy half.
Cell global_to_local(int p_side, const Cell &p_cell);

struct PathQuery {
	Cell start;
	Cell target;
	int range_cells = 1;
	int side = SIDE_A;
};

// Breadth-first search over free cells for the nearest cell from which the
// target is within range. Sets r_step to the first step and returns true, or
// returns false when no such cell is reachable.
bool find_first_step(const Board &p_board, const PathQuery &p_query, Cell *r_step);

} // namespace battle
