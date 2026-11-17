#include "tactics_objective_data.h"

#include "tactics_objectives.h"

using namespace godot;

namespace {

std::vector<tactics::Cell> to_cells(const TypedArray<Vector2i> &p_cells) {
	std::vector<tactics::Cell> cells;
	for (int64_t index = 0; index < p_cells.size(); index++) {
		const Vector2i cell = p_cells[index];
		cells.push_back({ cell.x, cell.y });
	}
	return cells;
}

} // namespace

bool TacticsWaveData::to_wave_def(tactics::WaveDef *r_def, std::string *r_error) const {
	r_def->round = round;
	r_def->entry_cells = to_cells(entry_cells);
	for (int64_t index = 0; index < leaders.size(); index++) {
		const Ref<TacticsLeaderData> leader = leaders[index];
		tactics::UnitDef def;
		std::vector<tactics::UnitDef> squad;
		if (leader.is_null()) {
			*r_error = "a wave of round " + std::to_string(round) + " has an empty leader entry";
			return false;
		}
		if (!leader->to_unit_def(&def, r_error) || !tactics_squad_to_unit_defs(def.id, leader->get_squad(), &squad, r_error)) {
			return false;
		}
		r_def->leaders.push_back(def);
		r_def->squads.push_back(squad);
	}
	return true;
}

bool TacticsGoalData::to_goal_def(tactics::GoalDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(kind);
	r_def->handler = tactics::find_goal_handler(r_def->id);
	r_def->value = value;
	r_def->supplies = supplies;
	if (r_def->handler == nullptr) {
		*r_error = "unknown goal kind " + r_def->id;
		return false;
	}
	return true;
}

bool TacticsObjectiveData::to_objective_def(tactics::ObjectiveDef *r_def, std::string *r_error) const {
	*r_def = tactics::ObjectiveDef();
	r_def->id = to_std_string(id);
	r_def->handler = tactics::find_objective_handler(to_std_string(kind));
	if (r_def->handler == nullptr) {
		*r_error = r_def->id + " has unknown kind " + to_std_string(kind);
		return false;
	}
	r_def->site = site;
	r_def->rounds = rounds;
	r_def->count = count;
	r_def->required_leader = required_leader;
	r_def->exit_cells = to_cells(exit_cells);
	r_def->road_cells = to_cells(road_cells);
	r_def->has_convoy = convoy.is_valid();
	if (r_def->has_convoy) {
		if (!convoy->to_unit_def(&r_def->convoy, r_error)) {
			return false;
		}
	}
	r_def->general = general;
	r_def->flee_hp_pct = flee_hp_pct;
	r_def->general_hold_cells = general_hold_cells;
	for (int64_t index = 0; index < waves.size(); index++) {
		const Ref<TacticsWaveData> wave = waves[index];
		tactics::WaveDef def;
		if (wave.is_null() || !wave->to_wave_def(&def, r_error)) {
			*r_error = r_def->id + ": " + (wave.is_null() ? std::string("empty wave entry") : *r_error);
			return false;
		}
		r_def->waves.push_back(def);
	}
	for (int64_t index = 0; index < goals.size(); index++) {
		const Ref<TacticsGoalData> goal = goals[index];
		tactics::GoalDef def;
		if (goal.is_null() || !goal->to_goal_def(&def, r_error)) {
			*r_error = r_def->id + ": " + (goal.is_null() ? std::string("empty goal entry") : *r_error);
			return false;
		}
		r_def->goals.push_back(def);
	}
	return true;
}

void TacticsWaveData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsWaveData, round);
	BATTLE_BIND_ACCESSORS(TacticsWaveData, leaders);
	BATTLE_BIND_ACCESSORS(TacticsWaveData, entry_cells);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "round", PROPERTY_HINT_RANGE, "1,99,1"), "set_round", "get_round");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "leaders", PROPERTY_HINT_ARRAY_TYPE, "TacticsLeaderData"), "set_leaders", "get_leaders");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "entry_cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_entry_cells", "get_entry_cells");
}

void TacticsGoalData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsGoalData, kind);
	BATTLE_BIND_ACCESSORS(TacticsGoalData, value);
	BATTLE_BIND_ACCESSORS(TacticsGoalData, supplies);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "kind"), "set_kind", "get_kind");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "value", PROPERTY_HINT_RANGE, "0,99,1"), "set_value", "get_value");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "supplies", PROPERTY_HINT_RANGE, "0,100,1"), "set_supplies", "get_supplies");
}

void TacticsObjectiveData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, id);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, kind);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, site);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, rounds);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, count);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, required_leader);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, exit_cells);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, road_cells);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, convoy);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, general);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, flee_hp_pct);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, general_hold_cells);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, waves);
	BATTLE_BIND_ACCESSORS(TacticsObjectiveData, goals);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "kind"), "set_kind", "get_kind");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "site", PROPERTY_HINT_RANGE, "-1,31,1"), "set_site", "get_site");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "rounds", PROPERTY_HINT_RANGE, "0,99,1"), "set_rounds", "get_rounds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "count", PROPERTY_HINT_RANGE, "0,8,1"), "set_count", "get_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "required_leader", PROPERTY_HINT_RANGE, "-1,7,1"), "set_required_leader", "get_required_leader");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "exit_cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_exit_cells", "get_exit_cells");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "road_cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_road_cells", "get_road_cells");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "convoy", PROPERTY_HINT_RESOURCE_TYPE, "TacticsTroopData"), "set_convoy", "get_convoy");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "general", PROPERTY_HINT_RANGE, "-1,7,1"), "set_general", "get_general");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "flee_hp_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_flee_hp_pct", "get_flee_hp_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "general_hold_cells", PROPERTY_HINT_RANGE, "0,16,1"), "set_general_hold_cells", "get_general_hold_cells");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "waves", PROPERTY_HINT_ARRAY_TYPE, "TacticsWaveData"), "set_waves", "get_waves");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "goals", PROPERTY_HINT_ARRAY_TYPE, "TacticsGoalData"), "set_goals", "get_goals");
}
