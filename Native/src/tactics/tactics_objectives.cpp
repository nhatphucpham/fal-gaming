#include "tactics_objectives.h"

#include "tactics_paths.h"
#include "tactics_sim.h"
#include "tactics_sites.h"
#include "tactics_validation.h"

// The five objective kinds and the secondary goals
// (Docs/systems/tactics_objectives.md).

namespace tactics {

namespace {

constexpr int PERCENT = 100;

bool fail(std::string *r_error, const std::string &p_message) {
	*r_error = p_message;
	return false;
}

const ObjectiveDef &objective_of(const TacticsSim &p_sim) {
	return p_sim.get_objective();
}

Cell site_cell(const TacticsSim &p_sim) {
	return p_sim.get_map().sites[objective_of(p_sim).site].cell;
}

int count_leaders_on_map(const TacticsSim &p_sim, int p_side) {
	int count = 0;
	for (const UnitState &unit : p_sim.get_units()) {
		count += unit.is_alive && unit.side == p_side && p_sim.is_leader(unit.index) ? 1 : 0;
	}
	return count;
}

bool has_cell(const std::vector<Cell> &p_cells, const Cell &p_cell) {
	for (const Cell &cell : p_cells) {
		if (cell == p_cell) {
			return true;
		}
	}
	return false;
}

bool are_on_map(const std::vector<Cell> &p_cells, const MapDef &p_map) {
	for (const Cell &cell : p_cells) {
		if (cell.col < 0 || cell.col >= p_map.width || cell.row < 0 || cell.row >= p_map.height) {
			return false;
		}
	}
	return true;
}

bool is_edge(const Cell &p_cell, const MapDef &p_map) {
	return p_cell.col == 0 || p_cell.row == 0 || p_cell.col == p_map.width - 1 || p_cell.row == p_map.height - 1;
}

bool has_stronghold(const ObjectiveDef &p_def, const MapDef &p_map) {
	return p_def.site >= 0 && p_def.site < static_cast<int>(p_map.sites.size()) && is_stronghold(p_map.sites[p_def.site].def);
}

std::vector<Cell> no_goals(const TacticsSim &, int) {
	return {};
}

int no_target(const TacticsSim &, int) {
	return NO_UNIT;
}

bool no_exit(const TacticsSim &, int, const Cell &) {
	return false;
}

// --- Take the pass ------------------------------------------------------

// The round ends with side A holding the pass and a leader of it on it.
void end_take_pass(TacticsSim &p_sim, int p_side, int p_cause) {
	const Cell pass = site_cell(p_sim);
	const int holder = p_sim.get_occupant(pass);
	const bool is_held = p_sim.get_site_states()[objective_of(p_sim).site].owner == SIDE_A && holder != NO_UNIT &&
			p_sim.get_units()[holder].side == SIDE_A && p_sim.is_leader(holder);
	if (p_side == SIDE_B && is_held) {
		p_sim.finish_battle(SIDE_A, "objective", p_cause);
	}
}

std::vector<Cell> march_to_site(const TacticsSim &p_sim, int p_leader) {
	return p_sim.get_units()[p_leader].side == SIDE_A ? std::vector<Cell>{ site_cell(p_sim) } : std::vector<Cell>{};
}

bool validate_take_pass(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error) {
	return has_stronghold(p_def, p_map) || fail(r_error, p_def.id + " needs `site`, a stronghold of the map");
}

// --- Hold the city ------------------------------------------------------

void send_waves(TacticsSim &p_sim, int p_side, int p_cause) {
	const ObjectiveDef &def = objective_of(p_sim);
	while (p_side == SIDE_B && p_sim.get_waves_sent() < static_cast<int>(def.waves.size()) && def.waves[p_sim.get_waves_sent()].round <= p_sim.get_round()) {
		const WaveDef &wave = def.waves[p_sim.get_waves_sent()];
		p_sim.set_waves_sent(p_sim.get_waves_sent() + 1);
		for (size_t index = 0; index < wave.leaders.size(); index++) {
			p_sim.spawn_leader(SIDE_B, wave.leaders[index], wave.squads[index], wave.entry_cells[index % wave.entry_cells.size()], "wave", p_cause);
		}
	}
}

// Side B holding the keep since an earlier round wins; else side A wins at
// the end of the last round it must hold.
void end_hold_city(TacticsSim &p_sim, int p_side, int p_cause) {
	if (p_side != SIDE_B) {
		return;
	}
	const ObjectiveDef &def = objective_of(p_sim);
	const SiteState &keep = p_sim.get_site_states()[def.site];
	if (keep.owner == SIDE_B && keep.owned_round < p_sim.get_round()) {
		p_sim.finish_battle(SIDE_B, "keep_lost", p_cause);
	} else if (p_sim.get_round() >= def.rounds) {
		p_sim.finish_battle(SIDE_A, "held", p_cause);
	}
}

// Side B is not beaten while a wave is still to come.
int rout_hold_city(const TacticsSim &p_sim, int p_side) {
	if (p_side == SIDE_B && p_sim.get_waves_sent() < static_cast<int>(objective_of(p_sim).waves.size())) {
		return NO_WINNER;
	}
	return 1 - p_side;
}

std::vector<Cell> march_to_keep(const TacticsSim &p_sim, int p_leader) {
	return p_sim.get_units()[p_leader].side == SIDE_B ? std::vector<Cell>{ site_cell(p_sim) } : std::vector<Cell>{};
}

bool validate_hold_city(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error) {
	if (!has_stronghold(p_def, p_map) || p_def.rounds < 1 || p_def.rounds > MAX_ROUNDS) {
		return fail(r_error, p_def.id + " needs `site`, a stronghold, and rounds 1..1000");
	}
	for (const WaveDef &wave : p_def.waves) {
		if (wave.round < 1 || wave.leaders.empty() || wave.entry_cells.empty() || !are_on_map(wave.entry_cells, p_map) || wave.squads.size() != wave.leaders.size()) {
			return fail(r_error, p_def.id + " has a wave without a round, leaders or entry cells on the map");
		}
	}
	return true;
}

// --- Escort -------------------------------------------------------------

// The convoy starts on the first free cell of its road (a soldier may
// stand on the road's first cells); off the road it could never set out.
void place_convoy(TacticsSim &p_sim, int p_cause) {
	const ObjectiveDef &def = objective_of(p_sim);
	Cell start = def.road_cells.front();
	for (const Cell &cell : def.road_cells) {
		if (p_sim.get_occupant(cell) == NO_UNIT) {
			start = cell;
			break;
		}
	}
	p_sim.spawn_lone_unit(SIDE_A, def.convoy, start, "convoy", p_cause);
}

// A seen enemy on the convoy's next road cell: why it cannot set out.
bool is_road_blocked_by_enemy(const TacticsSim &p_sim) {
	const std::vector<Cell> &road = objective_of(p_sim).road_cells;
	const auto at = std::find(road.begin(), road.end(), p_sim.get_units()[p_sim.get_convoy()].cell);
	if (at == road.end() || at + 1 == road.end()) {
		return false;
	}
	const int occupant = p_sim.get_occupant(*(at + 1));
	return occupant != NO_UNIT && p_sim.get_units()[occupant].side != SIDE_A && p_sim.is_unit_seen_by(SIDE_A, occupant);
}

// The convoy walks its road at the end of side A's phase and leaves the
// map at the road's end.
void walk_convoy(TacticsSim &p_sim, int p_side, int p_cause) {
	const int convoy = p_sim.get_convoy();
	if (p_side != SIDE_A || convoy == NO_UNIT || !p_sim.get_units()[convoy].is_alive) {
		return;
	}
	const std::vector<Cell> path = p_sim.get_convoy_path();
	if (path.size() < 2) {
		Event event;
		event.type = EventType::CONVOY_HALTED;
		event.unit = convoy;
		event.kind = p_sim.does_convoy_hold() ? "holding" : (is_road_blocked_by_enemy(p_sim) ? "enemy" : "blocked");
		event.cause = p_cause;
		p_sim.emit(event);
		return;
	}
	int cost = 0;
	for (size_t step = 1; step < path.size(); step++) {
		cost += get_step_cost(p_sim, convoy, path[step]);
	}
	p_sim.walk_unit(convoy, path, cost, "convoy", p_cause);
	if (p_sim.get_units()[convoy].cell == objective_of(p_sim).road_cells.back()) {
		p_sim.escape_unit(convoy, "convoy", p_cause);
		p_sim.finish_battle(SIDE_A, "escorted", p_cause);
	}
}

void convoy_died(TacticsSim &p_sim, int p_unit, int p_cause) {
	if (p_unit == p_sim.get_convoy()) {
		p_sim.finish_battle(SIDE_B, "convoy_lost", p_cause);
	}
}

int target_convoy(const TacticsSim &p_sim, int p_side) {
	const int convoy = p_sim.get_convoy();
	return p_side == SIDE_B && convoy != NO_UNIT && p_sim.get_units()[convoy].is_alive ? convoy : NO_UNIT;
}

// Side B goes for the convoy where it saw it last, else the road's end;
// side A (played by the AI) walks with it.
std::vector<Cell> march_to_convoy(const TacticsSim &p_sim, int p_leader) {
	const int side = p_sim.get_units()[p_leader].side;
	const int convoy = p_sim.get_convoy();
	if (convoy == NO_UNIT || !p_sim.get_units()[convoy].is_alive) {
		return {};
	}
	if (side == SIDE_A || p_sim.is_unit_seen_by(side, convoy)) {
		return { p_sim.get_units()[convoy].cell };
	}
	const Cell last = p_sim.get_last_seen(side, convoy);
	return { last != NO_CELL ? last : objective_of(p_sim).road_cells.back() };
}

bool validate_escort(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error) {
	if (!p_def.has_convoy || !p_def.convoy.is_noncombatant || p_def.road_cells.size() < 2 || !are_on_map(p_def.road_cells, p_map) || !is_edge(p_def.road_cells.back(), p_map)) {
		return fail(r_error, p_def.id + " needs a non-combatant convoy and a road of 2+ cells on the map ending on its edge");
	}
	for (size_t index = 1; index < p_def.road_cells.size(); index++) {
		if (get_manhattan(p_def.road_cells[index - 1], p_def.road_cells[index]) != 1 || has_cell(std::vector<Cell>(p_def.road_cells.begin(), p_def.road_cells.begin() + static_cast<long>(index)), p_def.road_cells[index])) {
			return fail(r_error, p_def.id + " has a road that does not go cell to next cell, or crosses itself");
		}
	}
	return true;
}

// --- Break the siege ----------------------------------------------------

bool is_siege_exit(const TacticsSim &p_sim, int p_side, const Cell &p_cell) {
	return p_side == SIDE_A && has_cell(objective_of(p_sim).exit_cells, p_cell);
}

int get_required_unit(const TacticsSim &p_sim) {
	const int required = objective_of(p_sim).required_leader;
	int order = 0;
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.start_side == SIDE_A && p_sim.is_leader(unit.index) && unit.arrival_kind.empty()) {
			if (order == required) {
				return unit.index;
			}
			order++;
		}
	}
	return NO_UNIT;
}

