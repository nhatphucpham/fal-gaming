#include "tactics_battle.h"

#include "tactics_combat.h"
#include "tactics_event_dictionary.h"
#include "tactics_orders.h"
#include "tactics_paths.h"
#include "tactics_skills.h"
#include "tactics_vision.h"

#include <godot_cpp/core/error_macros.hpp>

// TacticsBattle's read-only queries: unit and zone states, movement,
// forecast, squad preview, skill charge and declared AI intents.

using namespace godot;

namespace {

constexpr int HASH_HEX_DIGITS = 16;
const char *const INTENT_ACTION_NAMES[] = { "wait", "attack", "skill", "site" };

tactics::Cell to_cell(const Vector2i &p_cell) {
	return { p_cell.x, p_cell.y };
}

String format_hash(uint64_t p_hash) {
	const char *digits = "0123456789abcdef";
	String text;
	for (int shift = (HASH_HEX_DIGITS - 1) * 4; shift >= 0; shift -= 4) {
		text += String::chr(digits[(p_hash >> shift) & 0xFu]);
	}
	return text;
}

Array keyword_ids(const tactics::TacticsSim &p_sim, int p_unit) {
	Array ids;
	for (const tactics::KeywordDef *keyword : p_sim.collect_keywords(p_unit)) {
		ids.push_back(StringName(to_godot_string(keyword->id)));
	}
	return ids;
}

Array ids_to_array(const std::vector<std::string> &p_ids) {
	Array ids;
	for (const std::string &id : p_ids) {
		ids.push_back(StringName(to_godot_string(id)));
	}
	return ids;
}

Array units_to_array(const std::vector<int> &p_units) {
	Array units;
	for (int unit : p_units) {
		units.push_back(unit);
	}
	return units;
}

} // namespace

StringName TacticsBattle::get_end_reason() const {
	return StringName(to_godot_string(sim.get_end_reason()));
}

StringName TacticsBattle::get_terrain_id(const Vector2i &p_cell) const {
	ERR_FAIL_COND_V_MSG(!sim.is_on_map(to_cell(p_cell)), StringName(), vformat("Tactics: get_terrain_id() got %s, off the map", p_cell));
	return StringName(to_godot_string(sim.get_terrain(to_cell(p_cell)).id));
}

String TacticsBattle::get_state_hash() const {
	return format_hash(sim.get_state_hash());
}

Dictionary TacticsBattle::get_unit_state(int64_t p_unit) const {
	Dictionary state;
	if (!check_unit(p_unit, "get_unit_state")) {
		return state;
	}
	const int index = static_cast<int>(p_unit);
	const tactics::UnitState &unit = sim.get_units()[index];
	const bool is_leader = sim.is_leader(index);
	const tactics::Stats stats = sim.get_stats(index);
	state["index"] = unit.index;
	state["side"] = unit.side;
	state["role"] = StringName(is_leader ? "leader" : "soldier");
	state["id"] = StringName(to_godot_string(unit.def.id));
	state["base_unit_id"] = StringName(to_godot_string(unit.def.base_unit_id));
	state["leader"] = unit.leader;
	Array soldiers;
	for (int soldier : unit.soldiers) {
		soldiers.push_back(soldier);
	}
	state["soldiers"] = soldiers;
	state["alive"] = unit.is_alive;
	state["hp"] = unit.hp;
	state["max_hp"] = unit.def.max_hp;
	state["attack"] = stats.attack;
	state["armor"] = stats.armor;
	state["magic_resist"] = stats.magic_resist;
	state["min_range"] = stats.min_range_cells;
	state["max_range"] = stats.max_range_cells;
	state["move_points"] = stats.move_points;
	state["is_ranged"] = unit.def.is_ranged;
	state["cell"] = to_vector2i(unit.cell);
	state["keywords"] = keyword_ids(sim, index);
	state["has_moved"] = unit.has_moved;
	state["has_attacked"] = unit.has_attacked;
	state["has_cast"] = unit.has_cast;
	state["has_waited"] = unit.has_waited;
	state["has_squad_struck"] = unit.has_squad_struck;
	state["move_points_left"] = sim.get_move_budget(index);
	state["vision"] = unit.def.vision_cells;
	state["is_scout"] = tactics::is_scout(sim, index);
	state["is_out_of_leader_sight"] = sim.is_out_of_leader_sight(index);
	// Incidents: only what the player may see (a wavering soldier shows its
	// incident; a dormant seed stays hidden).
	const bool is_wavering = unit.stage == tactics::IncidentStage::WAVERING;
	state["start_side"] = unit.start_side;
	state["record_id"] = unit.record_id;
	state["has_fled"] = unit.has_fled;
	state["wavering"] = is_wavering ? StringName(to_godot_string(sim.get_incident_rules().incidents[unit.seed].id)) : StringName();
	state["is_wavering_good"] = is_wavering && sim.get_incident_rules().incidents[unit.seed].handler->is_good;
	// It wavers only because its leader does not see it (fog of war).
	state["is_wavering_unseen"] = is_wavering && unit.is_unseen_waver;
	state["marks"] = static_cast<int>(unit.marks.size());
	state["is_guarding"] = unit.guard_leader != tactics::NO_UNIT && sim.get_turn() < unit.guard_end_turn;
	state["holds_ground"] = sim.is_holding_ground(index);
	state["acts_free"] = sim.is_acting_free(index);
	if (is_leader) {
		state["order"] = StringName(tactics::get_order_handler(unit.order).id);
		state["heading"] = to_vector2i(unit.heading);
		state["heading_streak"] = unit.heading_streak;
		state["capacity"] = sim.get_squad_capacity(index);
	}
	return state;
}

