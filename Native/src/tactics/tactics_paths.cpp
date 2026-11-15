#include "tactics_paths.h"

#include "tactics_keywords.h"
#include "tactics_sim.h"

#include <functional>
#include <queue>
#include <utility>

namespace tactics {

namespace {

using QueueEntry = std::pair<int, int>;
using MinQueue = std::priority_queue<QueueEntry, std::vector<QueueEntry>, std::greater<QueueEntry>>;

// Cost of stepping into p_cell, or UNREACHABLE when the unit cannot.
int get_enter_cost(const TacticsSim &p_sim, const MoveProfile &p_profile, int p_side, const Cell &p_cell) {
	if (!p_sim.is_on_map(p_cell)) {
		return UNREACHABLE;
	}
	const int occupant = p_sim.get_occupant(p_cell);
	if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_side) {
		return UNREACHABLE;
	}
	const TerrainDef &terrain = p_sim.get_terrain(p_cell);
	if (terrain.is_impassable && !p_profile.ignores_impassable) {
		return UNREACHABLE;
	}
	if (p_profile.ignores_terrain_cost) {
		return 1;
	}
	const int terrain_index = p_sim.get_map().cell_terrain[p_sim.get_cell_index(p_cell)];
	return terrain.move_cost + p_profile.extra_cost_by_terrain[terrain_index];
}

bool is_next_to_enemy(const TacticsSim &p_sim, int p_side, const Cell &p_cell) {
	for (const Cell &direction : DIRECTIONS) {
		const Cell next = p_cell + direction;
		if (!p_sim.is_on_map(next)) {
			continue;
		}
		const int occupant = p_sim.get_occupant(next);
		if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_side) {
			return true;
		}
	}
	return false;
}

} // namespace

PathField find_paths(const TacticsSim &p_sim, int p_unit, int p_max_cost, ZocMode p_zoc) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	const MoveProfile profile = build_move_profile(p_sim, p_unit);
	const bool applies_zoc = p_zoc == ZocMode::APPLY && !profile.ignores_zone_of_control;
	const int cell_count = p_sim.get_map().width * p_sim.get_map().height;
	PathField field;
	field.origin = unit.cell;
	field.cost.assign(cell_count, UNREACHABLE);
	field.previous.assign(cell_count, NO_INDEX);
	std::vector<bool> is_done(cell_count, false);
	MinQueue queue;
	const int origin_index = p_sim.get_cell_index(unit.cell);
	field.cost[origin_index] = 0;
	queue.push({ 0, origin_index });
	while (!queue.empty()) {
		const QueueEntry entry = queue.top();
		queue.pop();
		if (is_done[entry.second]) {
			continue;
		}
		is_done[entry.second] = true;
		const Cell cell = p_sim.get_cell_at(entry.second);
		// Entering an enemy's zone of control ends the move there.
		if (applies_zoc && entry.second != origin_index && is_next_to_enemy(p_sim, unit.side, cell)) {
			continue;
		}
		for (const Cell &direction : DIRECTIONS) {
			const Cell next = cell + direction;
			const int step = get_enter_cost(p_sim, profile, unit.side, next);
			if (step == UNREACHABLE || entry.first + step > p_max_cost) {
				continue;
			}
			const int next_index = p_sim.get_cell_index(next);
			if (entry.first + step < field.cost[next_index]) {
				field.cost[next_index] = entry.first + step;
				field.previous[next_index] = entry.second;
				queue.push({ field.cost[next_index], next_index });
			}
		}
	}
	return field;
}

std::vector<int> find_goal_distances(const TacticsSim &p_sim, int p_unit, const std::vector<Cell> &p_goals) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	const MoveProfile profile = build_move_profile(p_sim, p_unit);
	const int cell_count = p_sim.get_map().width * p_sim.get_map().height;
	std::vector<int> distance(cell_count, UNREACHABLE);
	std::vector<bool> is_done(cell_count, false);
	MinQueue queue;
	for (const Cell &goal : p_goals) {
		const int index = p_sim.get_cell_index(goal);
		distance[index] = 0;
		queue.push({ 0, index });
	}
	while (!queue.empty()) {
		const QueueEntry entry = queue.top();
		queue.pop();
		if (is_done[entry.second]) {
			continue;
		}
		is_done[entry.second] = true;
		const Cell cell = p_sim.get_cell_at(entry.second);
		// Walking backward: stepping from a neighbour into this cell costs
		// this cell's enter cost.
		const int step = get_enter_cost(p_sim, profile, unit.side, cell);
		if (step == UNREACHABLE) {
			continue;
		}
		for (const Cell &direction : DIRECTIONS) {
			const Cell next = cell + direction;
			if (!p_sim.is_on_map(next)) {
				continue;
			}
			const int next_index = p_sim.get_cell_index(next);
			if (entry.first + step < distance[next_index]) {
				distance[next_index] = entry.first + step;
				queue.push({ distance[next_index], next_index });
			}
		}
	}
	return distance;
}

