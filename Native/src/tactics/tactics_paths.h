#pragma once

// Path search on the tactics map: Dijkstra over terrain costs with the
// unit's keywords, enemy cells blocked, allies passable but not a place to
// stop, and zones of control (entering a cell orthogonally next to an enemy
// ends the move). Ties break by cell index, so results are deterministic.

#include "tactics_types.h"

#include <climits>
#include <functional>
#include <vector>

namespace tactics {

class TacticsSim;

constexpr int UNREACHABLE = INT_MAX / 4;
constexpr int UNLIMITED_COST = UNREACHABLE - 1;

enum class ZocMode {
	APPLY = 0,
	// For distance estimates (AI, free soldiers): zones of control ignored.
	IGNORE = 1,
};

struct PathField {
	Cell origin;
	// Cost to reach each cell (row-major), UNREACHABLE when not reached.
	std::vector<int> cost;
	std::vector<int> previous;
};

// Every cell the unit can reach within p_max_cost from its cell; none for a
// dead unit.
PathField find_paths(const TacticsSim &p_sim, int p_unit, int p_max_cost, ZocMode p_zoc);
// Remaining cost from each cell to the nearest of p_goals (zones of control
// ignored), for walking toward something out of reach this phase.
std::vector<int> find_goal_distances(const TacticsSim &p_sim, int p_unit, const std::vector<Cell> &p_goals);
// From the origin to p_cell, both included; empty when unreached.
std::vector<Cell> get_path(const TacticsSim &p_sim, const PathField &p_field, const Cell &p_cell);
// The unit may end a move here: on the map, passable for it, and free (or
// its own cell).
bool can_stop_at(const TacticsSim &p_sim, int p_unit, const Cell &p_cell);
// Cells the unit can end its move on this phase, without its own cell, in
// row-major order.
std::vector<Cell> get_reachable_cells(const TacticsSim &p_sim, int p_unit);
// Steps of the same direction at the end of the path.
int get_trailing_straight_cells(const std::vector<Cell> &p_path);
// The cell of p_field the unit can stop on (its own included) with the
// lowest key, ties broken by path cost, then cell index.
Cell pick_reachable_cell(const TacticsSim &p_sim, int p_unit, const PathField &p_field, const std::function<int(const Cell &)> &p_key);
// Cells the unit could stand on to attack p_target (range from that cell).
std::vector<Cell> get_attack_cells(const TacticsSim &p_sim, int p_unit, int p_target);

} // namespace tactics
