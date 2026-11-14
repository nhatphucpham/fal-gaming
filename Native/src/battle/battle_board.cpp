#include "battle_board.h"

#include <cstdlib>

namespace battle {

namespace {

constexpr int CELL_COUNT = BOARD_COLS * BOARD_ROWS;
constexpr int NO_SLOT = -1;
constexpr int NEIGHBOR_COUNT = 4;

// Step order: forward, sideways toward the target's column, the other
// sideways, backward. With the target in the same column, the unit's own
// left (A: lower col, B: higher col) counts as toward it.
std::array<Cell, NEIGHBOR_COUNT> get_neighbor_steps(const PathQuery &p_query, const Cell &p_from) {
	const int forward = get_forward_row_step(p_query.side);
	int toward = p_query.target.col - p_from.col;
	if (toward == 0) {
		toward = p_query.side == SIDE_A ? -1 : 1;
	}
	toward = toward > 0 ? 1 : -1;
	return { { { 0, forward }, { toward, 0 }, { -toward, 0 }, { 0, -forward } } };
}

int get_cell_slot(const Cell &p_cell) {
	return p_cell.row * BOARD_COLS + p_cell.col;
}

Cell get_slot_cell(int p_slot) {
	return { p_slot % BOARD_COLS, p_slot / BOARD_COLS };
}

Cell trace_first_step(const std::array<int, CELL_COUNT> &p_parents, int p_start_slot, int p_goal_slot) {
	int slot = p_goal_slot;
	while (p_parents[slot] != p_start_slot) {
		slot = p_parents[slot];
	}
	return get_slot_cell(slot);
}

} // namespace

Board::Board() {
	clear();
}

int Board::get_slot(const Cell &p_cell) {
	return is_on_board(p_cell) ? get_cell_slot(p_cell) : NO_SLOT;
}

void Board::clear() {
	occupants.fill(NO_UNIT);
}

int Board::get_occupant(const Cell &p_cell) const {
	const int slot = get_slot(p_cell);
	return slot == NO_SLOT ? NO_UNIT : occupants[slot];
}

bool Board::is_free(const Cell &p_cell) const {
	return is_on_board(p_cell) && get_occupant(p_cell) == NO_UNIT;
}

void Board::place(const Cell &p_cell, int p_unit) {
	occupants[get_slot(p_cell)] = p_unit;
}

void Board::remove(const Cell &p_cell) {
	occupants[get_slot(p_cell)] = NO_UNIT;
}

bool is_on_board(const Cell &p_cell) {
	return p_cell.col >= 0 && p_cell.col < BOARD_COLS && p_cell.row >= 0 && p_cell.row < BOARD_ROWS;
}

int get_distance_cells(const Cell &p_a, const Cell &p_b) {
	const int cols = std::abs(p_a.col - p_b.col);
	const int rows = std::abs(p_a.row - p_b.row);
	return cols > rows ? cols : rows;
}

int get_forward_row_step(int p_side) {
	return p_side == SIDE_A ? 1 : -1;
}

bool is_local_cell_valid(int p_local_col, int p_local_rank) {
	return p_local_col >= 1 && p_local_col <= BOARD_COLS && p_local_rank >= 1 && p_local_rank <= SIDE_RANKS;
}

Cell local_to_global(int p_side, int p_local_col, int p_local_rank) {
	if (p_side == SIDE_A) {
		return { p_local_col - 1, SIDE_RANKS - p_local_rank };
	}
	return { BOARD_COLS - p_local_col, SIDE_RANKS - 1 + p_local_rank };
}

Cell global_to_local(int p_side, const Cell &p_cell) {
	if (p_side == SIDE_A) {
		return { p_cell.col + 1, SIDE_RANKS - p_cell.row };
	}
	return { BOARD_COLS - p_cell.col, p_cell.row - (SIDE_RANKS - 1) };
}

bool find_first_step(const Board &p_board, const PathQuery &p_query, Cell *r_step) {
	std::array<int, CELL_COUNT> parents;
	parents.fill(NO_SLOT);
	std::array<int, CELL_COUNT> queue;
	int queue_head = 0;
	int queue_tail = 0;
	const int start_slot = get_cell_slot(p_query.start);
	parents[start_slot] = start_slot;
	queue[queue_tail++] = start_slot;

	while (queue_head < queue_tail) {
		const int slot = queue[queue_head++];
		const Cell cell = get_slot_cell(slot);
		if (slot != start_slot && get_distance_cells(cell, p_query.target) <= p_query.range_cells) {
			*r_step = trace_first_step(parents, start_slot, slot);
			return true;
		}
		for (const Cell &step : get_neighbor_steps(p_query, cell)) {
			const Cell next = { cell.col + step.col, cell.row + step.row };
			if (!p_board.is_free(next) || parents[get_cell_slot(next)] != NO_SLOT) {
				continue;
			}
			parents[get_cell_slot(next)] = slot;
			queue[queue_tail++] = get_cell_slot(next);
		}
	}
	return false;
}

} // namespace battle
