#include "skill_areas.h"

#include "battle/battle_board.h"

namespace battle {

namespace {

void add_if_on_board(const Cell &p_cell, std::vector<Cell> *r_cells) {
	if (is_on_board(p_cell)) {
		r_cells->push_back(p_cell);
	}
}

void collect_single(const Cell &p_anchor, int, int, std::vector<Cell> *r_cells) {
	add_if_on_board(p_anchor, r_cells);
}

// Every cell within p_size cells (Chebyshev), the anchor included; row by
// row, then column.
void collect_square(const Cell &p_anchor, int, int p_size, std::vector<Cell> *r_cells) {
	for (int row = p_anchor.row - p_size; row <= p_anchor.row + p_size; row++) {
		for (int col = p_anchor.col - p_size; col <= p_anchor.col + p_size; col++) {
			add_if_on_board({ col, row }, r_cells);
		}
	}
}

// Front-left, front, front-right of the anchor, in global column order.
void collect_front3(const Cell &p_anchor, int p_side, int, std::vector<Cell> *r_cells) {
	const int row = p_anchor.row + get_forward_row_step(p_side);
	for (int offset = -1; offset <= 1; offset++) {
		add_if_on_board({ p_anchor.col + offset, row }, r_cells);
	}
}

// p_size cells straight ahead of the anchor, nearest first; 0 reaches the
// end of the column.
void collect_column_ahead(const Cell &p_anchor, int p_side, int p_size, std::vector<Cell> *r_cells) {
	const int forward = get_forward_row_step(p_side);
	const int length = p_size > 0 ? p_size : BOARD_ROWS;
	for (int step = 1; step <= length; step++) {
		add_if_on_board({ p_anchor.col, p_anchor.row + forward * step }, r_cells);
	}
}

// The anchor's whole column, from the caster's own back row forward.
void collect_column(const Cell &p_anchor, int p_side, int, std::vector<Cell> *r_cells) {
	for (int index = 0; index < BOARD_ROWS; index++) {
		const int row = p_side == SIDE_A ? index : BOARD_ROWS - 1 - index;
		r_cells->push_back({ p_anchor.col, row });
	}
}

// The anchor and the cells left and right of it, in global column order.
void collect_row3(const Cell &p_anchor, int, int, std::vector<Cell> *r_cells) {
	for (int offset = -1; offset <= 1; offset++) {
		add_if_on_board({ p_anchor.col + offset, p_anchor.row }, r_cells);
	}
}

// The anchor and its four orthogonal neighbours.
void collect_plus(const Cell &p_anchor, int, int, std::vector<Cell> *r_cells) {
	add_if_on_board(p_anchor, r_cells);
	add_if_on_board({ p_anchor.col, p_anchor.row - 1 }, r_cells);
	add_if_on_board({ p_anchor.col - 1, p_anchor.row }, r_cells);
	add_if_on_board({ p_anchor.col + 1, p_anchor.row }, r_cells);
	add_if_on_board({ p_anchor.col, p_anchor.row + 1 }, r_cells);
}

const AreaHandler AREA_HANDLERS[] = {
	{ "area.single", collect_single },
	{ "area.square", collect_square },
	{ "area.front3", collect_front3 },
	{ "area.column_ahead", collect_column_ahead },
	{ "area.column", collect_column },
	{ "area.plus", collect_plus },
	{ "area.row3", collect_row3 },
};

} // namespace

const AreaHandler *find_area_handler(const std::string &p_id) {
	for (const AreaHandler &handler : AREA_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

} // namespace battle