bool is_siege_broken(const TacticsSim &p_sim) {
	const int required = get_required_unit(p_sim);
	const bool has_required = required == NO_UNIT || p_sim.get_units()[required].has_escaped;
	return has_required && p_sim.count_escaped_leaders(SIDE_A) >= objective_of(p_sim).count;
}

// A leader of side A whose own move ends on an exit leaves with its squad.
void leave_by_exit(TacticsSim &p_sim, int p_leader, int p_cause) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	if (!is_siege_exit(p_sim, leader.side, leader.cell)) {
		return;
	}
	const std::vector<int> soldiers = leader.soldiers;
	p_sim.escape_unit(p_leader, "exit", p_cause);
	for (int soldier : soldiers) {
		if (p_sim.get_units()[soldier].is_alive) {
			p_sim.escape_unit(soldier, "exit", p_cause);
		}
	}
	if (is_siege_broken(p_sim)) {
		p_sim.finish_battle(SIDE_A, "broke_out", p_cause);
	} else if (count_leaders_on_map(p_sim, SIDE_A) == 0) {
		p_sim.finish_battle(SIDE_B, "leader_lost", p_cause);
	}
}

// The siege can no longer be broken: the leader that must get out fell, or
// too few leaders are left to get out.
void siege_leader_died(TacticsSim &p_sim, int p_unit, int p_cause) {
	if (!p_sim.is_leader(p_unit) || p_sim.get_units()[p_unit].side != SIDE_A) {
		return;
	}
	const bool lost_required = p_unit == get_required_unit(p_sim);
	if (lost_required || p_sim.count_escaped_leaders(SIDE_A) + count_leaders_on_map(p_sim, SIDE_A) < objective_of(p_sim).count) {
		p_sim.finish_battle(SIDE_B, "leader_lost", p_cause);
	}
}

