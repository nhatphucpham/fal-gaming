#include "tactics_battle.h"

#include "tactics_event_dictionary.h"

#include <godot_cpp/core/error_macros.hpp>

// TacticsBattle's incident setup (rules and seed, karma, roster records,
// forced seeds) and its incident queries: seeds for tests, karma and the
// end-of-battle report the roster reads.

using namespace godot;

namespace {

const char *const STAGE_NAMES[] = { "none", "dormant", "wavering", "fired" };

StringName to_id(const std::string &p_text) {
	return StringName(to_godot_string(p_text));
}

bool is_valid_side(int64_t p_side) {
	return p_side == tactics::SIDE_A || p_side == tactics::SIDE_B;
}

StringName get_status(const tactics::UnitState &p_unit) {
	if (p_unit.has_fled) {
		return StringName("fled");
	}
	return StringName(p_unit.is_alive ? "alive" : "dead");
}

} // namespace

bool TacticsBattle::set_incident_rules(const Ref<TacticsIncidentRulesData> &p_rules, int64_t p_seed) {
	ERR_FAIL_COND_V_MSG(p_rules.is_null(), false, "Tactics: set_incident_rules() got null rules");
	tactics::IncidentRules rules;
	std::string error;
	const bool is_valid = p_rules->to_incident_rules(&rules, &error) && sim.set_incident_rules(rules, static_cast<uint64_t>(p_seed), &error);
	ERR_FAIL_COND_V_MSG(!is_valid, false, "Tactics: set_incident_rules() refused: " + to_godot_string(error));
	return true;
}

void TacticsBattle::set_karma(int64_t p_side, int64_t p_bait, int64_t p_rescue) {
	ERR_FAIL_COND_MSG(!is_valid_side(p_side), vformat("Tactics: set_karma() got side %d, expected 0 or 1", p_side));
	ERR_FAIL_COND_MSG(sim.is_started(), "Tactics: set_karma() is refused once the battle started");
	sim.set_carried_karma(static_cast<int>(p_side), clamp_to_int(p_bait), clamp_to_int(p_rescue));
}

bool TacticsBattle::set_unit_record(int64_t p_unit, int64_t p_record_id, int64_t p_good_marks, int64_t p_bad_marks) {
	if (!check_unit(p_unit, "set_unit_record")) {
		return false;
	}
	std::string error;
	const bool is_set = sim.set_unit_record(static_cast<int>(p_unit), clamp_to_int(p_record_id), clamp_to_int(p_good_marks), clamp_to_int(p_bad_marks), &error);
	ERR_FAIL_COND_V_MSG(!is_set, false, "Tactics: " + to_godot_string(error));
	return true;
}

bool TacticsBattle::set_incident_seed(int64_t p_unit, const StringName &p_incident) {
	if (!check_unit(p_unit, "set_incident_seed")) {
		return false;
	}
	std::string error;
	const int incident = sim.find_incident(to_std_string(p_incident));
	const bool is_set = sim.set_forced_seed(static_cast<int>(p_unit), incident, &error);
	ERR_FAIL_COND_V_MSG(!is_set, false, vformat("Tactics: set_incident_seed(%d, %s) refused: %s", p_unit, p_incident, to_godot_string(error)));
	return true;
}

Array TacticsBattle::get_incident_seeds() const {
	Array seeds;
	for (const tactics::UnitState &unit : sim.get_units()) {
		if (unit.seed == tactics::NO_INDEX) {
			continue;
		}
		Dictionary entry;
		entry["unit"] = unit.index;
		entry["incident"] = to_id(sim.get_incident_rules().incidents[unit.seed].id);
		entry["stage"] = StringName(STAGE_NAMES[static_cast<int>(unit.stage)]);
		seeds.push_back(entry);
	}
	return seeds;
}

Dictionary TacticsBattle::get_karma(int64_t p_side) const {
	Dictionary karma;
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side), karma, vformat("Tactics: get_karma() got side %d, expected 0 or 1", p_side));
	const int side = static_cast<int>(p_side);
	karma["bait"] = sim.get_battle_karma(side, tactics::KarmaKind::BAIT);
	karma["rescue"] = sim.get_battle_karma(side, tactics::KarmaKind::RESCUE);
	karma["carried_bait"] = sim.get_carried_karma(side, tactics::KarmaKind::BAIT);
	karma["carried_rescue"] = sim.get_carried_karma(side, tactics::KarmaKind::RESCUE);
	return karma;
}

Dictionary TacticsBattle::get_battle_report() const {
	Dictionary report;
	report["is_finished"] = sim.is_finished();
	report["winner"] = sim.get_winner();
	report["reason"] = get_end_reason();
	report["round"] = sim.get_round();
	report["map"] = to_id(sim.get_map().id);
	Array karma;
	karma.push_back(get_karma(tactics::SIDE_A));
	karma.push_back(get_karma(tactics::SIDE_B));
	report["karma"] = karma;
	Array units;
	for (const tactics::UnitState &unit : sim.get_units()) {
		Dictionary entry;
		entry["unit"] = unit.index;
		entry["record_id"] = unit.record_id;
		entry["id"] = to_id(unit.def.id);
		entry["role"] = StringName(sim.is_leader(unit.index) ? "leader" : "soldier");
		entry["start_side"] = unit.start_side;
		entry["side"] = unit.side;
		entry["status"] = get_status(unit);
		entry["has_defected"] = unit.side != unit.start_side;
		entry["leader_id"] = unit.leader != tactics::NO_UNIT ? to_id(sim.get_units()[unit.leader].def.id) : StringName();
		Array marks;
		for (const tactics::MarkState &mark : unit.marks) {
			Dictionary item;
			item["incident"] = to_id(sim.get_incident_rules().incidents[mark.incident].id);
			item["leader_id"] = to_id(mark.leader_id);
			item["terrain"] = to_id(mark.terrain_id);
			item["cell"] = to_vector2i(mark.cell);
			item["round"] = mark.round;
			marks.push_back(item);
		}
		entry["marks"] = marks;
		units.push_back(entry);
	}
	report["units"] = units;
	return report;
}
