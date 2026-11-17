#include "tactics_battle.h"

#include "tactics_event_dictionary.h"
#include "tactics_objectives.h"
#include "tactics_sites.h"

#include <godot_cpp/core/error_macros.hpp>

#include <algorithm>

// TacticsBattle's sites and objectives (Docs/systems/tactics_sites.md,
// Docs/systems/tactics_objectives.md): the objective setup, using a site,
// the convoy's order and what the screen reads of them. What a side is
// told of a site follows what it has seen (fog of war).

using namespace godot;

namespace {

const char *const SITE_STATUS_NAMES[] = { "ready", "used", "burned" };

StringName to_id(const std::string &p_text) {
	return StringName(to_godot_string(p_text));
}

bool is_valid_side(int64_t p_side) {
	return p_side == tactics::SIDE_A || p_side == tactics::SIDE_B;
}

Array cells_to_array(const std::vector<tactics::Cell> &p_cells) {
	Array cells;
	for (const tactics::Cell &cell : p_cells) {
		cells.push_back(to_vector2i(cell));
	}
	return cells;
}

} // namespace

bool TacticsBattle::set_objective(const Ref<TacticsObjectiveData> &p_objective) {
	if (!check_not_emitting("set_objective")) {
		return false;
	}
	ERR_FAIL_COND_V_MSG(p_objective.is_null(), false, "Tactics: set_objective() got a null objective");
	tactics::ObjectiveDef def;
	std::string error;
	ERR_FAIL_COND_V_MSG(!p_objective->to_objective_def(&def, &error), false, "Tactics: " + to_godot_string(error));
	ERR_FAIL_COND_V_MSG(!sim.set_objective(def, &error), false, "Tactics: set_objective() refused: " + to_godot_string(error));
	return true;
}

Array TacticsBattle::use_site(int64_t p_unit, int64_t p_site, const StringName &p_choice, int64_t p_option) {
	if (!check_not_emitting("use_site")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.use_site(clamp_to_int(p_unit), clamp_to_int(p_site), to_std_string(p_choice), clamp_to_int(p_option), &error), Array(), "Tactics: use_site() refused: " + to_godot_string(error));
	return flush_events();
}

bool TacticsBattle::can_use_site(int64_t p_unit, int64_t p_site, const StringName &p_choice, int64_t p_option) const {
	std::string error;
	return sim.can_use_site(clamp_to_int(p_unit), clamp_to_int(p_site), to_std_string(p_choice), clamp_to_int(p_option), &error);
}

Array TacticsBattle::set_convoy_hold(bool p_holds) {
	if (!check_not_emitting("set_convoy_hold")) {
		return Array();
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.set_convoy_hold(p_holds, &error), Array(), "Tactics: set_convoy_hold() refused: " + to_godot_string(error));
	return flush_events();
}

// Each site within the leader's reach, with every choice it offers and
// whether the leader may take it now (`reason` says why not).
Array TacticsBattle::get_site_actions(int64_t p_unit) const {
	Array actions;
	if (!check_unit(p_unit, "get_site_actions")) {
		return actions;
	}
	const int unit = static_cast<int>(p_unit);
	const tactics::UnitState &leader = sim.get_units()[unit];
	const std::vector<tactics::SitePlacement> &sites = sim.get_map().sites;
	for (size_t index = 0; index < sites.size(); index++) {
		const tactics::SitePlacement &site = sites[index];
		if (!leader.is_alive || !sim.is_leader(unit) || tactics::get_manhattan(leader.cell, site.cell) > site.def.reach_cells || site.def.handler->choices.empty()) {
			continue;
		}
		Dictionary entry;
		entry["site"] = static_cast<int>(index);
		entry["site_id"] = to_id(site.def.id);
		entry["cell"] = to_vector2i(site.cell);
		Array choices;
		for (const std::string &choice : site.def.handler->choices) {
			Dictionary item;
			item["choice"] = to_id(choice);
			const int options = tactics::get_site_option_count(site.def, choice);
			item["options"] = options;
			bool can_take = false;
			std::string reason;
			for (int option = 0; option < options && !can_take; option++) {
				can_take = sim.can_use_site(unit, static_cast<int>(index), choice, option, &reason);
			}
			item["can"] = can_take;
			item["reason"] = can_take ? String() : to_godot_string(reason);
			choices.push_back(item);
		}
		entry["choices"] = choices;
		actions.push_back(entry);
	}
	return actions;
}

