#include "battle.h"

#include "battle_board.h"
#include "battle_event_dictionary.h"
#include "bridge_strings.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace {

constexpr int HASH_HEX_DIGITS = 16;

String format_hash(uint64_t p_hash) {
	const char *digits = "0123456789abcdef";
	String text;
	for (int shift = (HASH_HEX_DIGITS - 1) * 4; shift >= 0; shift -= 4) {
		text += String::chr(digits[(p_hash >> shift) & 0xFu]);
	}
	return text;
}

} // namespace

void Battle::set_rules(const Ref<BattleRulesData> &p_rules) {
	ERR_FAIL_COND_MSG(is_emitting, "Battle: set_rules() cannot be called from an event handler");
	ERR_FAIL_COND_MSG(p_rules.is_null(), "Battle: set_rules() got a null BattleRulesData");
	std::string error;
	ERR_FAIL_COND_MSG(!sim.set_rules(p_rules->to_rules(), &error), "Battle: " + to_godot_string(error));
	rules = p_rules;
}

bool Battle::register_class(const Ref<ClassData> &p_class) {
	ERR_FAIL_COND_V_MSG(is_emitting, false, "Battle: register_class() cannot be called from an event handler");
	ERR_FAIL_COND_V_MSG(p_class.is_null(), false, "Battle: register_class() got a null ClassData");
	std::string error;
	const String where = p_class->get_path().is_empty() ? String() : " in " + p_class->get_path();
	ERR_FAIL_COND_V_MSG(!sim.register_class(p_class->to_class_def(), &error), false, "Battle: " + to_godot_string(error) + where);
	return true;
}

int Battle::add_unit(int p_side, const Ref<UnitData> &p_unit, int p_star, int p_local_col, int p_local_rank) {
	ERR_FAIL_COND_V_MSG(is_emitting, -1, "Battle: add_unit() cannot be called from an event handler");
	ERR_FAIL_COND_V_MSG(p_unit.is_null(), -1, "Battle: add_unit() got a null UnitData");
	battle::UnitSpec spec;
	spec.unit_id = to_std_string(p_unit->get_id());
	spec.class_id = to_std_string(p_unit->get_class_id());
	spec.cost = p_unit->get_cost();
	spec.star = p_star;
	std::string error;
	const int index = sim.add_unit(p_side, spec, p_local_col, p_local_rank, &error);
	ERR_FAIL_COND_V_MSG(index < 0, -1, "Battle: " + to_godot_string(error));
	return index;
}

void Battle::clear() {
	ERR_FAIL_COND_MSG(is_emitting, "Battle: clear() cannot be called from an event handler");
	sim.clear();
}

void Battle::start() {
	ERR_FAIL_COND_MSG(is_emitting, "Battle: start() cannot be called from an event handler");
	std::string error;
	ERR_FAIL_COND_MSG(!sim.start(&error), "Battle: " + to_godot_string(error));
}

Array Battle::step() {
	Array result;
	ERR_FAIL_COND_V_MSG(is_emitting, result, "Battle: step() cannot be called from an event_emitted or battle_ended handler");
	ERR_FAIL_COND_V_MSG(!sim.is_started(), result, "Battle: step() called before start()");
	// Copy the tick's events before any handler runs: the simulation reuses
	// its event buffer on the next step.
	const std::vector<battle::BattleEvent> events = sim.step();
	for (const battle::BattleEvent &event : events) {
		result.push_back(event_to_dictionary(event));
		log_event(event);
	}
	is_emitting = true;
	for (int64_t index = 0; index < result.size(); index++) {
		emit_signal("event_emitted", result[index]);
	}
	if (sim.is_finished() && !events.empty() && events.back().type == battle::EventType::BATTLE_ENDED) {
		emit_signal("battle_ended", events.back().winner, get_end_reason_name(events.back().reason));
	}
	is_emitting = false;
	return result;
}

String Battle::run_to_end(int p_max_ticks) {
	ERR_FAIL_COND_V_MSG(is_emitting, get_state_hash(), "Battle: run_to_end() cannot be called from an event handler");
	if (!sim.is_started()) {
		start();
	}
	for (int steps = 0; steps < p_max_ticks && sim.is_started() && !sim.is_finished(); steps++) {
		step();
	}
	return get_state_hash();
}