void end_siege(TacticsSim &p_sim, int p_side, int p_cause) {
	if (p_side == SIDE_B && p_sim.get_round() >= objective_of(p_sim).rounds) {
		p_sim.finish_battle(SIDE_B, "time_limit", p_cause);
	}
}

int rout_siege(const TacticsSim &p_sim, int p_side) {
	if (p_side == SIDE_A && is_siege_broken(p_sim)) {
		return SIDE_A;
	}
	return 1 - p_side;
}

std::vector<Cell> march_to_exits(const TacticsSim &p_sim, int p_leader) {
	return p_sim.get_units()[p_leader].side == SIDE_A ? objective_of(p_sim).exit_cells : std::vector<Cell>{};
}

bool validate_siege(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error) {
	bool are_edges = !p_def.exit_cells.empty() && are_on_map(p_def.exit_cells, p_map);
	for (const Cell &cell : p_def.exit_cells) {
		are_edges = are_edges && is_edge(cell, p_map);
	}
	const bool is_valid = are_edges && p_def.count >= 1 && p_def.count <= 8 && p_def.rounds >= 1 && p_def.rounds <= MAX_ROUNDS && p_def.required_leader >= NO_INDEX;
	return is_valid || fail(r_error, p_def.id + " needs exit cells on the map's edge, count 1..8 and rounds 1..1000");
}

