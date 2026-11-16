#include "tactics_brain.h"

#include "tactics_combat.h"
#include "tactics_sim.h"

namespace tactics {

namespace {

// Range a ranged unit may gain from terrain (a hill) when picking strikes.
constexpr int TERRAIN_RANGE_SLACK = 2;
constexpr int MAX_TERRAIN_FIT = 9;

// Marks every cell p_enemy could attack next phase.
void mark_reach(const TacticsSim &p_sim, int p_enemy, std::vector<char> &r_marks) {
	const UnitState &enemy = p_sim.get_units()[p_enemy];
	const Stats stats = p_sim.get_stats(p_enemy);
	const PathField field = find_paths(p_sim, p_enemy, stats.move_points, ZocMode::APPLY);
	const MapDef &map = p_sim.get_map();
	for (size_t index = 0; index < field.cost.size(); index++) {
		if (field.cost[index] == UNREACHABLE) {
			continue;
		}
		const Cell from = p_sim.get_cell_at(static_cast<int>(index));
		if (from != enemy.cell && !can_stop_at(p_sim, p_enemy, from)) {
			continue;
		}
		const int reach = stats.max_range_cells;
		for (int rows = -reach; rows <= reach; rows++) {
			const int span = reach - abs_int(rows);
			for (int cols = -span; cols <= span; cols++) {
				const Cell cell = { from.col + cols, from.row + rows };
				if (cell.col < 0 || cell.row < 0 || cell.col >= map.width || cell.row >= map.height) {
					continue;
				}
				if (abs_int(rows) + abs_int(cols) >= stats.min_range_cells) {
					r_marks[p_sim.get_cell_index(cell)] = 1;
				}
			}
		}
	}
}

bool is_enemy_of(const UnitState &p_unit, int p_side) {
	return p_unit.is_alive && p_unit.side != p_side && !p_unit.has_fled;
}

} // namespace

std::vector<int> count_enemy_reach(const TacticsSim &p_sim, int p_side, const Cell &p_watch, std::vector<int> *r_watchers) {
	const int cell_count = p_sim.get_map().width * p_sim.get_map().height;
	std::vector<int> counts(cell_count, 0);
	std::vector<char> marks;
	for (const UnitState &unit : p_sim.get_units()) {
		if (!is_enemy_of(unit, p_side) || !p_sim.is_on_map(unit.cell)) {
			continue;
		}
		marks.assign(cell_count, 0);
		mark_reach(p_sim, unit.index, marks);
		for (int index = 0; index < cell_count; index++) {
			counts[index] += marks[index];
		}
		if (r_watchers != nullptr && p_sim.is_on_map(p_watch) && marks[p_sim.get_cell_index(p_watch)] != 0) {
			r_watchers->push_back(unit.index);
		}
	}
	return counts;
}

std::vector<int> find_enemies_reaching(const TacticsSim &p_sim, int p_side, const Cell &p_cell) {
	std::vector<int> enemies;
	if (!p_sim.is_on_map(p_cell)) {
		return enemies;
	}
	const int cell_count = p_sim.get_map().width * p_sim.get_map().height;
	std::vector<char> marks;
	for (const UnitState &unit : p_sim.get_units()) {
		if (!is_enemy_of(unit, p_side) || !p_sim.is_on_map(unit.cell)) {
			continue;
		}
		marks.assign(cell_count, 0);
		mark_reach(p_sim, unit.index, marks);
		if (marks[p_sim.get_cell_index(p_cell)] != 0) {
			enemies.push_back(unit.index);
		}
	}
	return enemies;
}

int get_dealt(const EngagementResult &p_result) {
	return p_result.attacker_hits * p_result.attacker_damage_per_hit;
}

int get_taken(const EngagementResult &p_result) {
	return p_result.defender_hits * p_result.defender_damage_per_hit;
}

bool is_favourable(const EngagementResult &p_result) {
	return p_result.is_defender_dead || (!p_result.is_attacker_dead && get_dealt(p_result) > get_taken(p_result));
}

std::vector<Strike> list_strikes(const TacticsSim &p_sim, int p_unit, const PathField &p_field, const std::function<bool(const Cell &)> &p_allow) {
	std::vector<Strike> strikes;
	const UnitState &unit = p_sim.get_units()[p_unit];
	if (!unit.is_alive || !p_sim.is_on_map(unit.cell)) {
		return strikes;
	}
	const Stats stats = p_sim.get_stats(p_unit);
	const int near = stats.move_points + stats.max_range_cells + TERRAIN_RANGE_SLACK;
	std::vector<int> enemies;
	for (const UnitState &other : p_sim.get_units()) {
		if (is_enemy_of(other, unit.side) && p_sim.is_on_map(other.cell) && get_manhattan(other.cell, unit.cell) <= near) {
			enemies.push_back(other.index);
		}
	}
	if (enemies.empty()) {
		return strikes;
	}
	TacticsSim scratch = p_sim;
	for (size_t index = 0; index < p_field.cost.size(); index++) {
		const Cell cell = p_sim.get_cell_at(static_cast<int>(index));
		if (p_field.cost[index] == UNREACHABLE || !can_stop_at(p_sim, p_unit, cell) || !p_allow(cell)) {
			continue;
		}
		bool is_placed = false;
		for (int enemy : enemies) {
			if (!is_in_range_from(p_sim, p_unit, cell, p_sim.get_units()[enemy].cell)) {
				continue;
			}
			if (!is_placed) {
				// A soldier that stays keeps no run (the squad step resets it).
				const int straight = cell == unit.cell ? 0 : get_trailing_straight_cells(get_path(p_sim, p_field, cell));
				scratch.place_for_query(p_unit, cell, straight);
				is_placed = true;
			}
			Strike strike;
			strike.cell = cell;
			strike.target = enemy;
			strike.cost = p_field.cost[index];
			strike.result = predict_engagement(scratch, p_unit, enemy);
			strikes.push_back(strike);
		}
	}
	return strikes;
}

Cell pick_safest_strike_cell(const TacticsSim &p_sim, const std::vector<Strike> &p_strikes, const std::vector<int> &p_reach, int p_target) {
	const Strike *best = nullptr;
	int best_fit = 0;
	for (const Strike &strike : p_strikes) {
		if (strike.target != p_target) {
			continue;
		}
		const int fit = get_terrain_fit(p_sim, strike.result.attacker, strike.cell);
		if (best != nullptr) {
			const int reach = p_reach[p_sim.get_cell_index(strike.cell)];
			const int best_reach = p_reach[p_sim.get_cell_index(best->cell)];
			if (strike.result.is_attacker_dead != best->result.is_attacker_dead) {
				if (strike.result.is_attacker_dead) {
					continue;
				}
			} else if (reach != best_reach) {
				if (reach > best_reach) {
					continue;
				}
			} else if (get_taken(strike.result) != get_taken(best->result)) {
				if (get_taken(strike.result) > get_taken(best->result)) {
					continue;
				}
			} else if (fit != best_fit) {
				if (fit < best_fit) {
					continue;
				}
			} else if (strike.cost != best->cost) {
				if (strike.cost > best->cost) {
					continue;
				}
			} else {
				// Strikes come in cell order: the first one stays.
				continue;
			}
		}
		best = &strike;
		best_fit = fit;
	}
	return best == nullptr ? NO_CELL : best->cell;
}

int get_terrain_fit(const TacticsSim &p_sim, int p_unit, const Cell &p_cell) {
	if (!p_sim.is_on_map(p_cell)) {
		return 0;
	}
	const TerrainDef &terrain = p_sim.get_terrain(p_cell);
	const bool is_ranged = p_sim.get_units()[p_unit].def.is_ranged;
	int fit = 0;
	if (is_ranged && terrain.ranged_range_bonus > 0) {
		fit += 3;
	}
	if (terrain.ranged_damage_taken_pct < 0) {
		fit += is_ranged ? 2 : 1;
	}
	if (terrain.armor_bonus > 0) {
		fit += 2;
	}
	if (terrain.damage_taken_pct > 0) {
		fit -= 3;
	}
	return fit > MAX_TERRAIN_FIT ? MAX_TERRAIN_FIT : (fit < -MAX_TERRAIN_FIT ? -MAX_TERRAIN_FIT : fit);
}

} // namespace tactics
