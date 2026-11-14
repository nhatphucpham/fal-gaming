#include "skill_selectors.h"

#include "skill_areas.h"

#include "battle/battle_board.h"
#include "battle/battle_sim.h"
#include "battle/battle_targeting.h"

#include <cstdlib>

namespace battle {

namespace {

bool select_self(const BattleSim &, const UnitState &p_caster, const SkillStepDef &, const AreaHandler *, int, Cell *r_anchor) {
	*r_anchor = p_caster.cell;
	return true;
}

// Anchored on the column's frontmost enemy, so the area (usually
// area.column) and the anchor both name that column.
bool select_column_most_enemies(const BattleSim &p_sim, const UnitState &p_caster, const SkillStepDef &, const AreaHandler *, int, Cell *r_anchor) {
	const int col = pick_column_most_enemies(p_sim, p_caster);
	if (col < 0) {
		return false;
	}
	*r_anchor = p_sim.get_units()[get_frontmost_enemy_in_column(p_sim, p_caster.side, col)].cell;
	return true;
}

// The enemy-occupied cell within selector_range (0: any distance) whose area
// catches the most enemies; ties by the standard target tie-break on the
// centre's occupant.
bool select_densest_area(const BattleSim &p_sim, const UnitState &p_caster, const SkillStepDef &p_step, const AreaHandler *p_area, int p_area_size, Cell *r_anchor) {
	const std::vector<UnitState> &units = p_sim.get_units();
	int best = NO_UNIT;
	int best_count = 0;
	std::vector<Cell> cells;
	for (const UnitState &candidate : units) {
		if (!candidate.is_alive || candidate.side == p_caster.side) {
			continue;
		}
		if (p_step.selector_range > 0 && get_distance_cells(p_caster.cell, candidate.cell) > p_step.selector_range) {
			continue;
		}
		cells.clear();
		p_area->collect(candidate.cell, p_caster.side, p_area_size, &cells);
		const int count = static_cast<int>(get_enemies_in_cells(p_sim, p_caster.side, cells).size());
		if (best == NO_UNIT || count > best_count || (count == best_count && is_preferred_candidate(p_caster, candidate, units[best]))) {
			best = candidate.index;
			best_count = count;
		}
	}
	if (best == NO_UNIT) {
		return false;
	}
	*r_anchor = units[best].cell;
	return true;
}

const SelectorHandler SELECTOR_HANDLERS[] = {
	{ "select.self", select_self },
	{ "select.column_most_enemies", select_column_most_enemies },
	{ "select.densest_area", select_densest_area },
};

} // namespace

const SelectorHandler *find_selector_handler(const std::string &p_id) {
	for (const SelectorHandler &handler : SELECTOR_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

std::vector<int> get_enemies_in_cells(const BattleSim &p_sim, int p_side, const std::vector<Cell> &p_cells) {
	std::vector<int> enemies;
	for (const Cell &cell : p_cells) {
		const int occupant = p_sim.get_board().get_occupant(cell);
		if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_side && p_sim.get_units()[occupant].is_alive) {
			enemies.push_back(occupant);
		}
	}
	return enemies;
}

int count_enemies_in_column(const BattleSim &p_sim, int p_side, int p_col) {
	int count = 0;
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.is_alive && unit.side != p_side && unit.cell.col == p_col) {
			count++;
		}
	}
	return count;
}

int get_frontmost_enemy_in_column(const BattleSim &p_sim, int p_side, int p_col) {
	for (int index = 0; index < BOARD_ROWS; index++) {
		const int row = p_side == SIDE_A ? index : BOARD_ROWS - 1 - index;
		const int occupant = p_sim.get_board().get_occupant({ p_col, row });
		if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_side) {
			return occupant;
		}
	}
	return NO_UNIT;
}

int pick_column_most_enemies(const BattleSim &p_sim, const UnitState &p_caster) {
	int best_col = -1;
	int best_count = 0;
	for (int col = 0; col < BOARD_COLS; col++) {
		const int count = count_enemies_in_column(p_sim, p_caster.side, col);
		if (count == 0) {
			continue;
		}
		if (best_col < 0 || count > best_count) {
			best_col = col;
			best_count = count;
			continue;
		}
		if (count < best_count) {
			continue;
		}
		const int distance = std::abs(col - p_caster.cell.col);
		const int best_distance = std::abs(best_col - p_caster.cell.col);
		const bool is_further_left = p_caster.side == SIDE_A ? col < best_col : col > best_col;
		if (distance < best_distance || (distance == best_distance && is_further_left)) {
			best_col = col;
		}
	}
	return best_col;
}

} // namespace battle
