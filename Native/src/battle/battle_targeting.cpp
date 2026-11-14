#include "battle_targeting.h"

#include "battle_board.h"
#include "battle_sim.h"

#include <cstdlib>

namespace battle {

namespace {

// Lowest score wins; candidates with equal scores go through
// is_preferred_candidate, which is a total order.
template <typename Filter, typename Score>
int pick_best_enemy(const BattleSim &p_sim, const UnitState &p_attacker, Filter p_filter, Score p_score) {
	const std::vector<UnitState> &units = p_sim.get_units();
	int best = NO_UNIT;
	int best_score = 0;
	for (const UnitState &candidate : units) {
		if (!candidate.is_alive || candidate.side == p_attacker.side || !p_filter(candidate)) {
			continue;
		}
		const int score = p_score(candidate);
		if (best == NO_UNIT || score < best_score || (score == best_score && is_preferred_candidate(p_attacker, candidate, units[best]))) {
			best = candidate.index;
			best_score = score;
		}
	}
	return best;
}

int count_row3_enemies(const BattleSim &p_sim, const UnitState &p_attacker, const Cell &p_center) {
	int count = 0;
	for (int offset = -1; offset <= 1; offset++) {
		const int occupant = p_sim.get_board().get_occupant({ p_center.col + offset, p_center.row });
		if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_attacker.side) {
			count++;
		}
	}
	return count;
}

int pick_column_first(const BattleSim &p_sim, const UnitState &p_attacker) {
	auto distance = [&](const UnitState &p_unit) { return get_distance_cells(p_attacker.cell, p_unit.cell); };
	auto in_range = [&](const UnitState &p_unit) { return p_sim.is_in_range(p_attacker, p_unit); };
	auto in_column_and_range = [&](const UnitState &p_unit) { return p_unit.cell.col == p_attacker.cell.col && in_range(p_unit); };

	int target = pick_best_enemy(p_sim, p_attacker, in_column_and_range, distance);
	if (target == NO_UNIT) {
		target = pick_best_enemy(p_sim, p_attacker, in_range, distance);
	}
	return target == NO_UNIT ? pick_nearest_enemy(p_sim, p_attacker) : target;
}

int pick_densest_row3(const BattleSim &p_sim, const UnitState &p_attacker) {
	auto in_range = [&](const UnitState &p_unit) { return p_sim.is_in_range(p_attacker, p_unit); };
	auto density_score = [&](const UnitState &p_unit) { return -count_row3_enemies(p_sim, p_attacker, p_unit.cell); };

	const int target = pick_best_enemy(p_sim, p_attacker, in_range, density_score);
	return target == NO_UNIT ? pick_nearest_enemy(p_sim, p_attacker) : target;
}

const TargetingHandler TARGETING_HANDLERS[] = {
	{ "target.nearest", pick_nearest_enemy, false },
	{ "target.column_first", pick_column_first, false },
	{ "target.densest_row3", pick_densest_row3, true },
};

} // namespace

const TargetingHandler *find_targeting_handler(const std::string &p_id) {
	for (const TargetingHandler &handler : TARGETING_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

bool is_preferred_candidate(const UnitState &p_attacker, const UnitState &p_a, const UnitState &p_b) {
	const bool a_in_column = p_a.cell.col == p_attacker.cell.col;
	const bool b_in_column = p_b.cell.col == p_attacker.cell.col;
	if (a_in_column != b_in_column) {
		return a_in_column;
	}
	if (p_a.hp != p_b.hp) {
		return p_a.hp < p_b.hp;
	}
	const int a_from_center = std::abs(p_a.cell.col - CENTER_COL);
	const int b_from_center = std::abs(p_b.cell.col - CENTER_COL);
	if (a_from_center != b_from_center) {
		return a_from_center < b_from_center;
	}
	if (p_a.cell.col != p_b.cell.col) {
		return p_attacker.side == SIDE_A ? p_a.cell.col < p_b.cell.col : p_a.cell.col > p_b.cell.col;
	}
	return p_a.index < p_b.index;
}

int pick_nearest_enemy(const BattleSim &p_sim, const UnitState &p_attacker) {
	auto any = [](const UnitState &) { return true; };
	auto distance = [&](const UnitState &p_unit) { return get_distance_cells(p_attacker.cell, p_unit.cell); };
	return pick_best_enemy(p_sim, p_attacker, any, distance);
}

} // namespace battle
