#pragma once

#include "tactics_types.h"

#include "battle/bridge_strings.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// A weather (`weather.rain`, ...): one file per weather in
// Data/Tactics/Weathers/, named by scenarios. Every number is a change
// applied while it lasts (Docs/systems/tactics_vision.md, Weather).
class TacticsWeatherData : public Resource {
	GDCLASS(TacticsWeatherData, Resource)

	StringName id;
	String name_key;
	String description_key;
	Ref<Texture2D> icon;
	int vision_delta = 0;
	int ranged_range_delta = 0;
	int burn_pct = 100;
	TypedArray<StringName> cost_terrain_ids;
	int cost_delta = 0;
	bool hides_intents = false;
	Vector2i wind;
	int wind_range_delta = 0;
	int waver_pct = 0;

protected:
	static void _bind_methods();

public:
	tactics::WeatherDef to_weather_def() const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_icon(const Ref<Texture2D> &p_value) { icon = p_value; }
	Ref<Texture2D> get_icon() const { return icon; }
	void set_vision_delta(int64_t p_value) { vision_delta = clamp_to_int(p_value); }
	int get_vision_delta() const { return vision_delta; }
	void set_ranged_range_delta(int64_t p_value) { ranged_range_delta = clamp_to_int(p_value); }
	int get_ranged_range_delta() const { return ranged_range_delta; }
	void set_burn_pct(int64_t p_value) { burn_pct = clamp_to_int(p_value); }
	int get_burn_pct() const { return burn_pct; }
	void set_cost_terrain_ids(const TypedArray<StringName> &p_value) { cost_terrain_ids = p_value; }
	TypedArray<StringName> get_cost_terrain_ids() const { return cost_terrain_ids; }
	void set_cost_delta(int64_t p_value) { cost_delta = clamp_to_int(p_value); }
	int get_cost_delta() const { return cost_delta; }
	void set_hides_intents(bool p_value) { hides_intents = p_value; }
	bool get_hides_intents() const { return hides_intents; }
	void set_wind(const Vector2i &p_value) { wind = p_value; }
	Vector2i get_wind() const { return wind; }
	void set_wind_range_delta(int64_t p_value) { wind_range_delta = clamp_to_int(p_value); }
	int get_wind_range_delta() const { return wind_range_delta; }
	void set_waver_pct(int64_t p_value) { waver_pct = clamp_to_int(p_value); }
	int get_waver_pct() const { return waver_pct; }
};

// A time of day (`daytime.night`, ...): one file per time in
// Data/Tactics/Daytimes/; a scenario lists its cycle.
class TacticsDaytimeData : public Resource {
	GDCLASS(TacticsDaytimeData, Resource)

	StringName id;
	String name_key;
	String description_key;
	Ref<Texture2D> icon;
	int vision_delta = 0;
	bool uses_lights = false;
	bool hides_intents = false;
	int waver_pct = 0;
	// How dark the screen draws it, 0 (day) to 100.
	int darkness_pct = 0;

protected:
	static void _bind_methods();

public:
	tactics::DaytimeDef to_daytime_def() const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_icon(const Ref<Texture2D> &p_value) { icon = p_value; }
	Ref<Texture2D> get_icon() const { return icon; }
	void set_vision_delta(int64_t p_value) { vision_delta = clamp_to_int(p_value); }
	int get_vision_delta() const { return vision_delta; }
	void set_uses_lights(bool p_value) { uses_lights = p_value; }
	bool get_uses_lights() const { return uses_lights; }
	void set_hides_intents(bool p_value) { hides_intents = p_value; }
	bool get_hides_intents() const { return hides_intents; }
	void set_waver_pct(int64_t p_value) { waver_pct = clamp_to_int(p_value); }
	int get_waver_pct() const { return waver_pct; }
	void set_darkness_pct(int64_t p_value) { darkness_pct = clamp_to_int(p_value); }
	int get_darkness_pct() const { return darkness_pct; }
};

} // namespace godot
