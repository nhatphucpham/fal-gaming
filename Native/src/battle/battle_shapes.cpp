#include "battle_shapes.h"

#include "battle_board.h"
#include "battle_sim.h"

namespace battle {

namespace {

// The first living enemy shield strictly between a ranged attacker and its
// target in the same column, or NO_UNIT.
int find_arrow_blocker(const BattleSim &p_sim, const UnitState &p_attacker, const UnitState &p_target) {
	if (!p_sim.get_class_def(p_attacker).is_ranged || p_attacker.cell.col != p_target.cell.col) {
		return NO_UNIT;
	}
	const int row_step = p_target.cell.row > p_attacker.cell.row ? 1 : -1;
	for (int row = p_attacker.cell.row + row_step; row != p_target.cell.row; row += row_step) {
		const int occupant = p_sim.get_board().get_occupant({ p_attacker.cell.col, row });
		if (occupant == NO_UNIT) {
			continue;
		}
		const UnitState &unit = p_sim.get_units()[occupant];
		if (unit.side != p_attacker.side && p_sim.get_class_def(unit).blocks_arrows) {
			return occupant;
		}
	}
	return NO_UNIT;
}

void collect_single(const BattleSim &p_sim, const UnitState &p_attacker, int p_target, std::vector<Hit> *r_hits) {
	const int blocker = find_arrow_blocker(p_sim, p_attacker, p_sim.get_units()[p_target]);
	if (blocker != NO_UNIT) {
		r_hits->push_back({ blocker, blocker });
		return;
	}
	r_hits->push_back({ p_target, NO_UNIT });
}

// The target's cell and the cells left and right of it, in global column
// order.
void collect_row3(const BattleSim &p_sim, const UnitState &p_attacker, int p_target, std::vector<Hit> *r_hits) {
	const Cell center = p_sim.get_units()[p_target].cell;
	for (int offset = -1; offset <= 1; offset++) {
		const int occupant = p_sim.get_board().get_occupant({ center.col + offset, center.row });
		if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_attacker.side) {
			r_hits->push_back({ occupant, NO_UNIT });
		}
	}
}

// shape.row3 plus the cell behind the target (seen from the attacker).
void collect_row3_behind(const BattleSim &p_sim, const UnitState &p_attacker, int p_target, std::vector<Hit> *r_hits) {
	collect_row3(p_sim, p_attacker, p_target, r_hits);
	const Cell center = p_sim.get_units()[p_target].cell;
	const Cell behind = { center.col, center.row + get_forward_row_step(p_attacker.side) };
	if (!is_on_board(behind)) {
		return;
	}
	const int occupant = p_sim.get_board().get_occupant(behind);
	if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_attacker.side) {
		r_hits->push_back({ occupant, NO_UNIT });
	}
}

const ShapeHandler SHAPE_HANDLERS[] = {
	{ "shape.single", collect_single },
	{ "shape.row3", collect_row3 },
	{ "shape.row3_behind", collect_row3_behind },
};

} // namespace

const ShapeHandler *find_shape_handler(const std::string &p_id) {
	for (const ShapeHandler &handler : SHAPE_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

} // namespace battle
