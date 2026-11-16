#include "tactics_sim.h"

#include "tactics_ai.h"
#include "tactics_orders.h"
#include "tactics_paths.h"
#include "tactics_skills.h"
#include "tactics_validation.h"
#include "tactics_zones.h"

// Setup and the turn loop: phases, AI phases, phase-start effects, intents
// and the end of the battle. Commands are in tactics_sim_commands.cpp.

namespace tactics {

namespace {

const char *const INTENT_ACTION_NAMES[] = { "wait", "attack", "skill" };

} // namespace

bool TacticsSim::setup(const Rules &p_rules, const MapDef &p_map, std::string *r_error) {
	if (started) {
		*r_error = "setup() cannot be called once the battle started";
		return false;
	}
	if (!validate_rules(p_rules, r_error) || !validate_map(p_map, r_error)) {
		return false;
	}
	const bool ai_sides[SIDE_COUNT] = { side_is_ai[SIDE_A], side_is_ai[SIDE_B] };
	*this = TacticsSim();
	side_is_ai[SIDE_A] = ai_sides[SIDE_A];
	side_is_ai[SIDE_B] = ai_sides[SIDE_B];
	rules = p_rules;
	map = p_map;
	occupants.assign(map.width * map.height, NO_UNIT);
	is_ready = true;
	return true;
}

// The leader and its squad may join side p_side: setup done, room on the
// side, valid definitions. Cell and capacity are checked once it exists.
bool TacticsSim::check_new_leader(int p_side, const UnitDef &p_leader, const std::vector<UnitDef> &p_squad, std::string *r_error) const {
	if (!is_ready || started) {
		*r_error = "add_leader() needs setup() first and a battle that has not started";
		return false;
	}
	if (p_side != SIDE_A && p_side != SIDE_B) {
		*r_error = "add_leader() got side " + std::to_string(p_side) + ", expected 0 or 1";
		return false;
	}
	int leaders_on_side = 0;
	for (const UnitState &unit : units) {
		leaders_on_side += unit.side == p_side && is_leader(unit.index) ? 1 : 0;
	}
	if (leaders_on_side >= rules.max_leaders_per_side) {
		*r_error = "side " + std::to_string(p_side) + " already has " + std::to_string(leaders_on_side) + " leaders";
		return false;
	}
	if (p_leader.role != UnitRole::LEADER || !validate_unit_def(p_leader, r_error)) {
		*r_error = p_leader.role != UnitRole::LEADER ? p_leader.id + " is not a leader" : *r_error;
		return false;
	}
	for (const UnitDef &soldier : p_squad) {
		if (soldier.role != UnitRole::SOLDIER || !validate_unit_def(soldier, r_error)) {
			*r_error = soldier.role != UnitRole::SOLDIER ? soldier.id + " is not a soldier type" : *r_error;
			return false;
		}
	}
	return true;
}

int TacticsSim::add_leader(int p_side, const UnitDef &p_leader, const Cell &p_cell, const std::vector<UnitDef> &p_squad, std::string *r_error) {
	if (!check_new_leader(p_side, p_leader, p_squad, r_error)) {
		return NO_UNIT;
	}
	UnitState leader;
	leader.index = static_cast<int>(units.size());
	leader.side = p_side;
	leader.def = p_leader;
	leader.hp = p_leader.max_hp;
	leader.cell = p_cell;
	leader.order = p_leader.default_order;
	leader.heading = map.facing[p_side];
	leader.start_side = p_side;
	units.push_back(leader);
	const int capacity = get_squad_capacity(leader.index);
	const bool is_cell_free = can_stop_at(*this, leader.index, p_cell);
	if (!is_cell_free || static_cast<int>(p_squad.size()) > capacity) {
		*r_error = !is_cell_free ? p_leader.id + " cannot stand on (" + std::to_string(p_cell.col) + ", " + std::to_string(p_cell.row) + ")"
								 : p_leader.id + " leads at most " + std::to_string(capacity) + " soldiers, got " + std::to_string(p_squad.size());
		units.pop_back();
		return NO_UNIT;
	}
	occupants[get_cell_index(p_cell)] = leader.index;
	for (const UnitDef &soldier_def : p_squad) {
		UnitState soldier;
		soldier.index = static_cast<int>(units.size());
		soldier.side = p_side;
		soldier.def = soldier_def;
		soldier.hp = soldier_def.max_hp;
		soldier.leader = leader.index;
		soldier.start_side = p_side;
		soldier.cell = NO_CELL;
		units[leader.index].soldiers.push_back(soldier.index);
		units.push_back(soldier);
	}
	place_soldiers(leader.index);
	return leader.index;
}

// Starting cells: the `order.follow` slots, each soldier on the free cell
// nearest its slot (Manhattan, then cell index).
void TacticsSim::place_soldiers(int p_leader) {
	const int order = units[p_leader].order;
	units[p_leader].order = find_order_index("order.follow");
	const std::vector<Cell> slots = get_formation_slots(*this, p_leader);
	units[p_leader].order = order;
	const int cell_count = map.width * map.height;
	for (size_t slot = 0; slot < slots.size(); slot++) {
		const int soldier = units[p_leader].soldiers[slot];
		int best = NO_INDEX;
		for (int index = 0; index < cell_count; index++) {
			const Cell cell = get_cell_at(index);
			if (occupants[index] == NO_UNIT && can_stop_at(*this, soldier, cell) && (best == NO_INDEX || get_manhattan(cell, slots[slot]) < get_manhattan(get_cell_at(best), slots[slot]))) {
				best = index;
			}
		}
		// validate_map() guarantees cells; a full map leaves the soldier out.
		if (best == NO_INDEX) {
			units[soldier].is_alive = false;
			continue;
		}
		units[soldier].cell = get_cell_at(best);
		occupants[best] = soldier;
	}
}

bool TacticsSim::start(std::string *r_error) {
	if (!is_ready || started) {
		*r_error = "start() needs setup() and a battle that has not started";
		return false;
	}
	int leaders[SIDE_COUNT] = { 0, 0 };
	for (const UnitState &unit : units) {
		leaders[unit.side] += is_leader(unit.index) ? 1 : 0;
	}
	if (leaders[SIDE_A] == 0 || leaders[SIDE_B] == 0) {
		*r_error = "start() needs at least one leader on each side";
		return false;
	}
	started = true;
	Event event;
	event.type = EventType::BATTLE_STARTED;
	event.value = static_cast<int>(units.size());
	emit(event);
	if (incident_rules.enabled) {
		plant_incident_seeds(*this);
	}
	begin_phase(SIDE_A);
	run_ai_phases();
	return true;
}

bool TacticsSim::end_phase(std::string *r_error) {
	if (!started || finished) {
		*r_error = "end_phase() needs a running battle";
		return false;
	}
	close_phase();
	begin_next_phase();
	run_ai_phases();
	return true;
}

void TacticsSim::run_ai_phases() {
	while (!finished && side_is_ai[active_side]) {
		run_ai_phase();
		close_phase();
		begin_next_phase();
	}
}

// After max_rounds full rounds the side that is not attacking holds out.
void TacticsSim::begin_next_phase() {
	if (finished) {
		return;
	}
	const int next = 1 - active_side;
	if (next == SIDE_A && round >= rules.max_rounds) {
		end_battle(SIDE_B, "time_limit", 0);
		return;
	}
	begin_phase(next);
}

void TacticsSim::begin_phase(int p_side) {
	turn++;
	active_side = p_side;
	if (p_side == SIDE_A) {
		round++;
	}
	Event event;
	event.type = EventType::PHASE_STARTED;
	event.side = p_side;
	const int cause = emit(event);
	expire_timed_effects(cause);
	for (UnitState &unit : units) {
		if (unit.side == p_side) {
			unit.has_moved = false;
			unit.has_acted = false;
			unit.has_squad_acted = false;
			unit.straight_cells = 0;
		}
	}
	apply_phase_start_effects(cause);
	if (!finished && incident_rules.enabled) {
		begin_incident_phase(*this, p_side, cause);
	}
	if (!finished && !side_is_ai[p_side] && side_is_ai[1 - p_side]) {
		declare_intents(cause);
	}
}

void TacticsSim::close_phase() {
	if (finished) {
		return;
	}
	// Squads that have not stepped yet (their leader never moved or acted,
	// or died) step now, in leader order.
	for (size_t index = 0; index < units.size() && !finished; index++) {
		if (units[index].side == active_side && is_leader(static_cast<int>(index)) && !units[index].has_squad_acted) {
			run_squad_step(static_cast<int>(index), 0);
		}
	}
	// Wavering soldiers fire or calm down once the player has had the
	// whole phase to react (Docs/systems/tactics.md, Incidents).
	if (!finished && incident_rules.enabled) {
		resolve_incident_phase(*this, active_side);
	}
	if (finished) {
		return;
	}
	for (UnitState &unit : units) {
		if (unit.side != active_side || !is_leader(unit.index) || !unit.is_alive) {
			continue;
		}
		if (!unit.has_moved) {
			unit.heading_streak = 0;
		}
		trigger_skill_charge(*this, unit.index, ChargeTrigger::PHASE_END, unit.has_moved ? 1 : 0, 0);
	}
	Event event;
	event.type = EventType::PHASE_ENDED;
	event.side = active_side;
	emit(event);
}

void TacticsSim::run_ai_phase() {
	for (size_t index = 0; index < units.size() && !finished; index++) {
		const int leader = static_cast<int>(index);
		if (units[index].side != active_side || !is_leader(leader) || !units[index].is_alive) {
			continue;
		}
		Intent intent = plan_intent(*this, leader);
		for (const Intent &declared : intents) {
			if (declared.leader == leader) {
				intent = declared;
			}
		}
		std::string error;
		const Cell destination = resolve_intent_destination(*this, leader, intent);
		if (destination != units[leader].cell) {
			move_leader(leader, destination, &error);
		}
		if (finished || !units[leader].is_alive) {
			continue;
		}
		const Intent action = resolve_intent_action(*this, leader, intent);
		const bool is_done = (action.action == IntentAction::SKILL && use_skill(leader, action.target_cell, &error)) ||
				(action.action == IntentAction::ATTACK && attack(leader, action.target, &error));
		if (!is_done && !finished && units[leader].is_alive) {
			wait(leader, &error);
		}
	}
	intents.clear();
}

void TacticsSim::declare_intents(int p_cause) {
	intents.clear();
	for (const UnitState &unit : units) {
		if (!unit.is_alive || !is_leader(unit.index) || !side_is_ai[unit.side]) {
			continue;
		}
		const Intent intent = plan_intent(*this, unit.index);
		intents.push_back(intent);
		Event event;
		event.type = EventType::INTENT_DECLARED;
		event.unit = unit.index;
		event.to = intent.destination;
		event.kind = INTENT_ACTION_NAMES[static_cast<int>(intent.action)];
		event.target = intent.target;
		event.from = intent.target_cell;
		event.cause = p_cause;
		emit(event);
	}
}

void TacticsSim::expire_timed_effects(int p_cause) {
	for (size_t index = 0; index < zones.size();) {
		if (turn < zones[index].end_turn) {
			index++;
			continue;
		}
		Event event;
		event.type = EventType::ZONE_EXPIRED;
		event.content_id = zones[index].def.id;
		event.cells = zones[index].cells;
		event.unit = zones[index].source;
		event.cause = p_cause;
		emit(event);
		zones.erase(zones.begin() + static_cast<long>(index));
	}
	for (size_t index = 0; index < buffs.size();) {
		if (turn < buffs[index].end_turn) {
			index++;
			continue;
		}
		Event event;
		event.type = EventType::BUFF_ENDED;
		event.unit = buffs[index].unit;
		event.content_id = buffs[index].source_id;
		event.cause = p_cause;
		emit(event);
		buffs.erase(buffs.begin() + static_cast<long>(index));
	}
}

// Zones act on the units of the side whose phase begins (each zone on the
// side its handler affects), in unit order, each zone in creation order.
void TacticsSim::apply_phase_start_effects(int p_cause) {
	const std::vector<ZoneState> active = zones;
	for (size_t unit = 0; unit < units.size(); unit++) {
		if (units[unit].side != active_side) {
			continue;
		}
		for (const ZoneState &zone : active) {
			const bool is_affected = !finished && units[unit].is_alive && zone.def.handler->on_phase_start != nullptr && does_zone_affect(*this, zone, static_cast<int>(unit));
			if (is_affected) {
				zone.def.handler->on_phase_start(*this, zone, static_cast<int>(unit), p_cause);
			}
		}
	}
}

void TacticsSim::check_rout(int p_cause) {
	if (finished || !started) {
		return;
	}
	int leaders[SIDE_COUNT] = { 0, 0 };
	for (const UnitState &unit : units) {
		leaders[unit.side] += unit.is_alive && is_leader(unit.index) ? 1 : 0;
	}
	if (leaders[SIDE_A] == 0) {
		end_battle(SIDE_B, "rout", p_cause);
	} else if (leaders[SIDE_B] == 0) {
		end_battle(SIDE_A, "rout", p_cause);
	}
}

// Only the leader's own move takes the objective: a pull onto it, or
// starting on it, does not (Docs/systems/tactics.md, Victory).
void TacticsSim::check_objective_taken(int p_leader, int p_cause) {
	const UnitState &leader = units[p_leader];
	if (!finished && map.has_objective && leader.side == map.objective_side && leader.cell == map.objective) {
		end_battle(map.objective_side, "objective", p_cause);
	}
}

void TacticsSim::end_battle(int p_winner, const std::string &p_reason, int p_cause) {
	finished = true;
	winner = p_winner;
	end_reason = p_reason;
	intents.clear();
	Event event;
	event.type = EventType::BATTLE_ENDED;
	event.winner = p_winner;
	event.kind = p_reason;
	event.cause = p_cause;
	emit(event);
}

} // namespace tactics