Array TacticsBattle::get_units() const {
	Array states;
	for (int index = 0; index < get_unit_count(); index++) {
		states.push_back(get_unit_state(index));
	}
	return states;
}

Array TacticsBattle::get_zones() const {
	Array zones;
	for (const tactics::ZoneState &zone : sim.get_zones()) {
		Dictionary entry;
		entry["zone"] = StringName(to_godot_string(zone.def.id));
		entry["side"] = zone.side;
		entry["source"] = zone.source;
		entry["cells"] = tactics_cells_to_array(zone.cells);
		entry["end_round"] = zone.end_round;
		zones.push_back(entry);
	}
	return zones;
}

Array TacticsBattle::get_reachable_cells(int64_t p_unit) const {
	if (!check_unit(p_unit, "get_reachable_cells")) {
		return Array();
	}
	return tactics_cells_to_array(tactics::get_reachable_cells(sim, static_cast<int>(p_unit)));
}

Array TacticsBattle::get_path_to(int64_t p_unit, const Vector2i &p_cell) const {
	if (!check_unit(p_unit, "get_path_to")) {
		return Array();
	}
	const int unit = static_cast<int>(p_unit);
	// Only cells move_leader() could end on (an ally's cell is passed, not
	// stopped on), so the path shown is one the move would take; an enemy
	// the side does not see is not known to be there (the walk may stop at
	// it, an ambush).
	if (!tactics::can_plan_stop_at(sim, unit, to_cell(p_cell))) {
		return Array();
	}
	const tactics::PathField field = tactics::find_move_paths(sim, unit);
	return tactics_cells_to_array(tactics::get_path(sim, field, to_cell(p_cell)));
}

Array TacticsBattle::get_formation_slots(int64_t p_leader) const {
	if (!check_unit(p_leader, "get_formation_slots")) {
		return Array();
	}
	ERR_FAIL_COND_V_MSG(!sim.is_leader(static_cast<int>(p_leader)), Array(), vformat("Tactics: get_formation_slots() got soldier %d", p_leader));
	return tactics_cells_to_array(tactics::get_formation_slots(sim, static_cast<int>(p_leader)));
}

namespace {

// The forecast dictionary of p_attacker engaging p_defender on p_sim.
Dictionary make_forecast(const tactics::TacticsSim &p_sim, int p_attacker, int p_defender) {
	Dictionary forecast;
	const tactics::EngagementResult result = p_sim.forecast_engagement(p_attacker, p_defender);
	forecast["is_valid"] = result.is_valid;
	forecast["attacker"] = p_attacker;
	forecast["defender"] = p_defender;
	if (!result.is_valid) {
		return forecast;
	}
	forecast["kind"] = StringName(result.kind == tactics::AttackKind::RANGED ? "ranged" : "melee");
	forecast["is_first_strike"] = result.is_first_strike;
	forecast["can_counter"] = result.can_counter;
	forecast["attacker_damage_per_hit"] = result.attacker_damage_per_hit;
	forecast["defender_damage_per_hit"] = result.defender_damage_per_hit;
	forecast["attacker_hits"] = result.attacker_hits;
	forecast["defender_hits"] = result.defender_hits;
	forecast["attacker_hp_after"] = result.attacker_hp_after;
	forecast["defender_hp_after"] = result.defender_hp_after;
	forecast["is_attacker_dead"] = result.is_attacker_dead;
	forecast["is_defender_dead"] = result.is_defender_dead;
	forecast["attacker_modifiers"] = ids_to_array(tactics::collect_hit_sources(p_sim, p_attacker, p_defender, false));
	forecast["defender_modifiers"] = result.can_counter ? ids_to_array(tactics::collect_hit_sources(p_sim, p_defender, p_attacker, true)) : Array();
	return forecast;
}

} // namespace

