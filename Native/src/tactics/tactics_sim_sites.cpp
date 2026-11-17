#include "tactics_sim.h"

#include "tactics_objectives.h"
#include "tactics_paths.h"
#include "tactics_sites.h"

#include <algorithm>

// TacticsSim's sites and objectives: using a site, what each side knows of
// the sites, the convoy's road, units that join or leave mid-battle
// (Docs/systems/tactics_sites.md, Docs/systems/tactics_objectives.md).

namespace tactics {

namespace {

bool fail(std::string *r_error, const std::string &p_message) {
	*r_error = p_message;
	return false;
}

bool has_choice(const SiteHandler &p_handler, const std::string &p_choice) {
	return std::find(p_handler.choices.begin(), p_handler.choices.end(), p_choice) != p_handler.choices.end();
}

} // namespace

bool TacticsSim::set_objective(const ObjectiveDef &p_objective, std::string *r_error) {
	if (!is_ready || started) {
		return fail(r_error, "set_objective() needs setup() and a battle that has not started");
	}
	if (!validate_objective(p_objective, map, r_error)) {
		return false;
	}
	int general = NO_UNIT;
	if (p_objective.general != NO_INDEX) {
		int order = 0;
		for (const UnitState &unit : units) {
			if (unit.side == SIDE_B && is_leader(unit.index)) {
				general = order == p_objective.general ? unit.index : general;
				order++;
			}
		}
		if (general == NO_UNIT) {
			return fail(r_error, p_objective.id + " names general " + std::to_string(p_objective.general) + " but side 1 has no such leader");
		}
	}
	if (p_objective.required_leader != NO_INDEX) {
		int leaders = 0;
		for (const UnitState &unit : units) {
			leaders += unit.side == SIDE_A && is_leader(unit.index) ? 1 : 0;
		}
		if (p_objective.required_leader >= leaders) {
			return fail(r_error, p_objective.id + " names leader " + std::to_string(p_objective.required_leader) + " but side 0 has " + std::to_string(leaders));
		}
	}
	objective = p_objective;
	general_unit = general;
	general_post = general != NO_UNIT ? units[general].cell : NO_CELL;
	return true;
}

bool TacticsSim::can_use_site(int p_unit, int p_site, const std::string &p_choice, int p_option, std::string *r_error) const {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	if (p_site < 0 || p_site >= static_cast<int>(map.sites.size())) {
		return fail(r_error, "there is no site " + std::to_string(p_site));
	}
	const SitePlacement &site = map.sites[p_site];
	const UnitState &leader = units[p_unit];
	if (!has_choice(*site.def.handler, p_choice)) {
		return fail(r_error, site.def.id + " has no choice \"" + p_choice + "\"");
	}
	if (leader.has_used_site) {
		return fail(r_error, "leader " + std::to_string(p_unit) + " already used a site this phase");
	}
	if (get_manhattan(leader.cell, site.cell) > site.def.reach_cells) {
		return fail(r_error, "leader " + std::to_string(p_unit) + " is too far from " + site.def.id);
	}
	if (p_option < 0 || p_option >= get_site_option_count(site.def, p_choice)) {
		return fail(r_error, site.def.id + " has no option " + std::to_string(p_option) + " for " + p_choice);
	}
	return site.def.handler->check(*this, p_site, p_unit, p_choice, p_option, r_error);
}

bool TacticsSim::has_site_action(int p_unit) const {
	std::string error;
	for (int site = 0; site < static_cast<int>(map.sites.size()); site++) {
		for (const std::string &choice : map.sites[site].def.handler->choices) {
			for (int option = 0; option < get_site_option_count(map.sites[site].def, choice); option++) {
				if (can_use_site(p_unit, site, choice, option, &error)) {
					return true;
				}
			}
		}
	}
	return false;
}

// Using a site is never taken back: the steps back end here
// (Docs/systems/tactics_sites.md, Undo).
bool TacticsSim::use_site(int p_unit, int p_site, const std::string &p_choice, int p_option, std::string *r_error) {
	if (!can_use_site(p_unit, p_site, p_choice, p_option, r_error)) {
		return false;
	}
	clear_undo();
	const SitePlacement &site = map.sites[p_site];
	units[p_unit].has_used_site = true;
	Event event;
	event.type = EventType::SITE_USED;
	event.unit = p_unit;
	event.side = units[p_unit].side;
	event.target = p_site;
	event.kind = p_choice;
	event.value = p_option;
	event.content_id = site.def.id;
	event.to = site.cell;
	event.amount = get_seen_mask(site.cell);
	const int use_id = emit(event);
	site.def.handler->apply(*this, p_site, p_unit, p_choice, p_option, use_id);
	if (!finished && site.def.ends_turn && units[p_unit].is_alive && !units[p_unit].has_waited) {
		wait(p_unit, r_error);
	}
	return true;
}

bool TacticsSim::set_convoy_hold(bool p_holds, std::string *r_error) {
	if (!started || finished || active_side != SIDE_A || side_is_ai[SIDE_A]) {
		return fail(r_error, "set_convoy_hold() needs a running battle in side 0's own phase");
	}
	if (convoy_unit == NO_UNIT || !units[convoy_unit].is_alive) {
		return fail(r_error, "there is no convoy");
	}
	if (convoy_holds == p_holds) {
		return true;
	}
	// The order belongs to the phase as a whole: no move before it comes
	// back without it.
	clear_undo();
	convoy_holds = p_holds;
	Event event;
	event.type = EventType::CONVOY_HALTED;
	event.unit = convoy_unit;
	event.kind = p_holds ? "hold" : "go";
	event.value = p_holds ? 1 : 0;
	emit(event);
	return true;
}

int TacticsSim::get_seen_mask(const Cell &p_cell) const {
	int mask = 0;
	for (int side = 0; side < SIDE_COUNT; side++) {
		mask |= is_cell_visible(side, p_cell) ? 1 << side : 0;
	}
	return mask;
}

SiteState TacticsSim::get_known_site(int p_side, int p_site) const {
	if (!environment.fog_of_war || !started) {
		SiteState state = sites[p_site];
		state.is_known = true;
		return state;
	}
	return site_memory[p_side][p_site];
}

void TacticsSim::change_site(int p_site, int p_side, const std::string &p_kind, int p_cause) {
	const SiteState &state = sites[p_site];
	Event event;
	event.type = EventType::SITE_CHANGED;
	event.target = p_site;
	event.side = p_side;
	event.kind = p_kind;
	event.value = static_cast<int>(state.status);
	event.threshold = state.owner;
	event.to = map.sites[p_site].cell;
	event.content_id = map.sites[p_site].def.id;
	event.amount = get_seen_mask(event.to);
	event.cause = p_cause;
	emit(event);
	// A stronghold's owner sees around it.
	refresh_vision(p_cause);
	update_site_memory();
}

void TacticsSim::update_site_memory() {
	if (!environment.fog_of_war || !started) {
		return;
	}
	for (int side = 0; side < SIDE_COUNT; side++) {
		site_memory[side].resize(sites.size());
		for (size_t index = 0; index < sites.size(); index++) {
			if (is_cell_visible(side, map.sites[index].cell)) {
				site_memory[side][index] = sites[index];
				site_memory[side][index].is_known = true;
			}
		}
	}
}

// The convoy goes along its road as far as its move points take it. An
// enemy its side sees standing on the road stops it before that cell; it
// passes its own side's units but never stops on one. Enemies beside the
// road do not stop it: holding it is the player's call ("Xe dừng").
std::vector<Cell> TacticsSim::get_convoy_path() const {
	std::vector<Cell> path;
	if (!started || finished || convoy_unit == NO_UNIT || convoy_holds || !units[convoy_unit].is_alive) {
		return path;
	}
	const UnitState &convoy = units[convoy_unit];
	const std::vector<Cell> &road = objective.road_cells;
	const auto at = std::find(road.begin(), road.end(), convoy.cell);
	if (at == road.end()) {
		return path;
	}
	path.push_back(convoy.cell);
	// Its own phase's points; out of it, a full phase's (the preview).
	int budget = active_side == SIDE_A ? convoy.move_points_left : get_stats(convoy_unit).move_points;
	for (auto next = at + 1; next != road.end(); ++next) {
		const int occupant = get_occupant(*next);
		if (occupant != NO_UNIT && units[occupant].side != SIDE_A && is_unit_seen_by(SIDE_A, occupant)) {
			break;
		}
		const int cost = get_step_cost(*this, convoy_unit, *next);
		if (cost == UNREACHABLE || cost > budget) {
			break;
		}
		budget -= cost;
		path.push_back(*next);
	}
	// Only our own units are known to stand there: an unseen enemy is an
	// ambush at the walk, not a shorter preview that would give it away.
	while (path.size() > 1 && get_occupant(path.back()) != NO_UNIT && units[get_occupant(path.back())].side == SIDE_A) {
		path.pop_back();
	}
	if (path.size() < 2) {
		path.clear();
	}
	return path;
}

int TacticsSim::count_escaped_leaders(int p_side) const {
	int count = 0;
	for (const UnitState &unit : units) {
		count += unit.side == p_side && unit.has_escaped && is_leader(unit.index) ? 1 : 0;
	}
	return count;
}

int TacticsSim::heal_unit(int p_unit, int p_amount, const std::string &p_source_id, int p_cause) {
	UnitState &unit = units[p_unit];
	if (!unit.is_alive || p_amount <= 0 || unit.hp >= unit.def.max_hp) {
		return 0;
	}
	const int gained = unit.hp + p_amount > unit.def.max_hp ? unit.def.max_hp - unit.hp : p_amount;
	unit.hp += gained;
	Event event;
	event.type = EventType::UNIT_HEALED;
	event.unit = p_unit;
	event.amount = gained;
	event.hp_after = unit.hp;
	event.content_id = p_source_id;
	event.cause = p_cause;
	emit(event);
	return gained;
}

void TacticsSim::add_supplies(int p_side, int p_amount, const std::string &p_source_id, int p_cause) {
	if (p_amount <= 0) {
		return;
	}
	supplies[p_side] += p_amount;
	Event event;
	event.type = EventType::SUPPLIES_GAINED;
	event.side = p_side;
	event.amount = p_amount;
	event.value = supplies[p_side];
	event.content_id = p_source_id;
	event.cause = p_cause;
	emit(event);
}

void TacticsSim::init_unit_phase(UnitState &r_unit) {
	r_unit.has_moved = false;
	r_unit.has_attacked = false;
	r_unit.has_cast = false;
	r_unit.has_waited = false;
	r_unit.has_squad_struck = false;
	r_unit.has_rescued = false;
	r_unit.has_used_site = false;
	r_unit.is_held_by_zoc = false;
	r_unit.straight_cells = 0;
	r_unit.last_step = { 0, 0 };
	r_unit.phase_start_cell = r_unit.cell;
	r_unit.phase_start_heading = r_unit.heading;
	r_unit.phase_start_streak = r_unit.heading_streak;
	r_unit.move_points_left = r_unit.is_alive ? get_stats(r_unit.index).move_points : 0;
}

int TacticsSim::add_runtime_unit(int p_side, const UnitDef &p_def, int p_leader, const std::string &p_kind) {
	UnitState unit;
	unit.index = static_cast<int>(units.size());
	unit.side = p_side;
	unit.def = p_def;
	unit.hp = p_def.max_hp;
	unit.leader = p_leader;
	unit.start_side = p_side;
	unit.arrival_kind = p_kind;
	unit.cell = NO_CELL;
	unit.heading = map.facing[p_side];
	unit.order = p_def.role == UnitRole::LEADER ? p_def.default_order : 0;
	units.push_back(unit);
	return unit.index;
}

// The free cell nearest p_near (Manhattan, then cell index) p_unit may
// stand on; NO_INDEX when there is none.
int TacticsSim::find_spawn_cell(int p_unit, const Cell &p_near) const {
	const int cell_count = map.width * map.height;
	int best = NO_INDEX;
	for (int index = 0; index < cell_count; index++) {
		const Cell cell = get_cell_at(index);
		if (occupants[index] == NO_UNIT && can_stop_at(*this, p_unit, cell) && (best == NO_INDEX || get_manhattan(cell, p_near) < get_manhattan(get_cell_at(best), p_near))) {
			best = index;
		}
	}
	return best;
}

void TacticsSim::emit_arrival(int p_unit, int p_cause) {
	UnitState &unit = units[p_unit];
	if (unit.side == active_side) {
		init_unit_phase(unit);
	}
	Event event;
	event.type = EventType::UNIT_ARRIVED;
	event.unit = p_unit;
	event.side = unit.side;
	event.target = unit.leader;
	event.to = unit.cell;
	event.kind = unit.arrival_kind;
	event.content_id = unit.def.id;
	const int arrival_id = emit(event);
	const size_t slot = events.size() - 1;
	refresh_vision(arrival_id);
	update_site_memory();
	// Bit 1: the other side sees it where it stands (as unit_moved).
	events[slot].value = is_unit_seen_by(1 - unit.side, p_unit) ? 2 : 0;
}

int TacticsSim::spawn_leader(int p_side, const UnitDef &p_leader, const std::vector<UnitDef> &p_squad, const Cell &p_near, const std::string &p_kind, int p_cause) {
	if (finished) {
		return NO_UNIT;
	}
	const int leader = add_runtime_unit(p_side, p_leader, NO_UNIT, p_kind);
	const int cell = find_spawn_cell(leader, p_near);
	if (cell == NO_INDEX) {
		units.pop_back();
		return NO_UNIT;
	}
	units[leader].cell = get_cell_at(cell);
	occupants[cell] = leader;
	emit_arrival(leader, p_cause);
	const int capacity = get_squad_capacity(leader);
	for (size_t index = 0; index < p_squad.size() && static_cast<int>(index) < capacity; index++) {
		spawn_soldier(leader, p_squad[index], p_kind, p_cause);
	}
	return leader;
}

int TacticsSim::spawn_soldier(int p_leader, const UnitDef &p_soldier, const std::string &p_kind, int p_cause) {
	if (finished) {
		return NO_UNIT;
	}
	int living = 0;
	for (int soldier : units[p_leader].soldiers) {
		living += units[soldier].is_alive ? 1 : 0;
	}
	if (living >= get_squad_capacity(p_leader)) {
		return NO_UNIT;
	}
	const int soldier = add_runtime_unit(units[p_leader].side, p_soldier, p_leader, p_kind);
	const int cell = find_spawn_cell(soldier, units[p_leader].cell);
	if (cell == NO_INDEX) {
		units.pop_back();
		return NO_UNIT;
	}
	units[soldier].cell = get_cell_at(cell);
	occupants[cell] = soldier;
	// A dead soldier's slot is taken first, as a defector takes it.
	std::vector<int> &squad = units[p_leader].soldiers;
	bool is_placed = false;
	for (int &slot : squad) {
		if (!is_placed && !units[slot].is_alive) {
			slot = soldier;
			is_placed = true;
		}
	}
	if (!is_placed) {
		squad.push_back(soldier);
	}
	emit_arrival(soldier, p_cause);
	return soldier;
}

int TacticsSim::spawn_lone_unit(int p_side, const UnitDef &p_def, const Cell &p_cell, const std::string &p_kind, int p_cause) {
	if (finished) {
		return NO_UNIT;
	}
	const int unit = add_runtime_unit(p_side, p_def, NO_UNIT, p_kind);
	const int cell = find_spawn_cell(unit, p_cell);
	if (cell == NO_INDEX) {
		units.pop_back();
		return NO_UNIT;
	}
	units[unit].cell = get_cell_at(cell);
	occupants[cell] = unit;
	if (p_kind == "convoy") {
		convoy_unit = unit;
	}
	emit_arrival(unit, p_cause);
	return unit;
}

void TacticsSim::escape_unit(int p_unit, const std::string &p_kind, int p_cause) {
	UnitState &unit = units[p_unit];
	if (!unit.is_alive) {
		return;
	}
	const bool is_seen = is_unit_seen_by(1 - unit.side, p_unit);
	occupants[get_cell_index(unit.cell)] = NO_UNIT;
	unit.is_alive = false;
	unit.has_escaped = true;
	buffs.erase(std::remove_if(buffs.begin(), buffs.end(), [&](const BuffState &p_buff) { return p_buff.unit == p_unit; }), buffs.end());
	intents.erase(std::remove_if(intents.begin(), intents.end(), [&](const Intent &p_intent) { return p_intent.leader == p_unit; }), intents.end());
	Event event;
	event.type = EventType::UNIT_ESCAPED;
	event.unit = p_unit;
	event.side = unit.side;
	event.from = unit.cell;
	event.kind = p_kind;
	event.value = is_seen ? 2 : 0;
	event.cause = p_cause;
	refresh_vision(emit(event));
	update_site_memory();
}

bool TacticsSim::has_enemy_next_to(int p_side, const Cell &p_cell) const {
	for (const Cell &direction : DIRECTIONS) {
		const Cell next = p_cell + direction;
		const int occupant = is_on_map(next) ? get_occupant(next) : NO_UNIT;
		if (occupant != NO_UNIT && units[occupant].side != p_side && units[occupant].is_alive && !units[occupant].def.is_noncombatant) {
			return true;
		}
	}
	return false;
}

} // namespace tactics