std::vector<Cell> get_path(const TacticsSim &p_sim, const PathField &p_field, const Cell &p_cell) {
	std::vector<Cell> reversed;
	if (!p_sim.is_on_map(p_cell) || p_field.cost[p_sim.get_cell_index(p_cell)] == UNREACHABLE) {
		return reversed;
	}
	for (int index = p_sim.get_cell_index(p_cell); index != NO_INDEX; index = p_field.previous[index]) {
		reversed.push_back(p_sim.get_cell_at(index));
	}
	return std::vector<Cell>(reversed.rbegin(), reversed.rend());
}

bool can_stop_at(const TacticsSim &p_sim, int p_unit, const Cell &p_cell) {
	if (!p_sim.is_on_map(p_cell)) {
		return false;
	}
	const int occupant = p_sim.get_occupant(p_cell);
	if (occupant != NO_UNIT && occupant != p_unit) {
		return false;
	}
	return !p_sim.get_terrain(p_cell).is_impassable || build_move_profile(p_sim, p_unit).ignores_impassable;
}

std::vector<Cell> get_reachable_cells(const TacticsSim &p_sim, int p_unit) {
	const PathField field = find_paths(p_sim, p_unit, p_sim.get_stats(p_unit).move_points, ZocMode::APPLY);
	std::vector<Cell> cells;
	for (size_t index = 0; index < field.cost.size(); index++) {
		const Cell cell = p_sim.get_cell_at(static_cast<int>(index));
		if (field.cost[index] != UNREACHABLE && cell != field.origin && can_stop_at(p_sim, p_unit, cell)) {
			cells.push_back(cell);
		}
	}
	return cells;
}

int get_trailing_straight_cells(const std::vector<Cell> &p_path) {
	if (p_path.size() < 2) {
		return 0;
	}
	const size_t last = p_path.size() - 1;
	const int step_col = p_path[last].col - p_path[last - 1].col;
	const int step_row = p_path[last].row - p_path[last - 1].row;
	int count = 0;
	for (size_t index = last; index > 0; index--) {
		if (p_path[index].col - p_path[index - 1].col != step_col || p_path[index].row - p_path[index - 1].row != step_row) {
			break;
		}
		count++;
	}
	return count;
}

Cell pick_reachable_cell(const TacticsSim &p_sim, int p_unit, const PathField &p_field, const std::function<int(const Cell &)> &p_key) {
	Cell best = p_sim.get_units()[p_unit].cell;
	int best_key = p_key(best);
	int best_cost = 0;
	for (size_t index = 0; index < p_field.cost.size(); index++) {
		const Cell cell = p_sim.get_cell_at(static_cast<int>(index));
		if (p_field.cost[index] == UNREACHABLE || !can_stop_at(p_sim, p_unit, cell)) {
			continue;
		}
		const int key = p_key(cell);
		const int cost = p_field.cost[index];
		const bool is_better = key < best_key || (key == best_key && (cost < best_cost || (cost == best_cost && static_cast<int>(index) < p_sim.get_cell_index(best))));
		if (is_better) {
			best = cell;
			best_key = key;
			best_cost = cost;
		}
	}
	return best;
}

std::vector<Cell> get_attack_cells(const TacticsSim &p_sim, int p_unit, int p_target) {
	std::vector<Cell> cells;
	const Cell target_cell = p_sim.get_units()[p_target].cell;
	const int cell_count = p_sim.get_map().width * p_sim.get_map().height;
	for (int index = 0; index < cell_count; index++) {
		const Cell cell = p_sim.get_cell_at(index);
		if (!can_stop_at(p_sim, p_unit, cell)) {
			continue;
		}
		const Stats stats = p_sim.get_stats_at(p_unit, cell);
		const int distance = get_manhattan(cell, target_cell);
		if (distance >= stats.min_range_cells && distance <= stats.max_range_cells) {
			cells.push_back(cell);
		}
	}
	return cells;
}

} // namespace tactics