Dictionary TacticsBattle::forecast_engagement(int64_t p_attacker, int64_t p_defender) const {
	if (!check_unit(p_attacker, "forecast_engagement") || !check_unit(p_defender, "forecast_engagement")) {
		return Dictionary();
	}
	return make_forecast(sim, static_cast<int>(p_attacker), static_cast<int>(p_defender));
}

bool TacticsBattle::can_undo_move(int64_t p_unit) const {
	return check_unit(p_unit, "can_undo_move") && sim.can_undo_move(static_cast<int>(p_unit));
}

Vector2i TacticsBattle::get_strike_cell(int64_t p_unit, int64_t p_target) const {
	if (!check_unit(p_unit, "get_strike_cell") || !check_unit(p_target, "get_strike_cell")) {
		return Vector2i(-1, -1);
	}
	return to_vector2i(sim.get_strike_cell(static_cast<int>(p_unit), static_cast<int>(p_target)));
}

Array TacticsBattle::get_strike_targets(int64_t p_unit) const {
	if (!check_unit(p_unit, "get_strike_targets")) {
		return Array();
	}
	return units_to_array(sim.get_strike_targets(static_cast<int>(p_unit)));
}

// Like forecast_engagement(), a move that cannot happen is not an error:
// the screen asks as the player touches cells.
Dictionary TacticsBattle::forecast_move_attack(int64_t p_unit, const Vector2i &p_cell, int64_t p_target) const {
	if (!check_unit(p_unit, "forecast_move_attack") || !check_unit(p_target, "forecast_move_attack")) {
		return Dictionary();
	}
	const int unit = static_cast<int>(p_unit);
	const int target = static_cast<int>(p_target);
	tactics::TacticsSim copy;
	std::string error;
	if (!sim.can_leader_attack(unit) || !sim.simulate_move(unit, to_cell(p_cell), &copy, &error)) {
		Dictionary refused;
		refused["is_valid"] = false;
		refused["attacker"] = unit;
		refused["defender"] = target;
		refused["target_gone"] = false;
		return refused;
	}
	Dictionary forecast = make_forecast(copy, unit, target);
	forecast["target_gone"] = !copy.get_units()[target].is_alive;
	Array squad;
	for (int soldier : copy.get_units()[unit].soldiers) {
		if (copy.get_units()[soldier].is_alive) {
			Dictionary placement;
			placement["unit"] = soldier;
			placement["cell"] = to_vector2i(copy.get_units()[soldier].cell);
			squad.push_back(placement);
		}
	}
	forecast["squad"] = squad;
	forecast["cell"] = p_cell;
	return forecast;
}

Array TacticsBattle::preview_squad(int64_t p_leader, const Vector2i &p_cell) const {
	Array placements;
	if (!check_unit(p_leader, "preview_squad")) {
		return placements;
	}
	std::string error;
	const std::vector<std::pair<int, tactics::Cell>> result = sim.preview_squad(static_cast<int>(p_leader), to_cell(p_cell), &error);
	ERR_FAIL_COND_V_MSG(!error.empty(), placements, "Tactics: preview_squad() refused: " + to_godot_string(error));
	for (const std::pair<int, tactics::Cell> &entry : result) {
		Dictionary placement;
		placement["unit"] = entry.first;
		placement["cell"] = to_vector2i(entry.second);
		placements.push_back(placement);
	}
	return placements;
}

