#include "tactics_sim.h"

#include "tactics_orders.h"
#include "tactics_validation.h"

#include <algorithm>

// TacticsSim's incident setup (rules, seed, karma, roster records, forced
// seeds) and the state changes incidents make: karma, fleeing, defecting.

namespace tactics {

bool TacticsSim::set_incident_rules(const IncidentRules &p_rules, uint64_t p_seed, std::string *r_error) {
	if (!is_ready || started) {
		*r_error = "set_incident_rules() needs setup() and a battle that has not started";
		return false;
	}
	if (!validate_incident_rules(p_rules, r_error)) {
		return false;
	}
	incident_rules = p_rules;
	incident_seed = p_seed;
	random.seed(p_seed);
	forced_seeds.clear();
	return true;
}

void TacticsSim::set_carried_karma(int p_side, int p_bait, int p_rescue) {
	if (started || p_side < 0 || p_side >= SIDE_COUNT) {
		return;
	}
	carried_karma[p_side][static_cast<int>(KarmaKind::BAIT)] = p_bait < 0 ? 0 : p_bait;
	carried_karma[p_side][static_cast<int>(KarmaKind::RESCUE)] = p_rescue < 0 ? 0 : p_rescue;
}

bool TacticsSim::set_unit_record(int p_unit, int p_record_id, int p_good_marks, int p_bad_marks, std::string *r_error) {
	if (started || p_unit < 0 || p_unit >= static_cast<int>(units.size())) {
		*r_error = "set_unit_record() needs an existing unit " + std::to_string(p_unit) + " before the battle starts";
		return false;
	}
	if (p_good_marks < 0 || p_bad_marks < 0) {
		*r_error = "set_unit_record() got negative marks for unit " + std::to_string(p_unit);
		return false;
	}
	units[p_unit].record_id = p_record_id;
	units[p_unit].good_marks = p_good_marks;
	units[p_unit].bad_marks = p_bad_marks;
	return true;
}

bool TacticsSim::set_forced_seed(int p_unit, int p_incident, std::string *r_error) {
	const bool is_soldier = p_unit >= 0 && p_unit < static_cast<int>(units.size()) && !is_leader(p_unit);
	if (started || !incident_rules.enabled || !is_soldier || p_incident < 0 || p_incident >= static_cast<int>(incident_rules.incidents.size())) {
		*r_error = "set_forced_seed() needs incident rules, a soldier and a known incident before the battle starts";
		return false;
	}
	forced_seeds.erase(std::remove_if(forced_seeds.begin(), forced_seeds.end(), [&](const std::pair<int, int> &p_seed) { return p_seed.first == p_unit; }), forced_seeds.end());
	forced_seeds.push_back({ p_unit, p_incident });
	return true;
}

int TacticsSim::find_incident(const std::string &p_id) const {
	for (size_t index = 0; index < incident_rules.incidents.size(); index++) {
		if (incident_rules.incidents[index].id == p_id) {
			return static_cast<int>(index);
		}
	}
	return NO_INDEX;
}

void TacticsSim::add_karma(int p_side, KarmaKind p_kind, int p_cause) {
	int &value = battle_karma[p_side][static_cast<int>(p_kind)];
	value++;
	Event event;
	event.type = EventType::KARMA_CHANGED;
	event.side = p_side;
	event.kind = get_karma_kind_id(p_kind);
	event.value = value;
	event.cause = p_cause;
	emit(event);
}

void TacticsSim::remove_fled_unit(int p_unit, const Cell &p_edge, int p_cause) {
	UnitState &unit = units[p_unit];
	occupants[get_cell_index(unit.cell)] = NO_UNIT;
	unit.is_alive = false;
	unit.has_fled = true;
	buffs.erase(std::remove_if(buffs.begin(), buffs.end(), [&](const BuffState &p_buff) { return p_buff.unit == p_unit; }), buffs.end());
	Event event;
	event.type = EventType::UNIT_FLED;
	event.unit = p_unit;
	event.from = unit.cell;
	event.to = p_edge;
	event.cause = p_cause;
	refresh_vision(emit(event));
}

// The new leader keeps squad order: the soldier takes the first dead slot,
// else goes last; a full squad of living soldiers refuses it.
bool TacticsSim::defect_unit(int p_unit, int p_new_leader, int p_cause) {
	if (p_new_leader == NO_UNIT) {
		return false;
	}
	std::vector<int> &squad = units[p_new_leader].soldiers;
	int slot = NO_INDEX;
	for (size_t index = 0; index < squad.size() && slot == NO_INDEX; index++) {
		slot = units[squad[index]].is_alive ? NO_INDEX : static_cast<int>(index);
	}
	if (slot == NO_INDEX && static_cast<int>(squad.size()) >= MAX_SQUAD_SIZE) {
		return false;
	}
	UnitState &unit = units[p_unit];
	const int from_side = unit.side;
	if (unit.leader != NO_UNIT) {
		std::vector<int> &old_squad = units[unit.leader].soldiers;
		old_squad.erase(std::remove(old_squad.begin(), old_squad.end(), p_unit), old_squad.end());
	}
	if (slot == NO_INDEX) {
		squad.push_back(p_unit);
	} else {
		squad[slot] = p_unit;
	}
	unit.side = units[p_new_leader].side;
	unit.leader = p_new_leader;
	unit.guard_leader = NO_UNIT;
	unit.was_attacked_since_move = false;
	unit.last_attacker = NO_UNIT;
	Event event;
	event.type = EventType::UNIT_DEFECTED;
	event.unit = p_unit;
	event.side = unit.side;
	event.value = from_side;
	event.target = p_new_leader;
	event.cause = p_cause;
	refresh_vision(emit(event));
	return true;
}

} // namespace tactics
