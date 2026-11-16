#include "tactics_environment_data.h"

using namespace godot;

tactics::WeatherDef TacticsWeatherData::to_weather_def() const {
	tactics::WeatherDef def;
	def.id = to_std_string(id);
	def.vision_delta = vision_delta;
	def.ranged_range_delta = ranged_range_delta;
	def.burn_pct = burn_pct;
	for (int64_t index = 0; index < cost_terrain_ids.size(); index++) {
		def.cost_terrain_ids.push_back(to_std_string(StringName(cost_terrain_ids[index])));
	}
	def.cost_delta = cost_delta;
	def.hides_intents = hides_intents;
	def.wind = { wind.x, wind.y };
	def.wind_range_delta = wind_range_delta;
	def.waver_pct = waver_pct;
	return def;
}

void TacticsWeatherData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, id);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, icon);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, vision_delta);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, ranged_range_delta);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, burn_pct);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, cost_terrain_ids);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, cost_delta);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, hides_intents);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, wind);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, wind_range_delta);
	BATTLE_BIND_ACCESSORS(TacticsWeatherData, waver_pct);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "icon", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_icon", "get_icon");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "vision_delta", PROPERTY_HINT_RANGE, "-8,8,1"), "set_vision_delta", "get_vision_delta");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ranged_range_delta", PROPERTY_HINT_RANGE, "-4,4,1"), "set_ranged_range_delta", "get_ranged_range_delta");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "burn_pct", PROPERTY_HINT_RANGE, "0,200,1"), "set_burn_pct", "get_burn_pct");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "cost_terrain_ids", PROPERTY_HINT_ARRAY_TYPE, "StringName"), "set_cost_terrain_ids", "get_cost_terrain_ids");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cost_delta", PROPERTY_HINT_RANGE, "0,8,1"), "set_cost_delta", "get_cost_delta");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "hides_intents"), "set_hides_intents", "get_hides_intents");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "wind"), "set_wind", "get_wind");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "wind_range_delta", PROPERTY_HINT_RANGE, "0,4,1"), "set_wind_range_delta", "get_wind_range_delta");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "waver_pct", PROPERTY_HINT_RANGE, "-100,100,1"), "set_waver_pct", "get_waver_pct");
}

tactics::DaytimeDef TacticsDaytimeData::to_daytime_def() const {
	tactics::DaytimeDef def;
	def.id = to_std_string(id);
	def.vision_delta = vision_delta;
	def.uses_lights = uses_lights;
	def.hides_intents = hides_intents;
	def.waver_pct = waver_pct;
	return def;
}

void TacticsDaytimeData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, id);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, icon);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, vision_delta);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, uses_lights);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, hides_intents);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, waver_pct);
	BATTLE_BIND_ACCESSORS(TacticsDaytimeData, darkness_pct);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "icon", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_icon", "get_icon");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "vision_delta", PROPERTY_HINT_RANGE, "-8,8,1"), "set_vision_delta", "get_vision_delta");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "uses_lights"), "set_uses_lights", "get_uses_lights");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "hides_intents"), "set_hides_intents", "get_hides_intents");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "waver_pct", PROPERTY_HINT_RANGE, "-100,100,1"), "set_waver_pct", "get_waver_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "darkness_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_darkness_pct", "get_darkness_pct");
}
