#include "tactics_battle.h"

#include "tactics_event_dictionary.h"
#include "tactics_orders.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace {

tactics::Cell to_cell(const Vector2i &p_cell) {
	return { p_cell.x, p_cell.y };
}

bool is_valid_side(int64_t p_side) {
	return p_side == tactics::SIDE_A || p_side == tactics::SIDE_B;
}

} // namespace

bool TacticsBattle::check_not_emitting(const char *p_method) const {
	ERR_FAIL_COND_V_MSG(is_emitting, false, vformat("Tactics: %s() cannot be called from an event handler", p_method));
	return true;
}

bool TacticsBattle::check_unit(int64_t p_unit, const char *p_method) const {
	ERR_FAIL_INDEX_V_MSG(p_unit, static_cast<int64_t>(get_unit_count()), false, vformat("Tactics: %s() got unit %d, which does not exist", p_method, p_unit));
	return true;
}

bool TacticsBattle::setup(const Ref<TacticsRulesData> &p_rules, const Ref<TacticsMapData> &p_map) {
	if (!check_not_emitting("setup")) {
		return false;
	}
	tactics::MapDef map;
	std::string error;
	const bool is_data_valid = p_rules.is_valid() && p_map.is_valid() && p_map->to_map_def(&map, &error);
	if (!is_data_valid || !sim.setup(p_rules->to_rules(), map, &error)) {
		// Like a failed load: an earlier setup does not stay to be started.
		if (!sim.is_started()) {
			clear_setup();
		}
		ERR_FAIL_V_MSG(false, "Tactics: setup() refused: " + (error.empty() ? String("it needs rules and a map") : to_godot_string(error)));
	}
	return true;
}

bool TacticsBattle::load_scenario(const Ref<TacticsScenarioData> &p_scenario) {
	ERR_FAIL_COND_V_MSG(p_scenario.is_null(), false, "Tactics: load_scenario() got a null scenario");
	if (!setup(p_scenario->get_rules(), p_scenario->get_map())) {
		// A running battle stays; an earlier setup does not.
		if (!sim.is_started()) {
			clear_setup();
		}
		return false;
	}
	for (int side = 0; side < tactics::SIDE_COUNT; side++) {
		const TypedArray<TacticsLeaderData> leaders = p_scenario->get_leaders(side);
		const TypedArray<Vector2i> spawns = p_scenario->get_map()->get_spawn_cells(side);
		const bool has_spawns = leaders.size() <= spawns.size();
		for (int64_t index = 0; has_spawns && index < leaders.size(); index++) {
			if (add_leader(side, leaders[index], spawns[index]) < 0) {
				clear_setup();
				return false;
			}
		}
		if (!has_spawns) {
			clear_setup();
			ERR_FAIL_V_MSG(false, vformat("Tactics: %s side %d has more leaders than spawn cells", p_scenario->get_id(), side));
		}
	}
	return true;
}

// A failed load leaves nothing to start; the AI sides are kept.
void TacticsBattle::clear_setup() {
	const bool ai_sides[tactics::SIDE_COUNT] = { sim.is_side_ai(tactics::SIDE_A), sim.is_side_ai(tactics::SIDE_B) };
	sim = tactics::TacticsSim();
	sim.set_side_ai(tactics::SIDE_A, ai_sides[tactics::SIDE_A]);
	sim.set_side_ai(tactics::SIDE_B, ai_sides[tactics::SIDE_B]);
}

void TacticsBattle::set_side_ai(int64_t p_side, bool p_is_ai) {
	ERR_FAIL_COND_MSG(!is_valid_side(p_side), vformat("Tactics: set_side_ai() got side %d, expected 0 or 1", p_side));
	ERR_FAIL_COND_MSG(sim.is_started(), "Tactics: set_side_ai() is refused once the battle started");
	sim.set_side_ai(static_cast<int>(p_side), p_is_ai);
}

bool TacticsBattle::is_side_ai(int64_t p_side) const {
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side), false, vformat("Tactics: is_side_ai() got side %d, expected 0 or 1", p_side));
	return sim.is_side_ai(static_cast<int>(p_side));
}

int TacticsBattle::add_leader(int64_t p_side, const Ref<TacticsLeaderData> &p_leader, const Vector2i &p_cell) {
	ERR_FAIL_COND_V_MSG(p_leader.is_null(), -1, "Tactics: add_leader() got a null leader");
	return add_leader_with_squad(p_side, p_leader, p_cell, p_leader->get_squad());
}

