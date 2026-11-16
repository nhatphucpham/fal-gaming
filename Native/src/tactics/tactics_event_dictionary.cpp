#include "tactics_event_dictionary.h"

#include "battle/bridge_strings.h"

using namespace godot;

namespace {

const char *const EVENT_TYPE_NAMES[] = {
	"battle_started",
	"phase_started",
	"phase_ended",
	"unit_moved",
	"order_changed",
	"leader_waited",
	"engagement_started",
	"engagement_ended",
	"damage_dealt",
	"unit_died",
	"skill_used",
	"skill_resolved",
	"skill_charge_changed",
	"skill_grew",
	"buff_applied",
	"buff_ended",
	"zone_created",
	"zone_expired",
	"passive_triggered",
	"intent_declared",
	"soldier_wavered",
	"incident_calmed",
	"incident_fired",
	"mark_earned",
	"unit_fled",
	"unit_defected",
	"karma_changed",
	"battle_ended",
	"vision_changed",
	"ambushed",
	"weather_changed",
	"daytime_changed",
};

StringName to_id(const std::string &p_text) {
	return StringName(to_godot_string(p_text));
}

Array units_to_array(const std::vector<int> &p_units) {
	Array units;
	for (int unit : p_units) {
		units.push_back(unit);
	}
	units.make_read_only();
	return units;
}

Array results_to_array(const std::vector<tactics::SkillTargetResult> &p_results) {
	Array results;
	for (const tactics::SkillTargetResult &result : p_results) {
		Dictionary entry;
		entry["unit"] = result.unit;
		entry["amount"] = result.amount;
		entry["hp_after"] = result.hp_after;
		entry["is_dead"] = result.is_dead;
		entry.make_read_only();
		results.push_back(entry);
	}
	results.make_read_only();
	return results;
}

void add_combat_payload(const tactics::Event &p_event, Dictionary &r_dict) {
	switch (p_event.type) {
		case tactics::EventType::ENGAGEMENT_STARTED:
			r_dict["unit"] = p_event.unit;
			r_dict["target"] = p_event.target;
			r_dict["kind"] = to_id(p_event.kind);
			r_dict["is_first_strike"] = p_event.is_first_strike;
			break;
		case tactics::EventType::ENGAGEMENT_ENDED:
			r_dict["unit"] = p_event.unit;
			r_dict["target"] = p_event.target;
			r_dict["amount"] = p_event.amount;
			r_dict["counter_amount"] = p_event.value;
			break;
		case tactics::EventType::DAMAGE_DEALT:
			r_dict["source"] = p_event.unit;
			r_dict["target"] = p_event.target;
			r_dict["amount"] = p_event.amount;
			r_dict["hp_after"] = p_event.hp_after;
			r_dict["is_counter"] = p_event.is_counter;
			r_dict["source_id"] = to_id(p_event.content_id);
			r_dict["guarded"] = p_event.guarded;
			break;
		default:
			r_dict["unit"] = p_event.unit;
			r_dict["killer"] = p_event.target;
			r_dict["cell"] = to_vector2i(p_event.from);
			break;
	}
}

void add_skill_payload(const tactics::Event &p_event, Dictionary &r_dict) {
	r_dict["unit"] = p_event.unit;
	switch (p_event.type) {
		case tactics::EventType::SKILL_USED:
			r_dict["skill"] = to_id(p_event.content_id);
			r_dict["cell"] = to_vector2i(p_event.to);
			r_dict["cells"] = tactics_cells_to_array(p_event.cells);
			r_dict["targets"] = units_to_array(p_event.units);
			break;
		case tactics::EventType::SKILL_RESOLVED:
			r_dict["skill"] = to_id(p_event.content_id);
			r_dict["results"] = results_to_array(p_event.results);
			break;
		case tactics::EventType::SKILL_CHARGE_CHANGED:
			r_dict["charge"] = to_id(p_event.content_id);
			r_dict["value"] = p_event.value;
			r_dict["threshold"] = p_event.threshold;
			break;
		default:
			r_dict["skill"] = to_id(p_event.content_id);
			r_dict["area_bonus"] = p_event.value;
			break;
	}
}

void add_effect_payload(const tactics::Event &p_event, Dictionary &r_dict) {
	r_dict["unit"] = p_event.unit;
	switch (p_event.type) {
		case tactics::EventType::BUFF_APPLIED:
			r_dict["stat"] = to_id(p_event.kind);
			r_dict["amount"] = p_event.amount;
			r_dict["end_round"] = p_event.end_round;
			r_dict["source_id"] = to_id(p_event.content_id);
			break;
		case tactics::EventType::BUFF_ENDED:
			r_dict["source_id"] = to_id(p_event.content_id);
			break;
		case tactics::EventType::ZONE_CREATED:
			r_dict["side"] = p_event.side;
			r_dict["zone"] = to_id(p_event.content_id);
			r_dict["cells"] = tactics_cells_to_array(p_event.cells);
			r_dict["end_round"] = p_event.end_round;
			break;
		case tactics::EventType::ZONE_EXPIRED:
			r_dict["zone"] = to_id(p_event.content_id);
			r_dict["cells"] = tactics_cells_to_array(p_event.cells);
			break;
		default:
			r_dict["passive"] = to_id(p_event.content_id);
			break;
	}
}

void add_incident_payload(const tactics::Event &p_event, Dictionary &r_dict) {
	r_dict["unit"] = p_event.unit;
	switch (p_event.type) {
		case tactics::EventType::SOLDIER_WAVERED:
			r_dict["incident"] = to_id(p_event.content_id);
			r_dict["is_good"] = p_event.is_first_strike;
			break;
		case tactics::EventType::INCIDENT_CALMED:
			r_dict["incident"] = to_id(p_event.content_id);
			r_dict["reason"] = to_id(p_event.kind);
			break;
		case tactics::EventType::INCIDENT_FIRED:
			r_dict["incident"] = to_id(p_event.content_id);
			r_dict["is_good"] = p_event.is_first_strike;
			r_dict["leader"] = p_event.target;
			r_dict["side"] = p_event.side;
			r_dict["cell"] = to_vector2i(p_event.to);
			break;
		case tactics::EventType::MARK_EARNED:
			r_dict["incident"] = to_id(p_event.content_id);
			r_dict["leader_id"] = to_id(p_event.kind);
			r_dict["terrain"] = to_id(p_event.detail_id);
			r_dict["cell"] = to_vector2i(p_event.to);
			r_dict["count"] = p_event.value;
			break;
		case tactics::EventType::UNIT_FLED:
			r_dict["from"] = to_vector2i(p_event.from);
			r_dict["to"] = to_vector2i(p_event.to);
			break;
		case tactics::EventType::UNIT_DEFECTED:
			r_dict["side"] = p_event.side;
			r_dict["from_side"] = p_event.value;
			r_dict["leader"] = p_event.target;
			break;
		default:
			r_dict.erase("unit");
			r_dict["side"] = p_event.side;
			r_dict["kind"] = to_id(p_event.kind);
			r_dict["value"] = p_event.value;
			break;
	}
}

void add_payload(const tactics::Event &p_event, Dictionary &r_dict) {
	switch (p_event.type) {
		case tactics::EventType::BATTLE_STARTED:
			r_dict["units"] = p_event.value;
			break;
		case tactics::EventType::PHASE_STARTED:
		case tactics::EventType::PHASE_ENDED:
			r_dict["side"] = p_event.side;
			break;
		case tactics::EventType::UNIT_MOVED:
			r_dict["unit"] = p_event.unit;
			r_dict["from"] = to_vector2i(p_event.from);
			r_dict["to"] = to_vector2i(p_event.to);
			r_dict["path"] = tactics_cells_to_array(p_event.cells);
			r_dict["kind"] = to_id(p_event.kind);
			// Whether the other side saw the unit where it set off and
			// where it stopped (fog of war).
			r_dict["seen_from"] = (p_event.value & 1) != 0;
			r_dict["seen_to"] = (p_event.value & 2) != 0;
			break;
		case tactics::EventType::VISION_CHANGED:
			r_dict["side"] = p_event.side;
			r_dict["cells"] = tactics_cells_to_array(p_event.cells);
			r_dict["lost_cells"] = tactics_cells_to_array(p_event.other_cells);
			r_dict["units"] = units_to_array(p_event.units);
			r_dict["lost_units"] = units_to_array(p_event.other_units);
			r_dict["lost_at"] = tactics_cells_to_array(p_event.other_units_cells);
			break;
		case tactics::EventType::AMBUSHED:
			r_dict["unit"] = p_event.unit;
			r_dict["by"] = p_event.target;
			r_dict["cell"] = to_vector2i(p_event.to);
			r_dict["blocked"] = to_vector2i(p_event.from);
			break;
		case tactics::EventType::WEATHER_CHANGED:
		case tactics::EventType::DAYTIME_CHANGED:
			r_dict["now"] = to_id(p_event.content_id);
			r_dict["before"] = to_id(p_event.detail_id);
			break;
		case tactics::EventType::ORDER_CHANGED:
			r_dict["unit"] = p_event.unit;
			r_dict["order"] = to_id(p_event.content_id);
			break;
		case tactics::EventType::LEADER_WAITED:
			r_dict["unit"] = p_event.unit;
			break;
		case tactics::EventType::ENGAGEMENT_STARTED:
		case tactics::EventType::ENGAGEMENT_ENDED:
		case tactics::EventType::DAMAGE_DEALT:
		case tactics::EventType::UNIT_DIED:
			add_combat_payload(p_event, r_dict);
			break;
		case tactics::EventType::SKILL_USED:
		case tactics::EventType::SKILL_RESOLVED:
		case tactics::EventType::SKILL_CHARGE_CHANGED:
		case tactics::EventType::SKILL_GREW:
			add_skill_payload(p_event, r_dict);
			break;
		case tactics::EventType::INTENT_DECLARED:
			r_dict["unit"] = p_event.unit;
			r_dict["to"] = to_vector2i(p_event.to);
			r_dict["action"] = to_id(p_event.kind);
			r_dict["target"] = p_event.target;
			r_dict["target_cell"] = to_vector2i(p_event.from);
			break;
		case tactics::EventType::SOLDIER_WAVERED:
		case tactics::EventType::INCIDENT_CALMED:
		case tactics::EventType::INCIDENT_FIRED:
		case tactics::EventType::MARK_EARNED:
		case tactics::EventType::UNIT_FLED:
		case tactics::EventType::UNIT_DEFECTED:
		case tactics::EventType::KARMA_CHANGED:
			add_incident_payload(p_event, r_dict);
			break;
		case tactics::EventType::BATTLE_ENDED:
			r_dict["winner"] = p_event.winner;
			r_dict["reason"] = to_id(p_event.kind);
			break;
		default:
			add_effect_payload(p_event, r_dict);
			break;
	}
}

} // namespace

StringName godot::get_tactics_event_type_name(tactics::EventType p_type) {
	return StringName(EVENT_TYPE_NAMES[static_cast<int>(p_type)]);
}

Dictionary godot::tactics_event_to_dictionary(const tactics::Event &p_event) {
	Dictionary dict;
	dict["id"] = p_event.id;
	dict["turn"] = p_event.turn;
	dict["round"] = p_event.round;
	dict["type"] = get_tactics_event_type_name(p_event.type);
	dict["cause"] = p_event.cause;
	add_payload(p_event, dict);
	return dict;
}

Vector2i godot::to_vector2i(const tactics::Cell &p_cell) {
	return Vector2i(p_cell.col, p_cell.row);
}

Array godot::tactics_cells_to_array(const std::vector<tactics::Cell> &p_cells) {
	Array cells;
	for (const tactics::Cell &cell : p_cells) {
		cells.push_back(to_vector2i(cell));
	}
	cells.make_read_only();
	return cells;
}
