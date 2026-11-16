#include "tactics_sim.h"

#include "tactics_keywords.h"
#include "tactics_paths.h"
#include "tactics_validation.h"
#include "tactics_vision.h"

#include <algorithm>

// TacticsSim's fog of war, weather and times of day: the environment, what
// each side sees and remembers, the ambush cut of a walk and the events
// that tell a side played by hand what it newly sees
// (Docs/systems/tactics_vision.md).

namespace tactics {

namespace {

bool is_fighting(const UnitState &p_unit) {
	return p_unit.is_alive && !p_unit.has_fled;
}

} // namespace

bool TacticsSim::set_environment(const EnvironmentDef &p_environment, std::string *r_error) {
	if (!is_ready || started) {
		*r_error = "set_environment() needs setup() and a battle that has not started";
		return false;
	}
	if (!validate_environment(p_environment, r_error)) {
		return false;
	}
	environment = p_environment;
	return true;
}

const WeatherDef &TacticsSim::get_weather_of_round(int p_round) const {
	const bool is_changed = environment.has_weather_change && p_round >= environment.weather_change_round;
	return is_changed ? environment.weather_after : environment.weather;
}

const DaytimeDef &TacticsSim::get_daytime_of_round(int p_round) const {
	if (environment.daytimes.empty()) {
		return default_daytime;
	}
	const int count = static_cast<int>(environment.daytimes.size());
	const int step = (p_round < 1 ? 0 : p_round - 1) / environment.daytime_step_rounds;
	return environment.daytimes[(environment.daytime_start_index + step) % count];
}

const WeatherDef &TacticsSim::get_weather() const {
	return get_weather_of_round(round);
}

const DaytimeDef &TacticsSim::get_daytime() const {
	return get_daytime_of_round(round);
}

bool TacticsSim::is_cell_visible(int p_side, const Cell &p_cell) const {
	if (!is_on_map(p_cell)) {
		return false;
	}
	const std::vector<uint8_t> &visible = vision[p_side].visible;
	return visible.empty() || visible[get_cell_index(p_cell)] != 0;
}

bool TacticsSim::is_cell_seen(int p_side, const Cell &p_cell) const {
	if (!is_on_map(p_cell)) {
		return false;
	}
	const std::vector<uint8_t> &seen = vision[p_side].seen;
	return seen.empty() || seen[get_cell_index(p_cell)] != 0;
}

bool TacticsSim::is_unit_seen_by(int p_side, int p_unit) const {
	const UnitState &unit = units[p_unit];
	if (!unit.is_alive || unit.side == p_side) {
		return unit.is_alive;
	}
	const std::vector<uint8_t> &seen = vision[p_side].unit_visible;
	return !environment.fog_of_war || (p_unit < static_cast<int>(seen.size()) && seen[p_unit] != 0);
}

Cell TacticsSim::get_last_seen(int p_side, int p_unit) const {
	const std::vector<Cell> &last = vision[p_side].last_seen;
	return p_unit < static_cast<int>(last.size()) ? last[p_unit] : NO_CELL;
}

bool TacticsSim::is_intent_known(int p_side, int p_leader) const {
	if (!is_unit_seen_by(p_side, p_leader)) {
		return false;
	}
	if (!environment.fog_of_war || !(get_weather().hides_intents || get_daytime().hides_intents)) {
		return true;
	}
	const Cell cell = units[p_leader].cell;
	for (const UnitState &unit : units) {
		if (!is_fighting(unit) || unit.side != p_side || !is_on_map(unit.cell)) {
			continue;
		}
		const int read = std::max(rules.intent_read_cells, get_scout_read_cells(*this, unit.index));
		if (get_manhattan(unit.cell, cell) <= read) {
			return true;
		}
	}
	return false;
}

bool TacticsSim::is_out_of_leader_sight(int p_soldier) const {
	const UnitState &soldier = units[p_soldier];
	if (!environment.fog_of_war || is_leader(p_soldier) || soldier.leader == NO_UNIT || !units[soldier.leader].is_alive) {
		return false;
	}
	return !does_unit_see_cell(*this, soldier.leader, soldier.cell);
}

void TacticsSim::reveal_attacker(int p_unit) {
	if (!environment.fog_of_war) {
		return;
	}
	units[p_unit].revealed_end_turn = turn + rules.attack_reveal_phases;
	refresh_vision(0);
}

void TacticsSim::note_walk_sight(int p_unit, const std::vector<Cell> &p_path) {
	if (!environment.fog_of_war || !started || p_path.size() < 3) {
		return;
	}
	const int side = units[p_unit].side;
	SideVision &memory = vision[side];
	const std::vector<uint8_t> lit = compute_lit_cells(*this);
	std::vector<uint8_t> cells(map.width * map.height, 0);
	for (size_t step = 1; step + 1 < p_path.size(); step++) {
		mark_unit_sight(*this, p_unit, p_path[step], lit, cells);
	}
	for (size_t index = 0; index < cells.size(); index++) {
		memory.seen[index] = memory.seen[index] | cells[index];
	}
	// Enemies it passed in sight are remembered where it saw them; hidden
	// ones still need someone next to them.
	for (const UnitState &enemy : units) {
		if (!is_fighting(enemy) || enemy.side == side || !is_on_map(enemy.cell) || cells[get_cell_index(enemy.cell)] == 0) {
			continue;
		}
		bool is_near = !get_terrain(enemy.cell).hides_units || turn < enemy.revealed_end_turn;
		for (size_t step = 1; step + 1 < p_path.size() && !is_near; step++) {
			is_near = get_manhattan(p_path[step], enemy.cell) <= rules.reveal_cells;
		}
		if (is_near) {
			memory.last_seen[enemy.index] = enemy.cell;
		}
	}
}

void TacticsSim::refresh_vision(int p_cause) {
	if (!environment.fog_of_war || !started) {
		return;
	}
	const std::vector<uint8_t> lit = compute_lit_cells(*this);
	const int cell_count = map.width * map.height;
	for (int side = 0; side < SIDE_COUNT; side++) {
		SideVision &memory = vision[side];
		const std::vector<uint8_t> was_visible = memory.visible;
		const std::vector<uint8_t> was_unit_visible = memory.unit_visible;
		compute_side_vision(*this, side, lit, memory);
		memory.seen.resize(cell_count, 0);
		memory.last_seen.resize(units.size(), NO_CELL);
		Event event;
		for (int index = 0; index < cell_count; index++) {
			const bool was = !was_visible.empty() && was_visible[index] != 0;
			const bool is = memory.visible[index] != 0;
			memory.seen[index] = memory.seen[index] | memory.visible[index];
			if (is && !was) {
				event.cells.push_back(get_cell_at(index));
			} else if (was && !is) {
				event.other_cells.push_back(get_cell_at(index));
			}
		}
		for (const UnitState &unit : units) {
			const bool was = unit.index < static_cast<int>(was_unit_visible.size()) && was_unit_visible[unit.index] != 0;
			const bool is = memory.unit_visible[unit.index] != 0;
			Cell &last = memory.last_seen[unit.index];
			if (unit.side == side || !is_fighting(unit)) {
				last = NO_CELL;
			} else if (is) {
				last = unit.cell;
			} else if (last != NO_CELL && memory.visible[get_cell_index(last)] != 0) {
				// The cell is seen again and it is not there: forgotten.
				last = NO_CELL;
			}
			if (unit.side != side && is_fighting(unit) && is && !was) {
				event.units.push_back(unit.index);
			} else if (unit.side != side && was && !is) {
				event.other_units.push_back(unit.index);
			}
		}
		const bool has_change = !event.cells.empty() || !event.other_cells.empty() || !event.units.empty() || !event.other_units.empty();
		if (has_change && !side_is_ai[side]) {
			event.type = EventType::VISION_CHANGED;
			event.side = side;
			event.cause = p_cause;
			emit(event);
		}
	}
}

void TacticsSim::announce_environment(int p_cause) {
	if (round <= 1) {
		return;
	}
	const WeatherDef &before = get_weather_of_round(round - 1);
	const WeatherDef &now = get_weather();
	if (before.id != now.id) {
		Event event;
		event.type = EventType::WEATHER_CHANGED;
		event.content_id = now.id;
		event.detail_id = before.id;
		event.cause = p_cause;
		emit(event);
	}
	const DaytimeDef &was = get_daytime_of_round(round - 1);
	const DaytimeDef &is = get_daytime();
	if (was.id != is.id) {
		Event event;
		event.type = EventType::DAYTIME_CHANGED;
		event.content_id = is.id;
		event.detail_id = was.id;
		event.cause = p_cause;
		emit(event);
	}
}

// Walks are planned around the enemies the side sees; one it does not see
// stops the walk on the last free cell before it, or where its zone of
// control is entered (Docs/systems/tactics_vision.md, Ambush).
int TacticsSim::cut_path_at_ambush(int p_unit, std::vector<Cell> &r_path, Cell *r_blocked) const {
	const UnitState &unit = units[p_unit];
	const bool ignores_zoc = build_move_profile(*this, p_unit).ignores_zone_of_control;
	int stop = static_cast<int>(r_path.size()) - 1;
	int ambusher = NO_UNIT;
	for (int step = 1; step < static_cast<int>(r_path.size()) && ambusher == NO_UNIT; step++) {
		const int occupant = get_occupant(r_path[step]);
		if (occupant != NO_UNIT && units[occupant].side != unit.side) {
			stop = step - 1;
			ambusher = occupant;
			*r_blocked = r_path[step];
			break;
		}
		if (ignores_zoc || step == static_cast<int>(r_path.size()) - 1) {
			continue;
		}
		for (const Cell &direction : DIRECTIONS) {
			const Cell next = r_path[step] + direction;
			const int enemy = is_on_map(next) ? get_occupant(next) : NO_UNIT;
			if (enemy != NO_UNIT && units[enemy].side != unit.side && ambusher == NO_UNIT) {
				stop = step;
				ambusher = enemy;
				*r_blocked = r_path[step + 1];
			}
		}
	}
	if (ambusher == NO_UNIT) {
		return NO_UNIT;
	}
	// Allies may be passed, not stood on: back up to a free cell.
	while (stop > 0 && get_occupant(r_path[stop]) != NO_UNIT && get_occupant(r_path[stop]) != p_unit) {
		stop--;
	}
	r_path.resize(stop + 1);
	return ambusher;
}

} // namespace tactics
