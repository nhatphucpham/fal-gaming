#include "battle.h"

#include "battle_board.h"
#include "battle_event_dictionary.h"
#include "bridge_strings.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace {

constexpr int HASH_HEX_DIGITS = 16;
const Vector2i INVALID_CELL(-1, -1);

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
	const String where = p_class->get_path().is_empty() ? String() : " in " + p_class->get_path();
	ERR_FAIL_COND_V_MSG(!p_class->has_valid_damage_kind(), false, vformat("Battle: %s has unknown damage_kind %d%s", p_class->get_id(), p_class->get_damage_kind(), where));
	std::string error;
	battle::ClassDef def;
	ERR_FAIL_COND_V_MSG(!p_class->to_class_def(&def, &error), false, vformat("Battle: %s: %s%s", p_class->get_id(), to_godot_string(error), where));
	ERR_FAIL_COND_V_MSG(!sim.register_class(def, &error), false, "Battle: " + to_godot_string(error) + where);
	return true;
}

int Battle::add_unit(int64_t p_side, const Ref<UnitData> &p_unit, int64_t p_star, int64_t p_local_col, int64_t p_local_rank) {
	ERR_FAIL_COND_V_MSG(is_emitting, -1, "Battle: add_unit() cannot be called from an event handler");
	ERR_FAIL_COND_V_MSG(p_unit.is_null(), -1, "Battle: add_unit() got a null UnitData");
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side), -1, vformat("Battle: add_unit() got side %d, expected 0 or 1", p_side));
	ERR_FAIL_COND_V_MSG(p_star < battle::MIN_STAR || p_star > battle::MAX_STAR, -1, vformat("Battle: add_unit() got star %d for %s, expected 1..3", p_star, p_unit->get_id()));
	ERR_FAIL_COND_V_MSG(!is_valid_local_cell(p_local_col, p_local_rank), -1, vformat("Battle: add_unit() got col %d rank %d for %s, expected col 1..7 and rank 1..4", p_local_col, p_local_rank, p_unit->get_id()));
	battle::UnitSpec spec;
	spec.unit_id = to_std_string(p_unit->get_id());
	spec.class_id = to_std_string(p_unit->get_class_id());
	spec.cost = p_unit->get_cost();
	spec.star = static_cast<int>(p_star);
	std::string error;
	const Ref<SkillData> skill_override = p_unit->get_skill_override();
	spec.has_skill_override = skill_override.is_valid();
	ERR_FAIL_COND_V_MSG(spec.has_skill_override && !skill_override->to_skill_def(&spec.skill_override, &error), -1, vformat("Battle: %s skill_override: %s", p_unit->get_id(), to_godot_string(error)));
	const Ref<PassiveData> passive_override = p_unit->get_passive_override();
	spec.has_passive_override = passive_override.is_valid();
	ERR_FAIL_COND_V_MSG(spec.has_passive_override && !passive_override->to_passive_def(&spec.passive_override, &error), -1, vformat("Battle: %s passive_override: %s", p_unit->get_id(), to_godot_string(error)));
	const int index = sim.add_unit(static_cast<int>(p_side), spec, static_cast<int>(p_local_col), static_cast<int>(p_local_rank), &error);
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
	// Build everything returned before any handler runs: the simulation
	// reuses its event buffer, and a handler may even free this node.
	const std::vector<battle::BattleEvent> events = sim.step();
	for (const battle::BattleEvent &event : events) {
		Dictionary dict = event_to_dictionary(event);
		dict.make_read_only();
		result.push_back(dict);
		log_event(event);
	}
	result.make_read_only();
	const bool has_ended = !events.empty() && events.back().type == battle::EventType::BATTLE_ENDED;
	const int winner = has_ended ? events.back().winner : battle::NO_WINNER;
	const StringName reason = has_ended ? get_end_reason_name(events.back().reason) : StringName();

	const ObjectID self_id(get_instance_id());
	is_emitting = true;
	for (int64_t index = 0; index < result.size(); index++) {
		emit_signal("event_emitted", result[index]);
		if (ObjectDB::get_instance(self_id) == nullptr) {
			return result;
		}
	}
	if (has_ended) {
		emit_signal("battle_ended", winner, reason);
		if (ObjectDB::get_instance(self_id) == nullptr) {
			return result;
		}
	}
	is_emitting = false;
	return result;
}

String Battle::run_to_end(int64_t p_max_ticks) {
	ERR_FAIL_COND_V_MSG(is_emitting, get_state_hash(), "Battle: run_to_end() cannot be called from an event handler");
	ERR_FAIL_COND_V_MSG(p_max_ticks < 0, get_state_hash(), vformat("Battle: run_to_end() needs max_ticks >= 0, got %d", p_max_ticks));
	if (!sim.is_started()) {
		start();
	}
	const ObjectID self_id(get_instance_id());
	for (int64_t steps = 0; steps < p_max_ticks && sim.is_started() && !sim.is_finished(); steps++) {
		step();
		// A handler freed this node: nothing of it may be touched any more.
		if (ObjectDB::get_instance(self_id) == nullptr) {
			return String();
		}
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
		case battle::EventType::SKILL_CAST_STARTED:
			UtilityFunctions::print(prefix + vformat("skill_cast_started unit=%d skill=%s cells=%d", p_event.unit, to_godot_string(p_event.skill_id), static_cast<int64_t>(p_event.cells.size())));
			break;
		default:
			break;
	}
}

String Battle::get_state_hash() const {
	return format_hash(sim.get_state_hash());
}

Dictionary Battle::get_unit_state(int64_t p_index) const {
	Dictionary state;
	ERR_FAIL_INDEX_V_MSG(p_index, static_cast<int64_t>(get_unit_count()), state, vformat("Battle: no unit with index %d", p_index));
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
	state["qi"] = unit.skills.qi;
	state["qi_max"] = unit.skills.qi_max;
	state["casting"] = unit.skills.cast.is_casting;
	state["statuses"] = get_status_array(unit, sim.get_tick());
	return state;
}

Array Battle::get_units() const {
	Array states;
	for (int index = 0; index < get_unit_count(); index++) {
		states.push_back(get_unit_state(index));
	}
	return states;
}

bool Battle::is_valid_side(int64_t p_side) {
	return p_side == SIDE_A || p_side == SIDE_B;
}

bool Battle::is_valid_local_cell(int64_t p_local_col, int64_t p_local_rank) {
	return p_local_col >= 1 && p_local_col <= battle::BOARD_COLS && p_local_rank >= 1 && p_local_rank <= battle::SIDE_RANKS;
}

Vector2i Battle::local_to_global(int64_t p_side, int64_t p_local_col, int64_t p_local_rank) {
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side) || !is_valid_local_cell(p_local_col, p_local_rank), INVALID_CELL, vformat("Battle: local_to_global() got side %d col %d rank %d", p_side, p_local_col, p_local_rank));
	const battle::Cell cell = battle::local_to_global(static_cast<int>(p_side), static_cast<int>(p_local_col), static_cast<int>(p_local_rank));
	return Vector2i(cell.col, cell.row);
}

Vector2i Battle::global_to_local(int64_t p_side, int64_t p_col, int64_t p_row) {
	const bool is_on_board = p_col >= 0 && p_col < battle::BOARD_COLS && p_row >= 0 && p_row < battle::BOARD_ROWS;
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side) || !is_on_board, INVALID_CELL, vformat("Battle: global_to_local() got side %d col %d row %d", p_side, p_col, p_row));
	const battle::Cell local = battle::global_to_local(static_cast<int>(p_side), { static_cast<int>(p_col), static_cast<int>(p_row) });
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
