#pragma once

#include "tactics_keyword_data.h"
#include "tactics_zone_data.h"

#include <godot_cpp/classes/resource.hpp>

#include <string>

namespace godot {

// A leader passive: a handler id (tactics_passives.cpp) and the numbers the
// handler reads; fields a handler does not use stay at their defaults. One
// file per passive in Data/Tactics/Passives/. Schema in
// Docs/systems/tactics.md.
class TacticsPassiveData : public Resource {
	GDCLASS(TacticsPassiveData, Resource)

	StringName id;
	String name_key;
	String description_key;
	StringName handler;
	StringName stat;
	int amount = 0;
	StringName condition_terrain_id;
	int condition_adjacent_allies = 0;
	Ref<TacticsKeywordData> keyword;
	int extra_capacity = 0;
	Ref<TacticsZoneData> zone;
	int radius_cells = 0;
	int duration_rounds = 0;

protected:
	static void _bind_methods();

public:
	// False and r_error on an unknown handler, stat, keyword or zone.
	bool to_passive_def(tactics::PassiveDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_handler(const StringName &p_value) { handler = p_value; }
	StringName get_handler() const { return handler; }
	void set_stat(const StringName &p_value) { stat = p_value; }
	StringName get_stat() const { return stat; }
	void set_amount(int64_t p_value) { amount = clamp_to_int(p_value); }
	int get_amount() const { return amount; }
	void set_condition_terrain_id(const StringName &p_value) { condition_terrain_id = p_value; }
	StringName get_condition_terrain_id() const { return condition_terrain_id; }
	void set_condition_adjacent_allies(int64_t p_value) { condition_adjacent_allies = clamp_to_int(p_value); }
	int get_condition_adjacent_allies() const { return condition_adjacent_allies; }
	void set_keyword(const Ref<TacticsKeywordData> &p_value) { keyword = p_value; }
	Ref<TacticsKeywordData> get_keyword() const { return keyword; }
	void set_extra_capacity(int64_t p_value) { extra_capacity = clamp_to_int(p_value); }
	int get_extra_capacity() const { return extra_capacity; }
	void set_zone(const Ref<TacticsZoneData> &p_value) { zone = p_value; }
	Ref<TacticsZoneData> get_zone() const { return zone; }
	void set_radius_cells(int64_t p_value) { radius_cells = clamp_to_int(p_value); }
	int get_radius_cells() const { return radius_cells; }
	void set_duration_rounds(int64_t p_value) { duration_rounds = clamp_to_int(p_value); }
	int get_duration_rounds() const { return duration_rounds; }
};

} // namespace godot