void Battle::log_event(const battle::BattleEvent &p_event) const {
	if (!log_enabled) {
		return;
	}
	const String prefix = vformat("[info][Battle][t=%d] ", p_event.tick);
	switch (p_event.type) {
		case battle::EventType::BATTLE_STARTED:
			UtilityFunctions::print(prefix + vformat("battle_started units=%d", get_unit_count()));
			break;
		case battle::EventType::UNIT_DIED:
			UtilityFunctions::print(prefix + vformat("unit_died unit=%d unit_id=%s killer=%d cause=e%d", p_event.unit, to_godot_string(sim.get_units()[p_event.unit].unit_id), p_event.killer, p_event.cause));
			break;
		case battle::EventType::BATTLE_ENDED:
			UtilityFunctions::print(prefix + vformat("battle_ended winner=%d reason=%s", p_event.winner, get_end_reason_name(p_event.reason)));
			break;
		default:
			break;
	}
}

String Battle::get_state_hash() const {
	return format_hash(sim.get_state_hash());
}

Dictionary Battle::get_unit_state(int p_index) const {
	Dictionary state;
	ERR_FAIL_INDEX_V_MSG(p_index, get_unit_count(), state, vformat("Battle: no unit with index %d", p_index));
	const battle::UnitState &unit = sim.get_units()[p_index];
	state["index"] = unit.index;
	state["side"] = unit.side;
	state["unit_id"] = StringName(to_godot_string(unit.unit_id));
	state["class_id"] = StringName(to_godot_string(sim.get_class_def(unit).id));
	state["star"] = unit.star;
	state["alive"] = unit.is_alive;
	state["hp"] = unit.hp;
	state["max_hp"] = unit.max_hp;
	state["attack"] = unit.attack;
	state["col"] = unit.cell.col;
	state["row"] = unit.cell.row;
	state["target"] = unit.target;
	state["move_ticks_left"] = sim.get_move_ticks_left(unit);
	return state;
}

Array Battle::get_units() const {
	Array states;
	for (int index = 0; index < get_unit_count(); index++) {
		states.push_back(get_unit_state(index));
	}
	return states;
}

Vector2i Battle::local_to_global(int p_side, int p_local_col, int p_local_rank) {
	const battle::Cell cell = battle::local_to_global(p_side, p_local_col, p_local_rank);
	return Vector2i(cell.col, cell.row);
}

Vector2i Battle::global_to_local(int p_side, int p_col, int p_row) {
	const battle::Cell local = battle::global_to_local(p_side, { p_col, p_row });
	return Vector2i(local.col, local.row);
}

void Battle::_bind_methods() {
	BIND_ENUM_CONSTANT(SIDE_A);
	BIND_ENUM_CONSTANT(SIDE_B);

	ClassDB::bind_method(D_METHOD("set_rules", "rules"), &Battle::set_rules);
	ClassDB::bind_method(D_METHOD("get_rules"), &Battle::get_rules);
	ClassDB::bind_method(D_METHOD("register_class", "class_data"), &Battle::register_class);
	ClassDB::bind_method(D_METHOD("add_unit", "side", "unit", "star", "local_col", "local_rank"), &Battle::add_unit);
	ClassDB::bind_method(D_METHOD("clear"), &Battle::clear);
	ClassDB::bind_method(D_METHOD("start"), &Battle::start);
	ClassDB::bind_method(D_METHOD("step"), &Battle::step);
	ClassDB::bind_method(D_METHOD("run_to_end", "max_ticks"), &Battle::run_to_end);
	ClassDB::bind_method(D_METHOD("is_started"), &Battle::is_started);
	ClassDB::bind_method(D_METHOD("is_finished"), &Battle::is_finished);
	ClassDB::bind_method(D_METHOD("get_winner"), &Battle::get_winner);
	ClassDB::bind_method(D_METHOD("get_tick"), &Battle::get_tick);
	ClassDB::bind_method(D_METHOD("get_state_hash"), &Battle::get_state_hash);
	ClassDB::bind_method(D_METHOD("get_unit_count"), &Battle::get_unit_count);
	ClassDB::bind_method(D_METHOD("get_unit_state", "index"), &Battle::get_unit_state);
	ClassDB::bind_method(D_METHOD("get_units"), &Battle::get_units);
	ClassDB::bind_method(D_METHOD("set_log_enabled", "enabled"), &Battle::set_log_enabled);
	ClassDB::bind_method(D_METHOD("is_log_enabled"), &Battle::is_log_enabled);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("local_to_global", "side", "local_col", "local_rank"), &Battle::local_to_global);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("global_to_local", "side", "col", "row"), &Battle::global_to_local);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "rules", PROPERTY_HINT_RESOURCE_TYPE, "BattleRulesData"), "set_rules", "get_rules");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "log_enabled"), "set_log_enabled", "is_log_enabled");

	ADD_SIGNAL(MethodInfo("event_emitted", PropertyInfo(Variant::DICTIONARY, "event")));
	ADD_SIGNAL(MethodInfo("battle_ended", PropertyInfo(Variant::INT, "winner"), PropertyInfo(Variant::STRING_NAME, "reason")));
}