Dictionary TacticsBattle::get_skill_charge(int64_t p_leader) const {
	Dictionary charge;
	if (!check_unit(p_leader, "get_skill_charge")) {
		return charge;
	}
	const tactics::UnitState &leader = sim.get_units()[p_leader];
	ERR_FAIL_COND_V_MSG(!leader.def.has_skill, charge, vformat("Tactics: unit %d has no skill", p_leader));
	charge["skill"] = StringName(to_godot_string(leader.def.skill.id));
	charge["charge"] = StringName(to_godot_string(leader.def.skill.charge_id));
	charge["value"] = leader.skill_charge;
	charge["threshold"] = leader.def.skill.charge_threshold;
	charge["is_ready"] = tactics::is_skill_ready(leader);
	charge["area_bonus"] = leader.skill_area_bonus;
	return charge;
}

Array TacticsBattle::get_enemy_intents() const {
	Array intents;
	for (const tactics::Intent &intent : sim.get_intents()) {
		// Under fog an intent shows only while the other side reads it
		// (Docs/systems/tactics_vision.md, Intents).
		if (!sim.is_intent_known(1 - sim.get_units()[intent.leader].side, intent.leader)) {
			continue;
		}
		Dictionary entry;
		entry["unit"] = intent.leader;
		entry["to"] = to_vector2i(intent.destination);
		entry["action"] = StringName(INTENT_ACTION_NAMES[static_cast<int>(intent.action)]);
		entry["target"] = intent.target;
		entry["target_cell"] = to_vector2i(intent.target_cell);
		intents.push_back(entry);
	}
	return intents;
}

bool TacticsBattle::can_move(int64_t p_unit) const {
	return check_unit(p_unit, "can_move") && sim.can_leader_move(static_cast<int>(p_unit));
}

bool TacticsBattle::can_act(int64_t p_unit) const {
	return check_unit(p_unit, "can_act") && sim.can_leader_act(static_cast<int>(p_unit));
}

bool TacticsBattle::can_attack(int64_t p_unit) const {
	return check_unit(p_unit, "can_attack") && sim.can_leader_attack(static_cast<int>(p_unit));
}

bool TacticsBattle::can_cast(int64_t p_unit) const {
	return check_unit(p_unit, "can_cast") && sim.can_leader_cast(static_cast<int>(p_unit));
}

bool TacticsBattle::is_closed(int64_t p_unit) const {
	return !check_unit(p_unit, "is_closed") || sim.is_leader_closed(static_cast<int>(p_unit));
}

int TacticsBattle::get_move_points_left(int64_t p_unit) const {
	return check_unit(p_unit, "get_move_points_left") ? sim.get_move_budget(static_cast<int>(p_unit)) : 0;
}

bool TacticsBattle::has_attacked(int64_t p_unit) const {
	return check_unit(p_unit, "has_attacked") && sim.get_units()[p_unit].has_attacked;
}

Array TacticsBattle::get_attack_targets(int64_t p_unit) const {
	if (!check_unit(p_unit, "get_attack_targets")) {
		return Array();
	}
	return units_to_array(sim.get_attack_targets(static_cast<int>(p_unit)));
}

Array TacticsBattle::get_skill_cells(int64_t p_unit) const {
	if (!check_unit(p_unit, "get_skill_cells")) {
		return Array();
	}
	return tactics_cells_to_array(sim.get_skill_cells(static_cast<int>(p_unit)));
}

// Like forecast_engagement(), an impossible cast is not an error here:
// the screen asks about cells as the player touches them.
Dictionary TacticsBattle::preview_skill(int64_t p_unit, const Vector2i &p_cell) const {
	Dictionary preview;
	if (!check_unit(p_unit, "preview_skill")) {
		return preview;
	}
	tactics::SkillPreview result;
	std::string error;
	preview["is_valid"] = sim.preview_skill(static_cast<int>(p_unit), to_cell(p_cell), &result, &error);
	preview["unit"] = static_cast<int>(p_unit);
	preview["cell"] = p_cell;
	if (!bool(preview["is_valid"])) {
		return preview;
	}
	preview["cells"] = tactics_cells_to_array(result.cells);
	preview["targets"] = units_to_array(result.targets);
	Array results;
	for (const tactics::SkillTargetResult &entry : result.results) {
		Dictionary item;
		item["unit"] = entry.unit;
		item["amount"] = entry.amount;
		item["hp_after"] = entry.hp_after;
		item["is_dead"] = entry.is_dead;
		results.push_back(item);
	}
	preview["results"] = results;
	preview["buffed"] = units_to_array(result.buffed);
	preview["zone_cells"] = tactics_cells_to_array(result.zone_cells);
	return preview;
}
