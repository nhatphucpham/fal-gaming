#include "battle_event_dictionary.h"

#include "bridge_strings.h"

#include "skill/skill_statuses.h"

#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace {

const char *const EVENT_TYPE_NAMES[] = {
	"battle_started",
	"unit_moved",
	"unit_attacked",
	"damage_dealt",
	"unit_died",
	"charge_ended",
	"battle_ended",
	"qi_changed",
	"skill_cast_started",
	"skill_resolved",
	"passive_triggered",
	"status_applied",
	"status_ended",
};
const char *const MOVE_KIND_NAMES[] = { "walk", "charge", "knockback" };
const char *const ATTACK_KIND_NAMES[] = { "melee", "ranged", "magic" };
const char *const END_REASON_NAMES[] = { "elimination", "time_limit" };

void add_moved_payload(const battle::BattleEvent &p_event, Dictionary &r_dict) {
	r_dict["unit"] = p_event.unit;
	r_dict["from_col"] = p_event.from.col;
	r_dict["from_row"] = p_event.from.row;
	r_dict["to_col"] = p_event.to.col;
	r_dict["to_row"] = p_event.to.row;
	r_dict["duration_ticks"] = p_event.duration_ticks;
	r_dict["kind"] = StringName(MOVE_KIND_NAMES[static_cast<int>(p_event.move_kind)]);
}

void add_damage_payload(const battle::BattleEvent &p_event, Dictionary &r_dict) {
	r_dict["source"] = p_event.source;
	r_dict["target"] = p_event.target;
	r_dict["amount"] = p_event.amount;
	r_dict["hp_after"] = p_event.hp_after;
	r_dict["is_counter"] = p_event.is_counter;
	r_dict["is_crit"] = p_event.is_crit;
	r_dict["blocked_by"] = p_event.blocked_by;
	r_dict["skill"] = StringName(to_godot_string(p_event.skill_id));
}

void add_skill_payload(const battle::BattleEvent &p_event, Dictionary &r_dict) {
	r_dict["unit"] = p_event.unit;
	switch (p_event.type) {
		case battle::EventType::QI_CHANGED:
			r_dict["qi"] = p_event.qi;
			r_dict["qi_max"] = p_event.qi_max;
			break;
		case battle::EventType::SKILL_CAST_STARTED:
			r_dict["skill"] = StringName(to_godot_string(p_event.skill_id));
			r_dict["cells"] = cells_to_array(p_event.cells);
			r_dict["end_tick"] = p_event.end_tick;
			break;
		case battle::EventType::SKILL_RESOLVED:
			r_dict["skill"] = StringName(to_godot_string(p_event.skill_id));
			r_dict["cells"] = cells_to_array(p_event.cells);
			r_dict["is_after_skill"] = p_event.is_after_skill;
			break;
		case battle::EventType::PASSIVE_TRIGGERED:
			r_dict["passive"] = StringName(to_godot_string(p_event.skill_id));
			break;
		case battle::EventType::STATUS_APPLIED:
			r_dict["status"] = StringName(battle::get_status_id(p_event.status));
			r_dict["source"] = p_event.source;
			r_dict["end_tick"] = p_event.end_tick;
			r_dict["amount"] = p_event.amount;
			break;
		case battle::EventType::STATUS_ENDED:
			r_dict["status"] = StringName(battle::get_status_id(p_event.status));
			break;
		default:
			break;
	}
}

void add_payload(const battle::BattleEvent &p_event, Dictionary &r_dict) {
	switch (p_event.type) {
		case battle::EventType::BATTLE_STARTED:
			break;
		case battle::EventType::UNIT_MOVED:
			add_moved_payload(p_event, r_dict);
			break;
		case battle::EventType::UNIT_ATTACKED:
			r_dict["unit"] = p_event.unit;
			r_dict["target"] = p_event.target;
			r_dict["kind"] = StringName(ATTACK_KIND_NAMES[static_cast<int>(p_event.attack_kind)]);
			r_dict["to_col"] = p_event.to.col;
			r_dict["to_row"] = p_event.to.row;
			break;
		case battle::EventType::DAMAGE_DEALT:
			add_damage_payload(p_event, r_dict);
			break;
		case battle::EventType::UNIT_DIED:
			r_dict["unit"] = p_event.unit;
			r_dict["killer"] = p_event.killer;
			break;
		case battle::EventType::CHARGE_ENDED:
			r_dict["unit"] = p_event.unit;
			r_dict["hit"] = p_event.hit;
			break;
		case battle::EventType::BATTLE_ENDED:
			r_dict["winner"] = p_event.winner;
			r_dict["reason"] = get_end_reason_name(p_event.reason);
			break;
		default:
			add_skill_payload(p_event, r_dict);
			break;
	}
}

} // namespace

StringName godot::get_event_type_name(battle::EventType p_type) {
	return StringName(EVENT_TYPE_NAMES[static_cast<int>(p_type)]);
}

StringName godot::get_end_reason_name(battle::EndReason p_reason) {
	return StringName(END_REASON_NAMES[static_cast<int>(p_reason)]);
}

Dictionary godot::event_to_dictionary(const battle::BattleEvent &p_event) {
	Dictionary dict;
	dict["id"] = p_event.id;
	dict["tick"] = p_event.tick;
	dict["type"] = get_event_type_name(p_event.type);
	dict["cause"] = p_event.cause;
	add_payload(p_event, dict);
	return dict;
}

Array godot::cells_to_array(const std::vector<battle::Cell> &p_cells) {
	Array cells;
	for (const battle::Cell &cell : p_cells) {
		cells.push_back(Vector2i(cell.col, cell.row));
	}
	return cells;
}

Array godot::get_status_array(const battle::UnitState &p_unit, int p_tick) {
	Array statuses;
	for (int kind = 0; kind < battle::STATUS_COUNT; kind++) {
		const battle::StatusSlot &slot = p_unit.skills.statuses[kind];
		if (!slot.is_active || p_tick >= slot.end_tick) {
			continue;
		}
		Dictionary status;
		status["status"] = StringName(battle::get_status_id(static_cast<battle::StatusKind>(kind)));
		status["end_tick"] = slot.end_tick;
		status["amount"] = slot.amount;
		status["source"] = slot.source;
		statuses.push_back(status);
	}
	return statuses;
}
