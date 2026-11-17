#pragma once

#include "tactics_environment_data.h"
#include "tactics_map_data.h"
#include "tactics_objective_data.h"
#include "tactics_rules_data.h"
#include "tactics_unit_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// A ready-to-play tactics battle: rules, map and the leaders of each side,
// placed on the map's spawn cells in order, each with its own squad. One
// file per scenario in Data/Tactics/Scenarios/, id `scenario.<name>`.
// TacticsBattle.load_scenario() reads it.
class TacticsScenarioData : public Resource {
	GDCLASS(TacticsScenarioData, Resource)

	StringName id;
	String name_key;
	Ref<TacticsRulesData> rules;
	Ref<TacticsMapData> map;
	TypedArray<TacticsLeaderData> leaders_a;
	TypedArray<TacticsLeaderData> leaders_b;
	// What the battle sees by (Docs/systems/tactics_vision.md). No weather
	// is clear; no daytimes is day all battle; weather_change_round 0 keeps
	// the weather.
	bool fog_of_war = false;
	Ref<TacticsWeatherData> weather;
	int weather_change_round = 0;
	Ref<TacticsWeatherData> weather_after;
	TypedArray<TacticsDaytimeData> daytimes;
	int daytime_step_rounds = 1;
	int daytime_start_index = 0;
	// The soldiers the scenario supplies to side A's leaders, in their
	// order: supplied_sizes[i] troops of supplied_troops for leader i. Empty
	// keeps each leader's own squad.
	PackedInt32Array supplied_sizes;
	TypedArray<TacticsTroopData> supplied_troops;
	// What the battle is won by (Docs/systems/tactics_objectives.md); null:
	// the map's objective cell, if any, taken by a move.
	Ref<TacticsObjectiveData> objective;
	// The soldier one supply buys at the muster (Docs/systems/tactics_roster.md).
	Ref<TacticsTroopData> reserve_troop;

protected:
	static void _bind_methods();

public:
	tactics::EnvironmentDef to_environment_def() const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_rules(const Ref<TacticsRulesData> &p_value) { rules = p_value; }
	Ref<TacticsRulesData> get_rules() const { return rules; }
	void set_map(const Ref<TacticsMapData> &p_value) { map = p_value; }
	Ref<TacticsMapData> get_map() const { return map; }
	void set_leaders_a(const TypedArray<TacticsLeaderData> &p_value) { leaders_a = p_value; }
	TypedArray<TacticsLeaderData> get_leaders_a() const { return leaders_a; }
	void set_leaders_b(const TypedArray<TacticsLeaderData> &p_value) { leaders_b = p_value; }
	TypedArray<TacticsLeaderData> get_leaders_b() const { return leaders_b; }
	void set_fog_of_war(bool p_value) { fog_of_war = p_value; }
	bool get_fog_of_war() const { return fog_of_war; }
	void set_weather(const Ref<TacticsWeatherData> &p_value) { weather = p_value; }
	Ref<TacticsWeatherData> get_weather() const { return weather; }
	void set_weather_change_round(int64_t p_value) { weather_change_round = clamp_to_int(p_value); }
	int get_weather_change_round() const { return weather_change_round; }
	void set_weather_after(const Ref<TacticsWeatherData> &p_value) { weather_after = p_value; }
	Ref<TacticsWeatherData> get_weather_after() const { return weather_after; }
	void set_daytimes(const TypedArray<TacticsDaytimeData> &p_value) { daytimes = p_value; }
	TypedArray<TacticsDaytimeData> get_daytimes() const { return daytimes; }
	void set_daytime_step_rounds(int64_t p_value) { daytime_step_rounds = clamp_to_int(p_value); }
	int get_daytime_step_rounds() const { return daytime_step_rounds; }
	void set_daytime_start_index(int64_t p_value) { daytime_start_index = clamp_to_int(p_value); }
	int get_daytime_start_index() const { return daytime_start_index; }
	void set_supplied_sizes(const PackedInt32Array &p_value) { supplied_sizes = p_value; }
	PackedInt32Array get_supplied_sizes() const { return supplied_sizes; }
	void set_supplied_troops(const TypedArray<TacticsTroopData> &p_value) { supplied_troops = p_value; }
	TypedArray<TacticsTroopData> get_supplied_troops() const { return supplied_troops; }
	void set_objective(const Ref<TacticsObjectiveData> &p_value) { objective = p_value; }
	Ref<TacticsObjectiveData> get_objective() const { return objective; }
	void set_reserve_troop(const Ref<TacticsTroopData> &p_value) { reserve_troop = p_value; }
	Ref<TacticsTroopData> get_reserve_troop() const { return reserve_troop; }
	// The squad the leader at p_index of a side starts with: the supplied
	// soldiers on side A when the scenario supplies them, else its own.
	TypedArray<TacticsTroopData> get_squad(int64_t p_side, int64_t p_index) const;
	// The leaders of a side (0 or 1); empty with an error for another side.
	TypedArray<TacticsLeaderData> get_leaders(int64_t p_side) const {
		ERR_FAIL_COND_V_MSG(p_side != tactics::SIDE_A && p_side != tactics::SIDE_B, TypedArray<TacticsLeaderData>(), vformat("Tactics: get_leaders() got side %d, expected 0 or 1", p_side));
		return p_side == tactics::SIDE_A ? leaders_a : leaders_b;
	}
};

} // namespace godot