// Every site as p_side knows it; an unknown one (never seen under fog)
// tells only where it stands and its kind, no state.
Array TacticsBattle::get_sites(int64_t p_side) const {
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side), Array(), vformat("Tactics: get_sites() got side %d, expected 0 or 1", p_side));
	Array result;
	const std::vector<tactics::SitePlacement> &sites = sim.get_map().sites;
	for (size_t index = 0; index < sites.size(); index++) {
		const tactics::SitePlacement &site = sites[index];
		const tactics::SiteState state = sim.is_started() ? sim.get_known_site(static_cast<int>(p_side), static_cast<int>(index)) : sim.get_site_states()[index];
		Dictionary entry;
		entry["site"] = static_cast<int>(index);
		entry["id"] = to_id(site.def.id);
		entry["kind"] = to_id(site.def.handler->id);
		entry["cell"] = to_vector2i(site.cell);
		entry["is_known"] = state.is_known || !sim.is_started();
		entry["status"] = StringName(SITE_STATUS_NAMES[static_cast<int>(state.status)]);
		entry["owner"] = state.owner;
		entry["uses"] = state.uses;
		entry["capture_side"] = state.capture_side;
		entry["capture_progress"] = state.capture_progress;
		entry["capture_phases"] = site.def.capture_phases;
		entry["burned_by"] = state.burned_by;
		entry["has_reinforced"] = state.has_reinforced;
		entry["reinforce_round"] = site.def.has_reinforcement ? site.def.reinforce_round : 0;
		entry["vision_cells"] = site.def.vision_cells;
		entry["armor_bonus"] = site.def.armor_bonus;
		entry["reach_cells"] = site.def.reach_cells;
		entry["is_visible"] = sim.is_cell_visible(static_cast<int>(p_side), site.cell);
		result.push_back(entry);
	}
	return result;
}

// The objective as the screen shows it: kind, its numbers and progress.
// Waves are told by round (the banner warns a round ahead); the general
// and the convoy by unit index.
Dictionary TacticsBattle::get_objective_state() const {
	Dictionary state;
	const tactics::ObjectiveDef &objective = sim.get_objective();
	if (objective.handler == nullptr) {
		const tactics::MapDef &map = sim.get_map();
		state["kind"] = StringName(map.has_objective ? "objective_kind.cell" : "");
		state["cell"] = to_vector2i(map.objective);
		state["side"] = map.objective_side;
		return state;
	}
	state["id"] = to_id(objective.id);
	state["kind"] = to_id(objective.handler->id);
	state["site"] = objective.site;
	// The cell the screen points at: the stronghold, else the general's
	// post (known from the map, wherever he went since), else none.
	tactics::Cell focus = objective.site != tactics::NO_INDEX ? sim.get_map().sites[objective.site].cell : sim.get_general_post();
	state["cell"] = focus != tactics::NO_CELL ? to_vector2i(focus) : Vector2i(-1, -1);
	state["rounds"] = objective.rounds;
	state["count"] = objective.count;
	state["required_leader"] = objective.required_leader;
	state["exit_cells"] = cells_to_array(objective.exit_cells);
	state["road_cells"] = cells_to_array(objective.road_cells);
	state["convoy"] = sim.get_convoy();
	state["convoy_holds"] = sim.does_convoy_hold();
	state["general"] = sim.get_general();
	state["general_fleeing"] = sim.is_general_fleeing();
	state["flee_hp_pct"] = objective.flee_hp_pct;
	state["escaped"] = sim.count_escaped_leaders(tactics::SIDE_A);
	state["waves_sent"] = sim.get_waves_sent();
	Array waves;
	for (const tactics::WaveDef &wave : objective.waves) {
		Dictionary entry;
		entry["round"] = wave.round;
		entry["leaders"] = static_cast<int>(wave.leaders.size());
		entry["entry_cells"] = cells_to_array(wave.entry_cells);
		waves.push_back(entry);
	}
	state["waves"] = waves;
	Array goals;
	const std::vector<int> &met = sim.get_met_goals();
	for (size_t index = 0; index < objective.goals.size(); index++) {
		const tactics::GoalDef &goal = objective.goals[index];
		Dictionary entry;
		entry["kind"] = to_id(goal.id);
		entry["value"] = goal.value;
		entry["supplies"] = goal.supplies;
		entry["is_met"] = std::find(met.begin(), met.end(), static_cast<int>(index)) != met.end();
		goals.push_back(entry);
	}
	state["goals"] = goals;
	return state;
}

Array TacticsBattle::get_convoy_path() const {
	return cells_to_array(sim.get_convoy_path());
}

int TacticsBattle::get_supplies(int64_t p_side) const {
	ERR_FAIL_COND_V_MSG(!is_valid_side(p_side), 0, vformat("Tactics: get_supplies() got side %d, expected 0 or 1", p_side));
	return sim.get_supplies(static_cast<int>(p_side));
}
