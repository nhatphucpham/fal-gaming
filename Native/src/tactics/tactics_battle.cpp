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
	return load_scenario_with_squads(p_scenario, tactics::SIDE_A, Array());
}

// An empty p_squads keeps every leader's own squad (load_scenario).
bool TacticsBattle::load_scenario_with_squads(const Ref<TacticsScenarioData> &p_scenario, int64_t p_side, const Array &p_squads) {
	ERR_FAIL_COND_V_MSG(p_scenario.is_null(), false, "Tactics: load_scenario() got a null scenario");
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side), false, vformat("Tactics: load_scenario_with_squads() got side %d, expected 0 or 1", p_side));
	const int64_t override_count = p_scenario->get_leaders(static_cast<int>(p_side)).size();
	ERR_FAIL_COND_V_MSG(!p_squads.is_empty() && p_squads.size() != override_count, false, vformat("Tactics: load_scenario_with_squads() got %d squads for %d leaders", p_squads.size(), override_count));
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
		const bool is_overridden = side == p_side && !p_squads.is_empty();
		for (int64_t index = 0; has_spawns && index < leaders.size(); index++) {
			const Ref<TacticsLeaderData> leader = leaders[index];
			const bool is_squad_array = !is_overridden || p_squads[index].get_type() == Variant::ARRAY;
			if (!is_squad_array || leader.is_null()) {
				clear_setup();
				ERR_FAIL_V_MSG(false, vformat("Tactics: %s side %d leader %d has no leader data or a squad that is not an Array", p_scenario->get_id(), side, index));
			}
			const Array squad = is_overridden ? Array(p_squads[index]) : Array(p_scenario->get_squad(side, index));
			if (add_leader_with_squad(side, leader, spawns[index], squad) < 0) {
				clear_setup();
				return false;
			}
		}
		if (!has_spawns) {
			clear_setup();
			ERR_FAIL_V_MSG(false, vformat("Tactics: %s side %d has more leaders than spawn cells", p_scenario->get_id(), side));
		}
	}
	if (!set_environment(p_scenario)) {
		clear_setup();
		return false;
	}
	if (p_scenario->get_objective().is_valid() && !set_objective(p_scenario->get_objective())) {
		clear_setup();
		return false;
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

bool TacticsBattle::undo_move(int64_t p_unit) {
	if (!check_not_emitting("undo_move")) {
		return false;
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.undo_move(clamp_to_int(p_unit), &error), false, "Tactics: undo_move() refused: " + to_godot_string(error));
	return true;
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
		case tactics::EventType::INCIDENT_FIRED:
			UtilityFunctions::print(prefix + vformat("incident_fired unit=%d incident=%s cause=e%d", p_event.unit, to_godot_string(p_event.content_id), p_event.cause));
			break;
		case tactics::EventType::UNIT_FLED:
			UtilityFunctions::print(prefix + vformat("unit_fled unit=%d cause=e%d", p_event.unit, p_event.cause));
			break;
		case tactics::EventType::UNIT_DEFECTED:
			UtilityFunctions::print(prefix + vformat("unit_defected unit=%d side=%d leader=%d cause=e%d", p_event.unit, p_event.side, p_event.target, p_event.cause));
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
	ClassDB::bind_method(D_METHOD("load_scenario_with_squads", "scenario", "side", "squads"), &TacticsBattle::load_scenario_with_squads);
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
	ClassDB::bind_method(D_METHOD("undo_move", "unit"), &TacticsBattle::undo_move);
	ClassDB::bind_method(D_METHOD("use_site", "unit", "site", "choice", "option"), &TacticsBattle::use_site, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("set_convoy_hold", "holds"), &TacticsBattle::set_convoy_hold);
	ClassDB::bind_method(D_METHOD("set_objective", "objective"), &TacticsBattle::set_objective);
	ClassDB::bind_method(D_METHOD("can_use_site", "unit", "site", "choice", "option"), &TacticsBattle::can_use_site, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_site_actions", "unit"), &TacticsBattle::get_site_actions);
	ClassDB::bind_method(D_METHOD("get_sites", "side"), &TacticsBattle::get_sites);
	ClassDB::bind_method(D_METHOD("get_objective_state"), &TacticsBattle::get_objective_state);
	ClassDB::bind_method(D_METHOD("get_convoy_path"), &TacticsBattle::get_convoy_path);
	ClassDB::bind_method(D_METHOD("get_supplies", "side"), &TacticsBattle::get_supplies);
	ClassDB::bind_method(D_METHOD("can_undo_move", "unit"), &TacticsBattle::can_undo_move);
	ClassDB::bind_method(D_METHOD("get_strike_cell", "unit", "target"), &TacticsBattle::get_strike_cell);
	ClassDB::bind_method(D_METHOD("get_strike_targets", "unit"), &TacticsBattle::get_strike_targets);
	ClassDB::bind_method(D_METHOD("forecast_move_attack", "unit", "cell", "target"), &TacticsBattle::forecast_move_attack);
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
	ClassDB::bind_method(D_METHOD("can_move", "unit"), &TacticsBattle::can_move);
	ClassDB::bind_method(D_METHOD("can_act", "unit"), &TacticsBattle::can_act);
	ClassDB::bind_method(D_METHOD("can_attack", "unit"), &TacticsBattle::can_attack);
	ClassDB::bind_method(D_METHOD("can_cast", "unit"), &TacticsBattle::can_cast);
	ClassDB::bind_method(D_METHOD("is_closed", "unit"), &TacticsBattle::is_closed);
	ClassDB::bind_method(D_METHOD("get_move_points_left", "unit"), &TacticsBattle::get_move_points_left);
	ClassDB::bind_method(D_METHOD("has_attacked", "unit"), &TacticsBattle::has_attacked);
	ClassDB::bind_method(D_METHOD("get_attack_targets", "unit"), &TacticsBattle::get_attack_targets);
	ClassDB::bind_method(D_METHOD("get_skill_cells", "unit"), &TacticsBattle::get_skill_cells);
	ClassDB::bind_method(D_METHOD("preview_skill", "unit", "cell"), &TacticsBattle::preview_skill);
	ClassDB::bind_method(D_METHOD("set_incident_rules", "rules", "seed"), &TacticsBattle::set_incident_rules);
	ClassDB::bind_method(D_METHOD("set_karma", "side", "bait", "rescue"), &TacticsBattle::set_karma);
	ClassDB::bind_method(D_METHOD("set_unit_record", "unit", "record_id", "good_marks", "bad_marks"), &TacticsBattle::set_unit_record);
	ClassDB::bind_method(D_METHOD("set_incident_seed", "unit", "incident"), &TacticsBattle::set_incident_seed);
	ClassDB::bind_method(D_METHOD("get_incident_seeds"), &TacticsBattle::get_incident_seeds);
	ClassDB::bind_method(D_METHOD("get_karma", "side"), &TacticsBattle::get_karma);
	ClassDB::bind_method(D_METHOD("get_battle_report"), &TacticsBattle::get_battle_report);
	ClassDB::bind_method(D_METHOD("set_bonds", "bonds", "rules"), &TacticsBattle::set_bonds);
	ClassDB::bind_method(D_METHOD("get_bonds"), &TacticsBattle::get_bonds);
	ClassDB::bind_method(D_METHOD("set_environment", "scenario"), &TacticsBattle::set_environment);
	ClassDB::bind_method(D_METHOD("has_fog_of_war"), &TacticsBattle::has_fog_of_war);
	ClassDB::bind_method(D_METHOD("get_fog_cells", "side"), &TacticsBattle::get_fog_cells);
	ClassDB::bind_method(D_METHOD("is_cell_visible", "side", "cell"), &TacticsBattle::is_cell_visible);
	ClassDB::bind_method(D_METHOD("is_unit_seen", "side", "unit"), &TacticsBattle::is_unit_seen);
	ClassDB::bind_method(D_METHOD("get_last_seen", "side"), &TacticsBattle::get_last_seen);
	ClassDB::bind_method(D_METHOD("get_lit_cells"), &TacticsBattle::get_lit_cells);
	ClassDB::bind_method(D_METHOD("is_intent_known", "side", "leader"), &TacticsBattle::is_intent_known);
	ClassDB::bind_method(D_METHOD("get_weather_id", "round"), &TacticsBattle::get_weather_id);
	ClassDB::bind_method(D_METHOD("get_daytime_id", "round"), &TacticsBattle::get_daytime_id);
	ClassDB::bind_method(D_METHOD("get_weather_change_round"), &TacticsBattle::get_weather_change_round);
	ClassDB::bind_method(D_METHOD("set_log_enabled", "enabled"), &TacticsBattle::set_log_enabled);
	ClassDB::bind_method(D_METHOD("is_log_enabled"), &TacticsBattle::is_log_enabled);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "log_enabled"), "set_log_enabled", "is_log_enabled");

	ADD_SIGNAL(MethodInfo("event_emitted", PropertyInfo(Variant::DICTIONARY, "event")));
	ADD_SIGNAL(MethodInfo("battle_ended", PropertyInfo(Variant::INT, "winner"), PropertyInfo(Variant::STRING_NAME, "reason")));
}