// --- Bring down the general ---------------------------------------------

bool is_general_exit(const TacticsSim &p_sim, int p_side, const Cell &p_cell) {
	return p_side == SIDE_B && p_sim.is_general_fleeing() && has_cell(objective_of(p_sim).exit_cells, p_cell);
}

// Hurt to flee_hp_pct or under, the general runs for his exits; the turn
// he turns is told (general_fleeing).
void check_general(TacticsSim &p_sim, int, int p_cause) {
	const int general = p_sim.get_general();
	if (general == NO_UNIT || p_sim.is_general_fleeing() || !p_sim.get_units()[general].is_alive) {
		return;
	}
	const UnitState &unit = p_sim.get_units()[general];
	if (static_cast<int64_t>(unit.hp) * PERCENT > static_cast<int64_t>(unit.def.max_hp) * objective_of(p_sim).flee_hp_pct) {
		return;
	}
	p_sim.set_general_fleeing(true);
	Event event;
	event.type = EventType::GENERAL_FLEEING;
	event.unit = general;
	event.cause = p_cause;
	p_sim.emit(event);
}

void general_moved(TacticsSim &p_sim, int p_leader, int p_cause) {
	if (p_leader != p_sim.get_general() || !is_general_exit(p_sim, SIDE_B, p_sim.get_units()[p_leader].cell)) {
		return;
	}
	p_sim.escape_unit(p_leader, "general", p_cause);
	p_sim.finish_battle(SIDE_B, "general_fled", p_cause);
}

void general_died(TacticsSim &p_sim, int p_unit, int p_cause) {
	if (p_unit == p_sim.get_general()) {
		p_sim.finish_battle(SIDE_A, "general_slain", p_cause);
	}
}

int target_general(const TacticsSim &p_sim, int p_side) {
	const int general = p_sim.get_general();
	return p_side == SIDE_A && general != NO_UNIT && p_sim.get_units()[general].is_alive ? general : NO_UNIT;
}

// The fleeing general runs for his exits; side A (the AI) goes where it
// last knew him.
std::vector<Cell> march_for_general(const TacticsSim &p_sim, int p_leader) {
	const int general = p_sim.get_general();
	if (p_leader == general && p_sim.is_general_fleeing()) {
		return objective_of(p_sim).exit_cells;
	}
	if (p_sim.get_units()[p_leader].side != SIDE_A || general == NO_UNIT) {
		return {};
	}
	const Cell last = p_sim.get_last_seen(SIDE_A, general);
	return { p_sim.is_unit_seen_by(SIDE_A, general) ? p_sim.get_units()[general].cell : (last != NO_CELL ? last : p_sim.get_general_post()) };
}

bool validate_general(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error) {
	bool are_edges = !p_def.exit_cells.empty() && are_on_map(p_def.exit_cells, p_map);
	for (const Cell &cell : p_def.exit_cells) {
		are_edges = are_edges && is_edge(cell, p_map);
	}
	const bool is_valid = are_edges && p_def.general >= 0 && p_def.flee_hp_pct >= 0 && p_def.flee_hp_pct <= PERCENT && p_def.general_hold_cells >= 0 && p_def.general_hold_cells <= 64;
	return is_valid || fail(r_error, p_def.id + " needs a general, flee_hp_pct 0..100, general_hold_cells 0..64 and exit cells on the edge");
}

