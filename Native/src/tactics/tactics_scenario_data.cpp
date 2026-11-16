#include "tactics_scenario_data.h"

using namespace godot;

tactics::EnvironmentDef TacticsScenarioData::to_environment_def() const {
	tactics::EnvironmentDef def;
	def.fog_of_war = fog_of_war;
	if (weather.is_valid()) {
		def.weather = weather->to_weather_def();
	}
	def.has_weather_change = weather_change_round > 0 && weather_after.is_valid();
	def.weather_change_round = weather_change_round;
	if (weather_after.is_valid()) {
		def.weather_after = weather_after->to_weather_def();
	}
	for (int64_t index = 0; index < daytimes.size(); index++) {
		const Ref<TacticsDaytimeData> daytime = daytimes[index];
		if (daytime.is_valid()) {
			def.daytimes.push_back(daytime->to_daytime_def());
		}
	}
	def.daytime_step_rounds = daytime_step_rounds;
	def.daytime_start_index = daytime_start_index;
	return def;
}

TypedArray<TacticsTroopData> TacticsScenarioData::get_squad(int64_t p_side, int64_t p_index) const {
	const TypedArray<TacticsLeaderData> leaders = get_leaders(p_side);
	ERR_FAIL_INDEX_V_MSG(p_index, leaders.size(), TypedArray<TacticsTroopData>(), vformat("Tactics: get_squad() got leader %d of %d", p_index, leaders.size()));
	if (p_side != tactics::SIDE_A || supplied_sizes.is_empty()) {
		const Ref<TacticsLeaderData> leader = leaders[p_index];
		return leader.is_valid() ? leader->get_squad() : TypedArray<TacticsTroopData>();
	}
	int64_t first = 0;
	for (int64_t index = 0; index < p_index && index < supplied_sizes.size(); index++) {
		first += supplied_sizes[index];
	}
	TypedArray<TacticsTroopData> squad;
	const int64_t size = p_index < supplied_sizes.size() ? supplied_sizes[p_index] : 0;
	for (int64_t index = first; index < first + size && index < supplied_troops.size(); index++) {
		squad.push_back(supplied_troops[index]);
	}
	return squad;
}

void TacticsScenarioData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, id);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, rules);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, map);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, leaders_a);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, leaders_b);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, fog_of_war);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, weather);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, weather_change_round);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, weather_after);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, daytimes);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, daytime_step_rounds);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, daytime_start_index);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, supplied_sizes);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, supplied_troops);
	ClassDB::bind_method(D_METHOD("get_leaders", "side"), &TacticsScenarioData::get_leaders);
	ClassDB::bind_method(D_METHOD("get_squad", "side", "index"), &TacticsScenarioData::get_squad);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "rules", PROPERTY_HINT_RESOURCE_TYPE, "TacticsRulesData"), "set_rules", "get_rules");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "map", PROPERTY_HINT_RESOURCE_TYPE, "TacticsMapData"), "set_map", "get_map");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "leaders_a", PROPERTY_HINT_ARRAY_TYPE, "TacticsLeaderData"), "set_leaders_a", "get_leaders_a");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "leaders_b", PROPERTY_HINT_ARRAY_TYPE, "TacticsLeaderData"), "set_leaders_b", "get_leaders_b");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "fog_of_war"), "set_fog_of_war", "get_fog_of_war");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "weather", PROPERTY_HINT_RESOURCE_TYPE, "TacticsWeatherData"), "set_weather", "get_weather");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "weather_change_round", PROPERTY_HINT_RANGE, "0,99,1"), "set_weather_change_round", "get_weather_change_round");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "weather_after", PROPERTY_HINT_RESOURCE_TYPE, "TacticsWeatherData"), "set_weather_after", "get_weather_after");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "daytimes", PROPERTY_HINT_ARRAY_TYPE, "TacticsDaytimeData"), "set_daytimes", "get_daytimes");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "daytime_step_rounds", PROPERTY_HINT_RANGE, "1,99,1"), "set_daytime_step_rounds", "get_daytime_step_rounds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "daytime_start_index", PROPERTY_HINT_RANGE, "0,16,1"), "set_daytime_start_index", "get_daytime_start_index");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "supplied_sizes"), "set_supplied_sizes", "get_supplied_sizes");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "supplied_troops", PROPERTY_HINT_ARRAY_TYPE, "TacticsTroopData"), "set_supplied_troops", "get_supplied_troops");
}
