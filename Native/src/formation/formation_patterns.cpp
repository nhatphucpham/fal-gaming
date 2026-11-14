#include "formation_patterns.h"

namespace formation {

namespace {

bool place(const PatternDef &p_pattern, int p_col, int p_rank, int p_flip, Placement *r_cells) {
	r_cells->clear();
	for (const Slot &slot : p_pattern.slots) {
		const LocalCell cell = { p_col + slot.dcol * p_flip, p_rank + slot.drank };
		if (!is_local_cell_on_board(cell)) {
			return false;
		}
		r_cells->push_back(cell);
	}
	return true;
}

// Slot offsets laid around every anchor cell, optionally mirrored; the
// anchor constraints pin it to a column or rank.
void collect_shape(const PatternDef &p_pattern, std::vector<Placement> *r_placements) {
	Placement cells;
	for (int rank = 1; rank <= RANKS; rank++) {
		if (p_pattern.anchor_rank != 0 && rank != p_pattern.anchor_rank) {
			continue;
		}
		for (int col = 1; col <= COLS; col++) {
			if (p_pattern.anchor_col != 0 && col != p_pattern.anchor_col) {
				continue;
			}
			if (place(p_pattern, col, rank, 1, &cells)) {
				r_placements->push_back(cells);
			}
			if (p_pattern.is_mirrored && place(p_pattern, col, rank, -1, &cells)) {
				r_placements->push_back(cells);
			}
		}
	}
}

const PatternHandler PATTERN_HANDLERS[] = {
	{ "pattern.shape", collect_shape },
};

} // namespace

const PatternHandler *find_pattern_handler(const std::string &p_id) {
	for (const PatternHandler &handler : PATTERN_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

bool is_local_cell_on_board(const LocalCell &p_cell) {
	return p_cell.col >= 1 && p_cell.col <= COLS && p_cell.rank >= 1 && p_cell.rank <= RANKS;
}

} // namespace formation
