#include "tactics_vision.h"

#include "tactics_keywords.h"
#include "tactics_sim.h"

namespace tactics {

namespace {

// Marks every cell within p_radius (Manhattan) of p_center.
void mark_diamond(const TacticsSim &p_sim, const Cell &p_center, int p_radius, std::vector<uint8_t> &r_cells) {
	for (int rows = -p_radius; rows <= p_radius; rows++) {
		const int span = p_radius - abs_int(rows);
		for (int cols = -span; cols <= span; cols++) {
			const Cell cell = { p_center.col + cols, p_center.row + rows };
			if (p_sim.is_on_map(cell)) {
				r_cells[p_sim.get_cell_index(cell)] = 1;
			}
		}
	}
}

bool is_fighting(const UnitState &p_unit) {
	return p_unit.is_alive && !p_unit.has_fled;
}

} // namespace

int get_sight_cost(const TacticsSim &p_sim, const Cell &p_from, const Cell &p_to, int p_limit) {
	int cost = get_manhattan(p_from, p_to);
	if (cost > p_limit) {
		return cost;
	}
	// Bresenham from cell to cell; the ends do not block.
	const int delta_col = abs_int(p_to.col - p_from.col);
	const int delta_row = -abs_int(p_to.row - p_from.row);
	const int step_col = p_from.col < p_to.col ? 1 : -1;
	const int step_row = p_from.row < p_to.row ? 1 : -1;
	int error = delta_col + delta_row;
	Cell cell = p_from;
	while (cell != p_to && cost <= p_limit) {
		const int doubled = 2 * error;
		if (doubled >= delta_row) {
			error += delta_row;
			cell.col += step_col;
		}
		if (doubled <= delta_col) {
			error += delta_col;
			cell.row += step_row;
		}
		if (cell != p_to) {
			cost += p_sim.get_terrain(cell).sight_block;
		}
	}
	return cost;
}

int get_vision_radius(const TacticsSim &p_sim, int p_unit, const Cell &p_cell, bool p_by_day) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	int radius = unit.def.vision_cells + p_sim.get_weather().vision_delta;
	if (p_sim.is_on_map(p_cell)) {
		radius += p_sim.get_terrain(p_cell).vision_bonus;
	}
	if (!p_by_day) {
		radius += p_sim.get_daytime().vision_delta;
	}
	return radius < 1 ? 1 : radius;
}

std::vector<uint8_t> compute_lit_cells(const TacticsSim &p_sim) {
	const MapDef &map = p_sim.get_map();
	std::vector<uint8_t> lit(map.width * map.height, 0);
	for (int index = 0; index < map.width * map.height; index++) {
		const int light = map.terrains[map.cell_terrain[index]].light_cells;
		if (light > 0) {
			mark_diamond(p_sim, p_sim.get_cell_at(index), light, lit);
		}
	}
	const int carried = p_sim.get_rules().leader_light_cells;
	for (const UnitState &unit : p_sim.get_units()) {
		if (is_fighting(unit) && p_sim.is_leader(unit.index) && p_sim.is_on_map(unit.cell) && carried > 0) {
			mark_diamond(p_sim, unit.cell, carried, lit);
		}
	}
	return lit;
}

void mark_unit_sight(const TacticsSim &p_sim, int p_unit, const Cell &p_from, const std::vector<uint8_t> &p_lit, std::vector<uint8_t> &r_cells) {
	const int radius = get_vision_radius(p_sim, p_unit, p_from, false);
	const bool uses_lights = p_sim.get_daytime().uses_lights;
	const int day_radius = uses_lights ? get_vision_radius(p_sim, p_unit, p_from, true) : radius;
	const int reach = radius > day_radius ? radius : day_radius;
	for (int rows = -reach; rows <= reach; rows++) {
		const int span = reach - abs_int(rows);
		for (int cols = -span; cols <= span; cols++) {
			const Cell cell = { p_from.col + cols, p_from.row + rows };
			if (!p_sim.is_on_map(cell)) {
				continue;
			}
			const int index = p_sim.get_cell_index(cell);
			if (r_cells[index] != 0) {
				continue;
			}
			const int limit = uses_lights && p_lit[index] != 0 ? day_radius : radius;
			if (get_sight_cost(p_sim, p_from, cell, limit) <= limit) {
				r_cells[index] = 1;
			}
		}
	}
}

bool is_scout(const TacticsSim &p_sim, int p_unit) {
	return get_scout_read_cells(p_sim, p_unit) > 0;
}

int get_scout_read_cells(const TacticsSim &p_sim, int p_unit) {
	int best = 0;
	for (const KeywordDef *keyword : p_sim.collect_keywords(p_unit)) {
		if (keyword->handler->is_scout && keyword->amount > best) {
			best = keyword->amount;
		}
	}
	return best;
}

void compute_side_vision(const TacticsSim &p_sim, int p_side, const std::vector<uint8_t> &p_lit, SideVision &r_vision) {
	const MapDef &map = p_sim.get_map();
	const int cell_count = map.width * map.height;
	const std::vector<UnitState> &units = p_sim.get_units();
	r_vision.visible.assign(cell_count, 0);
	r_vision.scout_visible.assign(cell_count, 0);
	r_vision.unit_visible.assign(units.size(), 0);
	// Cells a unit of the side stands next to: hidden enemies show there.
	std::vector<uint8_t> near(cell_count, 0);
	const int reveal = p_sim.get_rules().reveal_cells;
	for (const UnitState &unit : units) {
		if (!is_fighting(unit) || unit.side != p_side || !p_sim.is_on_map(unit.cell)) {
			continue;
		}
		mark_unit_sight(p_sim, unit.index, unit.cell, p_lit, r_vision.visible);
		if (is_scout(p_sim, unit.index)) {
			mark_unit_sight(p_sim, unit.index, unit.cell, p_lit, r_vision.scout_visible);
		}
		mark_diamond(p_sim, unit.cell, reveal, near);
	}
	// At night a leader's own light gives it away, in a forest too.
	const bool shows_lights = p_sim.get_daytime().uses_lights && p_sim.get_rules().leader_light_cells > 0;
	for (const UnitState &unit : units) {
		if (!is_fighting(unit) || !p_sim.is_on_map(unit.cell)) {
			continue;
		}
		if (unit.side == p_side || p_sim.get_turn() < unit.revealed_end_turn) {
			r_vision.unit_visible[unit.index] = 1;
			continue;
		}
		const int index = p_sim.get_cell_index(unit.cell);
		const bool is_lit = shows_lights && p_sim.is_leader(unit.index);
		const bool is_hidden = p_sim.get_terrain(unit.cell).hides_units && near[index] == 0 && r_vision.scout_visible[index] == 0 && !is_lit;
		r_vision.unit_visible[unit.index] = r_vision.visible[index] != 0 && !is_hidden ? 1 : 0;
	}
}

bool does_unit_see_cell(const TacticsSim &p_sim, int p_viewer, const Cell &p_cell) {
	const UnitState &viewer = p_sim.get_units()[p_viewer];
	if (!is_fighting(viewer) || !p_sim.is_on_map(viewer.cell) || !p_sim.is_on_map(p_cell)) {
		return false;
	}
	const int radius = get_vision_radius(p_sim, p_viewer, viewer.cell, false);
	int limit = radius;
	if (p_sim.get_daytime().uses_lights && compute_lit_cells(p_sim)[p_sim.get_cell_index(p_cell)] != 0) {
		limit = get_vision_radius(p_sim, p_viewer, viewer.cell, true);
	}
	return get_sight_cost(p_sim, viewer.cell, p_cell, limit) <= limit;
}

} // namespace tactics