int TacticsBattle::add_leader_with_squad(int64_t p_side, const Ref<TacticsLeaderData> &p_leader, const Vector2i &p_cell, const Array &p_squad) {
	if (!check_not_emitting("add_leader")) {
		return -1;
	}
	ERR_FAIL_COND_V_MSG(p_leader.is_null(), -1, "Tactics: add_leader() got a null leader");
	// Checked here: the simulation takes an int, and a side such as 2^32
	// would truncate to 0.
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side), -1, vformat("Tactics: add_leader() got side %d, expected 0 or 1", p_side));
	tactics::UnitDef leader;
	std::string error;
	ERR_FAIL_COND_V_MSG(!p_leader->to_unit_def(&leader, &error), -1, "Tactics: " + to_godot_string(error));
	std::vector<tactics::UnitDef> squad;
	ERR_FAIL_COND_V_MSG(!tactics_squad_to_unit_defs(leader.id, p_squad, &squad, &error), -1, "Tactics: " + to_godot_string(error));
	const int index = sim.add_leader(static_cast<int>(p_side), leader, to_cell(p_cell), squad, &error);
	ERR_FAIL_COND_V_MSG(index < 0, -1, "Tactics: " + to_godot_string(error));
	return index;
}

Array TacticsBattle::start() {
	if (!check_not_emitting("start")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.start(&error), Array(), "Tactics: " + to_godot_string(error));
	return flush_events();
}

Array TacticsBattle::move_leader(int64_t p_unit, const Vector2i &p_cell) {
	if (!check_not_emitting("move_leader")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.move_leader(clamp_to_int(p_unit), to_cell(p_cell), &error), Array(), "Tactics: move_leader() refused: " + to_godot_string(error));
	return flush_events();
}

Array TacticsBattle::attack(int64_t p_unit, int64_t p_target) {
	if (!check_not_emitting("attack")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.attack(clamp_to_int(p_unit), clamp_to_int(p_target), &error), Array(), "Tactics: attack() refused: " + to_godot_string(error));
	return flush_events();
}

Array TacticsBattle::use_skill(int64_t p_unit, const Vector2i &p_cell) {
	if (!check_not_emitting("use_skill")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.use_skill(clamp_to_int(p_unit), to_cell(p_cell), &error), Array(), "Tactics: use_skill() refused: " + to_godot_string(error));
	return flush_events();
}

Array TacticsBattle::wait(int64_t p_unit) {
	if (!check_not_emitting("wait")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.wait(clamp_to_int(p_unit), &error), Array(), "Tactics: wait() refused: " + to_godot_string(error));
	return flush_events();
}

Array TacticsBattle::set_order(int64_t p_unit, const StringName &p_order) {
	if (!check_not_emitting("set_order")) {
		return Array();
	}
	const int order = tactics::find_order_index(to_std_string(p_order));
	ERR_FAIL_COND_V_MSG(order == tactics::NO_INDEX, Array(), vformat("Tactics: set_order() got unknown order %s", p_order));
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.set_order(clamp_to_int(p_unit), order, &error), Array(), "Tactics: set_order() refused: " + to_godot_string(error));
	return flush_events();
}

Array TacticsBattle::end_phase() {
	if (!check_not_emitting("end_phase")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.end_phase(&error), Array(), "Tactics: end_phase() refused: " + to_godot_string(error));
	return flush_events();
}

Array TacticsBattle::flush_events() {
	const std::vector<tactics::Event> events = sim.take_events();
	Array result;
	for (const tactics::Event &event : events) {
		Dictionary dict = tactics_event_to_dictionary(event);
		dict.make_read_only();
		result.push_back(dict);
		log_event(event);
	}
	result.make_read_only();
	const ObjectID self_id(get_instance_id());
	is_emitting = true;
	for (size_t index = 0; index < events.size(); index++) {
		const tactics::Event &event = events[index];
		emit_signal("event_emitted", result[static_cast<int64_t>(index)]);
		if (ObjectDB::get_instance(self_id) == nullptr) {
			return result;
		}
		if (event.type == tactics::EventType::BATTLE_ENDED) {
			emit_signal("battle_ended", event.winner, StringName(to_godot_string(event.kind)));
			if (ObjectDB::get_instance(self_id) == nullptr) {
				return result;
			}
		}
	}
	is_emitting = false;
	return result;
}

void TacticsBattle::log_event(const tactics::Event &p_event) const {
	if (!log_enabled) {
		return;
	}
	const String prefix = vformat("[info][Tactics][t=%d] ", p_event.turn);
	switch (p_event.type) {
		case tactics::EventType::BATTLE_STARTED:
			UtilityFunctions::print(prefix + vformat("battle_started units=%d", p_event.value));
			break;
		case tactics::EventType::PHASE_STARTED:
			UtilityFunctions::print(prefix + vformat("phase_started side=%d round=%d", p_event.side, p_event.round));
			break;
		case tactics::EventType::UNIT_DIED:
			UtilityFunctions::print(prefix + vformat("unit_died unit=%d unit_id=%s killer=%d cause=e%d", p_event.unit, to_godot_string(sim.get_units()[p_event.unit].def.id), p_event.target, p_event.cause));
			break;
		case tactics::EventType::SKILL_USED:
			UtilityFunctions::print(prefix + vformat("skill_used unit=%d skill=%s targets=%d", p_event.unit, to_godot_string(p_event.content_id), static_cast<int64_t>(p_event.units.size())));
			break;
		case tactics::EventType::BATTLE_ENDED:
			UtilityFunctions::print(prefix + vformat("battle_ended winner=%d reason=%s", p_event.winner, to_godot_string(p_event.kind)));
			break;
		default:
			break;
	}
}