const ObjectiveHandler OBJECTIVE_HANDLERS[] = {
	{ "objective_kind.take_pass", SIDE_B, nullptr, nullptr, end_take_pass, nullptr, nullptr, nullptr, no_exit, march_to_site, no_target, validate_take_pass },
	{ "objective_kind.hold_city", SIDE_A, nullptr, send_waves, end_hold_city, nullptr, nullptr, rout_hold_city, no_exit, march_to_keep, no_target, validate_hold_city },
	{ "objective_kind.escort", NO_INDEX, place_convoy, nullptr, walk_convoy, nullptr, convoy_died, nullptr, no_exit, march_to_convoy, target_convoy, validate_escort },
	{ "objective_kind.break_siege", SIDE_B, nullptr, nullptr, end_siege, leave_by_exit, siege_leader_died, rout_siege, is_siege_exit, march_to_exits, no_target, validate_siege },
	{ "objective_kind.slay_general", SIDE_B, nullptr, check_general, nullptr, general_moved, general_died, nullptr, is_general_exit, march_for_general, target_general, validate_general },
};

// --- Goals --------------------------------------------------------------

bool are_villages_safe(const TacticsSim &p_sim, const GoalDef &) {
	for (size_t site = 0; site < p_sim.get_map().sites.size(); site++) {
		if (is_village(p_sim.get_map().sites[site].def) && p_sim.get_site_states()[site].status == SiteStatus::BURNED) {
			return false;
		}
	}
	return true;
}

bool has_no_losses(const TacticsSim &p_sim, const GoalDef &) {
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.start_side == SIDE_A && !unit.is_alive && !unit.has_fled && !unit.has_escaped && p_sim.is_on_map(unit.cell)) {
			return false;
		}
	}
	return true;
}

bool is_by_round(const TacticsSim &p_sim, const GoalDef &p_goal) {
	return p_sim.get_round() <= p_goal.value;
}

bool are_camps_taken(const TacticsSim &p_sim, const GoalDef &) {
	for (size_t site = 0; site < p_sim.get_map().sites.size(); site++) {
		if (is_camp(p_sim.get_map().sites[site].def) && p_sim.get_site_states()[site].owner != SIDE_A) {
			return false;
		}
	}
	return true;
}

const GoalHandler GOAL_HANDLERS[] = {
	{ "goal.villages_safe", are_villages_safe },
	{ "goal.no_losses", has_no_losses },
	{ "goal.by_round", is_by_round },
	{ "goal.camps_taken", are_camps_taken },
};

} // namespace

const ObjectiveHandler *find_objective_handler(const std::string &p_id) {
	for (const ObjectiveHandler &handler : OBJECTIVE_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

const GoalHandler *find_goal_handler(const std::string &p_id) {
	for (const GoalHandler &handler : GOAL_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

bool validate_objective(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error) {
	if (p_def.handler == nullptr) {
		return fail(r_error, p_def.id + " has no known kind");
	}
	if (p_def.has_convoy && !validate_unit_def(p_def.convoy, r_error)) {
		return false;
	}
	for (const WaveDef &wave : p_def.waves) {
		if (wave.squads.size() != wave.leaders.size()) {
			return fail(r_error, p_def.id + " has a wave with a squad count other than its leaders'");
		}
		for (size_t index = 0; index < wave.leaders.size(); index++) {
			if (wave.leaders[index].role != UnitRole::LEADER || !validate_unit_def(wave.leaders[index], r_error)) {
				return wave.leaders[index].role != UnitRole::LEADER ? fail(r_error, p_def.id + " has a wave leader that is not a leader") : false;
			}
			for (const UnitDef &soldier : wave.squads[index]) {
				if (!validate_unit_def(soldier, r_error)) {
					return false;
				}
			}
		}
	}
	for (const GoalDef &goal : p_def.goals) {
		if (goal.handler == nullptr || goal.supplies < 0 || goal.supplies > 100 || goal.value < 0 || goal.value > MAX_ROUNDS) {
			return fail(r_error, p_def.id + " has a goal of no known kind, or supplies outside 0..100");
		}
	}
	return p_def.handler->validate(p_def, p_map, r_error);
}

std::vector<int> find_met_goals(const TacticsSim &p_sim) {
	std::vector<int> met;
	const std::vector<GoalDef> &goals = p_sim.get_objective().goals;
	for (size_t index = 0; index < goals.size(); index++) {
		if (goals[index].handler->is_met(p_sim, goals[index])) {
			met.push_back(static_cast<int>(index));
		}
	}
	return met;
}

} // namespace tactics
