#pragma once

#include "tactics_types.h"

#include "battle/bridge_strings.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

// One terrain of the tactics map: how much it costs to enter and what it
// does to a unit standing on it. One file per terrain in
// Data/Tactics/Terrains/; maps reference them through their legend.
class TacticsTerrainData : public Resource {
	GDCLASS(TacticsTerrainData, Resource)

	StringName id;
	String name_key;
	int move_cost = 1;
	bool is_impassable = false;
	int armor_bonus = 0;
	int damage_taken_pct = 0;
	int ranged_damage_taken_pct = 0;
	int ranged_range_bonus = 0;

protected:
	static void _bind_methods();

public:
	tactics::TerrainDef to_terrain_def() const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_move_cost(int64_t p_value) { move_cost = clamp_to_int(p_value); }
	int get_move_cost() const { return move_cost; }
	void set_is_impassable(bool p_value) { is_impassable = p_value; }
	bool get_is_impassable() const { return is_impassable; }
	void set_armor_bonus(int64_t p_value) { armor_bonus = clamp_to_int(p_value); }
	int get_armor_bonus() const { return armor_bonus; }
	void set_damage_taken_pct(int64_t p_value) { damage_taken_pct = clamp_to_int(p_value); }
	int get_damage_taken_pct() const { return damage_taken_pct; }
	void set_ranged_damage_taken_pct(int64_t p_value) { ranged_damage_taken_pct = clamp_to_int(p_value); }
	int get_ranged_damage_taken_pct() const { return ranged_damage_taken_pct; }
	void set_ranged_range_bonus(int64_t p_value) { ranged_range_bonus = clamp_to_int(p_value); }
	int get_ranged_range_bonus() const { return ranged_range_bonus; }
};

} // namespace godot