void TacticsBattle::_bind_methods() {
	BIND_ENUM_CONSTANT(SIDE_A);
	BIND_ENUM_CONSTANT(SIDE_B);

	ClassDB::bind_method(D_METHOD("setup", "rules", "map"), &TacticsBattle::setup);
	ClassDB::bind_method(D_METHOD("load_scenario", "scenario"), &TacticsBattle::load_scenario);
	ClassDB::bind_method(D_METHOD("set_side_ai", "side", "is_ai"), &TacticsBattle::set_side_ai);
	ClassDB::bind_method(D_METHOD("is_side_ai", "side"), &TacticsBattle::is_side_ai);
	ClassDB::bind_method(D_METHOD("add_leader", "side", "leader", "cell"), &TacticsBattle::add_leader);
	ClassDB::bind_method(D_METHOD("add_leader_with_squad", "side", "leader", "cell", "squad"), &TacticsBattle::add_leader_with_squad);
	ClassDB::bind_method(D_METHOD("start"), &TacticsBattle::start);
	ClassDB::bind_method(D_METHOD("move_leader", "unit", "cell"), &TacticsBattle::move_leader);
	ClassDB::bind_method(D_METHOD("attack", "unit", "target"), &TacticsBattle::attack);
	ClassDB::bind_method(D_METHOD("use_skill", "unit", "cell"), &TacticsBattle::use_skill);
	ClassDB::bind_method(D_METHOD("wait", "unit"), &TacticsBattle::wait);
	ClassDB::bind_method(D_METHOD("set_order", "unit", "order"), &TacticsBattle::set_order);
	ClassDB::bind_method(D_METHOD("end_phase"), &TacticsBattle::end_phase);
	ClassDB::bind_method(D_METHOD("is_started"), &TacticsBattle::is_started);
	ClassDB::bind_method(D_METHOD("is_finished"), &TacticsBattle::is_finished);
	ClassDB::bind_method(D_METHOD("get_winner"), &TacticsBattle::get_winner);
	ClassDB::bind_method(D_METHOD("get_end_reason"), &TacticsBattle::get_end_reason);
	ClassDB::bind_method(D_METHOD("get_round"), &TacticsBattle::get_round);
	ClassDB::bind_method(D_METHOD("get_turn"), &TacticsBattle::get_turn);
	ClassDB::bind_method(D_METHOD("get_active_side"), &TacticsBattle::get_active_side);
	ClassDB::bind_method(D_METHOD("get_map_width"), &TacticsBattle::get_map_width);
	ClassDB::bind_method(D_METHOD("get_map_height"), &TacticsBattle::get_map_height);
	ClassDB::bind_method(D_METHOD("get_terrain_id", "cell"), &TacticsBattle::get_terrain_id);
	ClassDB::bind_method(D_METHOD("get_state_hash"), &TacticsBattle::get_state_hash);
	ClassDB::bind_method(D_METHOD("get_unit_count"), &TacticsBattle::get_unit_count);
	ClassDB::bind_method(D_METHOD("get_unit_state", "unit"), &TacticsBattle::get_unit_state);
	ClassDB::bind_method(D_METHOD("get_units"), &TacticsBattle::get_units);
	ClassDB::bind_method(D_METHOD("get_zones"), &TacticsBattle::get_zones);
	ClassDB::bind_method(D_METHOD("get_reachable_cells", "unit"), &TacticsBattle::get_reachable_cells);
	ClassDB::bind_method(D_METHOD("get_path_to", "unit", "cell"), &TacticsBattle::get_path_to);
	ClassDB::bind_method(D_METHOD("get_formation_slots", "leader"), &TacticsBattle::get_formation_slots);
	ClassDB::bind_method(D_METHOD("forecast_engagement", "attacker", "defender"), &TacticsBattle::forecast_engagement);
	ClassDB::bind_method(D_METHOD("preview_squad", "leader", "cell"), &TacticsBattle::preview_squad);
	ClassDB::bind_method(D_METHOD("get_skill_charge", "leader"), &TacticsBattle::get_skill_charge);
	ClassDB::bind_method(D_METHOD("get_enemy_intents"), &TacticsBattle::get_enemy_intents);
	ClassDB::bind_method(D_METHOD("set_log_enabled", "enabled"), &TacticsBattle::set_log_enabled);
	ClassDB::bind_method(D_METHOD("is_log_enabled"), &TacticsBattle::is_log_enabled);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "log_enabled"), "set_log_enabled", "is_log_enabled");

	ADD_SIGNAL(MethodInfo("event_emitted", PropertyInfo(Variant::DICTIONARY, "event")));
	ADD_SIGNAL(MethodInfo("battle_ended", PropertyInfo(Variant::INT, "winner"), PropertyInfo(Variant::STRING_NAME, "reason")));
}
